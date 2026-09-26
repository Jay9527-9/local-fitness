//
//  ExerciseDetailView.swift
//  页面 03：动作详情。
//
//  媒体版权：© Gym visual — https://gymvisual.com/
//  媒体未随包分发时，全部回退为 MuscleGlyph 的代码绘制占位图，不引用任何外部网络图片。
//

import SwiftUI

struct ExerciseDetailView: View {

    @StateObject private var viewModel: ExerciseDetailViewModel

    /// 点击肌群标签：跳回动作库并应用该肌群筛选
    var onOpenMuscle: (String) -> Void
    /// 编辑自定义动作
    var onEditExercise: (ExerciseLibraryItem) -> Void
    /// 加入计划后进入计划详情
    var onOpenPlan: (UUID) -> Void
    /// 历史记录：进入该动作的历史趋势页（页面 11）
    var onOpenHistory: () -> Void

    @State private var showAddToWorkout = false
    @State private var showPrescription = false
    @State private var showNewPlanName = false
    @State private var pendingPlan: Plan?
    /// 参数面板的目标：true = 添加到进行中训练，false = 添加到计划
    @State private var addToSession = false
    /// 选中的目标训练 id（页面 29 选择后进行中训练时）
    @State private var targetSessionID: UUID?
    /// 是否以「替换原配置」方式加入计划（页面 28）
    @State private var replaceExisting = false
    @State private var showSelectPlan = false
    @State private var showSessionPicker = false
    /// 复制为自定义动作后待编辑的新条目
    @State private var copiedItem: ExerciseLibraryItem?
    @State private var showEditCopied = false

    @Environment(\.dismiss) private var dismiss

    private let repository: FitnessRepository

