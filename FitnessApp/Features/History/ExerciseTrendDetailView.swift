//
//  ExerciseTrendDetailView.swift
//  页面 11：动作历史趋势。
//
//  入口两处：统计页「常练动作」点某个动作，或动作详情页的「历史记录」。
//
//  整页只读已完成训练，全部聚合在 `ExerciseTrendDetail.swift` 的纯值层里完成。
//  不含公开战绩、好友比较、分享——这一页是给本人看自己的进步用的。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class ExerciseTrendDetailViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let exerciseID: String
    /// 从上游带过来的快照名。动作被隐藏或从库里删除时，靠它把标题撑住。
    let fallbackName: String
    let repository: FitnessRepository

    @Published private(set) var loadState: LoadState = .loading
    @Published var rangeKind: TrendRangeKind = .last3Months
    @Published var unit: TrendWeightUnit = .kilograms

    @Published private(set) var overview = ExerciseTrendOverview(
        sessionCount: 0, setCount: 0, bestWeight: nil,
        bestOneRM: nil, lastTrainedAt: nil, oneRMSourceReps: nil
    )
    @Published private(set) var weightPoints: [TrendWeightPoint] = []
    @Published private(set) var volumePoints: [TrendVolumePoint] = []
    @Published private(set) var recentRecords: [ExerciseRecentRecord] = []
    @Published private(set) var suggestion = ExerciseStartSuggestion.fallback
    /// 动作在库里的当前显示名。已删除或已隐藏时为 nil。
    @Published private(set) var libraryName: String?

    /// 当前选中的数据点。切换范围或单位时清空——
    /// 旧的选中 id 在新范围里不一定存在，留着会指向一个看不见的点。
    @Published var selectedPointID: UUID?

    /// 原始训练记录只在这里读一次，切换范围 / 单位都不重新读盘。
    ///
    /// 单位切换**尤其不能**触发重新读取：它只是展示值的换算，
    /// 走一遍仓储会把刚刚算好的选中态一起冲掉。
    ///
    /// 只缓存原始 session 而不缓存筛完的 `ValidSet`：筛的结果随范围变化，
    /// 缓存它等于要维护两份可能不同步的状态。500 条记录重新筛一遍是微秒级。
    private var cachedSessions: [WorkoutSession] = []
    /// 是否已读过盘。`rangeText` 靠它区分「没数据」和「还没读到」。
    private var hasLoaded = false

    private let calendar = Calendar.current

    init(
        exerciseID: String,
        fallbackName: String,
        repository: FitnessRepository
    ) {
        self.exerciseID = exerciseID
        self.fallbackName = fallbackName
        self.repository = repository
    }

    // MARK: 派生

    var displayName: String {
        TrendExerciseNaming.name(
            libraryName: libraryName,
            fallback: fallbackName,
            exerciseID: exerciseID
        )
    }

    var isEmpty: Bool { overview.isEmpty }

    var rangeText: String? { currentRange.flatMap { TrendRangeBuilder.rangeText($0) } }

    var currentRange: TrendDateRange? {
        guard hasLoaded else { return nil }
        return TrendRangeBuilder.range(for: rangeKind, now: .now, calendar: calendar)
    }

    var weightTrendSummary: String {
        ExerciseTrendDetailBuilder.weightTrendSummary(
            points: weightPoints,
            overview: overview,
            rangeTitle: rangeKind.title
        )
    }

    var volumeTrendSummary: String {
        ExerciseTrendDetailBuilder.volumeTrendSummary(
            points: volumePoints,
            rangeTitle: rangeKind.title
        )
    }

    var overviewAccessibilityText: String { overview.accessibilityText }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            let sessions = try repository.fetchRecentSessions(
                limit: ExerciseTrendDetailBuilder.sessionFetchLimit
            )
            libraryName = try? repository
                .fetchExercises(ids: [exerciseID])
                .first
                .flatMap { $0.displayName.isEmpty ? nil : $0.displayName }

            cachedSessions = sessions
            hasLoaded = true
            recompute()
            loadState = .loaded
        } catch {
            loadState = .failed("读取动作历史失败：\(error.localizedDescription)")
        }
    }

    func reload() async {
        await load()
    }

    /// 切换时间范围。只重算聚合，不重新读盘。
    func selectRange(_ kind: TrendRangeKind) {
        guard kind != rangeKind else { return }
        rangeKind = kind
        selectedPointID = nil
        recompute()
    }

    /// 切换单位。只改展示，不碰任何缓存与聚合结果。
    func selectUnit(_ newUnit: TrendWeightUnit) {
        unit = newUnit
    }

    // MARK: 私有

    private func recompute() {
        let range = TrendRangeBuilder.range(
            for: rangeKind,
            now: .now,
            calendar: calendar
        )
        let sets = ExerciseTrendDetailBuilder.validSets(
            sessions: cachedSessions,
            exerciseID: exerciseID,
            range: range
        )

        overview = ExerciseTrendDetailBuilder.overview(from: sets)
        weightPoints = ExerciseTrendDetailBuilder.weightPoints(from: sets)
        volumePoints = ExerciseTrendDetailBuilder.volumePoints(from: sets)
        recentRecords = ExerciseTrendDetailBuilder.recentRecords(from: sets)
        // 建议**始终按全部历史**算，不受当前范围影响：
        // 「接着上次练」这件事跟「我当前在看近 30 天」没有关系。
        suggestion = ExerciseTrendDetailBuilder.startSuggestion(
            from: ExerciseTrendDetailBuilder.validSets(
                sessions: cachedSessions,
                exerciseID: exerciseID,
                range: TrendRangeBuilder.range(for: .allTime, now: .now, calendar: calendar)
            )
        )
    }
}

