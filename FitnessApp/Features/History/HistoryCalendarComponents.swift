//
//  HistoryCalendarComponents.swift
//  历史页的日历与当日时间线组件。
//
//  全部为无状态展示组件，数据与回调由 HistoryView 传入，
//  这样日历本身不持有任何加载状态，月份切换时只重绘不重建。
//

import SwiftUI

// MARK: - 月份切换

/// 「上个月 / 当前月份 / 下个月」
///
/// 中间是当前所在月份标题，同时兼作「回到本月」按钮：
/// 用户翻出去几个月后，点标题一次就能跳回来，不必逐月翻。
struct MonthSwitcher: View {
    let title: String
    let isCurrentMonth: Bool
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.item) {
            arrowButton(
                symbol: "chevron.left",
                label: "上个月",
                action: onPrevious
            )

            Button(action: onToday) {
                VStack(spacing: 2) {
                    Text(title)
                        .font(DS.Typography.cardTitle)
                        .foregroundColor(DS.Palette.textPrimary)
                    Text(isCurrentMonth ? "本月" : "回到本月")
                        .font(DS.Typography.caption2)
                        .foregroundColor(
                            isCurrentMonth ? DS.Palette.textTertiary : DS.Palette.accent
                        )
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrentMonth)
            .accessibilityLabel("当前月份 \(title)")
            .accessibilityHint(isCurrentMonth ? "" : "双击回到本月")

            arrowButton(
                symbol: "chevron.right",
                label: "下个月",
                action: onNext
            )
        }
    }

    private func arrowButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundColor(DS.Palette.textSecondary)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(DS.Palette.surfaceElevated)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - 星期表头

/// 周一至周日表头。与月历同宽，所以复用同一套 7 列网格。
struct WeekdayHeaderRow: View {
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 0),
        count: HistoryCalendar.dayCountInWeek
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(WeekdayLabel.all, id: \.self) { day in
                Text(WeekdayLabel.symbol(day))
                    .font(DS.Typography.caption2)
                    .foregroundColor(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 日期标记点

/// 日期下方的标记点行。
///
/// 固定高度：有无标记时单元格高度必须一致，否则日历会在翻月时抖动。
struct DayMarkerDots: View {
    let markers: [DayMarker]

    private var visible: [DayMarker] {
        Array(markers.prefix(DS.Size.calendarMarkerMaxDots))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(visible.enumerated()), id: \.offset) { _, marker in
                Circle()
                    .fill(Self.color(for: marker))
                    .frame(
                        width: DS.Size.calendarMarkerDot,
                        height: DS.Size.calendarMarkerDot
                    )
            }
        }
        .frame(height: DS.Size.calendarMarkerRowHeight)
    }

    static func color(for marker: DayMarker) -> Color {
        switch marker {
        case .strength: return DS.Palette.accent
        case .cardio: return DS.Palette.cardio
        case .rest: return DS.Palette.restMarker
        }
    }
}

// MARK: - 日期单元格

/// 日历里的单个日期。
///
/// 三层叠加顺序：今天描边（最外）→ 选中荧光绿圆 → 日期数字 → 标记点。
/// 今天与选中态可以同时成立：今天被选中时外圈描边仍在，只是被绿圆盖住内侧，
/// 所以两个圆故意做成不同直径（42 与 36），留出 3pt 可见的描边宽度。
struct DayCell: View {
    let entry: HistoryDayEntry
    let isSelected: Bool
    let isToday: Bool
    let isInCurrentMonth: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    private var dayNumber: String {
        let day = Calendar.current.component(.day, from: entry.day)
        return "\(day)"
    }

