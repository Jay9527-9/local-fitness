//
//  TrainingHomeView.swift
//  页面 01：训练首页
//  深色炭黑底 + 白色文字 + 单一荧光绿强调色。无社交、无登录、无网络。
//  分区：今日训练 → 快捷入口 → 我的计划 → 最近训练
//

import SwiftUI

struct TrainingHomeView: View {

    /// 仓储由导航容器注入；视图模型在内部以 @StateObject 持有。
    ///
    /// 为什么不放回父级 `homeRoot` 计算属性里 `TrainingHomeViewModel(repository:)`
    /// 然后以 `@ObservedObject` 传进来：那个计算属性每次 `body` 求值都会新建一个
    /// VM 实例，而 `.task { load() }` 闭包只捕获首次出现的那个实例。首屏启动时
    /// `body` 会被多次求值（Tab 过渡 / safeAreaInset / 引导判断），于是 `load()`
    /// 跑在第一个被丢弃的实例上，视图随后观察的是后来的新实例 —— `loadState`
    /// 永远停在 `.loading`，骨架屏卡死；切 Tab 后整棵子树重建、VM 干净重建才正常。
    /// 用 @StateObject 让 VM 随视图实例稳定存在，`.task` 与视图观察的是同一个实例。
    /// 刷新语义不受影响：训练结束后的 `homeReloadID`、切 Tab 的 `.id(tab)` 都会
    /// 重建 `TrainingHomeView`，从而重建它的 @StateObject 并重新走 `.task` 读盘。
    let repository: FitnessRepository

    @StateObject private var viewModel: TrainingHomeViewModel

    /// 由外部导航容器注入的路由回调
    var onStartTraining: (TodayTrainingState) -> Void
    var onNewStrength: () -> Void
    var onNewCardio: () -> Void
    var onOpenPlan: (Plan) -> Void
    var onOpenSession: (WorkoutSession) -> Void
    var onOpenCalendar: () -> Void
    var onOpenMore: () -> Void
    /// 恢复训练（页面 49）的「继续训练」：进入对应训练执行页。
    var onResumeSession: (WorkoutSession) -> Void
    /// 草稿损坏 / 恢复失败时进入数据恢复页（页面 50）。
    var onOpenRecovery: () -> Void

