//
//  FavoriteExercisesView.swift
//  页面 16：收藏动作。
//
//  从「我的」进入。数据只来自本地动作库的 `isFavorite` 状态，
//  不展示任何公开收藏 / 好友收藏 / 点赞数或分享入口。
//
//  结构：导航栏（返回 / 标题 / 排序）→ 搜索框 → 肌群 Chip → 收藏列表。
//  每行右侧是已收藏的荧光绿星标，点击取消收藏（180ms 淡出 + toast + 撤销）；
//  长按显示「添加到训练 / 查看详情 / 取消收藏（+ 自定义动作的编辑）」。
//

import SwiftUI

struct FavoriteExercisesView: View {

    let repository: FitnessRepository
    let onBack: () -> Void
    /// 查看详情：跨 Tab 到动作 Tab，由 RootView 打开动作详情
    let onOpenExercise: (ExerciseLibraryItem) -> Void
    /// 空状态「浏览动作库」：跨 Tab 到动作 Tab
    let onBrowseExercises: () -> Void

    @StateObject private var viewModel: FavoriteExercisesViewModel

    /// 待添加到训练的动作（弹「添加到训练」流程）
    @State private var addTarget: ExerciseLibraryItem?
    /// 待编辑的自定义动作
    @State private var editingCustom: ExerciseLibraryItem?

