//
//  WorkoutStatistics.swift
//  训练统计的纯值计算层。
//
//  与 `HistoryCalendar.swift` 同样的分层理由：这一整个文件里没有任何 SwiftUI 类型。
//  统计页最容易错、也最难在真机上肉眼验算的正是这些地方 ——
//  时间范围的边界归属、自然日与周的对齐、零值该不该补、
//  「没有数据」与「结果是 0」的区别、百分比的分母。
//  写成纯值类型后才能完整移植到 Python 里逐条跑断言。
//
//  一条贯穿全文件的规则：**「算不出来」和「算出来是 0」是两件事**。
//  统计卡上「—」表示前者，`0` 表示后者。把两者混成一个数字会让用户
//  以为自己的训练容量真的是 0 kg。
//

import Foundation

// MARK: - 时间范围

/// 统计页顶部的时间范围。规格指定六种：近 7 天 / 近 30 天 / 本月 / 近 3 个月 / 今年 / 自定义。
enum StatsRangeKind: String, Equatable, CaseIterable, Identifiable {
    case last7Days
    case last30Days
    case thisMonth
    case last3Months
    case thisYear
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last7Days: return "近 7 天"
        case .last30Days: return "近 30 天"
        case .thisMonth: return "本月"
        case .last3Months: return "近 3 个月"
        case .thisYear: return "今年"
        case .custom: return "自定义"
        }
    }

    /// 抽屉里的第二行说明，写清楚这个范围到底框住了哪一段。
    ///
    /// 「近 7 天」到底是 7 个自然日还是 168 小时，不同 App 的做法不一样，
    /// 用户在图表上看到柱子数量不对会以为统计坏了。这里明写「含今天」。
    var subtitle: String {
        switch self {
        case .last7Days: return "含今天在内的 7 个自然日"
        case .last30Days: return "含今天在内的 30 个自然日"
        case .thisMonth: return "从本月 1 日至今"
        case .last3Months: return "含本月在内的 3 个自然月"
        case .thisYear: return "从今年 1 月 1 日至今"
        case .custom: return "手动选择开始与结束日期"
        }
    }

    /// 是否需要用户再填起止日期
    var needsDateInput: Bool { self == .custom }
}

/// 一个已经解析好的时间范围。
///
/// 统一用**半开区间** `[start, end)` 表示：`start` 含、`end` 不含。
/// 用半开而不是闭区间，是因为「本月」的 `end` 若是闭合的「本月最后一天 23:59:59」，
/// 就得处理闰月、月末、以及最后那一秒里发生的训练算不算——半开区间直接绕开这些。
struct StatsDateRange: Equatable {
    /// 起点，含
    let start: Date
    /// 终点，不含
    let end: Date
    /// 产生这个范围的原始种类
    let kind: StatsRangeKind

    init(start: Date, end: Date, kind: StatsRangeKind) {
        self.start = start
        self.end = end
        self.kind = kind
    }

    /// 是否包含某个时间点
    func contains(_ date: Date) -> Bool {
        date >= start && date < end
    }

    /// 区间跨越的整天数。
    ///
    /// 用日历的 `dateComponents` 而不是 `timeInterval / 86400`：
    /// 跨夏令时的那一天在秒数上不是 86400，整数除法会算少一天。
    func dayCount(calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(0, days)
    }

    /// 给用户看的范围文案，如「8月21日 – 9月19日」
    func text(calendar: Calendar = .current) -> String {
        "\(FormatterKit.shortDate(start)) – \(FormatterKit.shortDate(end))"
    }
}

/// 时间范围解析。
///
/// 全部按**用户本地时区的自然日**切分，与 `HistoryDayIndex` 的口径一致。
/// 若这里按 UTC 切，东八区用户在早上 8 点前做的训练会掉到前一天，
/// 表现为「今天练了但今天那根柱子里没有」。
enum StatsRangeBuilder {

    /// 由种类与「当前时刻」解析出具体区间。
    ///
    /// - `now` 显式传入而不是取 `.now`：整个函数因为这一点而变成纯函数，
    ///   可以在 Python 里对任意历史时刻跑断言。
    static func range(
        for kind: StatsRangeKind,
        now: Date,
        customStart: Date? = nil,
        customEnd: Date? = nil,
        calendar: Calendar = .current
    ) -> StatsDateRange {
        let today = calendar.startOfDay(for: now)

        switch kind {
        case .last7Days:
            // 「近 7 天」含今天，所以起点是今天往前 6 天。
            // 写成 `-7` 会得到 8 个自然日，柱状图上会多一根。
            let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
            return StatsDateRange(start: start, end: endOfToday(now: now, calendar: calendar), kind: kind)

        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: today) ?? today
            return StatsDateRange(start: start, end: endOfToday(now: now, calendar: calendar), kind: kind)

        case .thisMonth:
            let start = firstDayOfMonth(for: now, calendar: calendar) ?? today
            return StatsDateRange(start: start, end: endOfToday(now: now, calendar: calendar), kind: kind)

        case .last3Months:
            // 「近 3 个月」= 含本月在内的 3 个自然月，起点是本月 1 日往前推 2 个月。
            let thisMonthStart = firstDayOfMonth(for: now, calendar: calendar) ?? today
            let start = calendar.date(byAdding: .month, value: -2, to: thisMonthStart) ?? thisMonthStart
            return StatsDateRange(start: start, end: endOfToday(now: now, calendar: calendar), kind: kind)

        case .thisYear:
            let start = firstDayOfYear(for: now, calendar: calendar) ?? today
            return StatsDateRange(start: start, end: endOfToday(now: now, calendar: calendar), kind: kind)

        case .custom:
            return customRange(
                start: customStart,
                end: customEnd,
                now: now,
                calendar: calendar
            )
        }
    }

    /// 自定义范围。
    ///
    /// 三条兜底，都是为了让「用户手滑」不至于把页面搞成空白或负数区间：
    /// - 没给起点：退回近 30 天，而不是崩溃或展示全空；
    /// - 终点早于起点：交换两者。用户先点结束日再点开始日是常见操作顺序；
    /// - 终点是「某天 00:00」：补到该天结束，否则选「今天」会一格数据都取不到。
    static func customRange(
        start: Date?,
        end: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> StatsDateRange {
        let fallback = range(for: .last30Days, now: now, calendar: calendar)
        guard let rawStart = start else { return fallback }

        let normalizedStart = calendar.startOfDay(for: rawStart)
        let rawEnd = end ?? now
        let normalizedEndDay = calendar.startOfDay(for: rawEnd)

        let lower = min(normalizedStart, normalizedEndDay)
        let upper = max(normalizedStart, normalizedEndDay)
        guard let exclusiveEnd = calendar.date(byAdding: .day, value: 1, to: upper) else {
            return fallback
        }
        return StatsDateRange(start: lower, end: exclusiveEnd, kind: .custom)
    }

    /// 该范围的「不含」终点。
    ///
    /// 一律取**明天的 00:00**而不是今天 23:59:59：
    /// 后者会漏掉 23:59:59.5 这种小数秒里写入的记录。
    private static func endOfToday(now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now
    }

    static func firstDayOfMonth(for date: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)
    }

    static func firstDayOfYear(for date: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components)
    }
}

