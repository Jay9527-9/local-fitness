//
//  ExerciseLibraryView.swift
//  页面 02：动作库
//
//  纯本地的动作检索、筛选与选择入口。延续深炭黑 + 荧光绿的独立设计系统。
//  不使用任何第三方 App 的 Logo、图标、插画、GIF 或专有文案。
//
//  结构：导航栏 → 最近使用（可选）→ 搜索框 → 肌群 Chip → 列表
//  媒体缺失时用 MuscleGlyph 的代码绘制占位图，不展示破图。
//

import SwiftUI

struct ExerciseLibraryView: View {

    @ObservedObject var viewModel: ExerciseLibraryViewModel

    /// 路由回调，由导航容器注入
    var onOpenExercise: (ExerciseLibraryItem) -> Void
    var onNewCustomExercise: () -> Void
    var onEditCustomExercise: (ExerciseLibraryItem) -> Void
    var onAddToWorkout: (ExerciseLibraryItem) -> Void

    /// 非 nil 时进入「挑选模式」：标题换成该文案，隐藏新增按钮，
    /// 用于「往计划里添加动作 / 替换动作」这一类需要明确上下文的入口。
    var pickerTitle: String?

    // MARK: 本地状态

    /// 高级筛选面板
    @State private var showAdvancedFilter = false
    /// 排序菜单
    @State private var showSortMenu = false
    /// 待删除二次确认的动作
    @State private var pendingDeletion: ExerciseLibraryItem?

