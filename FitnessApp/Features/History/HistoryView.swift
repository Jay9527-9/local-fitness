//
//  HistoryView.swift
//  历史页：月历 + 当日时间线 + 列表 + 统计入口。
//
//  规格要点（逐条对应）：
//  - 导航栏大标题「历史」+ 右侧新增菜单（4 项）
//  - 月历，周一至周日，今天细描边，选中日荧光绿圆
//  - 标记点：力量荧光绿 / 有氧蓝绿 / 休息日灰，同日多条并列
//  - 点击日期 → 当日时间线，按开始时间升序
//  - 无训练 → 「当天没有训练记录」+「新增训练」，不留大块空白
//  - 分段切换「日历 / 列表 / 统计」
//  - 长按日期 3 项菜单；长按卡片 3 项菜单
//  - 删除二次确认，只删当前本地记录
//  - 月 / 日 / 分段切换用 180–220ms 淡入
//  - 本地时区自然日筛选；动态字体；VoiceOver 朗读日期+训练数+选中态
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class HistoryViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var restDays: [RestDay] = []

    /// 当前显示的月份，默认为本月
    @Published var visibleMonth: Date = HistoryCalendar.startOfDay(for: .now)
    /// 当前选中的日期，默认为今天
    @Published var selectedDate: Date = .now
    @Published var segment: HistorySegment = .calendar

    /// 内部错误提示。删除失败等场景用它弹一条横幅，不打断当前视图。
    @Published var banner: String?

    private let repository: FitnessRepository
    private let calendar = Calendar.current

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            sessions = try repository.fetchRecentSessions(limit: 500)
            restDays = try repository.fetchRestDays()
            loadState = .loaded
        } catch {
            loadState = .failed("历史记录读取失败：\(error.localizedDescription)")
        }
    }

    /// 写入操作后只刷新数据，不回到 loading 态，避免整页闪一下骨架屏
    func reload() async {
        do {
            sessions = try repository.fetchRecentSessions(limit: 500)
            restDays = try repository.fetchRestDays()
            loadState = .loaded
        } catch {
            banner = "刷新失败：\(error.localizedDescription)"
        }
    }

    // MARK: 派生数据

    /// 自然日索引。日历渲染与当日时间线都从它取数，视图层不再自己过滤日期。
    var dayIndex: [Date: HistoryDayEntry] {
        HistoryDayIndex.build(
            sessions: sessions,
            restDays: restDays,
            calendar: calendar
        )
    }

    /// 当前显示月份的标题
    var monthTitle: String {
        HistoryCalendar.title(for: visibleMonth, calendar: calendar)
    }

    /// 当前显示的是否为真实本月
    var isCurrentMonth: Bool {
        HistoryCalendar.month(visibleMonth, contains: .now, calendar: calendar)
    }

    /// 选中日期的记录
    var selectedEntry: HistoryDayEntry {
        HistoryDayIndex.entry(for: selectedDate, in: dayIndex, calendar: calendar)
    }

    /// 列表分段的分组
    var monthSections: [HistoryMonthSection] {
        HistoryListGrouping.sections(from: sessions, calendar: calendar)
    }

    var finishedCount: Int {
        sessions.filter { $0.isFinished }.count
    }

    var totalVolume: Double {
        sessions.filter { $0.isFinished && $0.kind == .strength }
            .reduce(0) { $0 + $1.totalVolume }
    }

    var totalDistanceKm: Double {
        sessions.filter { $0.isFinished && $0.kind == .cardio }
            .reduce(0) { $0 + $1.distanceKilometers }
    }

    // MARK: 月份与日期切换

    func goToPreviousMonth() {
        visibleMonth = HistoryCalendar.month(byAdding: -1, to: visibleMonth, calendar: calendar)
    }

    func goToNextMonth() {
        visibleMonth = HistoryCalendar.month(byAdding: 1, to: visibleMonth, calendar: calendar)
    }

    func goToCurrentMonth() {
        visibleMonth = HistoryCalendar.startOfDay(for: .now)
        selectedDate = .now
    }

    /// 选中某天。若该天不在当前显示的月份里，顺带把日历切过去，
    /// 否则用户点了别的月的日期但日历没动，会觉得点击没生效。
    ///
    /// 两处顺序与取值都很讲究：
    /// - 先把月份切过去再改选中日期。反过来的话，在月份已经确定的视图里
    ///   会先按旧月份算一次「是否有选中日期」，那一帧的日历是错的。
    /// - `visibleMonth` 统一存 `startOfDay` 的形态，与 `goToPreviousMonth()`
    ///   写入的值同构。曾写成该月 1 号，导致 `visibleMonth` 在
    ///   「某天的 00:00」和「1 号的 00:00」两种形态之间漂移，
    ///   而 `MonthGridView` 的 `.animation(value: month)` 正是比较这个 Date。
    func select(_ date: Date) {
        if !HistoryCalendar.month(visibleMonth, contains: date, calendar: calendar) {
            visibleMonth = HistoryCalendar.startOfDay(for: date, calendar: calendar)
        }
        selectedDate = date
    }

    // MARK: 写入

    /// 新建一条训练草稿并返回 id，由调用方负责导航。
    /// 力量与有氧用同一条路径，只有 `kind` 不同。
    ///
    /// 补记过去的日期时，`startedAt` 取「选中日期的当天时刻」，而不是
    /// 选中日期的 00:00。曾写成 00:00，结果用户 9 月 10 日补记、9 月 19 日
    /// 才点完成，时长被算成 9 天 18 小时——`durationSeconds` 是
    /// `endedAt - startedAt`，锚点落在零点就等于把整段等待都算进修时。
    /// 这里保留用户点下按钮的真实时刻（时/分/秒），只把年月日换成选中那天。
    func createDraft(kind: WorkoutSession.Kind, on date: Date) -> UUID? {
        var draft = WorkoutSession(name: "新建\(kind.title)训练", kind: kind)
        if !HistoryCalendar.isSameDay(date, .now, calendar: calendar) {
            draft.startedAt = Self.timeOfDay(from: .now, onDayOf: date, calendar: calendar)
        }
        do {
            try repository.save(session: draft)
            return draft.id
        } catch {
            banner = "新建训练失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 取 `timeSource` 的「时刻」，配上 `day` 的「年月日」。
    ///
    /// 结果既不落在零点（避免跨日时长失真），又归属用户选中的那一天。
    /// 若拼接后晚于此刻（例如选今天但在测试中传入未来时刻），退回该天内的
    /// 一个安全时刻，保证 `startedAt <= now` 恒成立。
    static func timeOfDay(
        from timeSource: Date,
        onDayOf day: Date,
        calendar: Calendar = .current
    ) -> Date {
        let dayParts = calendar.dateComponents([.year, .month, .day], from: day)
        let timeParts = calendar.dateComponents([.hour, .minute, .second], from: timeSource)
        var merged = DateComponents()
        merged.year = dayParts.year
        merged.month = dayParts.month
        merged.day = dayParts.day
        merged.hour = timeParts.hour
        merged.minute = timeParts.minute
        merged.second = timeParts.second

        guard let combined = calendar.date(from: merged) else {
            return HistoryCalendar.startOfDay(for: day, calendar: calendar)
        }
        // 不允许开始时间晚于当前时刻
        return combined <= .now ? combined : HistoryCalendar.startOfDay(for: day, calendar: calendar)
    }

    /// 把某天标记为休息日。同一天重复标记会覆盖，不会堆出多条。
    func addRestDay(on date: Date, note: String? = nil) {
        let record = RestDay(
            date: HistoryCalendar.startOfDay(for: date, calendar: calendar),
            note: note,
            createdAt: .now
        )
        do {
            try repository.save(restDay: record)
            Task { await reload() }
        } catch {
            banner = "标记休息日失败：\(error.localizedDescription)"
        }
    }

    /// 更新某天休息日的备注（页面 34）。
    func updateRestDayNote(on date: Date, note: String?) {
        guard var record = restDays.first(where: {
            HistoryCalendar.isSameDay($0.date, date, calendar: calendar)
        }) else {
            addRestDay(on: date, note: note)
            return
        }
        record.note = note
        do {
            try repository.save(restDay: record)
            Task { await reload() }
        } catch {
            banner = "保存备注失败：\(error.localizedDescription)"
        }
    }

    /// 删除某天的休息日标记
    func removeRestDay(on date: Date) {
        guard let record = restDays.first(where: {
            HistoryCalendar.isSameDay($0.date, date, calendar: calendar)
        }) else { return }
        do {
            try repository.delete(restDayID: record.id)
            Task { await reload() }
        } catch {
            banner = "取消休息日失败：\(error.localizedDescription)"
        }
    }

    /// 某天是否有训练记录（含未完成草稿）。
    func hasSessions(on date: Date) -> Bool {
        !sessions(on: date).isEmpty
    }

    /// 某天的训练记录（按开始时间倒序）。
    func sessions(on date: Date) -> [WorkoutSession] {
        sessions
            .filter { HistoryCalendar.isSameDay($0.startedAt, date, calendar: calendar) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// 某天的休息日记录。
    func restDay(on date: Date) -> RestDay? {
        restDays.first { HistoryCalendar.isSameDay($0.date, date, calendar: calendar) }
    }

    /// 改训练标题
    func rename(session: WorkoutSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = session
        updated.name = trimmed
        do {
            try repository.save(session: updated)
            Task { await reload() }
        } catch {
            banner = "保存标题失败：\(error.localizedDescription)"
        }
    }

    /// 复制为新训练。
    ///
    /// 新记录一定是未结束状态，`endedAt` 置空、`startedAt` 设为此刻：
    /// 若原样复制一份已结束记录，历史里会凭空多出一条"已完成"的训练，
    /// 而用户本意是拿它当模板再练一次。
    func duplicate(session: WorkoutSession) {
        var copy = session
        copy.id = UUID()
        copy.name = "\(session.name) 副本"
        copy.startedAt = .now
        copy.endedAt = nil
        copy.note = session.note
        // 组记录保留重量与次数，但清掉完成时间，作为待完成的目标组
        copy.entries = session.entries.map { entry in
            var cleared = entry
            cleared.id = UUID()
            cleared.completedAt = nil
            return cleared
        }
        do {
            try repository.save(session: copy)
            Task { await reload() }
        } catch {
            banner = "复制训练失败：\(error.localizedDescription)"
        }
    }

    /// 只删除当前这一条本地记录
    func delete(session: WorkoutSession) {
        do {
            try repository.delete(sessionID: session.id)
            Task { await reload() }
        } catch {
            banner = "删除失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 页面

struct HistoryView: View {

    @ObservedObject var viewModel: HistoryViewModel
    /// 需要高亮并定位到的训练。来自训练总结页的「查看历史记录」。
    var highlightSessionID: UUID?
    var onOpenSession: (WorkoutSession) -> Void
    /// 新建力量 / 有氧训练后跳到训练执行页
    var onOpenDraft: (UUID) -> Void
    /// 进入训练统计（页面 10）
    var onOpenStats: () -> Void
    /// 页面内的写操作改动了数据，通知外层重建本页。
    ///
    /// 本页自身的视图模型已经通过 `reload()` 刷新了列表，所以这里不是「刷新数据」，
    /// 而是给外层一个重建时机 —— 页面 09 的详情页删除记录后返回时，
    /// 外层需要这个信号才能把 `HistoryView` 连同它的视图模型一起重建，
    /// 否则日历上会残留已删记录的标记点。
    var onDataChanged: () -> Void = {}

    @State private var showAddMenu = false
    @State private var dayMenuTarget: Date?
    @State private var pendingDelete: WorkoutSession?
    @State private var renameTarget: WorkoutSession?
    @State private var renameText = ""
    /// 页面 33 新增休息日抽屉
    @State private var showAddRestDay = false
    /// 页面 34 休息日详情抽屉
    @State private var restDayDetailTarget: RestDay?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    loadingView

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    calendarCard
                    segmentPicker
                    segmentContent
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .task { await viewModel.load() }
        .animation(DS.Motion.tabSwitch, value: viewModel.segment)
        .animation(DS.Motion.standard, value: viewModel.selectedDate)
        // 新增菜单
        .bottomDrawer(
            isPresented: $showAddMenu,
            height: 384,
            title: "新增",
            subtitle: "记录今天的训练或休息"
        ) {
            addMenuContent
        }
        // 长按日期菜单
        .bottomDrawer(
            isPresented: Binding(
                get: { dayMenuTarget != nil },
                set: { if !$0 { dayMenuTarget = nil } }
            ),
            height: 336,
            title: dayMenuTarget.map { FormatterKit.fullDate($0) } ?? "",
            subtitle: "这一天要做什么"
        ) {
            dayMenuContent
        }
        // 页面 33 新增休息日
        .bottomDrawer(isPresented: $showAddRestDay, height: 380) {
            AddRestDaySheet(
                defaultDate: viewModel.selectedDate,
                hasSessionsOnDay: viewModel.hasSessions(on: viewModel.selectedDate),
                existingRestDay: viewModel.restDay(on: viewModel.selectedDate),
                onSave: { date, note in
                    viewModel.addRestDay(on: date, note: note)
                    showAddRestDay = false
                },
                onEditExisting: { showAddRestDay = false }
            )
        }
        // 页面 34 休息日详情
        .bottomDrawer(
            isPresented: Binding(
                get: { restDayDetailTarget != nil },
                set: { if !$0 { restDayDetailTarget = nil } }
            ),
            height: 480
        ) {
            if let restDay = restDayDetailTarget {
                RestDayDetailSheet(
                    restDay: restDay,
                    sessionsOnDay: viewModel.sessions(on: restDay.date),
                    onSaveNote: { note in
                        viewModel.updateRestDayNote(on: restDay.date, note: note)
                        restDayDetailTarget = nil
                    },
                    onDelete: {
                        viewModel.removeRestDay(on: restDay.date)
                        restDayDetailTarget = nil
                    },
                    onClose: { restDayDetailTarget = nil },
                    onOpenSession: { id in
                        if let session = viewModel.sessions(on: restDay.date).first(where: { $0.id == id }) {
                            restDayDetailTarget = nil
                            onOpenSession(session)
                        }
                    }
                )
            }
        }
        // 编辑标题
        .alert("编辑训练标题", isPresented: renameAlertBinding) {
            TextField("训练名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    viewModel.rename(session: target, to: renameText)
                }
                renameTarget = nil
            }
        } message: {
            Text("只修改本地训练记录的标题，不影响其他数据。")
        }
        // 删除二次确认
        .alert("删除这条训练记录？", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                if let target = pendingDelete {
                    viewModel.delete(session: target)
                }
                pendingDelete = nil
            }
        } message: {
            Text(deleteConfirmMessage)
        }
        .overlay(alignment: .bottom) { bannerView }
    }

    // MARK: 导航栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Text("历史")
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                Haptics.light()
                showAddMenu = true
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.onAccent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DS.Palette.accent))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("新增")
            .accessibilityHint("新建训练、添加休息日或导入计划")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, 6)
        .background(DS.Palette.bg)
    }

    // MARK: 骨架屏

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            SkeletonBlock(height: 320)
            SkeletonBlock(height: 44)
            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(height: 92)
            }
        }
    }

    // MARK: 日历

    private var calendarCard: some View {
        CardContainer {
            VStack(spacing: DS.Spacing.item) {
                MonthSwitcher(
                    title: viewModel.monthTitle,
                    isCurrentMonth: viewModel.isCurrentMonth,
                    onPrevious: { withAnimation(DS.Motion.tabSwitch) { viewModel.goToPreviousMonth() } },
                    onNext: { withAnimation(DS.Motion.tabSwitch) { viewModel.goToNextMonth() } },
                    onToday: { withAnimation(DS.Motion.tabSwitch) { viewModel.goToCurrentMonth() } }
                )

                MonthGridView(
                    month: viewModel.visibleMonth,
                    index: viewModel.dayIndex,
                    selectedDate: viewModel.selectedDate,
                    onSelect: { date in
                        Haptics.light()
                        withAnimation(DS.Motion.standard) { viewModel.select(date) }
                    },
                    onLongPressDate: { date in
                        viewModel.select(date)
                        dayMenuTarget = date
                    }
                )

                legend
            }
        }
    }

    /// 标记点图例。三种颜色不解释一下没人猜得出灰色代表休息日。
    private var legend: some View {
        HStack(spacing: DS.Spacing.item) {
            legendItem(color: DS.Palette.accent, text: "力量")
            legendItem(color: DS.Palette.cardio, text: "有氧")
            legendItem(color: DS.Palette.restMarker, text: "休息日")
            Spacer()
            Text("长按日期可新增")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("标记说明：荧光绿为力量训练，蓝绿为有氧训练，灰色为休息日")
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(
                    width: DS.Size.calendarMarkerDot,
                    height: DS.Size.calendarMarkerDot
                )
            Text(text)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
    }

    // MARK: 分段控件

    private var segmentPicker: some View {
        HStack(spacing: 4) {
            ForEach(HistorySegment.allCases) { item in
                Button {
                    guard viewModel.segment != item else { return }
                    Haptics.light()
                    withAnimation(DS.Motion.tabSwitch) { viewModel.segment = item }
                } label: {
                    Text(item.title)
                        .font(DS.Typography.callout.weight(
                            viewModel.segment == item ? .semibold : .regular
                        ))
                        .foregroundStyle(
                            viewModel.segment == item
                                ? DS.Palette.onAccent
                                : DS.Palette.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            Capsule().fill(
                                viewModel.segment == item
                                    ? DS.Palette.accent
                                    : Color.clear
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(
                    viewModel.segment == item ? [.isButton, .isSelected] : .isButton
                )
            }
        }
        .padding(3)
        .background(
            Capsule().fill(DS.Palette.surfaceElevated)
        )
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch viewModel.segment {
        case .calendar:
            DayTimelineSection(
                entry: viewModel.selectedEntry,
                onOpenSession: onOpenSession,
                onAddTraining: { dayMenuTarget = viewModel.selectedDate },
                onEditTitle: { session in
                    renameText = session.name
                    renameTarget = session
                },
                onDuplicate: { viewModel.duplicate(session: $0) },
                onDelete: { pendingDelete = $0 },
                isRestDay: viewModel.selectedEntry.isRestDay
            )

        case .list:
            listSection

        case .stats:
            // 规格：统计进入训练数据汇总（页面 10 已实现）
            statsEntryCard
        }
    }

    // MARK: 列表分段

    @ViewBuilder
    private var listSection: some View {
        if viewModel.finishedCount == 0 {
            EmptyStateView(
                message: "还没有完成的训练记录。完成一次训练后，这里会按月份归档。",
                actionTitle: "新增训练",
                action: { dayMenuTarget = .now }
            )
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                summaryCard

                ForEach(viewModel.monthSections, id: \.title) { group in
                    VStack(alignment: .leading, spacing: DS.Spacing.item) {
                        SectionHeader(
                            title: group.title,
                            trailingText: "\(group.sessions.count) 次"
                        )
                        ForEach(group.sessions) { session in
                            HistoryListRow(
                                session: session,
                                isHighlighted: session.id == highlightSessionID,
                                onTap: { onOpenSession(session) }
                            )
                            .id(session.id)
                        }
                    }
                }
            }
        }
    }

    /// 汇总卡片（列表分段顶部）
    private var summaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("累计")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                HStack(alignment: .top, spacing: 0) {
                    stat(value: "\(viewModel.finishedCount)", unit: "次", label: "训练")
                    divider
                    stat(
                        value: "\(Int(viewModel.totalVolume.rounded()))",
                        unit: "kg",
                        label: "总容量"
                    )
                    divider
                    stat(
                        value: String(format: "%.1f", viewModel.totalDistanceKm),
                        unit: "km",
                        label: "总里程"
                    )
                }
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Palette.stroke)
            .frame(width: 1, height: 36)
            .padding(.horizontal, DS.Spacing.tight)
    }

    private func stat(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Palette.accent)
                Text(unit)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value) \(unit)")
    }

    // MARK: 统计分段

    /// 统计入口。规格说统计进入训练数据汇总，
    /// 汇总页由 `WorkoutStatisticsView` 实现（页面 10），
    /// 这里保留一张入口卡：分段控件本身只切换内容，入栈由用户显式点击触发。
    private var statsEntryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.body)
                        .foregroundStyle(DS.Palette.accent)
                    Text("训练数据汇总")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                }

                Text("按时间范围查看训练频率、容量趋势、常练动作与部位分布。")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onOpenStats) {
                    HStack(spacing: DS.Spacing.tight) {
                        Text("进入统计")
                            .font(DS.Typography.callout.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(DS.Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .fill(DS.Palette.accent)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(viewModel.finishedCount == 0)
                .opacity(viewModel.finishedCount == 0 ? 0.4 : 1)
                .accessibilityLabel("进入训练数据汇总")
            }
        }
    }

    // MARK: 菜单内容

    private var addMenuContent: some View {
        VStack(spacing: DS.Spacing.tight) {
            DrawerActionRow(
                title: "新建力量训练",
                subtitle: "从空白开始记录组数与重量",
                symbol: "dumbbell"
            ) {
                showAddMenu = false
                startDraft(kind: .strength, on: .now)
            }
            DrawerActionRow(
                title: "新建有氧训练",
                subtitle: "记录距离与时长",
                symbol: "figure.run"
            ) {
                showAddMenu = false
                startDraft(kind: .cardio, on: .now)
            }
            DrawerActionRow(
                title: "添加休息日",
                subtitle: "在日历上标记今天为休息日",
                symbol: "moon.zzz"
            ) {
                showAddMenu = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showAddRestDay = true
                }
            }
            DrawerActionRow(
                title: "导入本地计划",
                subtitle: "从已有的本地计划生成训练",
                symbol: "square.and.arrow.down"
            ) {
                showAddMenu = false
                // 计划导入走计划详情页的选择流程，此处仅作为入口占位
                viewModel.banner = "导入本地计划：请先在「训练」页选择一个计划后再开始。"
            }
        }
    }

    @ViewBuilder
    private var dayMenuContent: some View {
        if let date = dayMenuTarget {
            VStack(spacing: DS.Spacing.tight) {
                if viewModel.hasSessions(on: date) || viewModel.restDay(on: date) != nil {
                    DrawerActionRow(
                        title: "查看当天记录",
                        subtitle: "查看这一天的训练与休息日详情",
                        symbol: "list.bullet"
                    ) {
                        let target = date
                        dayMenuTarget = nil
                        if let restDay = viewModel.restDay(on: target) {
                            restDayDetailTarget = restDay
                        } else if let session = viewModel.sessions(on: target).first {
                            onOpenSession(session)
                        }
                    }
                }

                DrawerActionRow(
                    title: "新建力量训练",
                    subtitle: "记录到 \(FormatterKit.shortDate(date))",
                    symbol: "dumbbell"
                ) {
                    let target = date
                    dayMenuTarget = nil
                    startDraft(kind: .strength, on: target)
                }
                DrawerActionRow(
                    title: "新建有氧训练",
                    subtitle: "记录到 \(FormatterKit.shortDate(date))",
                    symbol: "figure.run"
                ) {
                    let target = date
                    dayMenuTarget = nil
                    startDraft(kind: .cardio, on: target)
                }

                if viewModel.restDay(on: date) != nil {
                    DrawerActionRow(
                        title: "编辑休息日备注",
                        subtitle: "修改这一天的休息日备注",
                        symbol: "moon.zzz"
                    ) {
                        let target = date
                        dayMenuTarget = nil
                        if let restDay = viewModel.restDay(on: target) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                restDayDetailTarget = restDay
                            }
                        }
                    }
                } else {
                    DrawerActionRow(
                        title: "添加休息日",
                        subtitle: "标记 \(FormatterKit.shortDate(date)) 为休息日",
                        symbol: "moon.zzz"
                    ) {
                        let target = date
                        dayMenuTarget = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showAddRestDay = true
                        }
                    }
                }

                DrawerActionRow(
                    title: "导入个人计划到当天",
                    subtitle: "从已有本地计划生成当天训练",
                    symbol: "square.and.arrow.down"
                ) {
                    dayMenuTarget = nil
                    viewModel.banner = "导入计划：请先在「训练」页选择一个计划后再开始。"
                }
            }
        }
    }

    private func startDraft(kind: WorkoutSession.Kind, on date: Date) {
        guard let id = viewModel.createDraft(kind: kind, on: date) else { return }
        onOpenDraft(id)
    }

    // MARK: 绑定与提示

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteConfirmMessage: String {
        guard let target = pendingDelete else { return "" }
        return "将删除「\(target.name)」及其全部组记录，只影响本机保存的这条记录，无法撤销。"
    }

    @ViewBuilder
    private var bannerView: some View {
        if let text = viewModel.banner {
            Text(text)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, DS.Spacing.item)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(DS.Palette.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .stroke(DS.Palette.stroke)
                )
                .padding(.horizontal, DS.Spacing.page)
                .padding(.bottom, DS.Spacing.item)
                .transition(.opacity)
                .onTapGesture { viewModel.banner = nil }
                .task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    viewModel.banner = nil
                }
        }
    }
}

