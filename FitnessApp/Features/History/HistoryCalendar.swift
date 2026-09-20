//
//  HistoryCalendar.swift
//  历史页的日历数学与日期聚合。
//
//  这一整个文件里没有任何 SwiftUI 类型，全是纯值计算。
//  原因：这里是最容易出错、也最难在真机上看出错的地方——
//  月初偏移、跨年、闰年、月末对齐、本地时区自然日归属。
//  把它写成纯值类型，才能完整移植到 Python 里做断言验证。
//

import Foundation

// MARK: - 日历数学

/// 历史页月历的纯计算逻辑。
///
/// 日历固定「周一在第一列」，与 `WeekdayLabel` 的 1=周一…7=周日 一致。
enum HistoryCalendar {

    /// 单元格数量固定为 6 行 × 7 列。
    ///
    /// 为什么不用 5 行自适应：月历在月份间切换时高度会跳动，
    /// 而下方的时间线是紧跟着日历的，高度一跳整页内容都会位移。
    /// 固定 42 格让日历高度恒定，切换月份时只有格子内容在变。
    static let weekCount = 6
    static let dayCountInWeek = 7
    static let cellCount = weekCount * dayCountInWeek

    /// 给定月份的 1 号是该月第一格之前的空白数量（0…6）。
    ///
    /// 例：2026 年 6 月 1 日是周一 → 0 个空白。
    ///     2026 年 2 月 1 日是周日 → 6 个空白。
    static func leadingBlankCount(for month: Date, calendar: Calendar = .current) -> Int {
        guard let firstDay = firstDayOfMonth(for: month, calendar: calendar) else { return 0 }
        // weekday: 1=周日 … 7=周六，经 normalize 变成 1=周一 … 7=周日
        let normalized = WeekdayLabel.normalize(calendarWeekday: calendar.component(.weekday, from: firstDay))
        return normalized - 1
    }

    /// 该月的天数
    static func dayCount(in month: Date, calendar: Calendar = .current) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return 0 }
        return range.count
    }

    /// 该月 1 号的 00:00
    static func firstDayOfMonth(for month: Date, calendar: Calendar = .current) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: month)
        return calendar.date(from: components)
    }

    /// 把某月展开成 42 个格子。
    ///
    /// 超出该月天数的尾部格子填 `nil`，而不是补下个月的日期：
    /// 补下个月会让用户以为那些格子属于当前月，点进去才发现是别的月，
    /// 也容易在跨月时误触。留白更诚实。
    static func gridDays(for month: Date, calendar: Calendar = .current) -> [Date?] {
        guard let firstDay = firstDayOfMonth(for: month, calendar: calendar) else {
            return Array(repeating: nil, count: cellCount)
        }
        let blanks = leadingBlankCount(for: month, calendar: calendar)
        let total = dayCount(in: month, calendar: calendar)

        var days: [Date?] = []
        days.reserveCapacity(cellCount)
        days.append(contentsOf: Array(repeating: nil, count: blanks))
        for offset in 0..<total {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstDay))
        }

        // 不足 42 格补 nil 到满格
        if days.count < cellCount {
            days.append(contentsOf: Array(repeating: nil, count: cellCount - days.count))
        }
        // 极端情况下（不该发生）超出则截断，保证返回长度恒定
        if days.count > cellCount {
            days = Array(days.prefix(cellCount))
        }
        return days
    }

    /// 月份偏移。用日历做加减而不是 `timeIntervalSince1970` 加减固定秒数，
    /// 否则跨夏令时和不同月份天数会算错。
    static func month(byAdding value: Int, to month: Date, calendar: Calendar = .current) -> Date {
        guard let base = firstDayOfMonth(for: month, calendar: calendar),
              let shifted = calendar.date(byAdding: .month, value: value, to: base)
        else { return month }
        return shifted
    }

    /// 月份标题，如「2026年9月」
    static func title(for month: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: month)
        let year = components.year ?? 0
        let monthValue = components.month ?? 1
        return "\(year)年\(monthValue)月"
    }

    /// 两个时间点是否同一自然日（用户本地时区）
    static func isSameDay(_ lhs: Date, _ rhs: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// 该时间点所在自然日的 00:00
    static func startOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 该月是否包含指定日期所在的自然日
    static func month(_ month: Date, contains date: Date, calendar: Calendar = .current) -> Bool {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return false }
        return interval.contains(date)
    }
}

// MARK: - 自然日聚合

/// 某一天在日历上的标记。
///
/// 顺序即显示顺序：力量在前、有氧居中、休息日在后，
/// 这样同一天的多个点位置稳定，不会因为数据插入顺序而左右横跳。
enum DayMarker: String, Equatable, CaseIterable {
    /// 力量训练
    case strength
    /// 有氧训练
    case cardio
    /// 休息日
    case rest

    /// VoiceOver 朗读用
    var voiceOverText: String {
        switch self {
        case .strength: return "力量训练"
        case .cardio: return "有氧训练"
        case .rest: return "休息日"
        }
    }
}

/// 某一天的全部本地记录，已按自然日归并。
///
/// 这是日历渲染与当日时间线的唯一数据来源，避免视图层自己做日期过滤。
struct HistoryDayEntry: Equatable {
    /// 该自然日的 00:00
    let day: Date
    /// 当天已结束的训练，按开始时间升序
    let sessions: [WorkoutSession]
    /// 当天是否被标记为休息日
    let isRestDay: Bool

