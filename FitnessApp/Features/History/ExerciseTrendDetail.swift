//
//  ExerciseTrendDetail.swift
//  FitnessApp
//
//  页面 11「动作历史趋势」的值语义层。
//
//  **这个文件不 import SwiftUI**，全部是纯值类型与静态函数。
//  理由与 `HistoryCalendar.swift` / `WorkoutStatistics.swift` 一致：
//  本机没有 Swift 编译器，纯值层可以逐字照搬成 Python 做断言推演
//  （见 `Tools/probe_page11_semantics.py`），任何边界算错都会在那里现形。
//

import Foundation

// MARK: - 时间范围

/// 趋势页的时间范围。与统计页的六种范围**不是同一套**：
/// 统计页问的是「这段时间我练了多少」，所以要「本月」「今年」这种日历区间；
/// 趋势页问的是「这个动作我练得怎么样」，日历区间在这里没有意义——
/// 「本月」在一个月刚开始时会给出近乎空白的图，而用户想看的是走势。
enum TrendRangeKind: String, CaseIterable, Identifiable, Equatable {
    case last30Days
    case last3Months
    case lastYear
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last30Days: return "近 30 天"
        case .last3Months: return "近 3 个月"
        case .lastYear: return "近一年"
        case .allTime: return "全部记录"
        }
    }

    /// 菜单副标题，说明这一档实际覆盖多长
    var subtitle: String {
        switch self {
        case .last30Days: return "含今天在内的 30 个自然日"
        case .last3Months: return "含今天在内的 3 个自然月"
        case .lastYear: return "含今天在内的 12 个自然月"
        case .allTime: return "本机全部已完成记录"
        }
    }

    /// 「全部记录」没有起点，范围文案不显示区间
    var showsRangeText: Bool {
        self != .allTime
    }
}

/// 半开区间 `[start, end)`，与 `StatsDateRange` 同口径。
///
/// 没有复用 `StatsDateRange`，是因为它的 `kind` 字段类型是 `StatsRangeKind`，
/// 强行复用会把两套无关的枚举绑在一起，改任何一边都会牵动另一边。
struct TrendDateRange: Equatable {
    let kind: TrendRangeKind
    let start: Date
    let end: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

/// 时间范围的构造。
enum TrendRangeBuilder {

