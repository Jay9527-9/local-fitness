//
//  PlanDetailView.swift
//  页面 04：计划详情与编辑。
//
//  结构：
//    顶部导航栏（返回 / 计划名称可点击重命名 / 更多菜单）
//    计划概览卡（名称 + 四项指标 + 全宽「开始训练」）
//    训练日横向选择器（周一至周日 + 编辑训练日）
//    动作列表（序号 / 缩略图 / 名称 / 组数×次数 / 休息 / 热身标记 / 拖拽把手）
//    底部「添加动作」
//
//  只使用 iOS 16 API：NavigationStack、sheet、safeAreaInset、LazyVStack、onMove。
//

import SwiftUI

struct PlanDetailView: View {

    @StateObject private var viewModel: PlanDetailViewModel

    /// 外部数据变更信号（例如从动作库挑完动作）。值变化时重新读取计划，
    /// 因为返回时不会走 onAppear，仅靠 onAppear 会看到过期列表。
    var refreshToken: Int

    /// 开始训练：上层负责把草稿推进训练执行页
    var onStartTraining: (WorkoutSession) -> Void
    /// 点击动作卡进入配置页
    var onOpenExerciseConfig: (PlanExercise) -> Void
    /// 添加动作：进入动作库并携带当前 planId
    var onAddExercise: (UUID) -> Void
    /// 替换动作：进入动作库挑选
    var onReplaceExercise: (PlanExercise) -> Void
    /// 打开副本计划
    var onOpenPlan: (UUID) -> Void
    /// 计划被删除后返回上一级
    var onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    // 弹层状态
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showWeekdayEditor = false
    @State private var editingDays: Set<Int> = []
    @State private var showStartConfirm = false
    @State private var pendingSession: WorkoutSession?

    @State private var rowMenuTarget: PlanDetailViewModel.Row?
    @State private var pendingRemoval: PlanDetailViewModel.Row?
    @State private var showDeletePlanConfirm = false
    @State private var showMoreMenu = false
    @State private var exportedFile: ExportedFile?
    @State private var isEditingList = false
    @FocusState private var renameFocused: Bool