// MARK: - 页面

struct ExerciseTrendDetailView: View {

    @ObservedObject var viewModel: ExerciseTrendDetailViewModel
    let onBack: () -> Void
    /// 点「最近记录」进入历史训练详情（页面 09）
    let onOpenSessionDetail: (UUID) -> Void
    /// 「开始练这个动作」确认后，用这份草稿 id 进入训练执行页
    let onStartTraining: (UUID) -> Void

    @State private var showRangeMenu = false
    @State private var showStartConfirm = false

    /// 动态字体档位。达到无障碍档位时图表降级为列表。
    @Environment(\.sizeCategory) private var sizeCategory

    private var useListFallback: Bool {
        TrendAccessibilityScale.shouldUseList(sizeCategory)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    TrendDetailSkeleton()

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.reload() } }
                    )

                case .loaded:
                    // 完全没有记录时只给一个空状态，而不是四张卡各空一次。
                    // 四张卡里三句「还没有…」叠在一起，读起来像页面坏了。
                    if viewModel.isEmpty {
                        emptyState
                    } else {
                        overviewCard
                        weightTrendCard
                        volumeTrendCard
                        recentCard
                    }
                }

                startTrainingButton
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .bottomDrawer(
            isPresented: $showRangeMenu,
            height: 320,
            title: "时间范围",
            subtitle: "选择后立即重新计算趋势"
        ) {
            TrendRangeMenuContent(
                selected: viewModel.rangeKind,
                onSelect: { kind in
                    viewModel.selectRange(kind)
                    // 选完就收起：四个选项都是单步动作，
                    // 留着抽屉等用户再点一次关闭是多余的一步。
                    showRangeMenu = false
                }
            )
        }
        .bottomDrawer(
            isPresented: $showStartConfirm,
            height: 460,
            title: nil,
            subtitle: nil
        ) {
            TrendStartSuggestionContent(
                exerciseName: viewModel.displayName,
                suggestion: viewModel.suggestion,
                unit: viewModel.unit,
                onCancel: { showStartConfirm = false },
                onConfirm: { startTraining() }
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

            // 标题是动作名而不是「动作历史趋势」：
            // 页面里已经有三张图在讲趋势了，导航栏再写一遍是浪费。
            // 动作名才是用户此刻需要确认的「我在看哪个动作」。
            Text(viewModel.displayName)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                Haptics.light()
                showRangeMenu = true
            } label: {
                HStack(spacing: 3) {
                    Text(viewModel.rangeKind.title)
                        .font(DS.Typography.caption)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(DS.Palette.accent)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(DS.Palette.surface)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("时间范围，当前 \(viewModel.rangeKind.title)")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    // MARK: 空状态

    /// 规格要求：没有任何历史记录时显示这一句，且保留「开始练这个动作」。
    /// 按钮在卡片外，空状态与有数据时共用同一个。
    private var emptyState: some View {
        EmptyStateView(message: "还没有这个动作的训练记录")
    }

    // MARK: 摘要卡

    private var overviewCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                    Text("累计数据")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)

                    if let rangeText = viewModel.rangeText {
                        Text(rangeText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    Spacer(minLength: 0)
                }

                // 两列。动态字体调大时两列还能读，一行三个必然互相挤压。
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: DS.Spacing.item),
                        GridItem(.flexible(), spacing: DS.Spacing.item)
                    ],
                    spacing: DS.Spacing.item
                ) {
                    TrendMetricCell(
                        title: "累计训练次数",
                        value: "\(viewModel.overview.sessionCount)",
                        unit: "次"
                    )
                    TrendMetricCell(
                        title: "累计完成组数",
                        value: "\(viewModel.overview.setCount)",
                        unit: "组"
                    )
                    TrendMetricCell(
                        title: "最高单组重量",
                        value: viewModel.overview.bestWeightText(unit: viewModel.unit),
                        unit: viewModel.overview.bestWeight == nil ? nil : viewModel.unit.shortTitle,
                        isAccent: true
                    )
                    TrendMetricCell(
                        title: "估算 1RM",
                        value: viewModel.overview.bestOneRMText(unit: viewModel.unit),
                        unit: viewModel.overview.bestOneRM == nil ? nil : viewModel.unit.shortTitle,
                        note: viewModel.overview.oneRMNoteText
                    )
                    TrendMetricCell(
                        title: "最近训练",
                        value: viewModel.overview.lastTrainedText
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.overviewAccessibilityText)
    }

    // MARK: 最高重量趋势

    private var weightTrendCard: some View {
        StatsChartCard(
            title: "最高重量趋势",
            subtitle: "仅统计正式组",
            trailingText: nil,
            onTrailingTap: nil,
            accessibilitySummary: viewModel.weightTrendSummary
        ) {
            // 这张卡只在「本范围有记录」时才出现（整页空态由 `emptyState` 接管），
            // 所以 `weightPoints` 必定非空——它和 `overview` 出自同一份 `sets`。
            // 因此这里不再写一份空分支：它永远走不到，留着只会让人以为要维护。
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                if useListFallback {
                    TrendWeightPointList(
                        points: viewModel.weightPoints,
                        unit: viewModel.unit
                    )
                } else {
                    TrendWeightChart(
                        points: viewModel.weightPoints,
                        selectedID: $viewModel.selectedPointID
                    )

                    if let selectedID = viewModel.selectedPointID,
                       let point = viewModel.weightPoints.first(where: { $0.id == selectedID }) {
                        TrendSelectedDetail(point: point, unit: viewModel.unit)
                    }
                }
            }
        }
    }

    // MARK: 容量趋势

    private var volumeTrendCard: some View {
        StatsChartCard(
            title: "单次训练容量趋势",
            subtitle: "重量 × 次数",
            trailingText: nil,
            onTrailingTap: nil,
            accessibilitySummary: viewModel.volumeTrendSummary
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                // 单位切换只在这一张图上，不放在导航栏：
                // 摘要卡的「最高单组重量」同样受它影响，但那个数字是
                // 「我举过多少」这种事实陈述，跟图表的读图偏好不是一回事。
                HStack {
                    Spacer(minLength: 0)
                    TrendUnitToggle(unit: $viewModel.unit)
                }

                if useListFallback {
                    TrendVolumePointList(
                        points: viewModel.volumePoints,
                        unit: viewModel.unit
                    )
                } else {
                    TrendVolumeChart(
                        points: viewModel.volumePoints,
                        unit: viewModel.unit
                    )
                }
            }
        }
    }

    // MARK: 最近记录

    private var recentCard: some View {
        StatsChartCard(
            title: "最近记录",
            subtitle: "按时间倒序",
            trailingText: "\(viewModel.recentRecords.count) 次",
            onTrailingTap: nil
        ) {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.recentRecords.enumerated()), id: \.element.id) { index, record in
                    TrendRecentRecordRow(record: record, unit: viewModel.unit) {
                        Haptics.light()
                        onOpenSessionDetail(record.sessionID)
                    }

                    if index < viewModel.recentRecords.count - 1 {
                        Divider().overlay(DS.Palette.stroke)
                    }
                }
            }
        }
    }

    // MARK: 开始训练

    /// 底部主按钮。**空状态下也保留**——规格明确要求：
    /// 没有任何历史记录时，用户最需要的恰恰是「现在就去练一次」。
    private var startTrainingButton: some View {
        PrimaryButton(title: "开始练这个动作") {
            Haptics.light()
            showStartConfirm = true
        }
    }

    /// 建一份自由训练草稿并落盘，然后把 id 交给外层进执行页。
    ///
    /// 训练名直接用动作名而不是「新建力量训练」：
    /// 用户是从某个动作的趋势页点进来的，执行页顶部写着别的名字会让人怀疑走错了页。
    private func startTraining() {
        let entries = ExerciseTrendDetailBuilder.draftEntries(
            exerciseID: viewModel.exerciseID,
            suggestion: viewModel.suggestion
        )
        let draft = WorkoutSession(
            name: viewModel.displayName,
            kind: .strength,
            entries: entries
        )
        try? viewModel.repository.save(session: draft)

        showStartConfirm = false
        onStartTraining(draft.id)
    }
}

