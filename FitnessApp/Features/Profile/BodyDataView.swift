//
//  BodyDataView.swift
//  页面 12：身体数据。
//
//  入口：我的页「身体数据」卡片。
//
//  整页只管理本地身体测量记录，不接入健康平台、账号、社交或云同步。
//  所有聚合在 `BodyData.swift` 的纯值层完成，单位换算只影响展示。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class BodyDataViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum Segment: String, CaseIterable, Identifiable {
        case trend
        case record

        var id: String { rawValue }

        var title: String {
            switch self {
            case .trend: return "趋势"
            case .record: return "记录"
            }
        }
    }

    let repository: FitnessRepository

    @Published private(set) var loadState: LoadState = .loading
    /// 原始记录，按日期倒序。派生值（摘要 / 趋势 / 统计）都是它的计算属性，
    /// 不存在「缓存与源数据漂移」的问题——数据量至多几百条，现算即可。
    @Published private(set) var measurements: [BodyMeasurement] = []
    @Published var segment: Segment = .trend
    @Published var selectedMetric: BodyMetric = .weight
    @Published var selectedPointID: UUID?

    /// 单位偏好。只影响展示，存 UserDefaults（纯本地设置）。
    @Published var weightUnit: BodyWeightUnit {
        didSet { UserDefaults.standard.set(weightUnit.rawValue, forKey: Self.weightUnitKey) }
    }
    @Published var lengthUnit: BodyLengthUnit {
        didSet { UserDefaults.standard.set(lengthUnit.rawValue, forKey: Self.lengthUnitKey) }
    }

    private static let weightUnitKey = "preference.bodyWeightUnit"
    private static let lengthUnitKey = "preference.bodyLengthUnit"

    private let calendar = Calendar.current

    init(repository: FitnessRepository) {
        self.repository = repository
        let weightRaw = UserDefaults.standard.string(forKey: Self.weightUnitKey) ?? ""
        self.weightUnit = BodyWeightUnit(rawValue: weightRaw) ?? .kilograms
        let lengthRaw = UserDefaults.standard.string(forKey: Self.lengthUnitKey) ?? ""
        self.lengthUnit = BodyLengthUnit(rawValue: lengthRaw) ?? .centimeters
    }

    // MARK: 派生

    var isEmpty: Bool { measurements.isEmpty }

    var overview: BodyDataOverview {
        BodyDataBuilder.overview(measurements: measurements)
    }

    var points: [BodyMetricPoint] {
        BodyDataBuilder.points(for: selectedMetric, measurements: measurements)
    }

    var stats: BodyMetricStats {
        BodyDataBuilder.stats(for: selectedMetric, measurements: measurements)
    }

    /// 趋势图是否可绘：至少两条记录。
    var hasEnoughForTrend: Bool { points.count >= 2 }

    var trendSummary: String {
        BodyDataBuilder.trendSummary(
            metric: selectedMetric,
            points: points,
            stats: stats,
            weightUnit: weightUnit,
            lengthUnit: lengthUnit
        )
    }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            let fetched = try repository.fetchBodyMeasurements(
                limit: BodyDataBuilder.fetchLimit
            )
            measurements = fetched.sorted { $0.date > $1.date }
            loadState = .loaded
        } catch {
            loadState = .failed("读取身体数据失败：\(error.localizedDescription)")
        }
    }

    func reload() async {
        await load()
    }

    // MARK: 交互

    func selectMetric(_ metric: BodyMetric) {
        guard metric != selectedMetric else { return }
        selectedMetric = metric
        // 旧指标的选中点在新指标里不一定存在，留着会指向一个看不见的点。
        selectedPointID = nil
    }

    /// 与给定日期同一自然日的已有记录（不含自身）。nil 表示没有冲突。
    func conflict(on date: Date, excluding id: UUID?) -> BodyMeasurement? {
        BodyDataBuilder.existingMeasurement(
            on: date, excluding: id, measurements: measurements, calendar: calendar
        )
    }

    /// 保存。仓储层保证同一天只留一条（覆盖语义）。
    func save(_ measurement: BodyMeasurement) {
        try? repository.save(measurement: measurement)
        refresh()
    }

    func delete(_ measurement: BodyMeasurement) {
        try? repository.delete(measurementID: measurement.id)
        refresh()
    }

    /// 保存 / 删除后重读盘，并清掉可能已失效的选中点。
    /// 「使训练统计与趋势缓存失效」在本页的落点就是这里：派生值全部重新计算。
    private func refresh() {
        measurements = (try? repository.fetchBodyMeasurements(limit: BodyDataBuilder.fetchLimit))
            .map { $0.sorted { $0.date > $1.date } } ?? measurements
        selectedPointID = nil
    }
}