    init(
        repository: FitnessRepository,
        planID: UUID,
        refreshToken: Int = 0,
        onStartTraining: @escaping (WorkoutSession) -> Void,
        onOpenExerciseConfig: @escaping (PlanExercise) -> Void,
        onAddExercise: @escaping (UUID) -> Void,
        onReplaceExercise: @escaping (PlanExercise) -> Void,
        onOpenPlan: @escaping (UUID) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: PlanDetailViewModel(repository: repository, planID: planID)
        )
        self.refreshToken = refreshToken
        self.onStartTraining = onStartTraining
        self.onOpenExerciseConfig = onOpenExerciseConfig
        self.onAddExercise = onAddExercise
        self.onReplaceExercise = onReplaceExercise
        self.onOpenPlan = onOpenPlan
        self.onDeleted = onDeleted
    }

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()
            content
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Palette.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .overlay { rowMenuOverlay }
        .overlay { confirmOverlay }
        .sheet(isPresented: $showRename) { renameSheet }
        .sheet(isPresented: $showWeekdayEditor) { weekdaySheet }
        .sheet(item: $exportedFile) { file in
            ShareSheet(items: [file.url])
        }
        .confirmationDialog("计划操作", isPresented: $showMoreMenu, titleVisibility: .visible) {
            moreMenuActions
        }
        .alert("开始训练？", isPresented: $showStartConfirm, presenting: pendingSession) { session in
            Button("取消", role: .cancel) { pendingSession = nil }
            Button("开始") {
                viewModel.toast = nil
                pendingSession = nil
                onStartTraining(session)
            }
        } message: { session in
            Text("将创建一个名为「\(session.name)」的训练草稿，进入训练执行页逐组记录。")
        }
        .alert("删除这个计划？", isPresented: $showDeletePlanConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                guard viewModel.deletePlan() else { return }
                onDeleted()
                dismiss()
            }
        } message: {
            Text("计划本身会被删除。已经完成的历史训练记录会保留，不会一并删除。")
        }
        .alert(
            "出错",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button("知道了", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onAppear { viewModel.load() }
        .onChange(of: refreshToken) { _ in
            viewModel.refresh()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            PlanDetailSkeleton()
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.card)
        case .failed(let message):
            EmptyStateView(message: message) {
                dismiss()
            }
            .padding(.horizontal, DS.Spacing.page)
        case .loaded:
            loadedContent
        }
    }

    /// 用一个 List 承载整页，而不是 ScrollView 里套 List。
    ///
    /// 原因：`onMove` 的拖拽排序只有在 List 自己是滚动容器时才稳定工作。
    /// 把 List 放进 ScrollView 就得给它写死高度，行高一变就会截断或留白，
    /// 排序到边缘时也滚不动。这里把概览卡、训练日、动作行都变成 List 的行，
    /// 行间用 `.listRowInsets` 控制留白，视觉上仍是卡片式分区。
    private var loadedContent: some View {
        List {
            overviewCard
                .listRowInsets(rowInsets(top: DS.Spacing.card, bottom: DS.Spacing.item))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            weekdaySection
                .listRowInsets(rowInsets(top: 0, bottom: DS.Spacing.item))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            exercisesHeaderRow

            if viewModel.isEmpty {
                emptyState
                    .listRowInsets(rowInsets(top: 0, bottom: DS.Spacing.item))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.rows) { row in
                    exerciseCard(row)
                        .listRowInsets(rowInsets(top: DS.Spacing.tight, bottom: DS.Spacing.tight))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove { source, destination in
                    viewModel.move(fromOffsets: source, toOffset: destination)
                }
            }

            if let toast = viewModel.toast, !toast.isEmpty {
                ToastLabel(text: toast)
                    .listRowInsets(rowInsets(top: 0, bottom: DS.Spacing.item))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.Palette.bg)
        .environment(\.editMode, .constant(isEditingList ? .active : .inactive))
    }

    private func rowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(
            top: top,
            leading: DS.Spacing.page,
            bottom: bottom,
            trailing: DS.Spacing.page
        )
    }

    // MARK: - 概览卡

    private var overviewCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.card) {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text(viewModel.planName)
                        .font(DS.Typography.sectionTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)
                        .accessibilityAddTraits(.isHeader)

                    if viewModel.isEmpty {
                        Text("还没有动作，先添加动作再开始训练")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    } else {
                        Text(overviewSubtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }

                overviewGrid

                PrimaryButton(
                    title: "开始训练",
                    icon: "play.fill",
                    isEnabled: viewModel.canStartTraining
                ) {
                    requestStartTraining()
                }
                .accessibilityHint(
                    viewModel.canStartTraining
                        ? "创建训练草稿并进入训练执行页"
                        : "计划内没有动作时不可开始"
                )
            }
        }
    }

    private var overviewSubtitle: String {
        "\(viewModel.trainingDaysText) · \(viewModel.exerciseCountText)"
    }

    private var overviewGrid: some View {
        // 用两行两列而不是四列，避免小屏上「预计时长」这类中等长度文案被截断
        VStack(spacing: DS.Spacing.item) {
            HStack(spacing: DS.Spacing.item) {
                metricCell(viewModel.overviewItems[0])
                metricCell(viewModel.overviewItems[1])
            }
            HStack(spacing: DS.Spacing.item) {
                metricCell(viewModel.overviewItems[2])
                metricCell(viewModel.overviewItems[3])
            }
        }
    }

    private func metricCell(_ item: (title: String, value: String)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
            Text(item.value)
                .font(DS.Typography.callout.weight(.medium))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title)：\(item.value)")
    }

    // MARK: - 训练日

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(
                title: "训练日",
                trailingText: "编辑训练日",
                trailingAction: {
                    viewModel.toast = nil
                    isEditingList = false
                    editingDays = Set(viewModel.plan?.trainingDays ?? [])
                    showWeekdayEditor = true
                }
            )

            HStack(spacing: DS.Spacing.tight) {
                ForEach(WeekdayLabel.all, id: \.self) { day in
                    weekdayBadge(day)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(
                (viewModel.plan?.trainingDays.isEmpty ?? true)
                    ? "训练日：未设置"
                    : "训练日：\(viewModel.plan?.trainingDaysText ?? "")"
            )
        }
    }

    private func weekdayBadge(_ day: Int) -> some View {
        let isSelected = (viewModel.plan?.trainingDays ?? []).contains(day)
        return VStack(spacing: 4) {
            Text(WeekdayLabel.symbol(day))
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.Palette.onAccent : DS.Palette.textSecondary)
                .frame(width: DS.Size.weekdayBadge, height: DS.Size.weekdayBadge)
                .background(
                    Circle().fill(
                        isSelected ? DS.Palette.accent : DS.Palette.surfaceElevated
                    )
                )
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.clear : DS.Palette.stroke,
                        lineWidth: 1
                    )
                )
            Text("周\(WeekdayLabel.symbol(day))")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? DS.Palette.textSecondary : DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("周\(WeekdayLabel.symbol(day))")
        .accessibilityValue(isSelected ? "训练日" : "休息日")
        // 这里只做展示，编辑走「编辑训练日」，避免误触改动计划
        .accessibilityAddTraits(.isStaticText)
    }

    // MARK: - 动作列表

    private var exercisesHeaderRow: some View {
        SectionHeader(
            title: "计划动作",
            trailingText: viewModel.isEmpty ? nil : "\(viewModel.rows.count) 个"
        )
        .listRowInsets(rowInsets(top: DS.Spacing.tight, bottom: DS.Spacing.tight))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var emptyState: some View {
        EmptyStateView(
            message: "这个计划还没有动作",
            actionTitle: "添加第一个动作"
        ) {
            viewModel.toast = nil
            onAddExercise(viewModel.plan?.id ?? UUID())
        }
    }

    private func exerciseCard(_ row: PlanDetailViewModel.Row) -> some View {
        HStack(spacing: DS.Spacing.item) {
            // 卡片主体作为单一可访问元素；拖拽把手单独可聚焦，
            // 否则 VoiceOver 用户无法进入排序模式。
            cardBody(row)

            dragHandle
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Palette.stroke, lineWidth: 1)
        )
    }

    private func cardBody(_ row: PlanDetailViewModel.Row) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Text("\(row.index)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 22, alignment: .center)

            // 缩略图：有本地素材时显示 JPG，否则退回到代码绘制的肌群图标
            PlanExerciseThumbnail(item: row.item, size: DS.Size.planThumbnail)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: DS.Spacing.tight) {
                    Text(row.name)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(
                            row.isMissing ? DS.Palette.textTertiary : DS.Palette.textPrimary
                        )
                        .lineLimit(1)

                    if row.entry.isWarmup {
                        Text("热身")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(DS.Palette.accent.opacity(0.16))
                            )
                    }
                }

                HStack(spacing: DS.Spacing.tight) {
                    Text(row.volumeText)
                    Text("·")
                    Text(row.restText)
                }
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)

                if row.entry.hasNote {
                    Text(row.entry.note ?? "")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.tight)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isEditingList else { return }
            guard !row.isMissing else { return }
            viewModel.toast = nil
            onOpenExerciseConfig(row.entry)
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !isEditingList else { return }
            guard !row.isMissing else { return }
            Haptics.medium()
            viewModel.toast = nil
            rowMenuTarget = row
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(for: row))
        .accessibilityHint("轻点编辑本动作配置，长按查看更多操作")
        .accessibilityAddTraits(.isButton)
    }

    /// 拖拽把手。
    ///
    /// 进入排序模式后由 List 自己渲染系统拖拽控件，这里必须隐藏，
    /// 否则会出现两个把手，用户不知道该拖哪个。
    /// 常规模式下它承担「进入排序模式」的入口职责。
    @ViewBuilder
    private var dragHandle: some View {
        if isEditingList {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: DS.Size.dragHandleWidth, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(DS.Motion.standard) { isEditingList = false }
                    Haptics.light()
                }
                .accessibilityLabel("完成排序")
        } else {
            Button {
                withAnimation(DS.Motion.standard) { isEditingList = true }
                Haptics.light()
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(width: DS.Size.dragHandleWidth, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("调整顺序")
            .accessibilityHint("进入排序模式后可拖动旁边的把手")
        }
    }

    private func accessibilityText(for row: PlanDetailViewModel.Row) -> String {
        var parts = ["第 \(row.index) 个动作，\(row.name)"]
        if row.entry.isWarmup { parts.append("热身组") }
        parts.append(row.volumeText)
        parts.append(row.restText)
        if row.entry.hasNote { parts.append("备注：\(row.entry.note ?? "")") }
        if row.entry.progression != .none {
            parts.append("递增规则：\(row.entry.progression.title)")
        }
        if row.isMissing { parts.append("这个动作已从动作库移除") }
        return parts.joined(separator: "，")
    }

    // MARK: - 底部添加动作

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.stroke)

            if isEditingList {
                // 排序模式下换成完成按钮。此刻「添加动作」没有意义，
                // 换掉可以避免用户在拖动过程中误触插入新动作打乱手势。
                PrimaryButton(title: "完成排序", icon: "checkmark") {
                    withAnimation(DS.Motion.standard) { isEditingList = false }
                    Haptics.light()
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.tight)
            } else {
                SecondaryButton(
                    title: viewModel.isEmpty ? "添加第一个动作" : "添加动作",
                    icon: "plus"
                ) {
                    viewModel.toast = nil
                    onAddExercise(viewModel.plan?.id ?? UUID())
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.tight)
            }
        }
        .background(DS.Palette.bg)
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("返回")

            Spacer(minLength: DS.Spacing.tight)

            // 计划名称本身就是重命名入口
            Button {
                viewModel.toast = nil
                renameText = viewModel.planName
                showRename = true
            } label: {
                HStack(spacing: 5) {
                    Text(viewModel.planName)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule().fill(DS.Palette.surfaceElevated)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("计划名称 \(viewModel.planName)")
            .accessibilityHint("轻点重命名计划")

            Spacer(minLength: DS.Spacing.tight)

            Button {
                viewModel.toast = nil
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, DS.Spacing.tight)
        .background(DS.Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Palette.stroke)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var moreMenuActions: some View {
        Button("复制计划") {
            guard let copy = viewModel.duplicatePlan() else { return }
            onOpenPlan(copy.id)
        }

        Button("导出本地备份") {
            if let url = viewModel.exportBackup() {
                exportedFile = ExportedFile(url: url)
            }
        }

        Button("删除计划", role: .destructive) {
            Haptics.warning()
            showDeletePlanConfirm = true
        }

        Button("取消", role: .cancel) {}
    }

    // MARK: - 重命名面板

    private var renameSheet: some View {
        BottomDrawer(
            height: 216,
            title: "重命名计划",
            subtitle: "名称会立即保存到本地",
            onDismiss: { showRename = false }
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                TextField("计划名称", text: $renameText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.surface)
                    )
                    .focused($renameFocused)
                    .submitLabel(.done)
                    .onSubmit { commitRename() }
                    .accessibilityLabel("计划名称")

                HStack(spacing: DS.Spacing.item) {
                    SecondaryButton(title: "取消") {
                        showRename = false
                    }
                    PrimaryButton(title: "保存", isEnabled: !trimmedRename.isEmpty) {
                        commitRename()
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.top, DS.Spacing.tight)
            .onAppear {
                // 面板动画结束后再聚焦，否则键盘动画会与抽屉动画互相打断
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    renameFocused = true
                }
            }
        }
    }

    private var trimmedRename: String {
        renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitRename() {
        guard !trimmedRename.isEmpty else { return }
        guard viewModel.rename(to: renameText) else { return }
        renameFocused = false
        showRename = false
        Haptics.success()
    }

    // MARK: - 训练日编辑面板

    private var weekdaySheet: some View {
        BottomDrawer(
            height: 268,
            title: "编辑训练日",
            subtitle: "可多选，至少选一天",
            onDismiss: { showWeekdayEditor = false }
        ) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    ForEach(WeekdayLabel.all, id: \.self) { day in
                        selectableWeekdayBadge(day)
                    }
                }

                Text(
                    editingDays.isEmpty
                        ? "未选择训练日"
                        : WeekdayLabel.ordered(Array(editingDays))
                            .map { WeekdayLabel.short($0) }
                            .joined(separator: "、")
                )
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)

                HStack(spacing: DS.Spacing.item) {
                    SecondaryButton(title: "取消") {
                        showWeekdayEditor = false
                    }
                    PrimaryButton(title: "保存", isEnabled: !editingDays.isEmpty) {
                        viewModel.saveTrainingDays(Array(editingDays))
                        showWeekdayEditor = false
                        Haptics.success()
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.top, DS.Spacing.tight)
        }
    }

    private func selectableWeekdayBadge(_ day: Int) -> some View {
        let isSelected = editingDays.contains(day)
        return Button {
            withAnimation(DS.Motion.standard) {
                if isSelected {
                    editingDays.remove(day)
                } else {
                    editingDays.insert(day)
                }
            }
            Haptics.light()
        } label: {
            Text(WeekdayLabel.symbol(day))
                .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? DS.Palette.onAccent : DS.Palette.textSecondary)
                .frame(width: DS.Size.weekdayBadge, height: DS.Size.weekdayBadge)
                .background(
                    Circle().fill(isSelected ? DS.Palette.accent : DS.Palette.surface)
                )
                .overlay(
                    Circle().strokeBorder(
                        isSelected ? Color.clear : DS.Palette.stroke,
                        lineWidth: 1
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("周\(WeekdayLabel.symbol(day))")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - 长按菜单

    @ViewBuilder
    private var rowMenuOverlay: some View {
        if let row = rowMenuTarget {
            BottomDrawer(
                height: rowMenuHeight,
                title: row.name,
                subtitle: menuSubtitle(for: row),
                onDismiss: { rowMenuTarget = nil }
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.availableActions(for: row.id).enumerated()), id: \.element) { index, action in
                        if index > 0 {
                            Divider().overlay(DS.Palette.stroke)
                        }
                        DrawerActionRow(
                            title: action.title,
                            symbol: action.symbol,
                            isDestructive: action.isDestructive,
                            isEnabled: isEnabled(action, for: row)
                        ) {
                            perform(action, on: row)
                        }
                    }
                }
            }
        }
    }

    private var rowMenuHeight: CGFloat {
        guard let row = rowMenuTarget else { return 380 }
        // 拖拽指示条 20 + 标题区 62 + 每行 50
        return 82 + CGFloat(viewModel.availableActions(for: row.id).count) * 50 + 12
    }

    private func menuSubtitle(for row: PlanDetailViewModel.Row) -> String {
        var parts = [row.muscleText, row.equipmentText, row.volumeText]
        if row.entry.isWarmup { parts.insert("热身组", at: 0) }
        return parts.joined(separator: " · ")
    }

    private func isEnabled(
        _ action: PlanDetailViewModel.RowAction,
        for row: PlanDetailViewModel.Row
    ) -> Bool {
        guard let plan = viewModel.plan, let index = plan.index(ofPlanExercise: row.id) else {
            return false
        }
        switch action {
        case .moveUp: return index > 0
        case .moveDown: return index < plan.exercises.count - 1
        default: return true
        }
    }

    private func perform(
        _ action: PlanDetailViewModel.RowAction,
        on row: PlanDetailViewModel.Row
    ) {
        rowMenuTarget = nil
        // 等抽屉离场动画播完再执行，避免界面在被遮住时突然变化
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            switch action {
            case .moveUp:
                viewModel.moveUp(row.id)
            case .moveDown:
                viewModel.moveDown(row.id)
            case .duplicate:
                viewModel.duplicate(row.id)
            case .replace:
                onReplaceExercise(row.entry)
            case .remove:
                pendingRemoval = row
            }
        }
    }

    // MARK: - 移除动作的二次确认

    @ViewBuilder
    private var confirmOverlay: some View {
        if let row = pendingRemoval {
            BottomDrawer(
                height: 268,
                title: "从计划移除？",
                subtitle: row.name,
                onDismiss: { pendingRemoval = nil }
            ) {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    Text("只会移除这个计划里的动作配置。动作库中的动作，以及已经完成的历史训练记录都不会被删除。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: DS.Spacing.item) {
                        SecondaryButton(title: "取消") {
                            pendingRemoval = nil
                        }
                        Button {
                            viewModel.remove(row.id)
                            pendingRemoval = nil
                        } label: {
                            Text("移除")
                                .font(DS.Typography.cardTitle)
                                .foregroundStyle(DS.Palette.danger)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: DS.Size.buttonHeight)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: DS.Radius.button,
                                        style: .continuous
                                    )
                                    .fill(DS.Palette.danger.opacity(0.14))
                                )
                        }
                        .buttonStyle(PressableButtonStyle())
                        .accessibilityLabel("确认从计划移除")
                    }
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.top, DS.Spacing.tight)
            }
        }
    }

    // MARK: - 开始训练

    private func requestStartTraining() {
        guard viewModel.canStartTraining else { return }
        guard let draft = viewModel.makeSessionDraft() else { return }
        pendingSession = draft
        showStartConfirm = true
    }
}

