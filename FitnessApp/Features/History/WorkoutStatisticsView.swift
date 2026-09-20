//
//  WorkoutStatisticsView.swift
//  页面 10：训练统计。
//
//  入口：历史页的「统计」分段。
//
//  数据全部来自本地历史训练记录，经 `WorkoutStatistics.swift` 的纯函数聚合。
//  本页不做任何自己的统计计算 —— 视图层只负责把值层算好的结构渲染出来，
//  这样「训练次数怎么数」「容量是否含热身」这类口径只有一个定义处，
//  推演脚本也只需要验一个地方。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class WorkoutStatisticsViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 统计页读多少条记录。
    ///
    /// 与历史页的 500 条同一上限：两边读的是同一份数据，
    /// 用不同上限会让统计数字与历史列表的条数对不上，
    /// 用户会认为是统计算错了。真要放开就一起放开。
    static let sessionFetchLimit = 500

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var sessions: [WorkoutSession] = []
    /// 动作库。统计动作名与肌群分布都要靠它。
    @Published private(set) var exercises: [ExerciseLibraryItem] = []

    @Published var rangeKind: StatsRangeKind = .last30Days
    /// 自定义范围的起止
    @Published var customStart: Date
    @Published var customEnd: Date
    @Published var volumeFilter: StatsVolumeFilter = .all

    /// 频率图选中的格
    @Published var selectedFrequencyDate: Date?
    /// 容量图选中的点
    @Published var selectedVolumeDate: Date?

    /// 缓存的聚合结果。范围或筛选变化时换 key，数据变化时 invalidate。
    private var summaryCache = StatsCache<StatsSummary>()
    private var frequencyCache = StatsCache<[StatsFrequencyBucket]>()
    private var volumeCache = StatsCache<[StatsVolumePoint]>()
    private var topExerciseCache = StatsCache<[TopExerciseStat]>()
    private var muscleCache = StatsCache<[MuscleDistributionRow]>()
    private var filterOptionsCache = StatsCache<[StatsVolumeFilter]>()

    private let repository: FitnessRepository
    private let calendar = Calendar.current

    init(repository: FitnessRepository) {
        self.repository = repository
        // 自定义范围默认取本月，用户一打开就是个有意义的区间，
        // 而不是需要先手动点两次才不空白。
        let now = Date()
        let monthStart = StatsRangeBuilder.firstDayOfMonth(for: now) ?? now
        self.customStart = monthStart
        self.customEnd = now
    }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            sessions = try repository.fetchRecentSessions(limit: Self.sessionFetchLimit)
            // includeHidden: true ——「常练动作」与「部位分布」都要能显示
            // 被用户隐藏过的动作。按默认 false 取会让这些动作在统计里凭空消失，
            // 组数总和与摘要卡上的总组数对不上。
            exercises = try repository.fetchExercises(includeHidden: true)
            invalidateCaches()
            loadState = .loaded
        } catch {
            loadState = .failed("统计读取失败：\(error.localizedDescription)")
        }
    }

    /// 数据写入后刷新，不回到 loading 态，避免整页闪骨架屏
    func reload() async {
        do {
            sessions = try repository.fetchRecentSessions(limit: Self.sessionFetchLimit)
            exercises = try repository.fetchExercises(includeHidden: true)
            invalidateCaches()
            loadState = .loaded
        } catch {
            loadState = .failed("统计刷新失败：\(error.localizedDescription)")
        }
    }

    /// 让全部缓存失效。任何一次数据写入后都必须调用。
    private func invalidateCaches() {
        summaryCache.invalidate()
        frequencyCache.invalidate()
        volumeCache.invalidate()
        topExerciseCache.invalidate()
        muscleCache.invalidate()
        filterOptionsCache.invalidate()
    }

    // MARK: 派生

    var exerciseLookup: [String: ExerciseLibraryItem] {
        Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 当前生效的时间范围
    var range: StatsDateRange {
        StatsRangeBuilder.range(
            for: rangeKind,
            now: .now,
            customStart: customStart,
            customEnd: customEnd,
            calendar: calendar
        )
    }

    /// 范围文案，用于标题下方与无障碍摘要
    var rangeText: String { range.text(calendar: calendar) }

    /// 摘要。走缓存，避免滚动时反复遍历 500 条记录。
    var summary: StatsSummary {
        let key = StatsCacheKey.rangeKey(range)
        if let cached = summaryCache.value(forKey: key) { return cached }

        // 一次训练只属于一个自然日，但区间边界是按 startedAt 判定的，
        // 所以这里先按 startedAt 过滤，与频率图、容量图完全同源。
        let scoped = sessions.filter { $0.isFinished && range.contains($0.startedAt) }
        let value = StatsSummary(sessions: scoped)
        var cache = summaryCache
        cache.store(value, forKey: key)
        summaryCache = cache
        return value
    }

    /// 频率图粒度。范围太长时自动降级为按周。
    var granularity: StatsFrequencyGranularity {
        StatsFrequencyBuilder.effectiveGranularity(requested: .daily, range: range, calendar: calendar)
    }

    var frequencyBuckets: [StatsFrequencyBucket] {
        let rangeKey = StatsCacheKey.rangeKey(range)
        let key = "\(rangeKey):\(granularity.rawValue)"
        if let cached = frequencyCache.value(forKey: key) { return cached }

        let value = StatsFrequencyBuilder.buckets(
            sessions: sessions,
            range: range,
            granularity: granularity,
            calendar: calendar
        )
        var cache = frequencyCache
        cache.store(value, forKey: key)
        frequencyCache = cache
        return value
    }

    var volumePoints: [StatsVolumePoint] {
        let key = StatsCacheKey.key(range: range, filter: volumeFilter)
        if let cached = volumeCache.value(forKey: key) { return cached }

        let value = StatsVolumeBuilder.points(
            sessions: sessions,
            range: range,
            filter: volumeFilter,
            exerciseLookup: exerciseLookup,
            calendar: calendar
        )
        var cache = volumeCache
        cache.store(value, forKey: key)
        volumeCache = cache
        return value
    }

    var topExercises: [TopExerciseStat] {
        let key = StatsCacheKey.rangeKey(range)
        if let cached = topExerciseCache.value(forKey: key) { return cached }

        let value = StatsTopExerciseBuilder.top(
            sessions: sessions,
            range: range,
            exerciseLookup: exerciseLookup,
            calendar: calendar
        )
        var cache = topExerciseCache
        cache.store(value, forKey: key)
        topExerciseCache = cache
        return value
    }

    var muscleRows: [MuscleDistributionRow] {
        let key = StatsCacheKey.rangeKey(range)
        if let cached = muscleCache.value(forKey: key) { return cached }

        let value = StatsMuscleDistributionBuilder.rows(
            sessions: sessions,
            range: range,
            exerciseLookup: exerciseLookup,
            calendar: calendar
        )
        var cache = muscleCache
        cache.store(value, forKey: key)
        muscleCache = cache
        return value
    }

    /// 容量趋势可选的筛选维度
    var volumeFilterOptions: [StatsVolumeFilter] {
        let key = StatsCacheKey.rangeKey(range)
        if let cached = filterOptionsCache.value(forKey: key) { return cached }

        let value = StatsVolumeBuilder.availableFilters(
            sessions: sessions,
            range: range,
            exerciseLookup: exerciseLookup,
            calendar: calendar
        )
        var cache = filterOptionsCache
        cache.store(value, forKey: key)
        filterOptionsCache = cache
        return value
    }

    var summaryMetrics: [StatsMetric] {
        summary.metrics(includeCardioDistance: true)
    }

    // MARK: 写入

    func selectRange(_ kind: StatsRangeKind) {
        rangeKind = kind
        // 换了范围就把选中态清掉：旧选中日期在新范围里可能不存在，
        // 留着会让图表上出现一个指向空白的选中标记。
        selectedFrequencyDate = nil
        selectedVolumeDate = nil
    }

    /// 自定义日期改动后调用。只在当前就是自定义范围时才有意义。
    func customDateChanged() {
        guard rangeKind == .custom else { return }
        selectedFrequencyDate = nil
        selectedVolumeDate = nil
    }

    func selectVolumeFilter(_ filter: StatsVolumeFilter) {
        volumeFilter = filter
        selectedVolumeDate = nil
    }

    /// 在当前范围内是否完全没有任何训练
    var isEmptyRange: Bool {
        summary.sessionCount == 0
    }
}