    private var isPicking: Bool { pickerTitle != nil }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    ExerciseListSkeleton(rowCount: 8)

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    recentSection
                    // 头部与列表拆成两个独立的直接子项。
                    // 惰性只对 LazyVStack 的**直接子视图**生效，若把 1324 行
                    // 包在一个 VStack 里交给它，首帧仍会全部建出来。
                    resultsHeaderSection
                    resultsListSection
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            // 底部留白 = 常规区间距 + 自绘 Tab 栏高度的一次性补偿。
            // 外层 RootView 用 safeAreaInset(edge: .bottom) 挂了 Tab 栏，
            // 系统已经把这个 inset 让给了 ScrollView，这里再补一点点视觉呼吸感即可。
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        // 挑选模式的提示条才需要占位。非挑选模式下**不能**挂一个空的
        // safeAreaInset —— 它会在 Tab 栏之上再插一条零高度的 inset，
        // 与 RootView 的 Tab 栏 inset 叠加后把内容顶出可视区，
        // 表现就是「底栏挡住列表最后几行」。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isPicking { pickingFooter }
        }
        .task { await viewModel.load() }
        .bottomDrawer(isPresented: $showAdvancedFilter, height: 620) {
            ExerciseFilterDrawer(
                filter: $viewModel.filter,
                items: viewModel.allExercises,
                equipments: viewModel.availableEquipments,
                hiddenCount: viewModel.hiddenCount,
                onDone: { showAdvancedFilter = false }
            )
        }
        .bottomDrawer(isPresented: $showSortMenu, height: 440) {
            ExerciseSortMenu(
                current: viewModel.sort,
                hasRecentUsage: viewModel.hasRecentUsageData,
                hasRecentFavorites: viewModel.hasRecentFavoriteData,
                onSelect: { order in
                    showSortMenu = false
                    withAnimation(DS.Motion.numberFade) {
                        viewModel.setSort(order)
                    }
                },
                onCancel: { showSortMenu = false }
            )
        }
        .alert(
            "删除动作",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                viewModel.deleteCustomExercise(item)
                pendingDeletion = nil
            }
        } message: { item in
            Text("「\(item.name)」将被永久删除，已记录的训练数据不受影响。")
        }
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
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .center) {
                Text(pickerTitle ?? "动作")
                    .font(isPicking ? DS.Typography.sectionTitle : DS.Typography.largeTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: DS.Spacing.item)

                // 排序菜单（页面 26）。挑选模式下同样可用，排序只影响列表展示。
                Button {
                    showSortMenu = true
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Palette.textPrimary)
                        .frame(width: 34, height: 34)
                        .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("排序方式，当前\(viewModel.sort.title)")

                // 挑选模式下不提供新建自定义动作，避免流程岔开
                if !isPicking {
                    Button(action: onNewCustomExercise) {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DS.Palette.onAccent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(DS.Palette.accent))
                            // 保持 44pt 触控区，视觉上仍是圆形小按钮
                            .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("新增自定义动作")
                }
            }

            searchField
            muscleChips
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.tight)
        .padding(.bottom, DS.Spacing.item)
        .background(DS.Palette.bg)
    }

    /// 挑选模式下的底部提示条。明确告诉用户「点一行就是选中它」，
    /// 否则用户会以为点进去是看详情。
    /// 调用点已用 if 判过 isPicking，这里不再返回空分支 ——
    /// 空分支会让 safeAreaInset 白白占掉一条 inset。
    private var pickingFooter: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.stroke)
            Text("轻点任意动作即可选中")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .background(DS.Palette.bg)
    }

    // MARK: - 搜索

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .accessibilityHidden(true)

            TextField("搜索动作名称或器械", text: $viewModel.searchText)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .tint(DS.Palette.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("搜索动作名称或器械")

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

            // 高级筛选入口，有生效条件时显示数量
            Button {
                showAdvancedFilter = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14, weight: .semibold))
                    if viewModel.filter.isAdvancedActive {
                        Text("\(viewModel.filter.advancedCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                }
                .foregroundStyle(
                    viewModel.filter.isAdvancedActive
                        ? DS.Palette.onAccent
                        : DS.Palette.textSecondary
                )
                .padding(.horizontal, viewModel.filter.isAdvancedActive ? 8 : 4)
                .frame(minHeight: 28)
                .background(
                    Capsule().fill(
                        viewModel.filter.isAdvancedActive
                            ? DS.Palette.accent
                            : DS.Palette.surfaceElevated
                    )
                )
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(
                viewModel.filter.isAdvancedActive
                    ? "高级筛选，已启用 \(viewModel.filter.advancedCount) 项条件"
                    : "高级筛选"
            )
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
                // 第一枚固定是「全部」，取消所有肌群筛选
                chip(
                    title: "全部",
                    count: nil,
                    isSelected: viewModel.filter.muscleCategory == nil
                        && !viewModel.filter.onlyFavorite
                ) {
                    viewModel.setMuscleCategory(nil)
                    viewModel.filter.onlyFavorite = false
                }

                ForEach(viewModel.muscleCategories, id: \.self) { category in
                    chip(
                        title: category,
                        count: viewModel.muscleCounts[category],
                        isSelected: viewModel.filter.muscleCategory == category
                    ) {
                        viewModel.setMuscleCategory(
                            viewModel.filter.muscleCategory == category ? nil : category
                        )
                    }
                }

                // 收藏作为一个快捷入口，与肌群并列
                chip(
                    title: "收藏",
                    count: viewModel.favoriteCount,
                    isSelected: viewModel.filter.onlyFavorite
                ) {
                    viewModel.filter.onlyFavorite.toggle()
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("肌群筛选")
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

    // MARK: - 最近使用

    /// 没有历史时不渲染，避免出现空白区域
    @ViewBuilder
    private var recentSection: some View {
        if !viewModel.recentExercises.isEmpty {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                SectionHeader(title: "最近使用")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DS.Spacing.item) {
                        ForEach(viewModel.recentExercises) { item in
                            RecentExerciseChip(item: item) {
                                viewModel.recordUsage(item)
                                onOpenExercise(item)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 结果列表

    /// 结果区头部：回退提示、区块标题、空态、署名。
    @ViewBuilder
    private var resultsHeaderSection: some View {
        // 结果由 ViewModel 预计算并缓存，这里只读。
        // 曾经写 `let results = viewModel.results` 又在下面调一次
        // `viewModel.results.contains(...)` —— 那是两个计算属性，
        // 每次 body 求值都会把 1324 条重新筛选 + 评分 + 排序两遍。
        let results = viewModel.results

        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            if viewModel.isSortFallback {
                sortFallbackHint
            }

            SectionHeader(
                title: "动作库",
                trailingText: "\(results.count) 项",
                trailingAction: nil
            )

            if results.isEmpty {
                emptyState
            }
        }
    }

    /// 结果行列表。每一行都是外层 LazyVStack 的直接子视图，滚动时才构建。
    @ViewBuilder
    private var resultsListSection: some View {
        let results = viewModel.results

        if !results.isEmpty {
            // 行间距自己带：外层 LazyVStack 用的是 section 级间距，
            // 行与行之间需要的是 tight 级，所以补在每行底部，
            // 最后一行的补白由列表末尾的署名或容器 padding 吸收。
            ForEach(results) { item in
                row(for: item)
                    .padding(.bottom, DS.Spacing.item)
            }

            if viewModel.hasLocalMediaInResults {
                MediaAttributionLabel()
                    .padding(.top, DS.Spacing.tight)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// 单行。抽成函数让每行的类型检查负担可控 —— 1324 行的 ForEach 闭包里
    /// 内联六个闭包与多个分支，会让编译器在泛型推导上花掉大量时间。
    private func row(for item: ExerciseLibraryItem) -> some View {
        ExerciseRow(
            item: item,
            onTap: {
                viewModel.recordUsage(item)
                // 挑选模式下点行就是选中，直接交给调用方写进计划；
                // 常规模式下才是打开详情。
                if isPicking {
                    onAddToWorkout(item)
                } else {
                    onOpenExercise(item)
                }
            },
            onAddToWorkout: { onAddToWorkout(item) },
            onToggleFavorite: { viewModel.toggleFavorite(item) },
            onToggleHidden: { viewModel.toggleHidden(item) },
            onEdit: { onEditCustomExercise(item) },
            onDelete: { pendingDeletion = item },
            trailingSymbol: isPicking ? "checkmark.circle" : "chevron.right"
        )
    }

    private var emptyState: some View {
        EmptyStateView(
            message: viewModel.emptyMessage,
            actionTitle: "新建自定义动作",
            action: onNewCustomExercise
        )
    }

    /// 「最近使用 / 最近收藏」无数据时的回退提示（页面 26）。
    private var sortFallbackHint: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textTertiary)
            Text(sortFallbackText)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.fieldFill)
        )
        .accessibilityLabel(sortFallbackText)
    }

    private var sortFallbackText: String {
        switch viewModel.sort {
        case .recentlyUsed: return "还没有最近使用的动作，已按默认顺序显示。"
        case .recentlyFavorited: return "还没有收藏过动作，已按默认顺序显示。"
        default: return ""
        }
    }
}

// MARK: - 最近使用条目

private struct RecentExerciseChip: View {

    let item: ExerciseLibraryItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.tight) {
                MuscleGlyph(
                    group: MuscleIconGroup.of(muscle: item.primaryMuscleText),
                    size: 32,
                    background: DS.Palette.surface
                )
                Text(item.displayName)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.trailing, DS.Spacing.item)
            .padding(.leading, DS.Spacing.tight)
            .padding(.vertical, DS.Spacing.tight)
            .background(
                Capsule().fill(DS.Palette.surface)
            )
            .overlay(
                Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("最近使用 \(item.displayName)，\(item.primaryMuscleText)")
        .accessibilityHint("打开动作详情")
    }
}

// MARK: - 动作行

struct ExerciseRow: View {

    let item: ExerciseLibraryItem
    let onTap: () -> Void
    let onAddToWorkout: () -> Void
    let onToggleFavorite: () -> Void
    let onToggleHidden: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// 右侧指示图标。常规模式是 chevron，挑选模式换成勾选圈。
    var trailingSymbol: String = "chevron.right"

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DS.Spacing.item) {
                ExerciseThumbnail(item: item, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(item.displayName)
                            .font(DS.Typography.body)
                            .foregroundStyle(
                                item.isHidden
                                    ? DS.Palette.textTertiary
                                    : DS.Palette.textPrimary
                            )
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Palette.accent)
                                .accessibilityHidden(true)
                        }
                    }

                    HStack(spacing: DS.Spacing.tight) {
                        tag(item.primaryMuscleText)
                        if !item.equipmentText.isEmpty {
                            tag(item.equipmentText)
                        }
                        tag(item.difficulty.title)
                        if item.isCustom {
                            tag("自定义", tint: DS.Palette.accent)
                        }
                        if item.isHidden {
                            tag("已隐藏", tint: DS.Palette.danger)
                        }
                    }
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: trailingSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
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
            .opacity(item.isHidden ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        // 长按菜单。iOS 16 的 contextMenu 在列表里即长按触发。
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("打开动作详情，长按显示更多操作")
    }

    private var accessibilityText: String {
        var parts = [item.displayName, item.primaryMuscleText]
        if !item.equipmentText.isEmpty { parts.append(item.equipmentText) }
        parts.append(item.difficulty.title)
        if item.isFavorite { parts.append("已收藏") }
        if item.isCustom { parts.append("自定义动作") }
        if item.isHidden { parts.append("已隐藏") }
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
            onToggleFavorite()
        } label: {
            Label(
                item.isFavorite ? "取消收藏" : "收藏",
                systemImage: item.isFavorite ? "star.slash" : "star"
            )
        }

        // 编辑与删除只对自定义动作开放
        if item.isCustom {
            Button {
                onEdit()
            } label: {
                Label("编辑", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        } else {
            // 导入动作不能删除，只能隐藏
            Button {
                onToggleHidden()
            } label: {
                Label(
                    item.isHidden ? "取消隐藏" : "隐藏",
                    systemImage: item.isHidden ? "eye" : "eye.slash"
                )
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

// MARK: - 骨架屏

/// 动作库专用的 8 行骨架屏
struct ExerciseListSkeleton: View {

    var rowCount: Int = 8

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 70)

            VStack(spacing: DS.Spacing.tight) {
                ForEach(0..<rowCount, id: \.self) { _ in
                    HStack(spacing: DS.Spacing.item) {
                        SkeletonBlock(height: 52, cornerRadius: DS.Radius.chip)
                            .frame(width: 52)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(height: 14, cornerRadius: 4)
                                .frame(maxWidth: .infinity)
                            SkeletonBlock(height: 11, cornerRadius: 4)
                                .frame(width: 140)
                        }
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
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入动作库")
    }
}

// MARK: - 预览

#Preview("动作库") {
    ExerciseLibraryView(
        viewModel: ExerciseLibraryViewModel(repository: PreviewFitnessRepository()),
        onOpenExercise: { _ in },
        onNewCustomExercise: {},
        onEditCustomExercise: { _ in },
        onAddToWorkout: { _ in }
    )
    .preferredColorScheme(.dark)
}

#Preview("动作库 · 空状态") {
    ExerciseLibraryView(
        viewModel: ExerciseLibraryViewModel(repository: PreviewFitnessRepository.makeNoExercises()),
        onOpenExercise: { _ in },
        onNewCustomExercise: {},
        onEditCustomExercise: { _ in },
        onAddToWorkout: { _ in }
    )
    .preferredColorScheme(.dark)
}
