//
//  PlanListView.swift
//  页面 15：我的计划。
//
//  纯本地计划管理：搜索 / 排序 / 三点菜单 / 长按多选 / 批量删除与导出 /
//  「＋」新建力量计划与导入本地备份。
//  只读本地私人计划，不展示官方计划、公开计划、好友计划或社区内容。
//
//  写入全部经 `FitnessRepository`；列表用 `LazyVStack` 承载长列表。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class PlanListViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let repository: FitnessRepository

    @Published private(set) var loadState: LoadState = .loading
    /// 全部计划（未排序、未筛选的原始集合）
    @Published private(set) var allPlans: [Plan] = []
    /// 搜索词
    @Published var searchQuery: String = ""
    /// 当前排序方式
    @Published var sortOrder: PlanSortOrder = .recentlyUsed
    /// 多选模式下选中的计划 id 集合
    @Published private(set) var selectedIDs: Set<UUID> = []
    /// 是否处于多选模式
    @Published private(set) var isSelecting = false
    /// 轻量提示
    @Published var toast: String?

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    // MARK: 派生

    /// 按当前排序与搜索词过滤后的计划列表。
    var visiblePlans: [Plan] {
        let filtered = PlanListSorting.filter(allPlans, query: searchQuery)
        return PlanListSorting.sort(filtered, by: sortOrder)
    }

    /// 搜索框输入是否产生「无匹配」结果（有输入、无结果）。
    var isSearchingWithNoResult: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && visiblePlans.isEmpty
    }

    /// 是否一个计划都没有（原始集合为空）。
    var isEmpty: Bool { allPlans.isEmpty }

    // MARK: 加载

    func load() {
        loadState = .loading
        do {
            allPlans = try repository.fetchPlans()
            loadState = .loaded
        } catch {
            loadState = .failed("读取计划失败：\(error.localizedDescription)")
        }
    }

    func reload() { load() }

    // MARK: 多选

    func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
        // 全部取消选中时退出多选模式，回到普通浏览
        if selectedIDs.isEmpty { isSelecting = false }
    }

    func enterSelecting(with id: UUID) {
        isSelecting = true
        selectedIDs = [id]
    }

    func exitSelecting() {
        isSelecting = false
        selectedIDs = []
    }

    func isSelected(_ id: UUID) -> Bool { selectedIDs.contains(id) }

    // MARK: 复制

    /// 复制计划。返回副本，供上层决定是否跳转。
    @discardableResult
    func duplicate(_ plan: Plan) -> Plan? {
        do {
            guard let copy = try repository.duplicate(planID: plan.id) else {
                toast = "复制失败"
                return nil
            }
            reload()
            showToast("已创建副本「\(copy.name)」")
            return copy
        } catch {
            showToast("复制失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: 删除

    /// 删除单个计划。只删计划，不删历史训练记录。
    func delete(_ plan: Plan) {
        do {
            try repository.delete(planID: plan.id)
            reload()
            showToast("已删除「\(plan.name)」")
        } catch {
            showToast("删除失败：\(error.localizedDescription)")
        }
    }

    /// 批量删除选中的计划。返回删除数量。
    @discardableResult
    func deleteSelected() -> Int {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return 0 }
        do {
            try repository.deletePlans(ids: ids)
            let count = ids.count
            selectedIDs = []
            isSelecting = false
            reload()
            showToast("已删除 \(count) 个计划")
            return count
        } catch {
            showToast("删除失败：\(error.localizedDescription)")
            return 0
        }
    }

    // MARK: 导入

    /// 导入本地计划备份。返回导入的计划数量（-1 表示失败）。
    func importBackup(from url: URL) -> Int {
        do {
            let data = try Data(contentsOf: url)
            let imported = try PlanBackupCodec.decode(data)
            for plan in imported {
                try repository.save(plan: plan)
            }
            reload()
            showToast("已导入 \(imported.count) 个计划")
            return imported.count
        } catch {
            showToast("导入失败：\(error.localizedDescription)")
            return -1
        }
    }

    // MARK: 导出

    /// 导出选中的计划到临时文件，返回文件 URL 供分享面板。
    func exportSelected() -> URL? {
        let selected = allPlans.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        do {
            return try PlanBackupCodec.write(plans: selected)
        } catch {
            showToast("导出失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: toast

    func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.toast == message else { return }
            self.toast = nil
        }
    }
}

// MARK: - 页面

struct PlanListView: View {

    @StateObject private var viewModel: PlanListViewModel

    /// 进入计划详情与编辑页
    let onOpenPlan: (Plan) -> Void
    /// 开始训练：上层负责建草稿并推进训练执行页
    let onStartTraining: (Plan) -> Void
    /// 新建力量计划（打开命名抽屉，由上层处理）
    let onNewPlan: () -> Void
    /// 导入本地计划备份
    let onImportBackup: () -> Void
    /// 返回上一页
    let onBack: () -> Void

    // 弹层状态
    @State private var menuPlan: Plan?
    @State private var pendingDelete: Plan?
    @State private var showBatchDeleteConfirm = false
    @State private var exportedFile: ExportedFile?

    init(
        repository: FitnessRepository,
        onOpenPlan: @escaping (Plan) -> Void,
        onStartTraining: @escaping (Plan) -> Void,
        onNewPlan: @escaping () -> Void,
        onImportBackup: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: PlanListViewModel(repository: repository)
        )
        self.onOpenPlan = onOpenPlan
        self.onStartTraining = onStartTraining
        self.onNewPlan = onNewPlan
        self.onImportBackup = onImportBackup
        self.onBack = onBack
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            content

            if let toast = viewModel.toast {
                ToastBanner(text: toast)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { viewModel.load() }
        .animation(DS.Motion.standard, value: viewModel.toast)
        .confirmationDialog(
            "计划操作",
            isPresented: Binding(
                get: { menuPlan != nil },
                set: { if !$0 { menuPlan = nil } }
            ),
            presenting: menuPlan,
            titleVisibility: .visible
        ) { plan in
            Button("开始训练") { onStartTraining(plan) }
            Button("编辑") { onOpenPlan(plan) }
            Button("复制计划") { _ = viewModel.duplicate(plan) }
            Button("删除计划", role: .destructive) { pendingDelete = plan }
        } message: { plan in
            Text(plan.name)
        }
        .alert(
            "删除计划",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { plan in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                viewModel.delete(plan)
                pendingDelete = nil
            }
        } message: { plan in
            Text("「\(plan.name)」将被删除，已完成的历史训练记录不受影响。")
        }
        .alert(
            "批量删除计划",
            isPresented: $showBatchDeleteConfirm
        ) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { _ = viewModel.deleteSelected() }
        } message: {
            Text("将删除选中的 \(viewModel.selectedIDs.count) 个计划，已完成的历史训练记录不受影响。")
        }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            PlanListSkeleton()

        case .failed(let message):
            EmptyStateView(
                message: message,
                actionTitle: "重试",
                action: { viewModel.reload() }
            )

        case .loaded:
            if viewModel.isEmpty {
                EmptyStateView(
                    message: "还没有训练计划",
                    actionTitle: "新建第一个计划",
                    action: { onNewPlan() }
                )
            } else {
                listContent
            }
        }
    }

    private var listContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.item) {
                searchAndSort

                if viewModel.isSearchingWithNoResult {
                    EmptyStateView(message: "没有匹配的计划")
                        .padding(.top, DS.Spacing.section)
                } else {
                    ForEach(viewModel.visiblePlans) { plan in
                        planCard(plan)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
    }

    // MARK: 搜索与排序

    private var searchAndSort: some View {
        VStack(spacing: DS.Spacing.item) {
            searchField
            sortRow
        }
    }

    private var searchField: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)

            TextField("按名称筛选", text: $viewModel.searchQuery)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .accessibilityLabel("按名称筛选计划")
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
                    ForEach(PlanSortOrder.allCases) { order in
                        sortChip(order)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func sortChip(_ order: PlanSortOrder) -> some View {
        let selected = viewModel.sortOrder == order
        return Button {
            Haptics.light()
            viewModel.sortOrder = order
        } label: {
            Text(order.title)
                .font(DS.Typography.caption2)
                .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(selected ? DS.Palette.accent : DS.Palette.fieldFill)
                )
                .overlay(
                    Capsule().stroke(selected ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("按\(order.title)排序")
    }

    // MARK: 计划卡片

    private func planCard(_ plan: Plan) -> some View {
        Button {
            if viewModel.isSelecting {
                Haptics.light()
                viewModel.toggleSelection(plan.id)
            } else {
                Haptics.light()
                onOpenPlan(plan)
            }
        } label: {
            PlanCardContent(
                plan: plan,
                isSelecting: viewModel.isSelecting,
                isSelected: viewModel.isSelected(plan.id)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            if !viewModel.isSelecting {
                Button {
                    onStartTraining(plan)
                } label: {
                    Label("开始训练", systemImage: "play.fill")
                }
                Button {
                    onOpenPlan(plan)
                } label: {
                    Label("编辑", systemImage: "pencil")
                }
                Button {
                    _ = viewModel.duplicate(plan)
                } label: {
                    Label("复制计划", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    pendingDelete = plan
                } label: {
                    Label("删除计划", systemImage: "trash")
                }
            }
        }
        .onLongPressGesture {
            Haptics.medium()
            viewModel.enterSelecting(with: plan.id)
        }
        .accessibilityLabel(PlanListAccessibility.cardLabel(plan, isSelected: viewModel.isSelected(plan.id)))
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            if viewModel.isSelecting {
                Button {
                    Haptics.light()
                    viewModel.exitSelecting()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消多选")

                Text("已选 \(viewModel.selectedIDs.count) 项")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                batchDeleteButton
                batchExportButton
            } else {
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

                Text("我的计划")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                addButton
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    /// 「＋」按钮：新建力量计划 / 导入本地计划备份。
    private var addButton: some View {
        Menu {
            Button {
                onNewPlan()
            } label: {
                Label("新建力量计划", systemImage: "plus.circle")
            }
            Button {
                onImportBackup()
            } label: {
                Label("导入本地计划备份", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("新建或导入计划")
    }

    private var batchDeleteButton: some View {
        Button {
            guard !viewModel.selectedIDs.isEmpty else { return }
            Haptics.warning()
            showBatchDeleteConfirm = true
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.selectedIDs.isEmpty ? DS.Palette.textTertiary : DS.Palette.danger)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedIDs.isEmpty)
        .accessibilityLabel("批量删除选中计划")
    }

    private var batchExportButton: some View {
        Button {
            guard let url = viewModel.exportSelected() else { return }
            exportedFile = ExportedFile(url: url)
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(viewModel.selectedIDs.isEmpty ? DS.Palette.textTertiary : DS.Palette.accent)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedIDs.isEmpty)
        .accessibilityLabel("批量导出选中计划")
    }
}

// MARK: - 卡片内容

/// 单张计划卡片的内容：名称 + 四行信息 + 三点菜单 / 多选勾选。
struct PlanCardContent: View {

    let plan: Plan
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        CardContainer {
            HStack(alignment: .top, spacing: DS.Spacing.item) {
                if isSelecting {
                    selectionBadge
                }

                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text(plan.name)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)

                    Text(plan.frequencyText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: DS.Spacing.tight) {
                        Text("\(plan.exerciseCount) 个动作")
                        Text("·")
                        Text("预计 \(plan.estimatedMinutes) 分钟")
                    }
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)

                    Text(lastUsedText)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !isSelecting {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: DS.Size.minTapTarget, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
    }

    /// 多选模式的选中徽章。
    private var selectionBadge: some View {
        ZStack {
            Circle()
                .fill(isSelected ? DS.Palette.accent : Color.clear)
                .frame(width: 24, height: 24)
            Circle()
                .stroke(isSelected ? Color.clear : DS.Palette.checkboxIdle, lineWidth: 1.6)
                .frame(width: 24, height: 24)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.onAccent)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }

    /// 最后训练日期文案。
    private var lastUsedText: String {
        guard let lastUsedAt = plan.lastUsedAt else { return "尚未训练" }
        return "上次训练 \(FormatterKit.shortDate(lastUsedAt))"
    }
}

// MARK: - 无障碍文案

enum PlanListAccessibility {
    /// 计划卡片的 VoiceOver 文案。
    static func cardLabel(_ plan: Plan, isSelected: Bool) -> String {
        var parts = [plan.name, plan.frequencyText, "\(plan.exerciseCount) 个动作"]
        parts.append("预计 \(plan.estimatedMinutes) 分钟")
        if let lastUsedAt = plan.lastUsedAt {
            parts.append("上次训练 \(FormatterKit.shortDate(lastUsedAt))")
        } else {
            parts.append("尚未训练")
        }
        if isSelected { parts.append("已选中") }
        return parts.joined(separator: "，")
    }
}

// MARK: - 骨架屏

/// 计划列表骨架屏。
struct PlanListSkeleton: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                SkeletonBlock(height: 44)
                SkeletonBlock(height: 34)
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonBlock(height: 118)
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入计划")
    }
}

// MARK: - 新建计划命名

/// 新建力量计划时的命名抽屉内容。
struct NewPlanNameContent: View {

    let onCreate: (String) -> Void

    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            TextField("计划名称", text: $name)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.done)
                .onSubmit { submit() }
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

            PrimaryButton(title: "创建计划", isEnabled: !trimmedName.isEmpty) {
                submit()
            }
        }
        .padding(DS.Spacing.card)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName)
    }
}

// MARK: - 预览

#Preview("我的计划") {
    PlanListView(
        repository: PreviewFitnessRepository(),
        onOpenPlan: { _ in },
        onStartTraining: { _ in },
        onNewPlan: {},
        onImportBackup: {},
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