// MARK: - 页面

struct WorkoutStatisticsView: View {

    @ObservedObject var viewModel: WorkoutStatisticsViewModel
    let onBack: () -> Void
    /// 进入数据管理页
    let onOpenDataManagement: () -> Void
    /// 进入某个动作的历史趋势子页
    let onOpenExerciseTrend: (TopExerciseStat) -> Void

    @State private var showRangePicker = false
    @State private var showFilterPicker = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    StatsSkeleton()

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    summarySection
                    frequencyCard
                    volumeCard
                    topExerciseCard
                    muscleCard
                    StatsDataManagementCard { onOpenDataManagement() }
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        // 时间范围抽屉
        .bottomDrawer(
            isPresented: $showRangePicker,
            height: viewModel.rangeKind == .custom ? 520 : 400,
            title: "时间范围",
            subtitle: "选择后立即重新计算本地统计"
        ) {
            StatsRangePickerContent(
                selected: viewModel.rangeKind,
                customStart: $viewModel.customStart,
                customEnd: $viewModel.customEnd,
                onSelect: { kind in
                    viewModel.selectRange(kind)
                    // 选非自定义项时顺手收起抽屉：用户已经表达完了意图，
                    // 让他自己再点一次关闭是多余的一步。
                    if !kind.needsDateInput { showRangePicker = false }
                },
                onCustomDateChanged: { viewModel.customDateChanged() }
            )
        }
        // 容量筛选抽屉
        .bottomDrawer(
            isPresented: $showFilterPicker,
            height: 460,
            title: "容量筛选",
            subtitle: "按肌群或单个动作查看容量趋势"
        ) {
            StatsVolumeFilterContent(
                filters: viewModel.volumeFilterOptions,
                selected: viewModel.volumeFilter,
                onSelect: { filter in
                    viewModel.selectVolumeFilter(filter)
                    showFilterPicker = false
                }
            )
        }
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("训练统计")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.tight)

            // 时间范围按钮。规格要求「右侧为时间范围按钮」。
            Button {
                Haptics.light()
                showRangePicker = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                    Text(viewModel.rangeKind.title)
                        .font(DS.Typography.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(DS.Palette.onAccent)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Capsule().fill(DS.Palette.accent))
                .contentShape(Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("时间范围：\(viewModel.rangeKind.title)")
            .accessibilityHint("轻点两下切换时间范围")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.Palette.stroke)
                    .frame(height: 1)
            }
        )
    }

    // MARK: 摘要区

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                Text(viewModel.rangeText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !viewModel.isEmptyRange {
                    Text(viewModel.summary.metrics().count > 4 ? "含有氧" : "")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }

            // 四张摘要卡排两列。多于四张（含距离）时自然变成三行。
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: DS.Spacing.item),
                    GridItem(.flexible(), spacing: DS.Spacing.item),
                ],
                spacing: DS.Spacing.item
            ) {
                ForEach(viewModel.summaryMetrics) { metric in
                    StatsMetricCard(metric: metric)
                }
            }

            if viewModel.isEmptyRange {
                EmptyStateView(
                    message: "这个时间范围内还没有完成的训练。换一个时间范围，或先完成一次训练。",
                    actionTitle: "切换到近 3 个月",
                    action: { viewModel.selectRange(.last3Months) }
                )
            }
        }
        // 整块摘要区合并成一句话，规格里举的就是这种句式
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            Text(viewModel.summary.accessibilitySummary(rangeTitle: viewModel.rangeKind.title))
        )
    }

    // MARK: 训练频率

    private var frequencyCard: some View {
        let buckets = viewModel.frequencyBuckets
        return StatsChartCard(
            title: "训练频率",
            subtitle: viewModel.granularity.title,
            trailingText: nil,
            onTrailingTap: nil,
            accessibilitySummary: nil
        ) {
            StatsFrequencyChart(
                buckets: buckets,
                granularity: viewModel.granularity,
                selectedDate: $viewModel.selectedFrequencyDate,
                onSelect: { _ in }
            )
        }
        .accessibilityLabel(
            Text(
                StatsFrequencyBuilder.accessibilitySummary(
                    buckets: buckets,
                    rangeTitle: viewModel.rangeKind.title
                )
            )
        )
    }

    // MARK: 训练容量趋势

    private var volumeCard: some View {
        let points = viewModel.volumePoints
        return StatsChartCard(
            title: "训练容量趋势",
            subtitle: nil,
            trailingText: viewModel.volumeFilter.title,
            onTrailingTap: { showFilterPicker = true }
        ) {
            StatsVolumeChart(
                points: points,
                selectedDate: $viewModel.selectedVolumeDate,
                onSelect: { _ in }
            )
        }
        .accessibilityLabel(
            Text(
                StatsVolumeBuilder.accessibilitySummary(
                    points: points,
                    rangeTitle: viewModel.rangeKind.title
                )
            )
        )
    }

    // MARK: 常练动作

    private var topExerciseCard: some View {
        let items = viewModel.topExercises
        return StatsChartCard(
            title: "常练动作",
            subtitle: "按完成组数排序",
            trailingText: items.isEmpty ? nil : "前 \(items.count) 个"
        ) {
            if items.isEmpty {
                CompactChartEmptyState(
                    message: "这个范围内还没有完成的动作记录。",
                    hint: "完成一次力量训练后，这里会按组数列出你最常练的动作。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, stat in
                        StatsTopExerciseRow(
                            stat: stat,
                            rank: index + 1,
                            onTap: { onOpenExerciseTrend(stat) }
                        )
                        if index < items.count - 1 {
                            Divider().overlay(DS.Palette.stroke)
                        }
                    }
                }
            }
        }
        .accessibilityLabel(
            Text(
                StatsTopExerciseBuilder.accessibilitySummary(
                    items: items,
                    rangeTitle: viewModel.rangeKind.title
                )
            )
        )
    }

    // MARK: 训练部位分布

    private var muscleCard: some View {
        let rows = viewModel.muscleRows
        let total = rows.reduce(0) { $0 + $1.setCount }
        return StatsChartCard(
            title: "训练部位分布",
            subtitle: "按主肌群统计完成组数",
            trailingText: total > 0 ? "共 \(total) 组" : nil
        ) {
            if rows.isEmpty {
                CompactChartEmptyState(
                    message: "这个范围内还没有完成的正式组。",
                    hint: "热身组不计入部位分布，完成正式组后这里会显示各部位占比。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        StatsMuscleBarRow(row: row)
                    }

                    Text("按主肌群归类，完成组数不含热身组。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, DS.Spacing.tight)
                }
            }
        }
        .accessibilityLabel(
            Text(
                StatsMuscleDistributionBuilder.accessibilitySummary(
                    rows: rows,
                    rangeTitle: viewModel.rangeKind.title
                )
            )
        )
    }
}