// MARK: - 摘要指标

/// 一张摘要卡的数值。
///
/// `value` 为 `nil` 表示**无法计算**，视图层渲染「—」。
/// 规格明确要求「无法计算的指标显示「—」，不显示误导性的 0」，
/// 所以这里用可选值把这个区别带到类型里，而不是靠视图层判断 `== 0`。
struct StatsMetric: Identifiable, Equatable {
    /// 稳定 id，用于 ForEach
    let id: String
    let title: String
    /// nil = 算不出来，显示「—」
    let value: String?
    let unit: String?
    /// 是否用荧光绿强调
    let isAccent: Bool
    /// VoiceOver 用的完整语句
    let accessibilityText: String

    init(
        id: String,
        title: String,
        value: String?,
        unit: String? = nil,
        isAccent: Bool = false,
        accessibilityText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.unit = unit
        self.isAccent = isAccent
        self.accessibilityText = accessibilityText
            ?? "\(title) \(value ?? "暂无数据")\(unit ?? "")"
    }

    /// 展示文案，「—」是唯一的空值表示
    var displayText: String { value ?? "—" }
}

/// 时间范围内的训练汇总。
struct StatsSummary: Equatable {

    /// 区间内的已完成训练，按开始时间升序
    let sessions: [WorkoutSession]

    init(sessions: [WorkoutSession]) {
        self.sessions = sessions
    }

    /// 训练次数
    var sessionCount: Int { sessions.count }

    /// 力量训练次数
    var strengthCount: Int { sessions.filter { $0.kind == .strength }.count }

    /// 有氧训练次数
    var cardioCount: Int { sessions.filter { $0.kind == .cardio }.count }

    /// 总训练时长（秒）
    var totalDurationSeconds: Int {
        sessions.reduce(0) { $0 + $1.durationSeconds }
    }

    /// 总完成组数。
    ///
    /// 用 `completedSetCount`（含热身）还是 `totalSets`（不含热身）？
    /// 这里选**含热身**：摘要卡的语义是「一共完成了多少组动作」，
    /// 热身也是真实完成的组。而容量那一格用 `totalVolume`，热身天然不计入。
    /// 两格口径不同是有意的：一个数「做了多少」，一个数「举了多少」。
    var totalSetCount: Int {
        sessions.reduce(0) { $0 + $1.completedSetCount }
    }

    /// 总训练容量。只有力量训练产生容量。
    var totalVolume: Double {
        sessions.filter { $0.kind == .strength }.reduce(0) { $0 + $1.totalVolume }
    }

    /// 有氧总里程（米）。
    var totalDistanceMeters: Double {
        sessions.filter { $0.kind == .cardio }
            .reduce(0) { $0 + ($1.distanceMeters ?? 0) }
    }

    /// 是否存在有氧记录。规格说「若包含有氧记录，额外显示总距离」。
    var hasCardio: Bool { cardioCount > 0 }

    /// 是否存在任何容量数据。决定容量趋势图是画线还是显示空状态。
    var hasVolume: Bool { totalVolume > 0 }

    /// 平均单次时长（秒）。没有训练时返回 nil 而不是 0。
    var averageDurationSeconds: Int? {
        guard sessionCount > 0 else { return nil }
        return totalDurationSeconds / sessionCount
    }

    /// 四张摘要卡。
    ///
    /// 顺序固定：训练次数 / 总时长 / 总完成组数 / 总容量。
    /// 有氧存在时在容量后追加总距离，而不是替换任何一格 ——
    /// 前四项是任何训练都有的，距离是额外的。
    func metrics(includeCardioDistance: Bool = true) -> [StatsMetric] {
        var result: [StatsMetric] = []

        result.append(
            StatsMetric(
                id: "sessionCount",
                title: "训练次数",
                value: sessionCount > 0 ? "\(sessionCount)" : "0",
                unit: "次",
                isAccent: true,
                accessibilityText: sessionCount > 0
                    ? "训练 \(sessionCount) 次"
                    : "这个时间范围内没有训练记录"
            )
        )

        result.append(
            StatsMetric(
                id: "duration",
                title: "总训练时长",
                value: sessionCount > 0
                    ? FormatterKit.plainNumber(Double(totalDurationSeconds) / 60.0)
                    : "0",
                unit: "分钟",
                accessibilityText: sessionCount > 0
                    ? "总训练时长 \(FormatterKit.duration(seconds: totalDurationSeconds))"
                    : "总训练时长 0 分钟"
            )
        )

        result.append(
            StatsMetric(
                id: "sets",
                title: "总完成组数",
                value: "\(totalSetCount)",
                unit: "组",
                accessibilityText: "总完成 \(totalSetCount) 组"
            )
        )

        // 容量是唯一可能「算不出来」的指标：
        // 只有有氧训练时它恒为 0，但那不是「你举了 0 kg」，
        // 而是「这段时间没有力量训练」。所以给 nil 让它显示「—」。
        let volumeText: String? = hasVolume
            ? FormatterKit.plainNumber(totalVolume)
            : (strengthCount > 0 ? "0" : nil)
        result.append(
            StatsMetric(
                id: "volume",
                title: "总训练容量",
                value: volumeText,
                unit: "kg",
                accessibilityText: volumeText == nil
                    ? "这个时间范围内没有力量训练，总容量无法计算"
                    : "总训练容量 \(FormatterKit.plainNumber(totalVolume)) 千克"
            )
        )

        if includeCardioDistance, hasCardio {
            // 有有氧但没填距离时显示「—」而不是 0.00 公里。
            let hasDistance = totalDistanceMeters > 0
            result.append(
                StatsMetric(
                    id: "distance",
                    title: "总距离",
                    value: hasDistance
                        ? String(format: "%.2f", totalDistanceMeters / 1000)
                        : nil,
                    unit: "公里",
                    accessibilityText: hasDistance
                        ? String(format: "有氧总距离 %.2f 公里", totalDistanceMeters / 1000)
                        : "有氧训练未记录距离"
                )
            )
        }

        return result
    }