    init(day: Date, sessions: [WorkoutSession], isRestDay: Bool) {
        self.day = day
        self.sessions = sessions
        self.isRestDay = isRestDay
    }

    /// 当天是否有任何记录
    var isEmpty: Bool {
        sessions.isEmpty && !isRestDay
    }

    /// 标记点序列。
    ///
    /// 规格要求「同一天有多条记录时使用多个并列点」，
    /// 所以每个训练各出一个点，而不是按类型去重成一个点。
    /// 休息日只出一个灰点。
    var markers: [DayMarker] {
        var result: [DayMarker] = sessions.map { $0.kind == .cardio ? .cardio : .strength }
        if isRestDay { result.append(.rest) }
        return result
    }

    /// 超出上限后被折叠掉的标记数量，用于无障碍朗读里补一句说明
    var hiddenMarkerCount: Int {
        max(0, markers.count - DS.Size.calendarMarkerMaxDots)
    }

    /// 日历日期格的无障碍标签：日期 + 训练数量 + 选中状态
    ///
    /// `formatter` 收的是闭包而不是 `DateFormatter`：调用侧传的是
    /// `FormatterKit.monthDayWeekday` 这样的静态方法，直接传函数引用比
    /// 在每次 body 求值时 new 一个 `DateFormatter` 便宜得多，也不会让
    /// 视图层为了造格式化器而持有可变状态。
    func accessibilityLabel(
        isSelected: Bool,
        isToday: Bool,
        formatter: (Date) -> String
    ) -> String {
        var parts: [String] = [formatter(day)]
        if isToday { parts.append("今天") }
        if sessions.isEmpty {
            if isRestDay {
                parts.append("休息日")
            } else {
                parts.append("无训练记录")
            }
        } else {
            parts.append("\(sessions.count) 次训练")
        }
        if isSelected { parts.append("已选中") }
        return parts.joined(separator: "，")
    }
}

/// 把训练记录与休息日按用户本地时区的自然日归并。
///
/// 用日历做 key 而不是 `Int(date.timeIntervalSince1970 / 86400)`：
/// 后者按 UTC 切天，在东八区会把本地 08:00 之前的训练算到前一天。
enum HistoryDayIndex {

    /// 构建「自然日 → 当日记录」的索引。
    ///
    /// - 只统计已结束的训练。进行中的草稿还没写 `endedAt`，
    ///   把它算进历史会让「训练数」在完成训练后凭空多一次。
    /// - 训练按 `startedAt` 升序，与当日时间线的排列一致。
    static func build(
        sessions: [WorkoutSession],
        restDays: [RestDay],
        calendar: Calendar = .current
    ) -> [Date: HistoryDayEntry] {
        var groupedSessions: [Date: [WorkoutSession]] = [:]
        for session in sessions where session.isFinished {
            let key = calendar.startOfDay(for: session.startedAt)
            groupedSessions[key, default: []].append(session)
        }

        var restKeys: Set<Date> = []
        for restDay in restDays {
            restKeys.insert(calendar.startOfDay(for: restDay.date))
        }

        // 合并两边的 key：只有休息日没有训练的日子也必须出现在索引里
        let allKeys = Set(groupedSessions.keys).union(restKeys)
        var result: [Date: HistoryDayEntry] = [:]
        for key in allKeys {
            let daySessions = (groupedSessions[key] ?? []).sorted { $0.startedAt < $1.startedAt }
            result[key] = HistoryDayEntry(
                day: key,
                sessions: daySessions,
                isRestDay: restKeys.contains(key)
            )
        }
        return result
    }

    /// 取某一天的记录。索引里没有时返回一个空的当天记录，而不是 nil，
    /// 这样视图层不必到处解包。
    static func entry(
        for date: Date,
        in index: [Date: HistoryDayEntry],
        calendar: Calendar = .current
    ) -> HistoryDayEntry {
        let key = calendar.startOfDay(for: date)
        return index[key] ?? HistoryDayEntry(day: key, sessions: [], isRestDay: false)
    }
}

// MARK: - 分隔段

/// 日历下方的分段控件
enum HistorySegment: String, Equatable, CaseIterable, Identifiable {
    case calendar
    case list
    case stats

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "日历"
        case .list: return "列表"
        case .stats: return "统计"
        }
    }
}

// MARK: - 列表分段的分组

/// 列表分段里的一段，按「年 月」聚合
struct HistoryMonthSection: Equatable {
    let title: String
    let sessions: [WorkoutSession]
}

/// 把训练记录按月份倒序分组，组内也按时间倒序。
///
/// 入参需已按 `startedAt` 倒序；这里不重新排序，只在分组后保证组顺序。
enum HistoryListGrouping {

    static func sections(
        from sessions: [WorkoutSession],
        calendar: Calendar = .current
    ) -> [HistoryMonthSection] {
        let finished = sessions
            .filter { $0.isFinished }
            .sorted { $0.startedAt > $1.startedAt }

        var order: [Date] = []
        var buckets: [Date: [WorkoutSession]] = [:]
        for session in finished {
            let components = calendar.dateComponents([.year, .month], from: session.startedAt)
            guard let key = calendar.date(from: components) else { continue }
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(session)
        }

        return order.map { key in
            HistoryMonthSection(
                title: HistoryCalendar.title(for: key, calendar: calendar),
                sessions: buckets[key] ?? []
            )
        }
    }
}