// MARK: - 列表行

/// 列表分段里的行。与日历分段的卡片分开实现：
/// 列表要更紧凑，且不需要类型色条（月份分组已经提供了上下文）。
private struct HistoryListRow: View {

    let session: WorkoutSession
    var isHighlighted: Bool = false
    let onTap: () -> Void

    private var kindColor: Color {
        session.kind == .cardio ? DS.Palette.cardio : DS.Palette.accent
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: session.kind.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(kindColor)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(kindColor.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(session.summaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.tight)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(FormatterKit.duration(seconds: session.durationSeconds))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(FormatterKit.shortDate(session.startedAt))
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .padding(DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        isHighlighted ? DS.Palette.accent : DS.Palette.stroke,
                        lineWidth: isHighlighted ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.name)，\(FormatterKit.shortDate(session.startedAt))，"
            + "\(FormatterKit.duration(seconds: session.durationSeconds))，\(session.summaryText)"
            + (isHighlighted ? "，本次训练" : "")
        )
    }
}

// MARK: - 预览

#Preview("历史 · 日历") {
    HistoryView(
        viewModel: HistoryViewModel(repository: PreviewFitnessRepository()),
        highlightSessionID: nil,
        onOpenSession: { _ in },
        onOpenDraft: { _ in },
        onOpenStats: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("历史 · 空数据") {
    HistoryView(
        viewModel: HistoryViewModel(repository: PreviewFitnessRepository.makeEmpty()),
        highlightSessionID: nil,
        onOpenSession: { _ in },
        onOpenDraft: { _ in },
        onOpenStats: {}
    )
    .preferredColorScheme(.dark)
}