    private var numberColor: Color {
        if isSelected { return DS.Palette.onAccent }
        if !isInCurrentMonth { return DS.Palette.textTertiary.opacity(0.5) }
        if isToday { return DS.Palette.accent }
        return DS.Palette.textPrimary
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                ZStack {
                    // 今天的细描边，位于最外层
                    if isToday {
                        Circle()
                            .stroke(DS.Palette.accent, lineWidth: DS.Size.calendarTodayStroke)
                            .frame(
                                width: DS.Size.calendarTodayRing,
                                height: DS.Size.calendarTodayRing
                            )
                    }
                    // 选中态的荧光绿实心圆
                    if isSelected {
                        Circle()
                            .fill(DS.Palette.accent)
                            .frame(
                                width: DS.Size.calendarSelectionCircle,
                                height: DS.Size.calendarSelectionCircle
                            )
                    }
                    Text(dayNumber)
                        .font(DS.Typography.callout.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(numberColor)
                        .monospacedDigit()
                }
                .frame(height: DS.Size.calendarCellHeight - DS.Size.calendarMarkerRowHeight)

                DayMarkerDots(markers: entry.markers)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                Haptics.medium()
                onLongPress()
            }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(
            entry.accessibilityLabel(
                isSelected: isSelected,
                isToday: isToday,
                formatter: FormatterKit.monthDayWeekday
            )
        )        .accessibilityHint("长按可新建训练或标记休息日")
    }
}

// MARK: - 月历

/// 完整的月历：星期表头 + 6×7 日期网格。
struct MonthGridView: View {
    let month: Date
    let index: [Date: HistoryDayEntry]
    let selectedDate: Date
    let onSelect: (Date) -> Void
    let onLongPressDate: (Date) -> Void

    private let calendar = Calendar.current

    private var gridDays: [Date?] {
        HistoryCalendar.gridDays(for: month, calendar: calendar)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.tight) {
            WeekdayHeaderRow()

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 0),
                    count: HistoryCalendar.dayCountInWeek
                ),
                spacing: 2
            ) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        DayCell(
                            entry: HistoryDayIndex.entry(
                                for: day,
                                in: index,
                                calendar: calendar
                            ),
                            isSelected: HistoryCalendar.isSameDay(
                                day, selectedDate, calendar: calendar
                            ),
                            isToday: HistoryCalendar.isSameDay(
                                day, .now, calendar: calendar
                            ),
                            isInCurrentMonth: HistoryCalendar.month(
                                month, contains: day, calendar: calendar
                            ),
                            onTap: { onSelect(day) },
                            onLongPress: { onLongPressDate(day) }
                        )
                    } else {
                        // 占位格：保持网格对齐，不参与交互
                        Color.clear
                            .frame(height: DS.Size.calendarCellHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .animation(DS.Motion.tabSwitch, value: month)
    }
}

// MARK: - 当日时间线

/// 选中日期下的时间线。
///
/// 空状态不占大块空白：规格要求「不显示空白大区域」，
/// 所以这里用一条紧凑提示 + 按钮，而不是居中的大插画。
struct DayTimelineSection: View {
    let entry: HistoryDayEntry
    let onOpenSession: (WorkoutSession) -> Void
    let onAddTraining: () -> Void
    let onEditTitle: (WorkoutSession) -> Void
    let onDuplicate: (WorkoutSession) -> Void
    let onDelete: (WorkoutSession) -> Void
    let isRestDay: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            header

