//
//  WorkoutSessionView.swift
//  页面 05：训练执行页。App 的核心页面，从计划详情点「开始训练」进入。
//
//  结构自下而上：
//  ┌ 顶部固定栏（最小化 / 训练名 + 计时器 / 结束）
//  ├ 概览区（已完成动作数、已完成组数、总容量；有氧换成时长 / 距离 / 消耗）
//  ├ LazyVStack 动作卡（名称、目标肌群、上次记录、组表、更多）
//  │   每张卡底部：新增一组 / 休息计时 / 动作说明
//  └ 底部固定「完成训练」主按钮
//
//  抽屉全部复用 BottomDrawer：组间休息面板、动作说明、更多菜单、完成确认、备注编辑。
//

import Combine
import SwiftUI

struct WorkoutSessionView: View {

    @StateObject private var viewModel: WorkoutSessionViewModel

    /// 完成后进入训练总结页
    private let onFinished: (WorkoutSession) -> Void
    /// 最小化后回到上一页
    private let onMinimize: () -> Void
    /// 「编辑动作配置」跳转到计划内的配置页
    private let onEditConfig: (PlanExercise) -> Void
    /// 「替换动作」打开动作选择器
    private let onRequestReplace: (WorkoutSessionViewModel.ExerciseCard) -> Void

    @State private var noPlanHint = false

    init(
        repository: FitnessRepository,
        sessionID: UUID,
        onFinished: @escaping (WorkoutSession) -> Void,
        onMinimize: @escaping () -> Void,
        onEditConfig: @escaping (PlanExercise) -> Void,
        onRequestReplace: @escaping (WorkoutSessionViewModel.ExerciseCard) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: WorkoutSessionViewModel(repository: repository, sessionID: sessionID)
        )
        self.onFinished = onFinished
        self.onMinimize = onMinimize
        self.onEditConfig = onEditConfig
        self.onRequestReplace = onRequestReplace
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Palette.bg.ignoresSafeArea()