    /// 给 VoiceOver 的一句话摘要，规格里举的例子就是这种句式。
    func accessibilitySummary(rangeTitle: String) -> String {
        guard sessionCount > 0 else {
            return "\(rangeTitle)没有训练记录"
        }
        var parts = ["\(rangeTitle)完成 \(sessionCount) 次训练"]
        parts.append("共 \(FormatterKit.duration(seconds: totalDurationSeconds))")
        if hasVolume {
            parts.append("总容量 \(FormatterKit.plainNumber(totalVolume)) 千克")
        }
        if hasCardio, totalDistanceMeters > 0 {
            parts.append(String(format: "总距离 %.2f 公里", totalDistanceMeters / 1000))
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 训练频率

/// 柱状图里的一根柱子。
struct StatsFrequencyBucket: Identifiable, Equatable {
    /// 这一格的代表日期（按日）或这一周的起始日（按周）
    let date: Date
    /// 该格覆盖的自然日。按日时只有一天；按周时有七天。
    let days: [Date]
    let strengthCount: Int
    let cardioCount: Int
    /// 该格内所有训练的总时长
    let durationSeconds: Int

    var id: Date { date }
    var totalCount: Int { strengthCount + cardioCount }
    var isEmpty: Bool { totalCount == 0 }

    /// 横轴标签。按周显示「9/1」，按日显示「9/19」。
    var axisLabel: String { FormatterKit.monthDaySlash(date) }

    /// 点击柱子时的详情文案
    var detailText: String {
        guard totalCount > 0 else {
            return "\(FormatterKit.shortDate(days.first ?? date)) 没有训练"
        }
        var parts: [String] = []
        if strengthCount > 0 { parts.append("力量 \(strengthCount) 次") }
        if cardioCount > 0 { parts.append("有氧 \(cardioCount) 次") }
        parts.append(FormatterKit.duration(seconds: durationSeconds))
        return parts.joined(separator: " · ")
    }

    /// VoiceOver 标签
    var accessibilityLabel: String {
        let dayText = days.count == 1
            ? FormatterKit.shortDate(date)
            : "\(FormatterKit.shortDate(date))那一周"
        guard totalCount > 0 else { return "\(dayText)，没有训练" }
        var parts = [dayText, "训练 \(totalCount) 次"]
        if strengthCount > 0 { parts.append("其中力量 \(strengthCount) 次") }
        if cardioCount > 0 { parts.append("有氧 \(cardioCount) 次") }
        parts.append("时长 \(FormatterKit.duration(seconds: durationSeconds))")
        return parts.joined(separator: "，")
    }
}

/// 频率图的横轴粒度。
///
/// 规格写「按周或按日显示」，粒度由范围长度决定：
/// 7 天按日看得清每一天，今年按日会有 300+ 根柱子挤成一团。
enum StatsFrequencyGranularity: String, Equatable, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "按日"
        case .weekly: return "按周"
        }
    }

    /// 由范围自动选粒度。阈值取 45 天：
    /// 30 天按日还能放下 30 根柱子，3 个月按日就太密了。
    static func recommended(for range: StatsDateRange, calendar: Calendar = .current) -> StatsFrequencyGranularity {
        range.dayCount(calendar: calendar) <= 45 ? .daily : .weekly
    }
}

/// 频率柱状图的数据构建。
enum StatsFrequencyBuilder {

    /// 单张图最多渲染多少根柱子。
    ///
    /// 超过就按周聚合。今年（365 天）按日会有 365 根，一根不到 1pt 宽，
    /// 既画不出来也点不中。
    static let maxBuckets = 60

    /// 构建柱子序列。
    ///
    /// - 参数 `fillEmpty`: 无训练的日期是否也占一根空柱。
    ///   按日时必须补（否则柱子的 x 位置会随训练日跳变，
    ///   看起来像时间轴被压缩了）；按周时也补，道理相同。
    ///   所以这个参数默认 true，只在极端范围下才由构建器自行降级。
    static func buckets(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        granularity: StatsFrequencyGranularity,
        calendar: Calendar = .current
    ) -> [StatsFrequencyBucket] {
        // 只统计区间内已完成的训练
        let scoped = sessions.filter { $0.isFinished && range.contains($0.startedAt) }

        switch granularity {
        case .daily:
            return dailyBuckets(sessions: scoped, range: range, calendar: calendar)
        case .weekly:
            return weeklyBuckets(sessions: scoped, range: range, calendar: calendar)
        }
    }