    /// 按当前时刻构造范围。
    ///
    /// **终点统一取「明天 00:00」**，与统计页同一个理由：
    /// 写成「今天 23:59:59」会漏掉 `23:59:59.5` 这种带小数秒的记录，
    /// 而 `completedAt` / `startedAt` 都是 `Date`，确实带亚秒精度。
    static func range(
        for kind: TrendRangeKind,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TrendDateRange {
        let endOfToday = endOfDay(for: now, calendar: calendar)

        switch kind {
        case .last30Days:
            // 30 个自然日 = 今天 + 往前 29 天。写成 -30 会得到 31 天。
            let start = calendar.date(byAdding: .day, value: -29, to: startOfDay(for: now, calendar: calendar))
            return TrendDateRange(kind: kind, start: start ?? now, end: endOfToday)

        case .last3Months:
            // 按**日历月**减，不是按 90 天减：用户说「3 个月」时想的是
            // 4 月 → 1 月，而不是「往前 2160 小时」。
            let start = calendar.date(byAdding: .month, value: -2, to: firstDayOfMonth(for: now, calendar: calendar))
            return TrendDateRange(kind: kind, start: start ?? now, end: endOfToday)

        case .lastYear:
            let start = calendar.date(byAdding: .month, value: -11, to: firstDayOfMonth(for: now, calendar: calendar))
            return TrendDateRange(kind: kind, start: start ?? now, end: endOfToday)

        case .allTime:
            // 起点取一个足够早的时间：Cocoa 纪元（2001-01-01）之前不可能有记录。
            // 不用 `Date.distantPast`，是因为它在 JSON 里序列化出来的值会让
            // 调试时的日志完全不可读。
            let floor = Date(timeIntervalSinceReferenceDate: 0)
            return TrendDateRange(kind: kind, start: floor, end: endOfToday)
        }
    }

    /// 范围文案，如「9/19 - 10/19」。全部记录返回 nil。
    static func rangeText(_ range: TrendDateRange) -> String? {
        guard range.kind.showsRangeText else { return nil }
        return FormatterKit.dateRangeSlash(range.start, range.end)
    }

    /// 某天 00:00
    static func startOfDay(for date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 某天之后的那一天 00:00，即本范围的开区间终点
    static func endOfDay(for date: Date, calendar: Calendar) -> Date {
        guard let next = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) else {
            // 理论上不会走到这里；兜底给「现在 +1 秒」而不是 `distantFuture`，
            // 后者会让「全部记录」的区间长得荒谬。
            return date.addingTimeInterval(1)
        }
        return next
    }

    /// 某月第一天 00:00。用 `dateComponents` 而不是减时间戳：
    /// 减固定的秒数在夏令时地区会漂到上个月最后一天 23:00。
    static func firstDayOfMonth(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

// MARK: - 重量单位

/// 展示用的重量单位。**只影响显示，绝不回写原始记录**。
///
/// 规格明确要求「切换时仅转换展示值，不修改原始记录」，
/// 所以这里连一个 `mutating` 方法都没有，全部是纯函数。
enum TrendWeightUnit: String, CaseIterable, Identifiable, Equatable {
    case kilograms
    case pounds

    var id: String { rawValue }

    /// 按钮上的短标签
    var shortTitle: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    var title: String {
        switch self {
        case .kilograms: return "公斤"
        case .pounds: return "磅"
        }
    }

    /// 1 kg = 2.20462262185 lb
    static let poundsPerKilogram: Double = 2.204_622_621_85

    /// 把「以 kg 记录的原始值」换算成本单位的展示值。
    /// kg 原样返回，不做任何舍入——舍入在格式化时做，
    /// 否则图表连算两次会把误差累积进去。
    func displayValue(fromKilograms value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value * Self.poundsPerKilogram
        }
    }

    /// 带单位的数值文案，如「80 kg」/「176 lb」。
    /// 重量保留 1 位小数（磅换算后常有小数），整数则不显示 `.0`。
    func text(fromKilograms value: Double) -> String {
        let converted = displayValue(fromKilograms: value)
        return "\(TrendNumberFormat.weight(converted)) \(shortTitle)"
    }

    /// 容量文案。容量通常到千级，取整显示。
    func volumeText(fromKilograms value: Double) -> String {
        let converted = displayValue(fromKilograms: value)
        return "\(FormatterKit.plainNumber(converted)) \(shortTitle)"
    }

    /// 纯数字 + 单位，用于 VoiceOver（朗读时不需要多余的精度）
    func accessibilityWeight(fromKilograms value: Double) -> String {
        let converted = displayValue(fromKilograms: value)
        return "\(FormatterKit.plainNumber(converted)) \(title)"
    }
}

/// 数值格式化。单独抽出来是因为它既被 Swift 用、也要能被 Python 照搬。
enum TrendNumberFormat {

    /// 重量：整数不带 `.0`，否则保留 1 位。
    ///
    /// 磅换算后 `80 kg` 会变成 `176.37 lb`，显示成 `176` 会让人以为精度丢了；
    /// 显示成 `176.4` 既准确又不啰嗦。
    static func weight(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - 1RM 估算

/// 单次最大重量（1RM）估算。
///
/// 用 **Epley 公式**：`1RM = w × (1 + reps / 30)`。
/// 选它而不是 Brzycki / Lombardi，是因为它在 1–10 次区间里误差最小，
/// 而这正是力量训练记录里最常见的次数区间。
enum OneRMEstimator {

    /// Epley 公式的适用范围上限。
    ///
    /// 超过 12 次后公式会显著高估：一组 20 次 60 kg 会被算成
    /// `60 × (1 + 20/30) = 100 kg`，而实际做不了 100 kg。
    /// 与其给一个漂亮但错的数，不如不参与计算（返回 nil）。
    static let maxReliableReps = 12

    /// 估算 1RM。无法给出有意义结果时返回 nil（不是 0）。
    ///
    /// 返回 nil 的三种情况：重量 ≤ 0（自重动作）、次数 ≤ 0（脏数据）、
    /// 次数超过可靠区间。调用方拿 nil 就显示「—」。
    static func epley(weight: Double, reps: Int) -> Double? {
        guard weight > 0, weight.isFinite else { return nil }
        guard reps > 0, reps <= maxReliableReps else { return nil }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    /// 一组记录是否落在 Epley 的可靠区间内。
    /// UI 用它决定要不要在 1RM 卡片下补一句「按 N 次组估算」。
    static func isReliable(weight: Double, reps: Int) -> Bool {
        epley(weight: weight, reps: reps) != nil
    }
}

// MARK: - 数据点

/// 「最高重量趋势」图上的一个点 = 一次训练里该动作的最高正式组重量。
///
/// 与统计页的容量点不同：这里**按训练日聚合，不是按月**。
/// 用户问的是「我这个动作的重量有没有涨」，按月平均会把
/// 「月初 60、月末 80」抹成「这个月 70」。
struct TrendWeightPoint: Identifiable, Equatable {
    let sessionID: UUID
    let date: Date
    /// 当次训练里该动作的最高正式组重量（kg，原始值）
    let topWeight: Double
    /// 达到最高重量那一组的次数，用于点击后展示「80 kg × 6」
    let repsAtTop: Int
    /// 当次训练的名称，点击后展示
    let sessionName: String
    /// 当次训练里该动作的正式组数
    let setCount: Int

    var id: UUID { sessionID }

    var hasWeight: Bool { topWeight > 0 }

    /// 坐标轴标签，如「9/12」
    var axisLabel: String { FormatterKit.monthDaySlash(date) }

    /// 点击后展示的详情，如「80 kg × 6」
    func bestSetText(unit: TrendWeightUnit) -> String {
        guard hasWeight else { return "自重" }
        let weightText = TrendNumberFormat.weight(unit.displayValue(fromKilograms: topWeight))
        return "\(weightText) \(unit.shortTitle) × \(repsAtTop)"
    }

    var accessibilityLabel: String {
        guard hasWeight else {
            return "\(FormatterKit.monthDaySlash(date))，自重训练，\(setCount) 组"
        }
        return "\(FormatterKit.monthDaySlash(date))，最高 \(FormatterKit.plainNumber(topWeight)) 公斤，\(repsAtTop) 次，共 \(setCount) 组"
    }
}

/// 「单次训练容量趋势」图上的一根柱子 = 一次训练里该动作的容量。
struct TrendVolumePoint: Identifiable, Equatable {
    let sessionID: UUID
    let date: Date
    /// 容量（kg·次，原始值）。热身组恒为 0 的贡献。
    let volume: Double
    let sessionName: String
    let setCount: Int

    var id: UUID { sessionID }

    var axisLabel: String { FormatterKit.monthDaySlash(date) }

    func volumeText(unit: TrendWeightUnit) -> String {
        unit.volumeText(fromKilograms: volume)
    }

    var accessibilityLabel: String {
        "\(FormatterKit.monthDaySlash(date))，\(setCount) 组，容量 \(FormatterKit.plainNumber(volume)) 公斤"
    }
}

/// 「最近记录」列表里的一行。
struct ExerciseRecentRecord: Identifiable, Equatable {
    let sessionID: UUID
    let date: Date
    let sessionName: String
    /// 该动作的正式组数
    let setCount: Int
    /// 最佳组的重量（kg 原始值）。自重动作为 0。
    let bestWeight: Double
    /// 最佳组的次数
    let bestReps: Int
    /// 该动作在这次的容量
    let volume: Double

    var id: UUID { sessionID }

    /// 最佳组文案，如「80 kg × 6」。自重动作显示「自重 × 12」。
    func bestSetText(unit: TrendWeightUnit) -> String {
        guard bestWeight > 0 else {
            return "自重 × \(bestReps)"
        }
        let weightText = TrendNumberFormat.weight(unit.displayValue(fromKilograms: bestWeight))
        return "\(weightText) \(unit.shortTitle) × \(bestReps)"
    }

    var accessibilityLabel: String {
        var parts = [FormatterKit.monthDaySlash(date)]
        parts.append(sessionName)
        parts.append("\(setCount) 组")
        if bestWeight > 0 {
            parts.append("最佳 \(FormatterKit.plainNumber(bestWeight)) 公斤 \(bestReps) 次")
        } else {
            parts.append("自重 \(bestReps) 次")
        }
        parts.append("容量 \(FormatterKit.plainNumber(volume)) 公斤")
        return parts.joined(separator: "，")
    }
}

// MARK: - 摘要

/// 趋势页顶部摘要卡的五个字段。
///
/// 每个「可能算不出来」的字段都是 Optional，
/// 与统计页的 `StatsMetric.value: String?` 同一套语义：
/// **算不出来显示「—」，算出来是 0 才显示 0**。
struct ExerciseTrendOverview: Equatable {

    /// 范围内该动作出现过的训练次数
    let sessionCount: Int
    /// 范围内该动作的正式组数
    let setCount: Int
    /// 最高单组重量（kg）。没有有效重量时为 nil —— 自重动作整段都是 0，
    /// 显示「0 kg」会让人以为自己举过 0 公斤。
    let bestWeight: Double?
    /// 最高估算 1RM（kg）。没有任何落在 Epley 可靠区间的组时为 nil。
    let bestOneRM: Double?
    /// 最近一次训练的日期。没有任何记录时为 nil。
    let lastTrainedAt: Date?

    /// 估算 1RM 来自哪一组，用于在卡片下补一句说明
    let oneRMSourceReps: Int?

    var isEmpty: Bool { sessionCount == 0 }

    func bestWeightText(unit: TrendWeightUnit) -> String {
        guard let best = bestWeight, best > 0 else { return "—" }
        return TrendNumberFormat.weight(unit.displayValue(fromKilograms: best))
    }

    func bestOneRMText(unit: TrendWeightUnit) -> String {
        guard let best = bestOneRM, best > 0 else { return "—" }
        return TrendNumberFormat.weight(unit.displayValue(fromKilograms: best))
    }

    /// 最近训练日期文案
    var lastTrainedText: String {
        guard let date = lastTrainedAt else { return "—" }
        return FormatterKit.shortDate(date)
    }

    /// 1RM 的来源说明。nil 表示没有可估算的组，UI 不显示这行。
    var oneRMNoteText: String? {
        guard let reps = oneRMSourceReps else { return nil }
        return "按 \(reps) 次组估算"
    }

    var accessibilityText: String {
        guard !isEmpty else { return "还没有这个动作的训练记录" }
        var parts = ["共 \(sessionCount) 次训练", "\(setCount) 组"]
        if let best = bestWeight {
            parts.append("最高单组 \(FormatterKit.plainNumber(best)) 公斤")
        } else {
            parts.append("最高单组无重量数据")
        }
        if let rm = bestOneRM {
            parts.append("估算单次最大重量 \(FormatterKit.plainNumber(rm)) 公斤")
        }
        if let date = lastTrainedAt {
            parts.append("最近 \(FormatterKit.shortDate(date))")
        }
        return parts.joined(separator: "，") + "。"
    }
}

// MARK: - 开始训练的建议

/// 「开始练这个动作」的预填建议。
///
/// 全部来自**最近一次有效记录**，不是全期最高：
/// 建议的意义是「接着上次练」，拿历史最高去建议会让新手一上来就加满重量。
struct ExerciseStartSuggestion: Equatable {
    /// 建议重量（kg 原始值）。自重动作为 0。
    let weight: Double
    /// 建议次数下限与上限
    let repsLow: Int
    let repsHigh: Int
    /// 建议组间休息（秒）
    let restSeconds: Int
    /// 建议组数
    let sets: Int
    /// 建议来自哪一天。nil 表示没有任何历史记录，用的是保守默认值。
    let sourceDate: Date?

    /// 没有历史记录时的保守默认：轻重量、中次数、常规休息。
    ///
    /// 3 组 / 8-12 次 / 90 秒是本项目处方面板的默认值，
    /// 与 `ExercisePrescription` 的初始值保持一致，避免两套默认值打架。
    static let fallback = ExerciseStartSuggestion(
        weight: 0,
        repsLow: 8,
        repsHigh: 12,
        restSeconds: 90,
        sets: 3,
        sourceDate: nil
    )

    var hasHistorySource: Bool { sourceDate != nil }

    /// 建议的来源说明，展示在确认抽屉里。
    /// 用户有权知道这个数字是「照抄上次」还是「我替他编的」。
    var sourceText: String {
        guard let date = sourceDate else {
            return "没有历史记录，已按常规方案预填"
        }
        return "按 \(FormatterKit.monthDaySlash(date)) 那次训练预填"
    }

    func weightText(unit: TrendWeightUnit) -> String {
        guard weight > 0 else { return "自重" }
        return "\(TrendNumberFormat.weight(unit.displayValue(fromKilograms: weight))) \(unit.shortTitle)"
    }

    var repsText: String {
        repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
    }
}

// MARK: - 聚合

/// 页面 11 的全部聚合。
enum ExerciseTrendDetailBuilder {

    /// 最近记录列表的默认条数。
    ///
    /// 10 而不是 5：这个列表的用途是「点进去看某次练得怎么样」，
    /// 5 条在每周 4 练的频率下只覆盖一周多，太短。
    static let recentLimit = 10

    /// 单次读取的原始记录上限。与统计页、历史页同一口径。
    static let sessionFetchLimit = 500

    /// 该动作在范围内的全部有效组。
    ///
    /// 「有效」= 所属训练已完成、组已完成、非热身。
    /// 热身组被排除的理由与全站一致：热身是做了，但不算训练量，
    /// 把它算进最高重量会让趋势凭空高一截。
    struct ValidSet {
        let sessionID: UUID
        let date: Date
        let sessionName: String
        let weight: Double
        let reps: Int
        let volume: Double
    }

    /// 收集范围内该动作的有效组，按时间从旧到新。
    ///
    /// 排序放在这里而不是各个图表里：三个图（重量 / 容量 / 最近记录）
    /// 都必须是同一条时间轴，各排一次迟早会不一致。
    static func validSets(
        sessions: [WorkoutSession],
        exerciseID: String,
        range: TrendDateRange
    ) -> [ValidSet] {
        var result: [ValidSet] = []

        for session in sessions {
            guard session.isFinished, range.contains(session.startedAt) else { continue }

            for entry in session.entries {
                guard entry.exerciseID == exerciseID,
                      entry.completedAt != nil,
                      !entry.isWarmup
                else { continue }

                result.append(
                    ValidSet(
                        sessionID: session.id,
                        date: session.startedAt,
                        sessionName: session.name,
                        weight: entry.weight,
                        reps: entry.reps,
                        volume: entry.volume
                    )
                )
            }
        }

        // 同一天可能有多条训练，稳定排序保证同日记录的内部顺序不变
        return result.sorted { $0.date < $1.date }
    }

    /// 按训练聚合出「最高重量趋势」的点。
    ///
    /// 只保留 **有该动作记录** 的训练，不补空日——
    /// 与统计页的容量趋势同一口径：补 0 会画出规格禁止的零值折线。
    static func weightPoints(from sets: [ValidSet]) -> [TrendWeightPoint] {
        guard !sets.isEmpty else { return [] }

        var order: [UUID] = []
        var bySession: [UUID: (date: Date, name: String, top: Double, reps: Int, count: Int)] = [:]

        for set in sets {
            if let existing = bySession[set.sessionID] {
                // 同重量取次数多的那一组作为代表：80×8 比 80×5 更能代表这次训练
                if set.weight > existing.top ||
                    (set.weight == existing.top && set.reps > existing.reps) {
                    bySession[set.sessionID] = (
                        existing.date, existing.name, set.weight, set.reps, existing.count + 1
                    )
                } else {
                    bySession[set.sessionID] = (
                        existing.date, existing.name, existing.top, existing.reps, existing.count + 1
                    )
                }
            } else {
                order.append(set.sessionID)
                bySession[set.sessionID] = (
                    set.date, set.sessionName, set.weight, set.reps, 1
                )
            }
        }

        return order.compactMap { id in
            guard let value = bySession[id] else { return nil }
            return TrendWeightPoint(
                sessionID: id,
                date: value.date,
                topWeight: value.top,
                repsAtTop: value.reps,
                sessionName: value.name,
                setCount: value.count
            )
        }
    }

    /// 按训练聚合出「单次训练容量趋势」的柱子。
    static func volumePoints(from sets: [ValidSet]) -> [TrendVolumePoint] {
        guard !sets.isEmpty else { return [] }

        var order: [UUID] = []
        var bySession: [UUID: (date: Date, name: String, volume: Double, count: Int)] = [:]

        for set in sets {
            if var existing = bySession[set.sessionID] {
                existing.volume += set.volume
                existing.count += 1
                bySession[set.sessionID] = existing
            } else {
                order.append(set.sessionID)
                bySession[set.sessionID] = (set.date, set.sessionName, set.volume, 1)
            }
        }

        return order.compactMap { id in
            guard let value = bySession[id] else { return nil }
            return TrendVolumePoint(
                sessionID: id,
                date: value.date,
                volume: value.volume,
                sessionName: value.name,
                setCount: value.count
            )
        }
    }

    /// 最近记录列表，倒序（最近在前），最多 `recentLimit` 条。
    static func recentRecords(
        from sets: [ValidSet],
        limit: Int = recentLimit
    ) -> [ExerciseRecentRecord] {
        guard limit > 0, !sets.isEmpty else { return [] }

        var order: [UUID] = []
        var bySession: [UUID: (date: Date, name: String, best: Double, reps: Int, volume: Double, count: Int)] = [:]

        for set in sets {
            if let existing = bySession[set.sessionID] {
                // 「最佳组」的定义：先比重量，同重量比次数。
                // 不按容量比——80×3(240) 不该盖过 70×10(700)，
                // 用户点进详情页想看的是「这次最重举了多少」。
                let better = set.weight > existing.best ||
                    (set.weight == existing.best && set.reps > existing.reps)
                bySession[set.sessionID] = (
                    existing.date,
                    existing.name,
                    better ? set.weight : existing.best,
                    better ? set.reps : existing.reps,
                    existing.volume + set.volume,
                    existing.count + 1
                )
            } else {
                order.append(set.sessionID)
                bySession[set.sessionID] = (set.date, set.sessionName, set.weight, set.reps, set.volume, 1)
            }
        }

        let records = order.compactMap { id -> ExerciseRecentRecord? in
            guard let value = bySession[id] else { return nil }
            return ExerciseRecentRecord(
                sessionID: id,
                date: value.date,
                sessionName: value.name,
                setCount: value.count,
                bestWeight: value.best,
                bestReps: value.reps,
                volume: value.volume
            )
        }

        return records
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map { $0 }
    }

    /// 顶部摘要卡。
    static func overview(from sets: [ValidSet]) -> ExerciseTrendOverview {
        guard !sets.isEmpty else {
            return ExerciseTrendOverview(
                sessionCount: 0, setCount: 0, bestWeight: nil,
                bestOneRM: nil, lastTrainedAt: nil, oneRMSourceReps: nil
            )
        }

        let sessionIDs = Set(sets.map { $0.sessionID })
        let setCount = sets.count

        // 最高单组重量：只认 weight > 0 的组。
        // 自重动作整段都是 0，此时 bestWeight 为 nil，显示「—」。
        let weighted = sets.filter { $0.weight > 0 }
        let bestWeight = weighted.map { $0.weight }.max()

        // 最高 1RM：在 Epley 可靠区间内的组里取最大估算值，
        // 并记住它来自几次组，好在 UI 上说明。
        var bestRM: Double?
        var bestRMReps: Int?
        for set in weighted {
            guard let estimate = OneRMEstimator.epley(weight: set.weight, reps: set.reps) else { continue }
            if bestRM == nil || estimate > (bestRM ?? 0) {
                bestRM = estimate
                bestRMReps = set.reps
            }
        }

        let lastTrainedAt = sets.map { $0.date }.max()

        return ExerciseTrendOverview(
            sessionCount: sessionIDs.count,
            setCount: setCount,
            bestWeight: bestWeight,
            bestOneRM: bestRM,
            lastTrainedAt: lastTrainedAt,
            oneRMSourceReps: bestRMReps
        )
    }

    /// 「开始练这个动作」的建议参数。
    ///
    /// 取自**最近一次有效记录**：最近一次训练里该动作的最高组给重量，
    /// 那次训练里该动作的最高次数给次数上限（下限取它的 8 折，向上取整且不低于 5）。
    /// 休息沿用项目默认的 90 秒，组数取最近那次的组数但不低于 3。
    static func startSuggestion(from sets: [ValidSet]) -> ExerciseStartSuggestion {
        guard let lastDate = sets.map({ $0.date }).max() else {
            return .fallback
        }

        let lastSets = sets.filter { $0.date == lastDate }
        guard !lastSets.isEmpty else { return .fallback }

        let topWeight = lastSets.map { $0.weight }.max() ?? 0
        let topReps = lastSets.map { $0.reps }.max() ?? 0
        let setCount = lastSets.count

        // 次数下限 = 上限的 8 折向上取整，并尽量不低于 5 ——
        // 低于 5 次就接近力量举而非增肌区间，对「接着上次练」这个意图不合适。
        //
        // 但外层还有一个 `min(repsHigh, …)`：上限自己就低于 5 时（上次做的是
        // 4 次的大重量组），下限会被压回与上限相等，否则会给出「5-4」这种
        // 倒挂区间。区间倒挂比区间偏窄难看得多。
        let repsHigh = max(1, topReps)
        let repsLow = min(repsHigh, max(5, Int((Double(repsHigh) * 0.8).rounded(.up))))

        return ExerciseStartSuggestion(
            // 建议重量沿用上次最高组，不自动加重：
            // 渐进超负荷该由用户决定，App 替他加重量出了伤没人负责。
            weight: topWeight,
            repsLow: repsLow,
            repsHigh: repsHigh,
            restSeconds: ExerciseStartSuggestion.fallback.restSeconds,
            sets: max(3, setCount),
            sourceDate: lastDate
        )
    }

    /// 展开成草稿的组条目。**只生成未完成的目标组**，不预填完成时间。
    ///
    /// 返回的是 `[SetEntry]`，调用方拿它拼 `WorkoutSession` 后落盘。
    /// 抽成纯函数是为了能推演：组号从 1 开始、目标次数正确、热身组排在最前。
    static func draftEntries(
        exerciseID: String,
        suggestion: ExerciseStartSuggestion,
        startingIndex: Int = 1
    ) -> [SetEntry] {
        let count = max(1, suggestion.sets)
        return (0..<count).map { offset in
            SetEntry(
                exerciseID: exerciseID,
                index: startingIndex + offset,
                // 未完成组的重量预填建议值：执行页一进来就有参考数，
                // 而不是让用户对着 0 猜。
                weight: suggestion.weight,
                reps: suggestion.repsLow,
                targetRepsLow: suggestion.repsLow,
                targetRepsHigh: suggestion.repsHigh,
                isWarmup: false,
                completedAt: nil
            )
        }
    }

    /// 图的 VoiceOver 摘要。没有数据时也要给出一句成立的话。
    static func weightTrendSummary(
        points: [TrendWeightPoint],
        overview: ExerciseTrendOverview,
        rangeTitle: String
    ) -> String {
        guard !points.isEmpty else {
            return "\(rangeTitle)内没有这个动作的训练记录。"
        }
        var parts = ["\(rangeTitle)内最高重量趋势，共 \(points.count) 次训练"]
        if let best = overview.bestWeight {
            parts.append("最高 \(FormatterKit.plainNumber(best)) 公斤")
        } else {
            parts.append("全部为自重训练")
        }
        if points.count > 1 {
            let first = points.first?.topWeight ?? 0
            let last = points.last?.topWeight ?? 0
            let delta = last - first
            if abs(delta) < 0.01 {
                parts.append("区间内基本持平")
            } else if delta > 0 {
                parts.append("比首次提高 \(FormatterKit.plainNumber(delta)) 公斤")
            } else {
                parts.append("比首次下降 \(FormatterKit.plainNumber(-delta)) 公斤")
            }
        }
        return parts.joined(separator: "，") + "。"
    }

    static func volumeTrendSummary(
        points: [TrendVolumePoint],
        rangeTitle: String
    ) -> String {
        guard !points.isEmpty else {
            return "\(rangeTitle)内没有这个动作的容量记录。"
        }
        let total = points.reduce(0) { $0 + $1.volume }
        let best = points.map { $0.volume }.max() ?? 0
        return "\(rangeTitle)内单次训练容量趋势，共 \(points.count) 次训练，"
            + "累计 \(FormatterKit.plainNumber(total)) 公斤，"
            + "单次最高 \(FormatterKit.plainNumber(best)) 公斤。"
    }
}

// MARK: - 动作名兜底

/// 趋势页的动作名三级兜底。
///
/// 与页面 09 的 `HistoryExerciseNaming` 同口径，但入口不同：
/// 这里拿到的可能是「统计页传过来的快照名」，也可能是「动作库里的当前名」。
/// 关键是**任何输入都不产出空字符串**——空白标题看起来像渲染失败。
enum TrendExerciseNaming {

    /// 库里的显示名 → 外部传入的快照名 → id → 「未知动作」
    static func name(libraryName: String?, fallback: String?, exerciseID: String) -> String {
        let candidates = [libraryName, fallback, exerciseID]
        for candidate in candidates {
            guard let value = candidate else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "未知动作"
    }
}