    init(
        item: ExerciseLibraryItem,
        repository: FitnessRepository,
        onOpenMuscle: @escaping (String) -> Void = { _ in },
        onEditExercise: @escaping (ExerciseLibraryItem) -> Void = { _ in },
        onOpenPlan: @escaping (UUID) -> Void = { _ in },
        onOpenHistory: @escaping () -> Void = { }
    ) {
        self.repository = repository
        _viewModel = StateObject(
            wrappedValue: ExerciseDetailViewModel(item: item, repository: repository)
        )
        self.onOpenMuscle = onOpenMuscle
        self.onEditExercise = onEditExercise
        self.onOpenPlan = onOpenPlan
        self.onOpenHistory = onOpenHistory
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                mediaCard
                titleBlock
                stepsSection
                muscleSection
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .navigationTitle("动作详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                favoriteButton
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                moreMenu
            }
        }
        // 底部固定主操作
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar
        }
        .task {
            await viewModel.load()
            viewModel.loadLastRecord()
        }
        // 详情页沉浸：本页在导航栈期间隐藏全局 Tab 栏，
        // 底部只保留「添加到训练」主操作条；视图移除后自动恢复。
        // 用 OR 聚合，push 出的计划详情 / 训练页自动继承沉浸态。
        .preference(key: SessionImmersiveKey.self, value: true)
        .sheet(isPresented: $showAddToWorkout) { addToWorkoutSheet }
        .sheet(isPresented: $showPrescription) { prescriptionSheet }
        .sheet(isPresented: $showNewPlanName) { newPlanSheet }
        .sheet(isPresented: $showSelectPlan) {
            SelectPlanView(
                exerciseID: viewModel.item.id,
                repository: repository,
                onPick: { plan, replace in
                    addToSession = false
                    replaceExisting = replace
                    pendingPlan = plan
                    showSelectPlan = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPrescription = true
                    }
                },
                onNewPlan: { name, days in
                    guard let plan = viewModel.createPlanAndAdd(name: name, trainingDays: days) else { return }
                    showSelectPlan = false
                    let id = plan.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onOpenPlan(id)
                    }
                },
                onCancel: { showSelectPlan = false }
            )
        }
        .bottomDrawer(isPresented: $showSessionPicker, height: 460) {
            ActiveSessionPicker(
                sessions: viewModel.unfinishedSessions,
                currentSessionID: viewModel.activeSession?.id,
                onSelect: { session in
                    addToSession = true
                    targetSessionID = session.id
                    pendingPlan = nil
                    showSessionPicker = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPrescription = true
                    }
                },
                onNewStrength: { showSessionPicker = false },
                onNewCardio: { showSessionPicker = false },
                onDiscard: { session in
                    try? repository.delete(sessionID: session.id)
                    Task {
                        await viewModel.load()
                    }
                }
            )
        }
        .sheet(isPresented: $showEditCopied) {
            CustomExerciseEditor(repository: repository, editing: copiedItem) { saved in
                try? repository.save(exercise: saved)
                copiedItem = saved
            } onDeleted: {
                showEditCopied = false
            }
        }
        .alert("隐藏这个动作？", isPresented: $viewModel.isConfirmingHide) {
            Button("取消", role: .cancel) { }
            Button("隐藏") { viewModel.confirmHide() }
        } message: {
            Text("隐藏后它不会出现在动作库列表和最近使用里。可以在动作库右上角的高级筛选里勾选「包含已隐藏」找回。")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: - 导航栏

    private var favoriteButton: some View {
        Button {
            viewModel.toggleFavorite()
        } label: {
            Image(systemName: viewModel.item.isFavorite ? "star.fill" : "star")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    viewModel.item.isFavorite ? DS.Palette.accent : DS.Palette.textTertiary
                )
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(viewModel.item.isFavorite ? "取消收藏" : "收藏")
        .accessibilityAddTraits(viewModel.item.isFavorite ? [.isSelected] : [])
    }

    private var moreMenu: some View {
        Menu {
            // 「历史记录」放在菜单第一项：它是唯一一条「看数据」的入口，
            // 其余几条都是「改动作」，混在一起容易被当成编辑项跳过。
            Button {
                onOpenHistory()
            } label: {
                Label("历史记录", systemImage: "chart.xyaxis.line")
            }

            Divider()

            // 编辑仅对自定义动作开放
            if viewModel.canEdit {
                Button {
                    onEditExercise(viewModel.item)
                } label: {
                    Label("编辑动作", systemImage: "square.and.pencil")
                }
            }

            Button {
                if let copy = viewModel.copyAsCustom() {
                    copiedItem = copy
                    showEditCopied = true
                }
            } label: {
                Label("复制为自定义动作", systemImage: "doc.on.doc")
            }

            Divider()

            Button(role: .destructive) {
                viewModel.requestHide()
            } label: {
                Label(viewModel.hideActionTitle, systemImage: viewModel.item.isHidden ? "eye" : "eye.slash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
    }

    // MARK: - 媒体区

    /// 16:9 圆角卡片。有本地媒体时循环播放 GIF，否则用代码绘制的肌群示意图。
    /// 右下角固定一个「演示」小标签。
    private var mediaCard: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if viewModel.item.hasLocalMedia && ExerciseMedia.isMediaBundled {
                    ExerciseAnimationView(item: viewModel.item, aspectRatio: 16.0 / 9.0)
                } else {
                    placeholderMedia
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))

            Text("演示")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.black.opacity(0.55))
                )
                .padding(DS.Spacing.tight)
                .accessibilityLabel("演示媒体")
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    /// 无媒体时的占位内容：代码绘制的肌群示意图，配一句说明。
    private var placeholderMedia: some View {
        ZStack {
            DS.Palette.surface

            VStack(spacing: DS.Spacing.item) {
                MuscleGlyph(
                    group: MuscleIconGroup.of(muscle: viewModel.item.primaryMuscleText),
                    size: 92,
                    background: DS.Palette.surfaceElevated,
                    tint: DS.Palette.textTertiary
                )

                Text(placeholderCaption)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.section)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(viewModel.item.displayName) 暂无演示动画，显示肌群示意图")
    }

    private var placeholderCaption: String {
        viewModel.item.isCustom
            ? "自定义动作，使用代码绘制的肌群示意图"
            : "本包未分发该动作的媒体，使用代码绘制的肌群示意图"
    }

    // MARK: - 标题与标签

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(viewModel.item.displayName)
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            // 别名作为副标题，解释检索时可能用到的其他说法
            if !viewModel.item.aliases.isEmpty {
                Text(viewModel.item.aliases.joined(separator: " · "))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            tagRow
        }
    }

    /// 主肌群、器械、难度、自定义标记。
    /// 主肌群用低透明度荧光绿底，其余用低对比深灰底。
    private var tagRow: some View {
        HStack(spacing: DS.Spacing.tight) {
            if !viewModel.item.primaryMuscleText.isEmpty {
                Text(viewModel.item.primaryMuscleText)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Palette.accent.opacity(0.16))
                    )
            }

            if !viewModel.item.equipmentText.isEmpty {
                detailTag(viewModel.item.equipmentText)
            }

            detailTag(viewModel.item.difficulty.title)

            if viewModel.item.isCustom {
                detailTag("自定义")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func detailTag(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DS.Palette.surfaceElevated)
            )
    }

    // MARK: - 动作要点

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("动作要点")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer {
                if viewModel.steps.isEmpty {
                    Text("暂未提供动作说明")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.item) {
                        ForEach(Array(viewModel.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(number: index + 1, text: step)
                        }
                    }
                }
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.item) {
            Text("\(number)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(DS.Palette.accent))

            Text(text)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(number) 步，\(text)")
    }

    // MARK: - 涉及肌群

    private var muscleSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("涉及肌群")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    if viewModel.muscleList.isEmpty {
                        Text("暂未提供肌群信息")
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textTertiary)
                    } else {
                        muscleGrid

                        Text("点击肌群可在动作库里筛选同类动作")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var muscleGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: DS.Spacing.tight)],
            alignment: .leading,
            spacing: DS.Spacing.tight
        ) {
            ForEach(viewModel.muscleList) { muscle in
                Button {
                    onOpenMuscle(muscle.name)
                } label: {
                    HStack(spacing: 4) {
                        if muscle.isPrimary {
                            Image(systemName: "target")
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(muscle.name)
                            .font(DS.Typography.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(
                        muscle.isPrimary ? DS.Palette.accent : DS.Palette.textSecondary
                    )
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(
                                muscle.isPrimary
                                    ? DS.Palette.accent.opacity(0.16)
                                    : DS.Palette.surfaceElevated
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(
                                muscle.isPrimary ? DS.Palette.accent.opacity(0.45) : DS.Palette.stroke,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(
                    muscle.isPrimary ? "主训练肌群 \(muscle.name)，点击筛选" : "协同肌群 \(muscle.name)，点击筛选"
                )
            }
        }
    }

    // MARK: - 底部主操作

    private var bottomBar: some View {
        VStack(spacing: DS.Spacing.tight) {
            PrimaryButton(title: "添加到训练", icon: "plus") {
                showAddToWorkout = true
            }
            .accessibilityHint("选择要加入的训练或计划")

            if !viewModel.hasAnyTarget {
                Text("还没有训练记录或计划。可以先新建一个力量训练。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.item)
        .padding(.bottom, DS.Spacing.tight)
        .background(
            DS.Palette.bg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Palette.stroke)
                        .frame(height: 1)
                }
        )
    }

    // MARK: - 弹窗内容

    @ViewBuilder
    private var addToWorkoutSheet: some View {
        AddToWorkoutSheet(
            item: viewModel.item,
            activeSessionSubtitle: viewModel.activeSessionSubtitle,
            plans: viewModel.plans,
            onAddToActiveSession: {
                // 页面 29：只有一条进行中训练直接进参数面板，多条先选。
                if viewModel.unfinishedSessions.count > 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showSessionPicker = true
                    }
                } else {
                    addToSession = true
                    targetSessionID = nil
                    pendingPlan = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showPrescription = true
                    }
                }
            },
            onPickPlan: { plan in
                addToSession = false
                replaceExisting = false
                pendingPlan = plan
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showPrescription = true
                }
            },
            onCreatePlan: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showNewPlanName = true
                }
            },
            onBrowsePlans: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showSelectPlan = true
                }
            }
        )
    }

    @ViewBuilder
    private var prescriptionSheet: some View {
        if addToSession {
            ExercisePrescriptionSheet(
                exerciseName: viewModel.item.displayName,
                muscleText: viewModel.item.primaryMuscleText,
                targetTitle: "添加到训练",
                prescription: $viewModel.draft,
                lastRecordSummary: viewModel.lastRecordSummary,
                onApplyLastRecord: { viewModel.applyLastRecord() },
                onCancel: { addToSession = false },
                onSave: {
                    viewModel.addToActiveSession(sessionID: targetSessionID)
                    addToSession = false
                    targetSessionID = nil
                }
            )
        } else if let plan = pendingPlan {
            ExercisePrescriptionSheet(
                exerciseName: viewModel.item.displayName,
                muscleText: viewModel.item.primaryMuscleText,
                targetTitle: "添加到计划",
                prescription: $viewModel.draft,
                lastRecordSummary: viewModel.lastRecordSummary,
                onApplyLastRecord: { viewModel.applyLastRecord() },
                onCancel: { pendingPlan = nil },
                onSave: {
                    if replaceExisting {
                        viewModel.replaceInPlan(planID: plan.id)
                    } else {
                        viewModel.add(toPlan: plan.id)
                    }
                    let id = plan.id
                    pendingPlan = nil
                    replaceExisting = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        onOpenPlan(id)
                    }
                }
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var newPlanSheet: some View {
        NewPlanNameSheet(
            defaultName: "\(viewModel.item.displayName)训练",
            exerciseName: viewModel.item.displayName,
            onCancel: { },
            onCreate: { name in
                guard let plan = viewModel.createPlanAndAdd(name: name) else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    onOpenPlan(plan.id)
                }
            }
        )
    }

    // MARK: - 轻提示

    /// 操作成功后的浮层提示，2 秒后自动消失。
    @ViewBuilder
    private var toastView: some View {
        if let toast = viewModel.toast {
            Text(toast)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, DS.Spacing.item)
                .background(
                    Capsule().fill(DS.Palette.surfaceElevated)
                )
                .overlay(
                    Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .padding(.bottom, 92)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .task(id: toast) {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(DS.Motion.standard) { viewModel.toast = nil }
                }
                .allowsHitTesting(false)
                .accessibilityLabel(toast)
        }
    }
}