// MARK: - 时间范围菜单内容

/// 四个范围选项。与统计页的六项分开写：
/// 统计页要「本月 / 今年」这种日历区间，趋势页不需要——
/// 「本月」在一个月刚开始时会给出近乎空白的图。
struct TrendRangeMenuContent: View {

    let selected: TrendRangeKind
    let onSelect: (TrendRangeKind) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(TrendRangeKind.allCases) { kind in
                Button {
                    Haptics.light()
                    onSelect(kind)
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title)
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Palette.textPrimary)

                            Text(kind.subtitle)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }

                        Spacer(minLength: 0)

                        if kind == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(DS.Palette.accent)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind.title)
                .accessibilityAddTraits(kind == selected ? [.isSelected] : [])

                if kind != TrendRangeKind.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }
}

// MARK: - 预览

#Preview("动作历史趋势 · 有数据") {
    ExerciseTrendDetailView(
        viewModel: ExerciseTrendDetailViewModel(
            exerciseID: "0001",
            fallbackName: "杠铃卧推",
            repository: PreviewFitnessRepository.makeStrengthHistory()
        ),
        onBack: {},
        onOpenSessionDetail: { _ in },
        onStartTraining: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("动作历史趋势 · 空数据") {
    ExerciseTrendDetailView(
        viewModel: ExerciseTrendDetailViewModel(
            exerciseID: "9999",
            fallbackName: "某个没练过的动作",
            repository: PreviewFitnessRepository.makeEmpty()
        ),
        onBack: {},
        onOpenSessionDetail: { _ in },
        onStartTraining: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("时间范围菜单") {
    TrendRangeMenuContent(selected: .last3Months, onSelect: { _ in })
        .padding()
        .background(DS.Palette.bg)
        .preferredColorScheme(.dark)
}