    init(
        repository: FitnessRepository,
        onBack: @escaping () -> Void,
        onOpenExercise: @escaping (ExerciseLibraryItem) -> Void,
        onBrowseExercises: @escaping () -> Void
    ) {
        self.repository = repository
        self.onBack = onBack
        self.onOpenExercise = onOpenExercise
        self.onBrowseExercises = onBrowseExercises
        _viewModel = StateObject(
            wrappedValue: FavoriteExercisesViewModel(repository: repository)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    ExerciseListSkeleton(rowCount: 6)

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    listSection
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .animation(DS.Motion.standard, value: viewModel.undoItem?.id)
        .task { await viewModel.load() }
        .overlay(alignment: .bottom) { undoToast }
        .alert(
            "操作未完成",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(item: $addTarget) { item in
            AddExerciseToWorkoutFlow(item: item, repository: repository) {
                addTarget = nil
                viewModel.reloadAfterExternalChange()
            }
        }
        .sheet(item: $editingCustom) { item in
            CustomExerciseEditor(repository: repository, editing: item) { saved in
                try? repository.save(exercise: saved)
                editingCustom = nil
                viewModel.reloadAfterExternalChange()
            } onDeleted: {
                editingCustom = nil
                viewModel.reloadAfterExternalChange()
            }
        }
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .center) {
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

                Text("收藏动作")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: DS.Spacing.item)

                sortMenu
            }

            searchField
            muscleChips
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.tight)
        .padding(.bottom, DS.Spacing.item)
        .background(DS.Palette.bg)
    }

    /// 排序菜单。选中项带勾。
    private var sortMenu: some View {
        Menu {
            ForEach(FavoriteSortOrder.allCases) { order in
                Button {
                    viewModel.sort = order
                } label: {
                    if viewModel.sort == order {
                        Label(order.title, systemImage: "checkmark")
                    } else {
                        Text(order.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("排序方式，当前 \(viewModel.sort.title)")
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .accessibilityHidden(true)

            TextField("搜索动作名称、别名、器械或肌群", text: $viewModel.searchText)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .tint(DS.Palette.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("搜索动作名称、别名、器械或肌群")

            if viewModel.isSearching {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("清除搜索内容")
            }
        }
        .padding(.horizontal, DS.Spacing.item)
        .frame(minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: - 肌群筛选 Chip

    private var muscleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: "全部",
                    count: viewModel.favoriteCount,
                    isSelected: viewModel.muscleCategory == nil
                ) {
                    viewModel.setMuscleCategory(nil)
                }

                ForEach(viewModel.muscleCategories, id: \.self) { category in
                    chip(
                        title: category,
                        count: viewModel.muscleCounts[category],
                        isSelected: viewModel.muscleCategory == category
                    ) {
                        viewModel.setMuscleCategory(category)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("肌群筛选")
    }

    private var muscleCounts: [String: Int] {
        FavoriteExercisesFilter.muscleCounts(in: viewModel.favorites)
    }

    private func chip(
        title: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(DS.Typography.caption)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .opacity(isSelected ? 0.7 : 0.5)
                }
            }
            .foregroundStyle(isSelected ? DS.Palette.onAccent : DS.Palette.textSecondary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(
                Capsule().fill(isSelected ? DS.Palette.accent : DS.Palette.surfaceElevated)
            )
            .overlay(
                Capsule().stroke(
                    isSelected ? Color.clear : DS.Palette.stroke,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(count.map { "\(title)，\($0) 个动作" } ?? title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - 列表

    @ViewBuilder
    private var listSection: some View {
        let results = viewModel.results

        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(title: "收藏", trailingText: "\(results.count) 项")

            if results.isEmpty {
                emptyState
            } else {
                VStack(spacing: DS.Spacing.tight) {
                    ForEach(results) { item in
                        FavoriteExerciseRow(
                            item: item,
                            onOpen: { onOpenExercise(item) },
                            onUnfavorite: {
                                withAnimation(DS.Motion.numberFade) {
                                    viewModel.unfavorite(item)
                                }
                            },
                            onAddToWorkout: { addTarget = item },
                            onEdit: { editingCustom = item }
                        )
                        .transition(.opacity)
                    }
                }

                if results.contains(where: \.hasLocalMedia) {
                    MediaAttributionLabel()
                        .padding(.top, DS.Spacing.tight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.favorites.isEmpty && !viewModel.hasActiveCondition {
            // 库本身没有收藏：给「浏览动作库」入口
            EmptyStateView(
                message: "还没有收藏动作",
                actionTitle: "浏览动作库",
                action: onBrowseExercises
            )
        } else {
            EmptyStateView(
                message: emptySearchMessage,
                actionTitle: "清除筛选",
                action: { viewModel.resetAll() }
            )
        }
    }

    private var emptySearchMessage: String {
        if viewModel.isSearching {
            return "没有找到匹配「\(viewModel.debouncedKeyword)」的收藏动作。"
        }
        return "该肌群下没有收藏动作。"
    }

    // MARK: - 撤销提示

    @ViewBuilder
    private var undoToast: some View {
        if viewModel.undoItem != nil {
            HStack(spacing: DS.Spacing.item) {
                Text("已取消收藏")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer(minLength: DS.Spacing.item)

                Button("撤销") {
                    withAnimation(DS.Motion.numberFade) {
                        viewModel.undoUnfavorite()
                    }
                }
                .font(DS.Typography.footnote.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, DS.Spacing.item)
            .background(
                Capsule().fill(DS.Palette.surfaceElevated)
            )
            .overlay(
                Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .padding(.horizontal, DS.Spacing.page)
            .padding(.bottom, DS.Spacing.section)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }
}

// MARK: - 收藏动作行

private struct FavoriteExerciseRow: View {

    let item: ExerciseLibraryItem
    let onOpen: () -> Void
    let onUnfavorite: () -> Void
    let onAddToWorkout: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.item) {
            // 左侧整块：缩略图 + 名称 + 标签，点击打开详情
            Button(action: onOpen) {
                HStack(spacing: DS.Spacing.item) {
                    ExerciseThumbnail(item: item, size: 52)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.displayName)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: DS.Spacing.tight) {
                            tag(item.primaryMuscleText)
                            if !item.equipmentText.isEmpty {
                                tag(item.equipmentText)
                            }
                            tag(item.difficulty.title)
                            if item.isCustom {
                                tag("自定义", tint: DS.Palette.accent)
                            }
                        }
                    }

                    Spacer(minLength: DS.Spacing.tight)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("打开动作详情")

            // 右侧已收藏星标，独立可点：取消收藏
            Button(action: onUnfavorite) {
                Image(systemName: "star.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("取消收藏 \(item.displayName)")
        }
        .padding(DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .contextMenu { menu }
    }

    private var accessibilityText: String {
        var parts = [item.displayName, item.primaryMuscleText]
        if !item.equipmentText.isEmpty { parts.append(item.equipmentText) }
        parts.append(item.difficulty.title)
        if item.isCustom { parts.append("自定义动作") }
        parts.append("已收藏")
        return parts.joined(separator: "，")
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            onAddToWorkout()
        } label: {
            Label("添加到训练", systemImage: "plus.circle")
        }

        Button {
            onOpen()
        } label: {
            Label("查看详情", systemImage: "info.circle")
        }

        Button {
            onUnfavorite()
        } label: {
            Label("取消收藏", systemImage: "star.slash")
        }

        // 编辑入口只对自定义动作开放
        if item.isCustom {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }
        }
    }

    private func tag(_ text: String, tint: Color = DS.Palette.textSecondary) -> some View {
        Text(text)
            .font(DS.Typography.caption2)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(DS.Palette.surfaceElevated)
            )
    }
}

// MARK: - 添加到训练流程

/// 「添加到训练」的三步弹层：目标选择 → 处方设置 → 新建计划命名。
/// 复用 `ExerciseDetailViewModel` 的写库逻辑，与动作详情页的流程一致。
private struct AddExerciseToWorkoutFlow: View {

    let repository: FitnessRepository
    let onDone: () -> Void

    @StateObject private var viewModel: ExerciseDetailViewModel
    @State private var pendingPlan: Plan?
    @State private var showPrescription = false
    @State private var showNewPlanName = false

    init(
        item: ExerciseLibraryItem,
        repository: FitnessRepository,
        onDone: @escaping () -> Void
    ) {
        self.repository = repository
        self.onDone = onDone
        _viewModel = StateObject(
            wrappedValue: ExerciseDetailViewModel(item: item, repository: repository)
        )
    }

    var body: some View {
        AddToWorkoutSheet(
            item: viewModel.item,
            activeSessionSubtitle: viewModel.activeSessionSubtitle,
            plans: viewModel.plans,
            onAddToActiveSession: {
                viewModel.addToActiveSession()
            },
            onPickPlan: { plan in
                pendingPlan = plan
                // 让目标选择面板先收起，再弹出处方设置
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPrescription = true
                }
            },
            onCreatePlan: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewPlanName = true
                }
            }
        )
        .task { await viewModel.load() }
        .sheet(isPresented: $showPrescription) {
            if let plan = pendingPlan {
                ExercisePrescriptionSheet(
                    exerciseName: viewModel.item.displayName,
                    muscleText: viewModel.item.primaryMuscleText,
                    targetTitle: "添加到计划",
                    prescription: $viewModel.draft,
                    onCancel: { pendingPlan = nil },
                    onSave: {
                        viewModel.add(toPlan: plan.id)
                        pendingPlan = nil
                        showPrescription = false
                        onDone()
                    }
                )
            } else {
                EmptyView()
            }
        }
        .sheet(isPresented: $showNewPlanName) {
            NewPlanNameSheet(
                defaultName: "\(viewModel.item.displayName)训练",
                exerciseName: viewModel.item.displayName,
                onCancel: { },
                onCreate: { name in
                    if viewModel.createPlanAndAdd(name: name) != nil {
                        showNewPlanName = false
                        onDone()
                    }
                }
            )
        }
    }
}

// MARK: - 预览

#Preview("收藏动作") {
    FavoriteExercisesView(
        repository: PreviewFitnessRepository(),
        onBack: {},
        onOpenExercise: { _ in },
        onBrowseExercises: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("收藏动作 · 空状态") {
    FavoriteExercisesView(
        repository: PreviewFitnessRepository.makeNoExercises(),
        onBack: {},
        onOpenExercise: { _ in },
        onBrowseExercises: {}
    )
    .preferredColorScheme(.dark)
}