            if entry.isEmpty {
                emptyState
            } else {
                ForEach(entry.sessions, id: \.id) { session in
                    HistorySessionCard(
                        session: session,
                        onTap: { onOpenSession(session) },
                        onEditTitle: { onEditTitle(session) },
                        onDuplicate: { onDuplicate(session) },
                        onDelete: { onDelete(session) }
                    )
                }

                if entry.sessions.isEmpty && isRestDay {
                    restDayOnlyRow
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Text(FormatterKit.fullDate(entry.day))
                .font(DS.Typography.cardTitle)
                .foregroundColor(DS.Palette.textPrimary)
            Spacer()
            if !entry.sessions.isEmpty {
                Text("\(entry.sessions.count) 次训练")
                    .font(DS.Typography.footnote)
                    .foregroundColor(DS.Palette.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        CardContainer(padding: DS.Spacing.card) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "calendar.badge.minus")
                        .font(.body)
                        .foregroundColor(DS.Palette.textTertiary)
                    Text("当天没有训练记录")
                        .font(DS.Typography.body)
                        .foregroundColor(DS.Palette.textSecondary)
                }
                Button(action: onAddTraining) {
                    Text("新增训练")
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundColor(DS.Palette.onAccent)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(
                            Capsule().fill(DS.Palette.accent)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("为这一天新增训练")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 只标了休息日、没有训练时的说明行
    private var restDayOnlyRow: some View {
        CardContainer(padding: DS.Spacing.card) {
            HStack(spacing: DS.Spacing.tight) {
                Circle()
                    .fill(DS.Palette.restMarker)
                    .frame(
                        width: DS.Size.calendarMarkerDot,
                        height: DS.Size.calendarMarkerDot
                    )
                Text("已标记为休息日")
                    .font(DS.Typography.body)
                    .foregroundColor(DS.Palette.textSecondary)
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 训练卡片

/// 当日时间线里的一张训练卡。
///
/// 力量显示「组数 · 容量」，有氧显示「距离 · 时长」——与 `summaryText` 的分支一致，
/// 所以这里直接复用它，不在视图层重新拼一遍文案。
struct HistorySessionCard: View {
    let session: WorkoutSession
    let onTap: () -> Void
    let onEditTitle: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    private var kindColor: Color {
        session.kind == .cardio ? DS.Palette.cardio : DS.Palette.accent
    }

    var body: some View {
        Button(action: onTap) {
            CardContainer(padding: DS.Spacing.card) {
                HStack(alignment: .top, spacing: DS.Spacing.item) {
                    // 左侧色条标识类型
                    Capsule()
                        .fill(kindColor)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                        HStack(spacing: DS.Spacing.tight) {
                            Text(session.name)
                                .font(DS.Typography.cardTitle)
                                .foregroundColor(DS.Palette.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            kindBadge
                        }

                        Text(session.summaryText)
                            .font(DS.Typography.footnote)
                            .foregroundColor(DS.Palette.textSecondary)
                            .lineLimit(2)

                        HStack(spacing: DS.Spacing.item) {
                            MetaLabel(
                                text: FormatterKit.duration(seconds: session.durationSeconds),
                                icon: "clock"
                            )
                            if session.kind == .strength && session.completedSetCount > 0 {
                                MetaLabel(
                                    text: "\(session.completedSetCount) 组",
                                    icon: "checkmark.circle"
                                )
                            }
                            if session.kind == .cardio, let meters = session.distanceMeters, meters > 0 {
                                MetaLabel(
                                    text: FormatterKit.distance(meters: meters),
                                    icon: "figure.run"
                                )
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button {
                onEditTitle()
            } label: {
                Label("编辑训练标题", systemImage: "pencil")
            }
            Button {
                onDuplicate()
            } label: {
                Label("复制为新训练", systemImage: "plus.square.on.square")
            }
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除记录", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("双击查看详情，长按显示更多操作")
    }

    private var kindBadge: some View {
        Text(session.kind.title)
            .font(DS.Typography.caption2)
            .foregroundColor(kindColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(kindColor.opacity(0.14))
            )
    }

    private var accessibilityText: String {
        var parts = [
            session.name,
            session.kind.title,
            "时长 \(FormatterKit.duration(seconds: session.durationSeconds))",
        ]
        if session.kind == .strength {
            parts.append("完成 \(session.completedSetCount) 组")
            parts.append("容量 \(FormatterKit.volume(session.totalVolume))")
        } else if let meters = session.distanceMeters, meters > 0 {
            parts.append("距离 \(FormatterKit.distance(meters: meters))")
        }
        return parts.joined(separator: "，")
    }
}