// MARK: - 动作卡缩略图

/// 计划动作卡左侧缩略图。有本地素材时用 JPG，否则用代码绘制的肌群图标。
/// 与动作库的 `ExerciseThumbnail` 分开，是因为这里需要处理「动作已被移除」的情况。
struct PlanExerciseThumbnail: View {

    var item: ExerciseLibraryItem?
    var size: CGFloat = DS.Size.planThumbnail

    var body: some View {
        Group {
            if let item, let url = ExerciseMedia.thumbnailURL(for: item),
               let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous))
            } else {
                MuscleGlyph(
                    group: item.map { MuscleIconGroup.of(muscle: $0.primaryMuscle) } ?? .other,
                    size: size,
                    tint: DS.Palette.textSecondary
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 轻量提示

/// 保存成功之类的短暂提示。用文字条而不是浮层，避免遮挡列表操作。
struct ToastLabel: View {

    var text: String

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .transition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - 系统分享面板

/// 导出备份用。`ShareLink` 对 URL 的可用性在 iOS 16.0 上有版本差异，
/// 这里直接用 UIActivityViewController 包一层，行为更可控。
struct ShareSheet: UIViewControllerRepresentable {

    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 给 `URL` 加 Identifiable 需要用 `@retroactive`（Swift 6 才有），
/// Swift 5.7 下会直接编译失败。所以用一个自有包装类型承载 sheet(item:) 的身份。
struct ExportedFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - 骨架屏

struct PlanDetailSkeleton: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            SkeletonBlock(height: 232)
            SkeletonBlock(height: 20, cornerRadius: 6)
                .frame(width: 70)
            SkeletonBlock(height: 44, cornerRadius: DS.Radius.chip)
            SkeletonBlock(height: 20, cornerRadius: 6)
                .frame(width: 90)
            ForEach(0..<4, id: \.self) { _ in
                SkeletonBlock(height: 80)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入计划详情")
    }
}

// MARK: - 预览

#Preview("计划详情") {
    PlanDetailPreviewHost(empty: false)
        .preferredColorScheme(.dark)
}

#Preview("空计划") {
    PlanDetailPreviewHost(empty: true)
        .preferredColorScheme(.dark)
}

/// 预览宿主。之所以单独包一层：
/// `#Preview` 宏体内不能写 `let repo = ...; return View(...)` 这种多语句写法，
/// 用一个辅助视图承载实例创建，宏体只保留单个表达式。
private struct PlanDetailPreviewHost: View {

    let empty: Bool

    var body: some View {
        let repo = empty ? PreviewFitnessRepository.makeEmptyPlan() : PreviewFitnessRepository()
        NavigationStack {
            PlanDetailView(
                repository: repo,
                planID: repo.previewOwnPlanID,
                onStartTraining: { _ in },
                onOpenExerciseConfig: { _ in },
                onAddExercise: { _ in },
                onReplaceExercise: { _ in },
                onOpenPlan: { _ in },
                onDeleted: {}
            )
        }
    }
}