// MARK: - 页面

struct BodyDataView: View {

    @ObservedObject var viewModel: BodyDataViewModel
    let onBack: () -> Void
    /// 保存 / 删除后通知外层，让我的页的摘要卡刷新。
    let onDataChanged: () -> Void

    @State private var showEditor = false
    @State private var editingMeasurement: BodyMeasurement?
    @State private var pendingDraft: BodyMeasurement?
    @State private var showOverwriteConfirm = false
    @State private var pendingDelete: BodyMeasurement?
    @State private var showDeleteConfirm = false

    @Environment(\.sizeCategory) private var sizeCategory

    private var useListFallback: Bool {
        BodyAccessibilityScale.shouldUseList(sizeCategory)
    }

    var body: some View {
        List {
            switch viewModel.loadState {
            case .loading:
                row { BodyDataSkeleton() }

            case .failed(let message):
                row {
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.reload() } }
                    )
                }

            case .loaded:
                row {
                    BodySummaryCard(
                        overview: viewModel.overview,
                        weightUnit: $viewModel.weightUnit,
                        lengthUnit: $viewModel.lengthUnit
                    )
                }

                row { BodySegmentControl(segment: $viewModel.segment) }

                // 注意：这里必须把趋势 / 记录的内容**直接内联**进 List 的
                // ViewBuilder，不能包在一个 `@ViewBuilder var` 里再引用——
                // List 只展平它自己 ViewBuilder 产出的顶层 TupleView，
                // 嵌套的 TupleView（来自某个 var）会被当成一整行。
                if viewModel.segment == .trend {
                    BodyMetricChipRow(selected: viewModel.selectedMetric) { metric in
                        viewModel.selectMetric(metric)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(DS.Palette.bg)

                    if viewModel.hasEnoughForTrend {
                        row { trendCard }
                    } else {
                        row {
                            EmptyStateView(message: "记录更多数据后可查看趋势")
                        }
                    }
                } else {
                    if viewModel.measurements.isEmpty {
                        row {
                            EmptyStateView(message: "还没有身体数据记录")
                        }
                    } else {
                        ForEach(viewModel.measurements) { measurement in
                            BodyRecordCard(
                                measurement: measurement,
                                weightUnit: viewModel.weightUnit,
                                lengthUnit: viewModel.lengthUnit
                            ) {
                                Haptics.light()
                                openEditor(measurement)
                            }
                            .listRowInsets(EdgeInsets(
                                top: 6, leading: DS.Spacing.page, bottom: 6, trailing: DS.Spacing.page
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(DS.Palette.bg)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = measurement
                                    showDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    pendingDelete = measurement
                                    showDeleteConfirm = true
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .bottomDrawer(
            isPresented: $showEditor,
            height: 640,
            title: editingMeasurement == nil ? "新增身体数据" : "编辑身体数据",
            subtitle: "至少填写一个测量值"
        ) {
            ScrollView(.vertical, showsIndicators: false) {
                BodyEditorContent(editing: editingMeasurement) { draft in
                    submit(draft)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.bottom, DS.Spacing.card)
            }
        }
        .bottomDrawer(
            isPresented: $showOverwriteConfirm,
            height: 320,
            title: nil,
            subtitle: nil
        ) {
            if let pendingDraft {
                BodyOverwriteConfirmContent(
                    existingDate: pendingDraft.date,
                    onCancel: { showOverwriteConfirm = false },
                    onOverwrite: {
                        showOverwriteConfirm = false
                        commit(pendingDraft)
                    }
                )
                .padding(.horizontal, DS.Spacing.card)
            }
        }
        .bottomDrawer(
            isPresented: $showDeleteConfirm,
            height: 320,
            title: nil,
            subtitle: nil
        ) {
            if let pendingDelete {
                BodyDeleteConfirmContent(
                    measurement: pendingDelete,
                    weightUnit: viewModel.weightUnit,
                    lengthUnit: viewModel.lengthUnit,
                    onCancel: { showDeleteConfirm = false },
                    onDelete: {
                        showDeleteConfirm = false
                        viewModel.delete(pendingDelete)
                        Haptics.success()
                        onDataChanged()
                    }
                )
                .padding(.horizontal, DS.Spacing.card)
            }
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

            Text("身体数据")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                Haptics.light()
                openEditor(nil)
            } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新增身体数据")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    // MARK: 趋势卡

    private var trendCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("\(viewModel.selectedMetric.title)趋势")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                if useListFallback {
                    BodyMetricPointList(
                        points: viewModel.points,
                        metric: viewModel.selectedMetric,
                        weightUnit: viewModel.weightUnit,
                        lengthUnit: viewModel.lengthUnit
                    )
                } else {
                    BodyTrendChart(
                        points: viewModel.points,
                        selectedID: $viewModel.selectedPointID
                    )

                    if let selectedID = viewModel.selectedPointID,
                       let point = viewModel.points.first(where: { $0.id == selectedID }) {
                        BodySelectedDetail(
                            point: point,
                            metric: viewModel.selectedMetric,
                            weightUnit: viewModel.weightUnit,
                            lengthUnit: viewModel.lengthUnit
                        )
                    }
                }

                BodyStatGrid(
                    metric: viewModel.selectedMetric,
                    stats: viewModel.stats,
                    weightUnit: viewModel.weightUnit,
                    lengthUnit: viewModel.lengthUnit
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.trendSummary)
    }

    // MARK: 编辑

    private func openEditor(_ measurement: BodyMeasurement?) {
        editingMeasurement = measurement
        showEditor = true
    }

    /// 编辑器保存：先查同日冲突，冲突则转覆盖确认，否则直接落盘。
    private func submit(_ draft: BodyMeasurement) {
        if viewModel.conflict(on: draft.date, excluding: draft.id) != nil {
            showEditor = false
            pendingDraft = draft
            showOverwriteConfirm = true
        } else {
            commit(draft)
            showEditor = false
        }
    }

    private func commit(_ draft: BodyMeasurement) {
        viewModel.save(draft)
        Haptics.success()
        onDataChanged()
    }
}

// MARK: - 分段控件

/// 「趋势 / 记录」分段控件。自定义实现，选中态用荧光绿，与系统分段控件的
/// 蓝色选中态区分开（页面 11 的单位切换器同一理由）。
struct BodySegmentControl: View {

    @Binding var segment: BodyDataViewModel.Segment

    var body: some View {
        HStack(spacing: 0) {
            ForEach(BodyDataViewModel.Segment.allCases) { option in
                Button {
                    Haptics.light()
                    segment = option
                } label: {
                    Text(option.title)
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(
                            segment == option ? DS.Palette.onAccent : DS.Palette.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(segment == option ? DS.Palette.accent : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(segment == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip + 3, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip + 3, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - 行封装

/// 把任意内容包成一个无分隔线、无背景的 List 行，统一本页的 List 行样式。
private struct BodyListRow<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .listRowInsets(EdgeInsets(
                top: 6, leading: DS.Spacing.page, bottom: 6, trailing: DS.Spacing.page
            ))
            .listRowSeparator(.hidden)
            .listRowBackground(DS.Palette.bg)
    }
}

extension BodyDataView {
    /// 本页统一的 List 行封装。
    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        BodyListRow(content: content)
    }
}

// MARK: - 预览

#Preview("身体数据 · 有数据") {
    BodyDataView(
        viewModel: BodyDataViewModel(repository: PreviewFitnessRepository()),
        onBack: {},
        onDataChanged: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("身体数据 · 空数据") {
    BodyDataView(
        viewModel: BodyDataViewModel(repository: PreviewFitnessRepository.makeEmpty()),
        onBack: {},
        onDataChanged: {}
    )
    .preferredColorScheme(.dark)
}