    init(
        repository: FitnessRepository,
        onStartTraining: @escaping (TodayTrainingState) -> Void,
        onNewStrength: @escaping () -> Void,
        onNewCardio: @escaping () -> Void,
        onOpenPlan: @escaping (Plan) -> Void,
        onOpenSession: @escaping (WorkoutSession) -> Void,
        onOpenCalendar: @escaping () -> Void,
        onOpenMore: @escaping () -> Void,
        onResumeSession: @escaping (WorkoutSession) -> Void,
        onOpenRecovery: @escaping () -> Void
    ) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: TrainingHomeViewModel(repository: repository))
        self.onStartTraining = onStartTraining
        self.onNewStrength = onNewStrength
        self.onNewCardio = onNewCardio
        self.onOpenPlan = onOpenPlan
        self.onOpenSession = onOpenSession
        self.onOpenCalendar = onOpenCalendar
        self.onOpenMore = onOpenMore
        self.onResumeSession = onResumeSession
        self.onOpenRecovery = onOpenRecovery
    }

    /// 计划操作抽屉的目标，nil 表示不展示
    @State private var drawerPlan: Plan?
    /// 待删除二次确认的计划
    @State private var pendingDeletion: Plan?
    /// 恢复训练抽屉（页面 49）
    @State private var showResumeDrawer = false
    /// 本次进入首页是否已提示过恢复训练，避免刷新重复弹。
    @State private var didPromptResume = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.load() }
        // 用计划对象直接驱动抽屉，避免「展示中但对象为空」
        .sheet(item: $drawerPlan) { plan in
            PlanActionDrawer(
                plan: plan,
                onStart: {
                    drawerPlan = nil
                    onStartTraining(todayStateFor(plan))
                },
                onEdit: {
                    drawerPlan = nil
                    onOpenPlan(plan)
                },
                onDuplicate: {
                    drawerPlan = nil
                    viewModel.duplicatePlan(plan)
                },
                onDelete: {
                    drawerPlan = nil
                    pendingDeletion = plan
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        // 删除二次确认
        .alert(
            "删除计划",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { plan in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                viewModel.deletePlan(plan)
                pendingDeletion = nil
            }
        } message: { plan in
            Text("「\(plan.name)」将被永久删除，训练记录不受影响。")
        }
        // 恢复训练抽屉（页面 49）
        .bottomDrawer(
            isPresented: $showResumeDrawer,
            height: 420,
            title: "检测到未完成训练",
            subtitle: "你可以继续，也可以稍后处理或放弃草稿"
        ) {
            ResumeSessionDrawer(
                drafts: viewModel.unfinishedDrafts,
                onResume: { session in
                    showResumeDrawer = false
                    onResumeSession(session)
                },
                onLater: { showResumeDrawer = false },
                onAbandon: { session in
                    viewModel.abandonDraft(session)
                    if viewModel.unfinishedDrafts.isEmpty {
                        showResumeDrawer = false
                    }
                },
                onOpenRecovery: {
                    showResumeDrawer = false
                    onOpenRecovery()
                }
            )
        }
        .onChange(of: viewModel.loadState) { state in
            if state == .loaded && !didPromptResume && !viewModel.unfinishedDrafts.isEmpty {
                didPromptResume = true
                showResumeDrawer = true
            }
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            TrainingHomeSkeleton()

        case .failed(let message):
            failureView(message)

        case .loaded:
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                TodayTrainingCard(
                    state: viewModel.todayState,
                    dateText: viewModel.todayDateText,
                    onPrimary: { onStartTraining(viewModel.todayState) }
                )

                quickActions

                myPlansSection

                recentSessionsSection
            }
        }
    }

    private func failureView(_ message: String) -> some View {
        EmptyStateView(
            message: message,
            actionTitle: "重试",
            action: { Task { await viewModel.load() } }
        )
        .padding(.top, DS.Spacing.section)
    }

    // MARK: - 导航栏

    private var navigationBar: some View {
        HStack(alignment: .center) {
            Text("训练")
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            // 日历 / 计划
            Button(action: onOpenCalendar) {
                Image(systemName: "calendar")
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("日历与计划")

            // 更多
            Button(action: onOpenMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("更多")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, 6)
        .background(DS.Palette.bg)
    }

    // MARK: - 快捷入口

    private var quickActions: some View {
        HStack(spacing: DS.Spacing.item) {
            SecondaryButton(title: "新建力量训练", icon: "dumbbell", action: onNewStrength)
            SecondaryButton(title: "新建有氧训练", icon: "figure.run", action: onNewCardio)
        }
    }

    // MARK: - 我的计划

    private var myPlansSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(
                title: "我的计划",
                trailingText: viewModel.plans.isEmpty ? nil : "全部",
                trailingAction: viewModel.plans.isEmpty ? nil : onOpenMore
            )

            if viewModel.plans.isEmpty {
                EmptyStateView(
                    message: "还没有训练计划，新建一个模板，之后就能一键开始。",
                    actionTitle: "新建力量训练",
                    action: onNewStrength
                )
            } else {
                // iOS 16 没有 scrollTargetLayout / scrollTargetBehavior，
                // 横向滚动交给系统贴靠，卡片宽度由可用宽度推导。
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: DS.Spacing.item) {
                        ForEach(viewModel.plans) { plan in
                            PlanCard(
                                plan: plan,
                                onOpen: { onOpenPlan(plan) },
                                onMenu: { drawerPlan = plan }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 最近训练

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(title: "最近训练")

            if viewModel.recentSessions.isEmpty {
                EmptyStateView(message: "完成第一次训练后，这里会按日期显示记录摘要。")
            } else {
                VStack(spacing: DS.Spacing.item) {
                    ForEach(viewModel.recentSessions) { session in
                        SessionRow(session: session) { onOpenSession(session) }
                    }
                }
            }
        }
    }

    // MARK: - 辅助

    /// 从计划卡发起训练时的今日状态
    private func todayStateFor(_ plan: Plan) -> TodayTrainingState {
        .scheduled(
            planID: plan.id,
            name: plan.name,
            exerciseCount: plan.exerciseCount,
            estimatedMinutes: plan.estimatedMinutes
        )
    }
}

// MARK: - 今日训练卡

private struct TodayTrainingCard: View {

    let state: TodayTrainingState
    let dateText: String
    let onPrimary: () -> Void

    var body: some View {
        CardContainer(padding: DS.Spacing.card + 2) {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                header
                body(for: state)
                PrimaryButton(
                    title: state.primaryButtonTitle,
                    icon: state.primaryButtonIcon,
                    isEnabled: state.isActionable,
                    action: onPrimary
                )
            }
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("今日训练")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)

            Spacer(minLength: DS.Spacing.item)

            HStack(spacing: DS.Spacing.tight) {
                if case .inProgress = state {
                    Circle()
                        .fill(DS.Palette.accent)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(dateText)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
    }

    // MARK: 状态内容

    @ViewBuilder
    private func body(for state: TodayTrainingState) -> some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                SkeletonBlock(height: 18, cornerRadius: 5).frame(width: 140)
                SkeletonBlock(height: 14, cornerRadius: 5).frame(width: 200)
            }

        case .empty:
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("今天还没有安排训练")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text("从一个动作开始，或者选择已有计划。")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .scheduled(_, let name, let exerciseCount, let estimatedMinutes):
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text(name)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.card) {
                    MetaLabel(text: "\(exerciseCount) 个动作", icon: "list.bullet")
                    MetaLabel(text: "约 \(estimatedMinutes) 分钟", icon: "clock")
                }
            }

        case .inProgress(_, let name, let completedSets, let totalSets, let elapsed):
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text(name)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: DS.Spacing.card) {
                    MetaLabel(text: "\(completedSets) / \(totalSets) 组", icon: "checkmark.circle")
                    MetaLabel(text: elapsedText(elapsed), icon: "clock")
                }
                ProgressBar(value: state.progress)
                Text("已完成 \(Int(state.progress * 100))%")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    private func elapsedText(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return minutes >= 60 ? "\(minutes / 60) 小时 \(minutes % 60) 分" : "\(minutes) 分钟"
    }
}

