//
//  SelectPlanView.swift
//  页面 28：选择要添加到的计划。
//
//  搜索 / 排序（最近使用 / 最近创建 / 名称）/ 新建计划（名称 + 每周训练天数）。
//  若计划已包含该动作，选择后提示「计划已包含该动作」，可选新增一份 / 替换原配置 / 取消。
//  不展示官方、公开或他人计划。
//

import SwiftUI

// MARK: - 排序

enum PlanPickSort: String, CaseIterable, Identifiable {
    case recentlyUsed
    case recentlyCreated
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUsed: return "最近使用"
        case .recentlyCreated: return "最近创建"
        case .name: return "名称"
        }
    }
}

// MARK: - 纯逻辑

enum PlanPickLogic {

    /// 按名称实时筛选计划。
    static func filter(_ plans: [Plan], query: String) -> [Plan] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return plans }
        return plans.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    /// 按当前排序方式排序。
    static func sort(_ plans: [Plan], by order: PlanPickSort) -> [Plan] {
        switch order {
        case .recentlyUsed:
            return plans.sorted { lhs, rhs in
                let l = lhs.lastUsedAt ?? .distantPast
                let r = rhs.lastUsedAt ?? .distantPast
                if l != r { return l > r }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .recentlyCreated:
            return plans.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .name:
            return plans.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    /// 计划是否已包含该动作。
    static func planContains(_ plan: Plan, exerciseID: String) -> Bool {
        plan.exercises.contains { $0.exerciseID == exerciseID }
    }
}

// MARK: - ViewModel

@MainActor
final class SelectPlanViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let exerciseID: String
    private let repository: FitnessRepository

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var allPlans: [Plan] = []
    @Published var searchQuery: String = ""
    @Published var sortOrder: PlanPickSort = .recentlyUsed

    init(exerciseID: String, repository: FitnessRepository) {
        self.exerciseID = exerciseID
        self.repository = repository
    }

    var visiblePlans: [Plan] {
        PlanPickLogic.sort(
            PlanPickLogic.filter(allPlans, query: searchQuery),
            by: sortOrder
        )
    }

    var isEmpty: Bool { allPlans.isEmpty }

    func load() {
        loadState = .loading
        do {
            allPlans = try repository.fetchPlans()
            loadState = .loaded
        } catch {
            loadState = .failed("读取计划失败：\(error.localizedDescription)")
        }
    }

    /// 计划是否已包含当前动作。
    func containsExercise(_ plan: Plan) -> Bool {
        PlanPickLogic.planContains(plan, exerciseID: exerciseID)
    }
}

// MARK: - 页面

struct SelectPlanView: View {

    @StateObject private var viewModel: SelectPlanViewModel
    /// 选中计划（Bool = 是否「替换原配置」）
    let onPick: (Plan, Bool) -> Void
    /// 新建计划：名称 + 每周训练天数
    let onNewPlan: (String, [Int]) -> Void
    let onCancel: () -> Void

    @State private var showNewPlan = false
    /// 命中的冲突计划（已包含该动作）
    @State private var conflictPlan: Plan?

    init(
        exerciseID: String,
        repository: FitnessRepository,
        onPick: @escaping (Plan, Bool) -> Void,
        onNewPlan: @escaping (String, [Int]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SelectPlanViewModel(exerciseID: exerciseID, repository: repository)
        )
        self.onPick = onPick
        self.onNewPlan = onNewPlan
        self.onCancel = onCancel
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.item) {
                searchField
                sortRow

                switch viewModel.loadState {
                case .loading:
                    PlanListSkeleton()
                case .failed(let message):
                    EmptyStateView(message: message, actionTitle: "重试") { viewModel.load() }
                case .loaded:
                    if viewModel.isEmpty {
                        EmptyStateView(message: "还没有训练计划", actionTitle: "新建计划") {
                            showNewPlan = true
                        }
                    } else if viewModel.visiblePlans.isEmpty {
                        EmptyStateView(message: "没有匹配的计划")
                    } else {
                        ForEach(viewModel.visiblePlans) { plan in
                            planRow(plan)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { viewModel.load() }
        .confirmationDialog(
            "计划已包含该动作",
            isPresented: Binding(
                get: { conflictPlan != nil },
                set: { if !$0 { conflictPlan = nil } }
            ),
            presenting: conflictPlan,
            titleVisibility: .visible
        ) { plan in
            Button("新增一份") { onPick(plan, false); conflictPlan = nil }
            Button("替换原配置") { onPick(plan, true); conflictPlan = nil }
            Button("取消", role: .cancel) { conflictPlan = nil }
        } message: { plan in
            Text("「\(plan.name)」已包含该动作。")
        }
        .sheet(isPresented: $showNewPlan) {
            NewPlanWithDaysSheet(
                onCreate: { name, days in
                    showNewPlan = false
                    onNewPlan(name, days)
                }
            )
        }
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("取消")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消选择计划")

            Spacer(minLength: DS.Spacing.item)

            Text("选择计划")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                showNewPlan = true
            } label: {
                Text("新建计划")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建计划")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    private var searchField: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)

            TextField("按计划名称筛选", text: $viewModel.searchQuery)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("按计划名称筛选")
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    private var sortRow: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text("排序")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.tight) {
                    ForEach(PlanPickSort.allCases) { order in
                        let selected = viewModel.sortOrder == order
                        Button {
                            Haptics.light()
                            viewModel.sortOrder = order
                        } label: {
                            Text(order.title)
                                .font(DS.Typography.caption2)
                                .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.textSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(selected ? DS.Palette.accent : DS.Palette.fieldFill))
                                .overlay(Capsule().stroke(selected ? Color.clear : DS.Palette.stroke, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? [.isSelected] : [])
                        .accessibilityLabel("按\(order.title)排序")
                    }
                }
            }
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        Button {
            Haptics.light()
            if viewModel.containsExercise(plan) {
                conflictPlan = plan
            } else {
                onPick(plan, false)
            }
        } label: {
            HStack(spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.name)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)

                    Text(metaText(plan))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(plan.name)，\(metaText(plan))")
    }

    private func metaText(_ plan: Plan) -> String {
        var parts = [plan.frequencyText, "\(plan.exerciseCount) 个动作"]
        if let lastUsedAt = plan.lastUsedAt {
            parts.append("上次 \(FormatterKit.shortDate(lastUsedAt))")
        } else {
            parts.append("尚未训练")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 新建计划（名称 + 每周训练天数）

private struct NewPlanWithDaysSheet: View {

    let onCreate: (String, [Int]) -> Void

    @State private var name: String = ""
    @State private var daysPerWeek: Int = 3

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    Text("计划名称")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)

                    TextField("例如：推拉腿 · 三日", text: $name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(DS.Palette.fieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(DS.Palette.stroke, lineWidth: 1)
                        )
                        .accessibilityLabel("计划名称")
                }

                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    Text("每周训练天数")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)

                    StepperBlock(
                        value: $daysPerWeek,
                        range: 1...7,
                        step: 1,
                        valueText: "\(daysPerWeek) 天",
                        accessibilityLabel: "每周训练天数"
                    )
                }

                PrimaryButton(title: "创建并选择", isEnabled: !trimmedName.isEmpty) {
                    create()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.section)
            .background(DS.Palette.bg)
            .navigationTitle("新建计划")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        // 简化：每周训练 N 天 = 周一 … 依次排布
        let days = Array(1...daysPerWeek)
        onCreate(trimmedName, days)
        dismiss()
    }
}

// MARK: - 预览

#Preview("选择计划") {
    SelectPlanView(
        exerciseID: "0025",
        repository: PreviewFitnessRepository(),
        onPick: { _, _ in },
        onNewPlan: { _, _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