// MARK: - 紧凑空状态

/// 图表卡内部的紧凑空状态。
///
/// 不复用 `EmptyStateView`：那张卡自带虚线边框与较大的内边距，
/// 套进已经有一层边框的图表卡里会出现双层框，视觉上很脏。
struct CompactChartEmptyState: View {

    let message: String
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(message)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let hint {
                Text(hint)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([message, hint].compactMap { $0 }.joined(separator: "。"))
    }
}

// MARK: - 预览

#Preview("训练统计 · 混合数据") {
    WorkoutStatisticsView(
        viewModel: WorkoutStatisticsViewModel(repository: PreviewFitnessRepository()),
        onBack: {},
        onOpenDataManagement: {},
        onOpenExerciseTrend: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("训练统计 · 只有有氧") {
    WorkoutStatisticsView(
        viewModel: WorkoutStatisticsViewModel(repository: PreviewFitnessRepository.makeCardioOnlyHistory()),
        onBack: {},
        onOpenDataManagement: {},
        onOpenExerciseTrend: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("训练统计 · 空数据") {
    WorkoutStatisticsView(
        viewModel: WorkoutStatisticsViewModel(repository: PreviewFitnessRepository.makeEmpty()),
        onBack: {},
        onOpenDataManagement: {},
        onOpenExerciseTrend: { _ in }
    )
    .preferredColorScheme(.dark)
}