// MARK: - 状态扩展

private extension TodayTrainingState {
    var primaryButtonIcon: String? {
        switch self {
        case .inProgress: return "play.fill"
        case .loading: return nil
        default: return nil
        }
    }

    /// 载入中不可点击
    var isActionable: Bool {
        if case .loading = self { return false }
        return true
    }
}

// MARK: - 计划卡

private struct PlanCard: View {

    let plan: Plan
    let onOpen: () -> Void
    let onMenu: () -> Void

    var body: some View {
        // containerRelativeFrame 是 iOS 17 API，这里用 GeometryReader 拿到
        // 横向滚动容器的可用宽度，再夹到 200…260，等价于「屏宽的约 65%」。
        GeometryReader { proxy in
            card
                .frame(width: Self.cardWidth(for: proxy.size.width))
                // GeometryReader 默认左上对齐，这里让它居中，纵向不受拉伸影响
                .frame(
                    width: proxy.size.width,
                    height: proxy.size.height,
                    alignment: .leading
                )
        }
        .frame(height: DS.Size.planCardHeight)
    }

    /// 屏宽约 65%，小屏最小 200，大屏最大 260
    private static func cardWidth(for available: CGFloat) -> CGFloat {
        // 减去卡片间距后的实际可用宽度，避免最后一张卡被裁掉
        let usable = max(0, available - DS.Spacing.item)
        return min(max(usable * 0.65, DS.Size.planCardMinWidth), DS.Size.planCardMaxWidth)
    }

    private var card: some View {
        // 打开计划与三点菜单是两个并列按钮，避免嵌套导致的点击冲突
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text(plan.name)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 为右上角菜单按钮预留位置
                        .padding(.trailing, 32)

                    Spacer(minLength: DS.Spacing.tight)

                    MetaLabel(text: plan.frequencyText, icon: "calendar")
                    MetaLabel(text: "\(plan.exerciseCount) 个动作", icon: "list.bullet")
                    MetaLabel(
                        text: lastUsedText,
                        icon: plan.lastUsedAt == nil ? "clock.badge.questionmark" : "clock"
                    )
                }
                .padding(DS.Spacing.card)
                .frame(maxWidth: .infinity, minHeight: DS.Size.planCardHeight, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "\(plan.name)，\(plan.frequencyText)，\(plan.exerciseCount) 个动作，\(lastUsedText)"
            )

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("\(plan.name) 的更多操作")
        }
    }

    private var lastUsedText: String {
        guard let date = plan.lastUsedAt else { return "尚未使用" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return "上次 \(formatter.string(from: date))"
    }
}

// MARK: - 训练记录行

private struct SessionRow: View {

    let session: WorkoutSession
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                Image(systemName: session.kind.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(session.name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                    Text(session.summaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.tight)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(durationText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(dateText)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .padding(DS.Spacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.name)，\(dateText)，时长 \(durationText)，\(session.summaryText)")
    }

    private var durationText: String {
        let minutes = session.durationSeconds / 60
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return "\(minutes) 分钟"
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: session.startedAt)
    }
}

// MARK: - 计划操作抽屉

private struct PlanActionDrawer: View {

    let plan: Plan
    let onStart: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .accessibilityHidden(true)

            Text(plan.name)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.card)
                .padding(.bottom, DS.Spacing.item)

            row("开始训练", symbol: "play.fill", action: onStart)
            row("编辑", symbol: "pencil", action: onEdit)
            row("复制", symbol: "doc.on.doc", action: onDuplicate)
            row("删除", symbol: "trash", isDestructive: true, action: onDelete)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DS.Palette.surfaceElevated)
    }

    private func row(
        _ title: String,
        symbol: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                Text(title)
                    .font(DS.Typography.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isDestructive ? DS.Palette.danger : DS.Palette.textPrimary)
            .padding(.horizontal, DS.Spacing.page)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - 预览

#Preview("训练首页 · 有进行中训练") {
    TrainingHomeView(
        repository: PreviewFitnessRepository(),
        onStartTraining: { _ in },
        onNewStrength: {},
        onNewCardio: {},
        onOpenPlan: { _ in },
        onOpenSession: { _ in },
        onOpenCalendar: {},
        onOpenMore: {},
        onResumeSession: { _ in },
        onOpenRecovery: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("训练首页 · 空状态") {
    TrainingHomeView(
        repository: PreviewFitnessRepository.makeEmpty(),
        onStartTraining: { _ in },
        onNewStrength: {},
        onNewCardio: {},
        onOpenPlan: { _ in },
        onOpenSession: { _ in },
        onOpenCalendar: {},
        onOpenMore: {},
        onResumeSession: { _ in },
        onOpenRecovery: {}
    )
    .preferredColorScheme(.dark)
}