// MARK: - 预览

#Preview("动作详情 · 有媒体") {
    NavigationStack {
        ExerciseDetailView(
            item: ExerciseLibraryItem(
                id: "0001",
                name: "3/4 sit-up",
                aliases: ["卷腹", "仰卧起坐"],
                category: "waist",
                categoryZh: "核心",
                equipment: "body weight",
                equipmentZh: "自重",
                target: "abs",
                primaryMuscle: "腹直肌",
                muscleGroup: "hip flexors",
                secondaryMuscles: ["hip flexors", "lower back"],
                difficulty: .beginner,
                instructionsZh: "平躺，膝盖弯曲，双脚平放在地上。收紧腹肌，慢慢将上半身抬离地面。",
                stepsZh: [
                    "平躺，膝盖弯曲，双脚平放在地上。",
                    "将双手放在脑后，肘部朝外。",
                    "收紧腹肌，将上半身抬离地面。",
                    "在顶部停顿片刻，再缓慢放回。",
                ],
                image: "images/0001-2gPfomN.jpg",
                gifURL: "videos/0001-2gPfomN.gif",
                attribution: "© Gym visual — https://gymvisual.com/",
                mediaID: "2gPfomN",
                isFavorite: true
            ),
            repository: PreviewFitnessRepository()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("动作详情 · 自定义动作") {
    NavigationStack {
        ExerciseDetailView(
            item: ExerciseLibraryItem(
                id: "custom-1",
                name: "自创 · 单臂哑铃划船停顿版",
                aliases: ["划船", "哑铃", "单臂"],
                categoryZh: "背",
                equipment: "dumbbell",
                equipmentZh: "哑铃",
                target: "lats",
                primaryMuscle: "背阔肌",
                muscleGroup: "biceps",
                secondaryMuscles: ["rhomboids", "biceps"],
                difficulty: .intermediate,
                instructionsZh: "单臂撑凳，拉至腹部后在最上端停顿两秒，再缓慢下放。",
                stepsZh: ["单臂撑于平凳", "拉至腹部", "顶端停顿两秒", "缓慢下放"],
                isCustom: true
            ),
            repository: PreviewFitnessRepository()
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("动作详情 · 无步骤说明") {
    NavigationStack {
        ExerciseDetailView(
            item: ExerciseLibraryItem(
                id: "custom-2",
                name: "自创 · 无说明动作",
                categoryZh: "肩",
                equipment: "dumbbell",
                equipmentZh: "哑铃",
                target: "delts",
                primaryMuscle: "三角肌",
                secondaryMuscles: [],
                difficulty: .intermediate,
                isCustom: true
            ),
            repository: PreviewFitnessRepository()
        )
    }
    .preferredColorScheme(.dark)
}