    private static func dailyBuckets(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        calendar: Calendar
    ) -> [StatsFrequencyBucket] {
        var grouped: [Date: [WorkoutSession]] = [:]
        for session in sessions {
            let key = calendar.startOfDay(for: session.startedAt)
            grouped[key, default: []].append(session)
        }

        var result: [StatsFrequencyBucket] = []
        var cursor = calendar.startOfDay(for: range.start)
        // 上限保护：范围异常大时不要在这里空转几十万次。
        // 正常范围远小于此，触发即说明入参有问题，直接截断比卡死好。
        let limit = 400
        while cursor < range.end, result.count < limit {
            result.append(makeBucket(date: cursor, days: [cursor], sessions: grouped[cursor] ?? []))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func weeklyBuckets(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        calendar: Calendar
    ) -> [StatsFrequencyBucket] {
        var grouped: [Date: [WorkoutSession]] = [:]
        for session in sessions {
            let key = weekStart(for: session.startedAt, calendar: calendar)
            grouped[key, default: []].append(session)
        }

        var result: [StatsFrequencyBucket] = []
        var cursor = weekStart(for: range.start, calendar: calendar)
        let limit = 80
        while cursor < range.end, result.count < limit {
            // 这一周的七个自然日
            var days: [Date] = []
            for offset in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: offset, to: cursor) {
                    days.append(day)
                }
            }
            result.append(makeBucket(date: cursor, days: days, sessions: grouped[cursor] ?? []))
            guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private static func makeBucket(
        date: Date,
        days: [Date],
        sessions: [WorkoutSession]
    ) -> StatsFrequencyBucket {
        StatsFrequencyBucket(
            date: date,
            days: days,
            strengthCount: sessions.filter { $0.kind == .strength }.count,
            cardioCount: sessions.filter { $0.kind == .cardio }.count,
            durationSeconds: sessions.reduce(0) { $0 + $1.durationSeconds }
        )
    }

    /// 某一天所在周的周一 00:00。
    ///
    /// 与 `WeekdayLabel` 的 1 = 周一 … 7 = 周日 保持一致。
    /// 用 `firstWeekday` 交给日历算，不要自己减 `weekday - 1` ——
    /// 不同地区的 `firstWeekday` 不同，硬减会在周日首日地区错一天。
    static func weekStart(for date: Date, calendar: Calendar = .current) -> Date {
        var working = calendar
        working.firstWeekday = 2 // 周一
        let components: Set<Calendar.Component> = [.yearForWeekOfYear, .weekOfYear]
        guard let start = working.date(from: working.dateComponents(components, from: date)) else {
            return calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: start)
    }

    /// 若传入粒度会产生过多柱子，返回降级后的粒度。
    ///
    /// 视图层先调它，再调 `buckets`。这个判断独立出来是为了能在推演里单独验证，
    /// 不必构造真实的训练数组。
    static func effectiveGranularity(
        requested: StatsFrequencyGranularity,
        range: StatsDateRange,
        calendar: Calendar = .current
    ) -> StatsFrequencyGranularity {
        guard requested == .daily else { return .weekly }
        let days = range.dayCount(calendar: calendar)
        return days > maxBuckets ? .weekly : .daily
    }

    /// 图表文字摘要，规格里举的例子就是这种句式。
    static func accessibilitySummary(
        buckets: [StatsFrequencyBucket],
        rangeTitle: String
    ) -> String {
        let active = buckets.filter { !$0.isEmpty }
        let strength = buckets.reduce(0) { $0 + $1.strengthCount }
        let cardio = buckets.reduce(0) { $0 + $1.cardioCount }
        let total = strength + cardio

        guard total > 0 else {
            return "\(rangeTitle)的训练频率图，这个范围内没有训练记录"
        }
        var parts = ["\(rangeTitle)的训练频率图"]
        parts.append("共 \(total) 次训练")
        if strength > 0 { parts.append("力量 \(strength) 次") }
        if cardio > 0 { parts.append("有氧 \(cardio) 次") }
        parts.append("分布在 \(active.count) 个\(buckets.count <= 7 || active.count == 1 ? "日期" : "时间格")上")
        parts.append("最高一格是 \(maxCount(in: buckets)) 次")
        return parts.joined(separator: "，")
    }

    /// 最高的柱子有多高，用于图表纵轴上限。空数据返回 0。
    static func maxCount(in buckets: [StatsFrequencyBucket]) -> Int {
        buckets.map { $0.totalCount }.max() ?? 0
    }
}

// MARK: - 容量趋势

/// 容量趋势图上的一个点。
struct StatsVolumePoint: Identifiable, Equatable {
    /// 该训练日的 00:00
    let date: Date
    /// 当日容量合计
    let volume: Double
    /// 当日贡献容量的训练次数
    let sessionCount: Int
    /// 当日贡献容量最多的动作名（用于 VoiceOver 与点击详情）
    let topExerciseName: String?

    var id: Date { date }

    var axisLabel: String { FormatterKit.monthDaySlash(date) }

    var accessibilityLabel: String {
        var parts = [FormatterKit.shortDate(date), "容量 \(FormatterKit.plainNumber(volume)) 千克"]
        parts.append("\(sessionCount) 次训练")
        if let topExerciseName {
            parts.append("主要来自\(topExerciseName)")
        }
        return parts.joined(separator: "，")
    }
}

/// 容量趋势的筛选维度。
enum StatsVolumeFilter: Equatable, Hashable {
    /// 全部动作
    case all
    /// 按肌群（图标分组）
    case muscle(MuscleIconGroup)
    /// 按单个动作
    case exercise(id: String, name: String)

    /// 稳定的 key，用于缓存
    var cacheKey: String {
        switch self {
        case .all: return "all"
        case .muscle(let group): return "muscle:\(group.rawValue)"
        case .exercise(let id, _): return "exercise:\(id)"
        }
    }

    /// 抽屉里的标题
    var title: String {
        switch self {
        case .all: return "全部动作"
        case .muscle(let group): return group.title
        case .exercise(_, let name): return name
        }
    }

    var isAll: Bool {
        if case .all = self { return true }
        return false
    }
}

/// 容量趋势构建。
enum StatsVolumeBuilder {

    /// 按训练日汇总容量。
    ///
    /// **只产出有容量的日期**：没有训练的日子不进数组。
    /// 这与频率图相反 —— 频率图必须补空缺日期让时间轴连续，
    /// 而容量折线若在没练的日子插一个 0，折线会掉到横轴再弹回来，
    /// 读起来像「那天练了但一点没举起来」。规格也明确要求
    /// 「无容量数据时显示空状态，而非绘制零值折线」。
    static func points(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        filter: StatsVolumeFilter = .all,
        exerciseLookup: [String: ExerciseLibraryItem] = [:],
        calendar: Calendar = .current
    ) -> [StatsVolumePoint] {
        var volumeByDay: [Date: Double] = [:]
        var countByDay: [Date: Int] = [:]
        var topByDay: [Date: (name: String, volume: Double)] = [:]

        for session in sessions where session.isFinished && range.contains(session.startedAt) {
            let day = calendar.startOfDay(for: session.startedAt)
            var sessionContributed = false

            for entry in session.entries where entry.isCompleted {
                guard filter.accepts(entry: entry, lookup: exerciseLookup) else { continue }
                let volume = entry.volume
                // 热身组 volume 恒为 0，这里跳过它们，
                // 否则「当天有记录」会被判定成真，从而在图上留下一个 0 值点。
                guard volume > 0 else { continue }

                volumeByDay[day, default: 0] += volume
                sessionContributed = true

                let name = StatsExerciseNaming.displayName(for: entry.exerciseID, lookup: exerciseLookup)
                let current = topByDay[day]
                if current == nil || volume > current!.volume {
                    topByDay[day] = (name, volume)
                }
            }

            if sessionContributed {
                countByDay[day, default: 0] += 1
            }
        }

        return volumeByDay.keys.sorted().map { day in
            StatsVolumePoint(
                date: day,
                volume: volumeByDay[day] ?? 0,
                sessionCount: countByDay[day] ?? 0,
                topExerciseName: topByDay[day]?.name
            )
        }
    }

    /// 图表文字摘要
    static func accessibilitySummary(points: [StatsVolumePoint], rangeTitle: String) -> String {
        guard !points.isEmpty else {
            return "\(rangeTitle)的容量趋势图，这个范围内没有容量数据"
        }
        let total = points.reduce(0) { $0 + $1.volume }
        let peak = points.max { $0.volume < $1.volume }
        var parts = ["\(rangeTitle)的容量趋势图"]
        parts.append("共 \(points.count) 个训练日")
        parts.append("总容量 \(FormatterKit.plainNumber(total)) 千克")
        if let peak {
            parts.append("最高一天是 \(FormatterKit.shortDate(peak.date))，\(FormatterKit.plainNumber(peak.volume)) 千克")
        }
        return parts.joined(separator: "，")
    }

    /// 可选的筛选维度列表。只列出**实际出现过**的肌群与动作，
    /// 否则抽屉里会堆满用户从没练过的条目。
    static func availableFilters(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        exerciseLookup: [String: ExerciseLibraryItem],
        maxExercises: Int = 12,
        calendar: Calendar = .current
    ) -> [StatsVolumeFilter] {
        var muscleGroups: Set<MuscleIconGroup> = []
        // 动作按「出现次数」排序后再截断，保证列表里是高价值的那些
        var exerciseUseCount: [String: Int] = [:]

        for session in sessions where session.isFinished && range.contains(session.startedAt) {
            for entry in session.entries where entry.isCompleted && !entry.isWarmup {
                guard entry.volume > 0 else { continue }
                exerciseUseCount[entry.exerciseID, default: 0] += 1
                let muscle = exerciseLookup[entry.exerciseID]?.primaryMuscleText ?? ""
                muscleGroups.insert(MuscleIconGroup.of(muscle: muscle))
            }
        }

        var result: [StatsVolumeFilter] = [.all]

        // 肌群按固定枚举顺序输出，不按哈希顺序 ——
        // 后者每次运行都可能不同，抽屉里的条目会跳来跳去。
        for group in MuscleIconGroup.allCases where muscleGroups.contains(group) {
            result.append(.muscle(group))
        }

        let topExercises = exerciseUseCount
            .sorted { lhs, rhs in
                // 组数相同时按 id 升序，保证顺序稳定
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(maxExercises)

        for (id, _) in topExercises {
            result.append(.exercise(id: id, name: StatsExerciseNaming.displayName(for: id, lookup: exerciseLookup)))
        }

        return result
    }
}

extension StatsVolumeFilter {
    /// 这一组是否计入当前筛选。
    func accepts(entry: SetEntry, lookup: [String: ExerciseLibraryItem]) -> Bool {
        switch self {
        case .all:
            return true
        case .muscle(let group):
            let muscle = lookup[entry.exerciseID]?.primaryMuscleText ?? ""
            return MuscleIconGroup.of(muscle: muscle) == group
        case .exercise(let id, _):
            return entry.exerciseID == id
        }
    }
}

// MARK: - 常练动作

/// 「常练动作」列表里的一行。
struct TopExerciseStat: Identifiable, Equatable {
    let exerciseID: String
    let displayName: String
    let primaryMuscle: String
    let iconGroup: MuscleIconGroup
    /// 累计完成组数（不含热身）
    let setCount: Int
    /// 累计容量
    let volume: Double
    /// 该动作涉及的最早一次训练时间，用于子页
    let firstTrainedAt: Date?
    /// 该动作涉及的最后一次训练时间
    let lastTrainedAt: Date?

    var id: String { exerciseID }

    var setCountText: String { "\(setCount) 组" }
    var volumeText: String { "容量 \(FormatterKit.plainNumber(volume)) kg" }

    var accessibilityLabel: String {
        "\(displayName)，\(primaryMuscle)，完成 \(setCount) 组，累计容量 \(FormatterKit.plainNumber(volume)) 千克"
    }
}

enum StatsTopExerciseBuilder {

    /// 默认取前几名。规格指定前 5。
    static let defaultLimit = 5

    /// 按完成组数排序取前 N。
    ///
    /// 排序是**稳定的**：组数相同时按累计容量降序，容量也相同时按 exerciseID 升序。
    /// 只按组数排的话，并列的动作顺序取决于字典遍历顺序，
    /// 每次进页面列表都可能换位置，点错了还会跳到别的动作。
    static func top(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        exerciseLookup: [String: ExerciseLibraryItem],
        limit: Int = defaultLimit,
        calendar: Calendar = .current
    ) -> [TopExerciseStat] {
        var setCount: [String: Int] = [:]
        var volume: [String: Double] = [:]
        var firstAt: [String: Date] = [:]
        var lastAt: [String: Date] = [:]

        for session in sessions where session.isFinished && range.contains(session.startedAt) {
            // 同一个动作在一次训练里可能出现两次（替换动作后会出现两张卡），
            // 按 session 去重计数只影响「涉及训练次数」，不影响组数与容量。
            for entry in session.entries where entry.isCompleted && !entry.isWarmup {
                setCount[entry.exerciseID, default: 0] += 1
                volume[entry.exerciseID, default: 0] += entry.volume

                let startedAt = session.startedAt
                if firstAt[entry.exerciseID] == nil || startedAt < firstAt[entry.exerciseID]! {
                    firstAt[entry.exerciseID] = startedAt
                }
                if lastAt[entry.exerciseID] == nil || startedAt > lastAt[entry.exerciseID]! {
                    lastAt[entry.exerciseID] = startedAt
                }
            }
        }

        let sorted = setCount.keys.sorted { lhs, rhs in
            let lhsSets = setCount[lhs] ?? 0
            let rhsSets = setCount[rhs] ?? 0
            if lhsSets != rhsSets { return lhsSets > rhsSets }
            let lhsVolume = volume[lhs] ?? 0
            let rhsVolume = volume[rhs] ?? 0
            if lhsVolume != rhsVolume { return lhsVolume > rhsVolume }
            return lhs < rhs
        }

        return sorted.prefix(max(0, limit)).map { id -> TopExerciseStat in
            let item = exerciseLookup[id]
            return TopExerciseStat(
                exerciseID: id,
                displayName: StatsExerciseNaming.displayName(for: id, lookup: exerciseLookup),
                primaryMuscle: item?.primaryMuscleText ?? "",
                iconGroup: MuscleIconGroup.of(muscle: item?.primaryMuscleText ?? ""),
                setCount: setCount[id] ?? 0,
                volume: volume[id] ?? 0,
                firstTrainedAt: firstAt[id],
                lastTrainedAt: lastAt[id]
            )
        }
    }

    /// 图表文字摘要
    static func accessibilitySummary(items: [TopExerciseStat], rangeTitle: String) -> String {
        guard !items.isEmpty else {
            return "\(rangeTitle)没有完成的动作记录"
        }
        let names = items.prefix(3).map { "\($0.displayName) \($0.setCount) 组" }
        return "\(rangeTitle)最常练的 \(items.count) 个动作：\(names.joined(separator: "、"))"
    }
}

// MARK: - 肌群分布

/// 「训练部位分布」的一行。
struct MuscleDistributionRow: Identifiable, Equatable {
    let group: MuscleIconGroup
    let setCount: Int
    /// 0…1 的占比
    let ratio: Double

    var id: String { group.rawValue }
    var title: String { group.title }
    var percentText: String { "\(Int((ratio * 100).rounded()))%" }
    var setCountText: String { "\(setCount) 组" }

    /// 代表色。分布条是这套配色里唯一出现第二、第三种颜色的地方，
    /// 因为横向进度条必须能区分相邻行，全靠荧光绿深浅在深色底上分不开。
    var colorHex: UInt32 { MuscleDistributionPalette.hex(for: group) }

    var accessibilityLabel: String {
        "\(title)，\(setCount) 组，占比 \(percentText)"
    }
}

/// 肌群代表色。
///
/// 刻意压低饱和度并避开荧光绿：荧光绿是「当前选中」的语义，
/// 若某个肌群也用荧光绿，用户会分不清哪一行是选中的。
enum MuscleDistributionPalette {

    /// 固定映射。同一肌群在任何页面都是同一个颜色。
    static func hex(for group: MuscleIconGroup) -> UInt32 {
        switch group {
        case .chest: return 0xE8776B
        case .back: return 0x5B9BD5
        case .shoulder: return 0xE0A85C
        case .arm: return 0xA98BDB
        case .core: return 0x6FC3A8
        case .leg: return 0x9BAE5C
        case .glute: return 0xD98BB0
        case .calf: return 0x7FB3C8
        case .cardio: return 0x3ED8C6
        case .neck: return 0xB0A08C
        case .other: return 0x8A8A8F
        }
    }
}

enum StatsMuscleDistributionBuilder {

    /// 按主肌群统计完成组数。
    ///
    /// 只算已完成的**正式组**（不含热身）：这一卡的语义是「练了哪些部位多少组」，
    /// 热身组会把每个部位都垫高一点，反而看不出重点。
    static func rows(
        sessions: [WorkoutSession],
        range: StatsDateRange,
        exerciseLookup: [String: ExerciseLibraryItem],
        calendar: Calendar = .current
    ) -> [MuscleDistributionRow] {
        var countByGroup: [MuscleIconGroup: Int] = [:]

        for session in sessions where session.isFinished && range.contains(session.startedAt) {
            for entry in session.entries where entry.isCompleted && !entry.isWarmup {
                let muscle = exerciseLookup[entry.exerciseID]?.primaryMuscleText ?? ""
                let group = MuscleIconGroup.of(muscle: muscle)
                countByGroup[group, default: 0] += 1
            }
        }

        let total = countByGroup.values.reduce(0, +)
        // 组数为 0 时整体返回空数组，让视图显示空状态而不是一排 0% 的条。
        guard total > 0 else { return [] }

        // 按固定枚举顺序输出，不按组数排序：
        // 顺序固定后，换时间范围时同一部位始终在同一行，
        // 用户能直接对比两个范围的差异，而不是重新认一遍列表。
        return MuscleIconGroup.allCases.compactMap { group in
            guard let count = countByGroup[group], count > 0 else { return nil }
            return MuscleDistributionRow(
                group: group,
                setCount: count,
                ratio: Double(count) / Double(total)
            )
        }
    }

    /// 图表文字摘要
    static func accessibilitySummary(rows: [MuscleDistributionRow], rangeTitle: String) -> String {
        guard !rows.isEmpty else {
            return "\(rangeTitle)没有完成的组数，无法统计部位分布"
        }
        let top = rows.prefix(3).map { "\($0.title) \($0.percentText)" }
        return "\(rangeTitle)训练部位分布，前三位：\(top.joined(separator: "、"))"
    }
}

// MARK: - 动作名解析

/// 动作 id → 展示名。与页面 09 用同一套三级兜底口径。
enum StatsExerciseNaming {

    /// 别名 → 原名 → id 本身 → 「未知动作」。
    ///
    /// 最后一级不可省：动作被删除后历史记录仍要能显示。
    /// 显示空白会让整行看起来像渲染失败。
    static func displayName(
        for exerciseID: String,
        lookup: [String: ExerciseLibraryItem]
    ) -> String {
        if let item = lookup[exerciseID] {
            let display = item.displayName
            if !display.isEmpty { return display }
            if !item.name.isEmpty { return item.name }
        }
        let trimmed = exerciseID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知动作" : trimmed
    }
}

// MARK: - 缓存

/// 统计结果的缓存。
///
/// 规格要求「采用日期范围缓存避免每次滚动重复计算」。
/// 这里用一个 key 只存**一份**结果，而不是 LRU 字典：
/// 统计页同时只有一个时间范围 + 一个筛选组合是活跃的，
/// 用户换范围时旧结果已经没用了，存多了只是把内存留给废数据。
///
/// 缓存失效靠 `version` 递增：数据变化后 `invalidate()` 一下，
/// 下一个 key 查询自然落空。不用时间戳做 TTL ——
/// 本地数据不会自己变，只有用户操作会改它，显式失效比超时更准。
struct StatsCache<Value> {

    private struct Entry {
        let key: String
        let value: Value
    }

    private var entry: Entry?

    /// 数据版本。任何写入后递增它即可让全部缓存失效。
    private(set) var version: Int = 0

    init() {}

    /// 取缓存。key 或 version 不匹配时返回 nil。
    func value(forKey key: String) -> Value? {
        guard let entry, entry.key == key else { return nil }
        return entry.value
    }

    /// 写缓存
    mutating func store(_ value: Value, forKey key: String) {
        entry = Entry(key: key, value: value)
    }

    /// 使缓存失效。数据写入后调用。
    mutating func invalidate() {
        entry = nil
        version += 1
    }

    /// 当前是否有缓存
    var isEmpty: Bool { entry == nil }
}

/// 统计页的缓存键。
///
/// 把「范围 + 筛选」拼成一个字符串。
/// 范围用**起止时间戳**而不是种类：自定义范围内改了日期但种类仍是 custom，
/// 只用种类做 key 会命中旧缓存，图表不动。
enum StatsCacheKey {

    static func key(range: StatsDateRange, filter: StatsVolumeFilter) -> String {
        let start = Int(range.start.timeIntervalSince1970)
        let end = Int(range.end.timeIntervalSince1970)
        return "\(range.kind.rawValue):\(start)-\(end):\(filter.cacheKey)"
    }

    /// 只按范围缓存（摘要 / 频率 / 常练动作 / 分布四张卡共用）
    static func rangeKey(_ range: StatsDateRange) -> String {
        let start = Int(range.start.timeIntervalSince1970)
        let end = Int(range.end.timeIntervalSince1970)
        return "\(range.kind.rawValue):\(start)-\(end)"
    }
}

// MARK: - 动作历史趋势（页面 10 子页）

/// 单个月份的聚合结果。
///
/// 与 `StatsVolumePoint` 的关键区别：**这里保留空月份**。
/// 容量趋势图要去掉没练的日子（否则横轴上全是零），
/// 但「这个动作我最近一年练得怎么样」这个问题里，
/// 「三月没练」本身就是答案的一部分，抹掉空月会让趋势看起来连续得虚假。
struct ExerciseTrendPoint: Identifiable, Equatable {
    let monthStart: Date
    /// 该动作在这个月完成的正式组数（不含热身）
    let setCount: Int
    /// 该动作在这个月的累计容量
    let volume: Double
    /// 这个月里的最高单组重量，0 表示该月没练
    let topWeight: Double
    /// 该月包含的训练次数
    let sessionCount: Int

    /// id 用月初时间戳：同一个月只会有一个点
    var id: Double { monthStart.timeIntervalSince1970 }

    var isEmpty: Bool { setCount == 0 }

    /// 「2026年3月」，趋势行的标签
    var axisLabel: String {
        let c = Calendar.current.dateComponents([.year, .month], from: monthStart)
        return "\(c.year ?? 0)年\(c.month ?? 0)月"
    }

    /// 「3月」，空间紧的时候用
    var shortLabel: String {
        "\(Calendar.current.component(.month, from: monthStart))月"
    }

    var detailText: String {
        guard !isEmpty else { return "未训练" }
        return "\(setCount) 组 · \(FormatterKit.plainNumber(volume)) kg"
    }

    var accessibilityLabel: String {
        guard !isEmpty else { return "\(shortLabel)未训练" }
        return "\(shortLabel)，\(setCount) 组，容量 \(FormatterKit.plainNumber(volume)) 公斤"
    }
}

/// 某一次训练里该动作的小结，用于「最近记录」列表
struct ExerciseTrendSessionSummary: Identifiable, Equatable {
    let sessionID: UUID
    let date: Date
    let setCount: Int
    let volume: Double
    let topWeight: Double

    var id: UUID { sessionID }
}

/// 趋势页头部的汇总
struct ExerciseTrendSummary: Equatable {

    let exerciseID: String
    let fallbackName: String
    let points: [ExerciseTrendPoint]
    let recent: [ExerciseTrendSessionSummary]

    /// 有记录的月份数（不是自然月总数）
    var activeMonthCount: Int { points.filter { !$0.isEmpty }.count }

    var totalSetCount: Int { points.reduce(0) { $0 + $1.setCount } }

    var totalVolume: Double { points.reduce(0) { $0 + $1.volume } }

    /// 最高单组重量。没有任何记录时为 nil ——
    /// 显示「0 kg」会让用户以为自己举过 0 公斤。
    var bestWeight: Double? {
        let values = points.map { $0.topWeight }.filter { $0 > 0 }
        return values.isEmpty ? nil : values.max()
    }

    var displayName: String {
        let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知动作" : trimmed
    }

    var bestWeightText: String {
        guard let best = bestWeight else { return "—" }
        return "\(FormatterKit.plainNumber(best)) kg"
    }

    var accessibilityText: String {
        guard activeMonthCount > 0 else {
            return "\(displayName)，最近 12 个月没有训练记录。"
        }
        var parts = ["\(displayName)，最近 12 个月中 \(activeMonthCount) 个月有训练"]
        parts.append("共 \(totalSetCount) 组")
        parts.append("累计容量 \(FormatterKit.plainNumber(totalVolume)) 公斤")
        if let best = bestWeight {
            parts.append("最高单组 \(FormatterKit.plainNumber(best)) 公斤")
        }
        return parts.joined(separator: "，") + "。"
    }
}

/// 动作历史趋势的聚合。
enum ExerciseTrendBuilder {

    /// 默认看最近 12 个月。
    ///
    /// 12 而不是 6：这个页面的用途是看长期进步，半年数据在很多训练频率下
    /// 只有十几条记录，抖动太大看不出趋势。12 个月的横轴也更像一个「年度回顾」。
    static let defaultMonths = 12

    /// 按月聚合。返回的数组**长度恒等于 `months`**，含空月份。
    ///
    /// 顺序是从旧到新 —— 与折线图、进度条的阅读方向一致。
    /// 只有一个月在范围内时也照常返回一条，调用方不需要为「只有一个点」写特例。
    static func monthlyPoints(
        sessions: [WorkoutSession],
        exerciseID: String,
        months: Int = defaultMonths,
        now: Date,
        calendar: Calendar
    ) -> [ExerciseTrendPoint] {
        guard months > 0 else { return [] }
        // 防呆上限：万一有人传了 1200，别把主线程卡住
        let safeMonths = min(months, 60)

        guard let currentMonthStart = firstDayOfMonth(for: now, calendar: calendar) else {
            return []
        }

        // 先把每个月的月初算出来，再逐月填。
        // 不用「先聚合再补空月」：后者在月份跨越年份时容易把 12 月和 1 月排反。
        var monthStarts: [Date] = []
        for offset in stride(from: safeMonths - 1, through: 0, by: -1) {
            guard let start = calendar.date(
                byAdding: .month,
                value: -offset,
                to: currentMonthStart
            ) else { continue }
            monthStarts.append(start)
        }

        // 只扫一遍原始记录，按月份归类
        var setsByMonth: [Double: Int] = [:]
        var volumeByMonth: [Double: Double] = [:]
        var topWeightByMonth: [Double: Double] = [:]
        var sessionsByMonth: [Double: Set<UUID>] = [:]

        for session in sessions where session.isFinished {
            // 一条记录只归入一个月份（按 startedAt），不做跨月拆分
            guard let monthStart = firstDayOfMonth(for: session.startedAt, calendar: calendar) else {
                continue
            }
            let key = monthStart.timeIntervalSince1970
            guard monthStarts.contains(where: { $0.timeIntervalSince1970 == key }) else {
                continue
            }

            var touched = false
            for entry in session.entries {
                // 与全站口径一致：热身组不算组数也不算容量
                guard entry.exerciseID == exerciseID,
                      entry.completedAt != nil,
                      !entry.isWarmup
                else { continue }

                touched = true
                setsByMonth[key, default: 0] += 1
                volumeByMonth[key, default: 0] += entry.volume
                topWeightByMonth[key] = max(topWeightByMonth[key] ?? 0, entry.weight)
            }

            if touched {
                sessionsByMonth[key, default: []].insert(session.id)
            }
        }

        return monthStarts.map { monthStart in
            let key = monthStart.timeIntervalSince1970
            return ExerciseTrendPoint(
                monthStart: monthStart,
                setCount: setsByMonth[key] ?? 0,
                volume: volumeByMonth[key] ?? 0,
                topWeight: topWeightByMonth[key] ?? 0,
                sessionCount: sessionsByMonth[key]?.count ?? 0
            )
        }
    }

    /// 该动作最近若干次完成的记录，倒序（最近的在前）。
    static func recentSessions(
        sessions: [WorkoutSession],
        exerciseID: String,
        limit: Int = 5,
        calendar: Calendar
    ) -> [ExerciseTrendSessionSummary] {
        guard limit > 0 else { return [] }

        var result: [ExerciseTrendSessionSummary] = []

        for session in sessions where session.isFinished {
            var setCount = 0
            var volume: Double = 0
            var topWeight: Double = 0

            for entry in session.entries {
                guard entry.exerciseID == exerciseID,
                      entry.completedAt != nil,
                      !entry.isWarmup
                else { continue }
                setCount += 1
                volume += entry.volume
                topWeight = max(topWeight, entry.weight)
            }

            guard setCount > 0 else { continue }

            result.append(
                ExerciseTrendSessionSummary(
                    sessionID: session.id,
                    date: session.startedAt,
                    setCount: setCount,
                    volume: volume,
                    topWeight: topWeight
                )
            )

            // 提前退出：`fetchRecentSessions` 已按倒序返回，
            // 但排序契约不该在这里假设两次，显式取满就停更省。
            if result.count >= limit { break }
        }

        return result.sorted { $0.date > $1.date }
    }

    /// 某个月的月初。用 `dateComponents` 而不是减时间戳：
    /// 减 86400 在夏令时地区会漂到上个月最后一天 23:00。
    private static func firstDayOfMonth(for date: Date, calendar: Calendar) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components)
    }
}