            ZStack(alignment: .bottom) {
                content

                if let toast = viewModel.toast {
                    ToastBanner(text: toast)
                        .padding(.bottom, 90)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }

            // 休息结束后在页面顶部留一条提示，指明现在该做下一组。
            // 与底部 toast 分开：toast 可能在倒计时结束时正好在显示别的消息。
            if viewModel.pendingRestAttention {
                RestFinishedBanner()
                    .padding(.top, DS.Spacing.item)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .zIndex(30)
            }
        }
        .animation(DS.Motion.drawer, value: viewModel.restTimer?.isPresented ?? false)
        .animation(DS.Motion.standard, value: viewModel.toast)
        .animation(DS.Motion.standard, value: viewModel.pendingRestAttention)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
        .onAppear {
            viewModel.load()
            wireCallbacks()
        }
        .onDisappear { viewModel.onDisappear() }
        // 从后台回到前台：计时按 startedAt 计算，只需恢复秒表刷新
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            viewModel.resumeFromMinimize()
        }
        .overlay { restDrawer }
        .overlay { infoDrawer }
        .overlay { menuDrawer }
        .overlay { finishDrawer }
        .overlay { noteDrawer }
        .overlay { deleteConfirm }
        .alert("这个动作不在计划里", isPresented: $noPlanHint) {
            Button("好", role: .cancel) {}
        } message: {
            Text("自由训练没有预设配置可以编辑。可以改用「替换动作」或直接调整重量次数。")
        }
    }

    private func wireCallbacks() {
        viewModel.onEditConfig = { card in
            if let planEntry = card.planEntry {
                onEditConfig(planEntry)
            } else {
                noPlanHint = true
            }
        }
        viewModel.onReplaceExercise = { card in
            // 替换是在动作选择器里写库的，这里先打标记，
            // 等页面重新出现时由 refreshSession 对比出新旧动作并提示。
            viewModel.willReplaceExercise()
            onRequestReplace(card)
        }
    }

    // MARK: - 内容分发

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            SessionSkeleton()
        case .missing:
            ScrollView {
                EmptyStateView(
                    message: "这次训练记录已经不在了，可能已被删除。",
                    actionTitle: "返回",
                    action: onMinimize
                )
                .padding(DS.Spacing.page)
            }
        case .failed(let message):
            ScrollView {
                EmptyStateView(message: message, actionTitle: "重试") {
                    viewModel.load()
                }
                .padding(DS.Spacing.page)
            }
        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.item) {
                    overviewCard
                        .padding(.horizontal, DS.Spacing.page)

                    ForEach(viewModel.cards) { card in
                        ExerciseCardView(
                            card: card,
                            session: viewModel,
                            onToggle: { entry in
                                viewModel.toggleCompletion(card: card, entry: entry)
                            },
                            onEditCell: { entry, field in
                                viewModel.editingCell = WorkoutSessionViewModel.SetEntryCell(
                                    entryID: entry.id,
                                    field: field
                                )
                            },
                            onCommitCell: { entry, weight, reps in
                                viewModel.updateValue(card: card, entry: entry, weight: weight, reps: reps)
                            },
                            onRemoveSet: { entry in
                                viewModel.removeSet(card: card, entry: entry)
                            },
                            canRemoveSet: viewModel.canRemoveSet(card: card),
                            onAddSet: { viewModel.addSet(card: card) },
                            onRest: { viewModel.startManualRest(card: card) },
                            onInfo: { viewModel.infoCard = card },
                            onMore: { viewModel.menuCardID = card.id }
                        )
                        .id(card.id)
                        .padding(.horizontal, DS.Spacing.page)
                    }

                    if viewModel.cards.isEmpty {
                        EmptyStateView(
                            message: "这次训练还没有动作。可以从「动作」页挑一个加进来，或直接结束训练。"
                        )
                        .padding(.horizontal, DS.Spacing.page)
                    }
                }
                .padding(.top, DS.Spacing.card)
                .padding(.bottom, DS.Spacing.section)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityElement(children: .contain)
            // 页面 14：完成当前动作后自动定位下一动作。
            .onChange(of: viewModel.advanceTargetID) { targetID in
                guard let targetID else { return }
                withAnimation(DS.Motion.standard) {
                    proxy.scrollTo(targetID, anchor: .top)
                }
                viewModel.advanceTargetID = nil
            }
        }
    }

    // MARK: - 顶部固定栏

    private var topBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                viewModel.minimize()
                onMinimize()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("最小化训练，返回上一页")

            VStack(alignment: .center, spacing: 1) {
                Text(viewModel.sessionName)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // 秒表放在独立子视图里自驱动，避免每秒把整屏动作卡一起重建
                SessionHeaderClock(
                    startedAt: viewModel.sessionStartedAt,
                    isFinished: viewModel.isSessionFinished
                )
            }
            .frame(maxWidth: .infinity)

            Button {
                viewModel.presentFinishDrawer()
            } label: {
                Text("结束")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.horizontal, 14)
                    .frame(minHeight: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("结束训练")
        }
        .padding(.horizontal, DS.Spacing.tight)
        .frame(height: DS.Size.sessionBarHeight)
        .background(DS.Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Palette.stroke)
                .frame(height: 1)
        }
    }

    // MARK: - 概览区

    private var overviewCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                // 力量训练的进度条；有氧没有组的概念，不显示
                if !viewModel.isCardio {
                    ProgressBar(value: viewModel.progress)
                        .accessibilityHidden(true)
                }

                HStack(alignment: .top, spacing: DS.Spacing.item) {
                    if viewModel.isCardio {
                        ForEach(viewModel.cardioMetrics, id: \.title) { metric in
                            overviewMetric(title: metric.title, value: metric.value)
                        }
                    } else {
                        ForEach(viewModel.strengthMetrics, id: \.title) { metric in
                            overviewMetric(title: metric.title, value: metric.value)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(viewModel.accessibilityOverview)
        }
    }

    /// 单个概览数字。数值变化时 180ms 淡入。
    private func overviewMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            FadingNumberText(value: value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: - 底部固定主按钮

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Palette.stroke)
                .frame(height: 1)

            PrimaryButton(title: "完成训练", icon: "checkmark") {
                viewModel.presentFinishDrawer()
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.tight)
        }
        .background(DS.Palette.bg)
    }

    // MARK: - 组间休息面板

    @ViewBuilder
    private var restDrawer: some View {
        if let timer = viewModel.restTimer, timer.isPresented {
            RestCountdownPanel(
                timer: timer,
                onTogglePause: { viewModel.toggleRestPause() },
                onAdjust: { viewModel.adjustRest(by: $0) },
                onSkip: { viewModel.skipRest() },
                onClose: { viewModel.dismissRestPanel() },
                onSetDefaultRest: { viewModel.setDefaultRest(seconds: $0) },
                currentDefaultRest: viewModel.currentDefaultRestSeconds,
                canSetDefault: viewModel.canSetDefaultRest
            )
            .transition(.move(edge: .bottom))
            .zIndex(20)
            // 面板自己持有 1s 时钟，只把求值时刻回灌给 ViewModel，
            // 父页面不会因为每秒 tick 而整页重绘。
            .onReceive(restTick) { _ in
                viewModel.refreshRestClock()
            }
        }
    }

    /// 面板可见期间每秒触发一次。面板消失后 publisher 随之失效。
    private var restTick: Publishers.Autoconnect<Timer.TimerPublisher> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    // MARK: - 动作说明只读抽屉

    @ViewBuilder
    private var infoDrawer: some View {
        if let card = viewModel.infoCard {
            BottomDrawer(
                height: 460,
                title: card.name,
                subtitle: card.muscleText.isEmpty ? nil : card.muscleText,
                onDismiss: { viewModel.infoCard = nil }
            ) {
                ExerciseInfoDrawerContent(card: card)
            }
            .transition(.opacity)
            .zIndex(21)
        }
    }

    // MARK: - 更多菜单

    @ViewBuilder
    private var menuDrawer: some View {
        if let card = viewModel.cards.first(where: { $0.id == viewModel.menuCardID }) {
            BottomDrawer(
                height: 310,
                title: card.name,
                subtitle: card.configText,
                onDismiss: { viewModel.menuCardID = nil }
            ) {
                VStack(spacing: 0) {
                    DrawerActionRow(title: "编辑动作配置", symbol: "slider.horizontal.3") {
                        viewModel.perform(.editConfig, on: card)
                    }
                    Divider().overlay(DS.Palette.stroke)
                    DrawerActionRow(title: "替换动作", subtitle: "保留已完成组记录", symbol: "arrow.triangle.2.circlepath") {
                        viewModel.perform(.replace, on: card)
                    }
                    Divider().overlay(DS.Palette.stroke)
                    DrawerActionRow(title: "添加备注", symbol: "text.bubble") {
                        viewModel.perform(.note, on: card)
                    }
                    Divider().overlay(DS.Palette.stroke)
                    DrawerActionRow(
                        title: "删除动作",
                        subtitle: "从本次训练移除",
                        symbol: "trash",
                        isDestructive: true
                    ) {
                        viewModel.perform(.delete, on: card)
                    }
                }
            }
            .transition(.opacity)
            .zIndex(22)
        }
    }

    // MARK: - 完成确认抽屉

    @ViewBuilder
    private var finishDrawer: some View {
        if viewModel.isFinishDrawerPresented {
            BottomDrawer(
                height: 460,
                title: "完成本次训练？",
                subtitle: "确认后写入本地记录",
                onDismiss: { dismissFinishDrawer() }
            ) {
                FinishSummaryContent(
                    session: viewModel,
                    onCancel: { dismissFinishDrawer() },
                    onResume: { dismissFinishDrawer() },
                    onConfirm: {
                        if let finished = viewModel.confirmFinish() {
                            onFinished(finished)
                        }
                    }
                )
            }
            .transition(.opacity)
            .zIndex(23)
        }
    }

    /// 取消与继续训练共用同一条退出路径：只收起抽屉，不改动训练草稿。
    private func dismissFinishDrawer() {
        viewModel.isFinishDrawerPresented = false
    }

    // MARK: - 备注编辑抽屉

    @ViewBuilder
    private var noteDrawer: some View {
        if let card = viewModel.noteCard {
            BottomDrawer(
                height: 320,
                title: "添加备注",
                subtitle: card.name,
                onDismiss: { viewModel.noteCard = nil }
            ) {
                NoteEditorContent(
                    text: $viewModel.noteDraft,
                    onSave: { viewModel.saveNote() },
                    onCancel: { viewModel.noteCard = nil }
                )
            }
            .transition(.opacity)
            .zIndex(24)
        }
    }

    // MARK: - 删除二次确认

    @ViewBuilder
    private var deleteConfirm: some View {
        if let card = viewModel.pendingDeleteCard {
            BottomDrawer(
                height: 300,
                title: "删除「\(card.name)」？",
                subtitle: "该动作的 \(card.totalCount) 组记录会从本次训练移除",
                onDismiss: { viewModel.pendingDeleteCard = nil }
            ) {
                VStack(spacing: DS.Spacing.item) {
                    Text("已完成的历史记录不受影响，计划里的配置也不会改动。")
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DS.Spacing.card)

                    Button {
                        viewModel.confirmDeleteCard(card)
                        viewModel.pendingDeleteCard = nil
                    } label: {
                        Text("删除")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(DS.Palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.button)
                                    .fill(DS.Palette.danger.opacity(0.18))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.button)
                                    .stroke(DS.Palette.danger.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, DS.Spacing.card)
                    .accessibilityLabel("确认删除动作")

                    SecondaryButton(title: "取消") {
                        viewModel.pendingDeleteCard = nil
                    }
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.bottom, DS.Spacing.item)
                }
            }
            .transition(.opacity)
            .zIndex(25)
        }
    }
}
