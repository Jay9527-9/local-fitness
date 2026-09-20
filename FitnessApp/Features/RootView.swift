//
//  RootView.swift
//  四栏 Tab 骨架：训练 / 动作 / 历史 / 我的。
//  Tab 栏用 safeAreaInset 固定，内容不会被遮挡，也不侵入底部手势区。
//
//  各 Tab 内部的导航用 NavigationStack 包裹，深层页面在各自栈内推入，
//  这样切 Tab 不会互相干扰返回栈。
//

import SwiftUI

// MARK: - Tab 定义

enum MainTab: String, CaseIterable, Identifiable {
    case training
    case exercises
    case history
    case profile

    var id: String { rawValue }

    /// 标签文案
    var title: String {
        switch self {
        case .training:  return "训练"
        case .exercises: return "动作"
        case .history:   return "历史"
        case .profile:   return "我的"
        }
    }

    /// 线框图标
    var symbolName: String {
        switch self {
        case .training:  return "figure.strengthtraining.traditional"
        case .exercises: return "dumbbell"
        case .history:   return "clock.arrow.circlepath"
        case .profile:   return "person"
        }
    }

    /// 选中态的实心图标，增强对比
    var selectedSymbolName: String {
        switch self {
        case .training:  return "figure.strengthtraining.traditional"
        case .exercises: return "dumbbell.fill"
        case .history:   return "clock.arrow.circlepath"
        case .profile:   return "person.fill"
        }
    }
}

// MARK: - Tab 栏

struct MainTabBar: View {

    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    guard selection != tab else { return }
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: selection == tab ? tab.selectedSymbolName : tab.symbolName)
                            .font(.system(size: 20, weight: selection == tab ? .semibold : .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(DS.Typography.caption2)
                    }
                    .foregroundStyle(selection == tab ? DS.Palette.accent : DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
        .background(
            DS.Palette.bg
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Palette.stroke)
                        .frame(height: 1)
                }
        )
    }
}

// MARK: - 根视图

struct RootView: View {

    private let repository: FitnessRepository

    @State private var selection: MainTab = .training
    /// 训练结束后置为新值，驱动首页与历史页重新读盘。
    /// 训练 Tab 与历史 Tab 是两棵独立的视图树，跨 Tab 后不一定走 onAppear。
    @State private var sessionSummaryReloadToken = UUID()
    /// 从训练总结页跳到历史栏时要定位的那次训练
    @State private var pendingHistorySessionID: UUID?
    /// 从「动作收藏」跨 Tab 到动作栏时要打开的动作详情
    @State private var pendingExerciseDetail: ExerciseLibraryItem?
    /// 首次启动（或清除全部数据后）展示引导（页面 47）。
    @State private var showOnboarding = !ProfileSettings.hasCompletedOnboarding

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()

            TabTransitionContainer(tab: selection) {
                tabContent
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                MainTabBar(selection: $selection)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(
                repository: repository,
                onComplete: {
                    ProfileSettings.hasCompletedOnboarding = true
                    showOnboarding = false
                },
                onSkip: {
                    ProfileSettings.hasCompletedOnboarding = true
                    showOnboarding = false
                }
            )
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .training:
            TrainingTab(
                repository: repository,
                reloadToken: sessionSummaryReloadToken,
                onOpenHistory: { sessionID in
                    sessionSummaryReloadToken = UUID()
                    pendingHistorySessionID = sessionID
                    selection = .history
                }
            )

        case .exercises:
            ExercisesTab(
                repository: repository,
                pendingDetail: pendingExerciseDetail,
                onConsumePendingDetail: { pendingExerciseDetail = nil }
            )

        case .history:
            HistoryTab(
                repository: repository,
                highlightSessionID: pendingHistorySessionID,
                onConsumeHighlight: { pendingHistorySessionID = nil },
                onClearedAllData: {
                    selection = .training
                    showOnboarding = true
                }
            )

        case .profile:
            ProfileTab(
                repository: repository,
                onOpenHistory: { sessionID in
                    sessionSummaryReloadToken = UUID()
                    pendingHistorySessionID = sessionID
                    selection = .history
                },
                onOpenExerciseDetail: { item in
                    pendingExerciseDetail = item
                    selection = .exercises
                },
                onBrowseExercises: {
                    selection = .exercises
                },
                onViewHistory: {
                    pendingHistorySessionID = nil
                    selection = .history
                },
                onClearedAllData: {
                    selection = .training
                    showOnboarding = true
                }
            )
        }
    }
}

// MARK: - 我的 Tab

/// 我的页及其子页面的导航栈。
///
/// 身体数据（页面 12）、个人资料、我的计划、动作收藏、训练偏好、数据管理
/// 都从「我的」页推入。与历史 / 动作栏同理：路由类型必须与它所在的
/// `NavigationStack` 一一对应。
private struct ProfileTab: View {

    let repository: FitnessRepository
    /// 训练总结页「查看历史记录」要跨 Tab 跳转：由 RootView 切 Tab 并定位本次训练。
    let onOpenHistory: (UUID) -> Void
    /// 「动作收藏」的「查看详情」跨 Tab 到动作栏：由 RootView 切 Tab 并打开详情。
    let onOpenExerciseDetail: (ExerciseLibraryItem) -> Void
    /// 「动作收藏」空状态的「浏览动作库」跨 Tab 到动作栏。
    let onBrowseExercises: () -> Void
    /// 导入备份成功页「查看训练历史」跨 Tab 到历史栏（不定位具体训练）。
    let onViewHistory: () -> Void
    /// 清除全部本地数据后重置到首次启动引导（页面 46）。
    let onClearedAllData: () -> Void

    @State private var path = NavigationPath()
    /// 子页保存 / 删除后 +1，强制重建我的页，让摘要卡重新读盘。
    ///
    /// 与历史页的 `historyReloadToken` 同一套路：我的页常驻栈底，
    /// 从子页返回时不会走 `onAppear`，只能靠 `.id()` 强制重建。
    @State private var profileReloadToken = UUID()

    // 直接导出 / 导入备份（「数据」组菜单项）用的数据管理 VM 与状态。
    @StateObject private var dataVM: WorkoutDataManagementViewModel
    @State private var exportedFile: ExportedFile?
    @State private var showFileImporter = false
    @State private var pendingImportURL: URL?
    @State private var showImportPolicyPicker = false

    // 页面 15：我的计划 → 计划详情 → 动作选择器 / 训练执行页。
    // 与 TrainingTab 一样，动作选择器是一个 sheet，选完写库后回到详情。
    @State private var pickerContext: ExercisePickerContext?
    @State private var showExercisePicker = false
    @State private var planRefreshToken: Int = 0
    // 「＋」菜单的「新建力量计划」命名抽屉与「导入本地计划备份」文件选择。
    @State private var showNewPlanSheet = false
    @State private var showPlanImporter = false

    init(
        repository: FitnessRepository,
        onOpenHistory: @escaping (UUID) -> Void,
        onOpenExerciseDetail: @escaping (ExerciseLibraryItem) -> Void,
        onBrowseExercises: @escaping () -> Void,
        onViewHistory: @escaping () -> Void,
        onClearedAllData: @escaping () -> Void
    ) {
        self.repository = repository
        self.onOpenHistory = onOpenHistory
        self.onOpenExerciseDetail = onOpenExerciseDetail
        self.onBrowseExercises = onBrowseExercises
        self.onViewHistory = onViewHistory
        self.onClearedAllData = onClearedAllData
        _dataVM = StateObject(
            wrappedValue: WorkoutDataManagementViewModel(repository: repository)
        )
    }

    var body: some View {
        // 与 TrainingTab.body 同一个坑：原来这条表达式把
        // NavigationStack + ProfileView + **19 个 case 的 switch** + 3 个 sheet
        // + 1 个 fileImporter + 2 个 bottomDrawer 全塞在一起，规模约 11000 字符
        // / 66 层大括号 —— 已经越过类型检查器上限，编译器会以
        // `failed to produce diagnostic for expression` 放弃（同文件 1153 行刚犯过）。
        //
        // 拆成三块：导航宿主 / 路由 switch / 各种弹出层。
        navHost
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .bottomDrawer(
                isPresented: $showImportPolicyPicker,
                height: 420,
                title: "导入方式",
                subtitle: "本机已有 \(dataVM.finishedCount) 次训练记录"
            ) {
                importPolicyContent
            }
            .sheet(isPresented: $showExercisePicker, onDismiss: {
                pickerContext = nil
                planRefreshToken &+= 1
            }) {
                exercisePickerSheet
            }
            .bottomDrawer(
                isPresented: $showNewPlanSheet,
                height: 300,
                title: "新建力量计划",
                subtitle: "创建后进入计划详情添加动作"
            ) {
                NewPlanNameContent { name in
                    createPlan(named: name)
                }
            }
            .fileImporter(
                isPresented: $showPlanImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handlePlanImport(result)
            }
    }

    /// 我的页导航宿主。栈底是「我的」，路由分派交给 `profileDestination`。
    private var navHost: some View {
        NavigationStack(path: $path) {
            ProfileView(
                viewModel: ProfileViewModel(repository: repository),
                onOpenBodyData: { path.append(ProfileRoute.bodyData) },
                onOpenProfileEdit: { path.append(ProfileRoute.profileEdit) },
                onOpenPlans: { path.append(ProfileRoute.planList) },
                onOpenFavorites: { path.append(ProfileRoute.favorites) },
                onOpenTrainingPreferences: { path.append(ProfileRoute.trainingPreferences) },
                onOpenDataManagement: { path.append(ProfileRoute.dataManagement) },
                onOpenAppSettings: { path.append(ProfileRoute.appSettings) },
                onExportBackup: { exportBackup() },
                onImportBackup: { showFileImporter = true }
            )
            .id(profileReloadToken)
            // 我的页自带大标题导航栏，隐藏系统栏避免双层标题
            .navigationBarHidden(true)
            .navigationDestination(for: ProfileRoute.self) { route in
                profileDestination(for: route)
            }
        }
    }

    /// 我的页路由分派。19 个 case 全部只做「构造子页 + 接回调」。
    ///
    /// **单个 case 里闭包多的（≥4 个），一律拆成独立方法。**
    /// 分派方法本身是一个巨大的 `switch`，每个 case 的类型推理会累积到
    /// 整个表达式上；`sessionDraft` 那种「5 个闭包 + 每个闭包里还有
    /// `guard` / 多语句」的 case 内联进来，会让整个 `switch` 报
    /// `type of expression is ambiguous` —— 而且错误指在别处。
    @ViewBuilder
    private func profileDestination(for route: ProfileRoute) -> some View {
        switch route {
        case .bodyData:
            BodyDataView(
                viewModel: BodyDataViewModel(repository: repository),
                onBack: {
                    popOne()
                    profileReloadToken = UUID()
                },
                onDataChanged: { profileReloadToken = UUID() }
            )

        case .profileEdit:
            ProfileEditView(
                repository: repository,
                onCancel: {
                    popOne()
                },
                onSaved: {
                    // 保存成功：返回并刷新「我的」概览（昵称 / 头像 / 天数）
                    popOne()
                    profileReloadToken = UUID()
                }
            )

        case .planList:
            profilePlanListView

        case .planDetail(let planID):
            planDetailView(planID: planID)

        case .exerciseConfig(let planID, let entry):
            PlanExerciseConfigView(
                entry: entry,
                item: lookupExercise(for: entry),
                planName: lookupPlanName(planID),
                onSave: { updated in
                    try? repository.updatePlanExercise(updated, inPlan: planID)
                }
            )

        case .sessionDraft(let sessionID):
            profileSessionDraftView(sessionID: sessionID)

        case .sessionSummary(let sessionID):
            profileSessionSummaryView(sessionID: sessionID)

        case .favorites:
            profileFavoritesView

        case .trainingPreferences:
            TrainingPreferencesView(onBack: { popOne() })

        case .appSettings:
            profileAppSettingsView

        case .unitSettings:
            UnitSettingsView(onBack: { popOne() })

        case .soundAndHaptics:
            SoundAndHapticsView(onBack: { popOne() })

        case .reduceMotion:
            ReduceMotionView(onBack: { popOne() })

        case .permissions:
            PermissionSettingsView(onBack: { popOne() })

        case .dataManagement:
            profileDataManagementView

        case .exportBackup:
            ExportBackupView(
                viewModel: ExportBackupViewModel(repository: repository),
                onBack: { popOne() }
            )

        case .importBackup:
            ImportBackupView(
                viewModel: ImportBackupViewModel(repository: repository),
                onDone: {
                    popOne()
                    profileReloadToken = UUID()
                },
                onViewHistory: {
                    popToRoot()
                    onViewHistory()
                }
            )

        case .clearRecords:
            ClearWorkoutRecordsView(
                repository: repository,
                onBack: {
                    popOne()
                    profileReloadToken = UUID()
                },
                onOpenExportBackup: {
                    path.append(ProfileRoute.exportBackup)
                }
            )

        case .clearAllData:
            ClearAllDataView(
                repository: repository,
                onBack: {
                    popOne()
                    profileReloadToken = UUID()
                },
                onOpenExportBackup: {
                    path.append(ProfileRoute.exportBackup)
                },
                onClearedAllData: {
                    popToRoot()
                    onClearedAllData()
                }
            )
        }
    }

    /// 返回上一页。只弹一层，不清空整栈（与其它 Tab 的 popOne 同一约定）。
    private func popOne() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// 我的页里的训练执行页（页面 05 / 31 分派）。
    ///
    /// 从 `profileDestination(for:)` 的 `.sessionDraft` 分支拆出来：
    /// 那个 case 有 5 个闭包，其中一个带 `guard`，内联在 19 个 case 的
    /// 巨型 `switch` 里会把整段表达式的检查规模推上去。
    /// 这里也顺带把有氧 / 力量的分派收在一处。
    @ViewBuilder
    private func profileSessionDraftView(sessionID: UUID) -> some View {
        if isCardioSession(sessionID) {
            CardioSessionView(
                repository: repository,
                sessionID: sessionID,
                onFinished: { finished in
                    path.append(ProfileRoute.sessionSummary(finished.id))
                },
                onMinimize: {
                    // 有氧页没有「草稿」概念，最小化等于退出。
                    popOne()
                }
            )
        } else {
            WorkoutSessionView(
                repository: repository,
                sessionID: sessionID,
                onFinished: { finished in
                    path.append(ProfileRoute.sessionSummary(finished.id))
                },
                onMinimize: { popOne() },
                onEditConfig: { entry in
                    guard let planID = try? repository.fetchSession(id: sessionID)?.planID else { return }
                    path.append(ProfileRoute.exerciseConfig(planID: planID, entry: entry))
                },
                onRequestReplace: { card in
                    pickerContext = ExercisePickerContext(
                        planID: nil,
                        replacingEntryID: nil,
                        sessionID: sessionID,
                        replacingExerciseID: card.exerciseID
                    )
                    showExercisePicker = true
                }
            )
        }
    }

    /// 该草稿是不是有氧训练。查不到草稿时按力量训练处理（执行页自己会兜底）。
    private func isCardioSession(_ sessionID: UUID) -> Bool {
        (try? repository.fetchSession(id: sessionID))??.kind == .cardio
    }

    // MARK: 我的页：闭包多的子页各自成方法
    //
    // 下面五个子页都有 4–7 个闭包。**内联在 `profileDestination(for:)` 里
    // 会把那个巨型 `switch` 的检查规模推到阈值以上**，报出来的却是
    // 别处的 `type of expression is ambiguous`。拆出来之后每个方法的
    // 检查规模都是独立计算的，互不累加。

    /// 我的计划（页面 15）。
    private var profilePlanListView: some View {
        PlanListView(
            repository: repository,
            onOpenPlan: { plan in
                path.append(ProfileRoute.planDetail(plan.id))
            },
            onStartTraining: { plan in
                startPlanDraft(plan)
            },
            onNewPlan: {
                showNewPlanSheet = true
            },
            onImportBackup: {
                showPlanImporter = true
            },
            onBack: {
                popOne()
                profileReloadToken = UUID()
            }
        )
    }

    /// 动作收藏。
    private var profileFavoritesView: some View {
        FavoriteExercisesView(
            repository: repository,
            onBack: { popOne() },
            onOpenExercise: { item in
                onOpenExerciseDetail(item)
            },
            onBrowseExercises: {
                onBrowseExercises()
            }
        )
    }

    /// 应用设置。
    private var profileAppSettingsView: some View {
        AppSettingsView(
            onBack: {
                popOne()
                profileReloadToken = UUID()
            },
            onOpenUnits: {
                path.append(ProfileRoute.unitSettings)
            },
            onOpenSoundAndHaptics: {
                path.append(ProfileRoute.soundAndHaptics)
            },
            onOpenReduceMotion: {
                path.append(ProfileRoute.reduceMotion)
            },
            onOpenPermissions: {
                path.append(ProfileRoute.permissions)
            }
        )
    }

    /// 数据管理（页面 10 的导出 / 导入 / 清除入口）。
    private var profileDataManagementView: some View {
        WorkoutDataManagementView(
            viewModel: WorkoutDataManagementViewModel(repository: repository),
            onBack: {
                popOne()
                profileReloadToken = UUID()
            },
            onDataChanged: { profileReloadToken = UUID() },
            onOpenExportBackup: {
                path.append(ProfileRoute.exportBackup)
            },
            onOpenImportBackup: {
                path.append(ProfileRoute.importBackup)
            },
            onOpenClearRecords: {
                path.append(ProfileRoute.clearRecords)
            },
            onOpenClearAll: {
                path.append(ProfileRoute.clearAllData)
            }
        )
    }

    /// 训练总结页（页面 07）。两个出口都要清栈：总结页通常压在
    /// 执行页之上，逐层弹出会在中间层触发多余的 onAppear 读盘。
    private func profileSessionSummaryView(sessionID: UUID) -> some View {
        SessionSummaryView(
            repository: repository,
            sessionID: sessionID,
            onDone: {
                popToRoot()
                profileReloadToken = UUID()
            },
            onOpenHistory: {
                // 跨 Tab 到历史栏定位本次训练，交给 RootView 处理。
                popToRoot()
                onOpenHistory(sessionID)
            }
        )
    }

    /// 清空整个栈，回到「我的」首页。
    ///
    /// 用于「总结页完成 / 导入完成 / 清除全部数据」这类**已离开本页语义**的场景：
    /// 一次次 `removeLast()` 会在中间每一层触发 `onAppear` 重新读盘，
    /// 一次清空更稳，也不会闪出中间页。
    private func popToRoot() {
        path = NavigationPath()
    }

    // MARK: 页面 15 计划详情 / 执行页 / 动作选择器

    /// 计划详情页。与 TrainingTab 的 planDetailView 同构：所有跳转都走 path。
    private func planDetailView(planID: UUID) -> some View {
        PlanDetailView(
            repository: repository,
            planID: planID,
            refreshToken: planRefreshToken,
            onStartTraining: { session in
                path.append(ProfileRoute.sessionDraft(session.id))
            },
            onOpenExerciseConfig: { entry in
                path.append(ProfileRoute.exerciseConfig(planID: planID, entry: entry))
            },
            onAddExercise: { targetPlanID in
                pickerContext = ExercisePickerContext(planID: targetPlanID)
                showExercisePicker = true
            },
            onReplaceExercise: { entry in
                pickerContext = ExercisePickerContext(planID: planID, replacingEntryID: entry.id)
                showExercisePicker = true
            },
            onOpenPlan: { copyID in
                path.append(ProfileRoute.planDetail(copyID))
            },
            onDeleted: {
                if !path.isEmpty { path.removeLast() }
                profileReloadToken = UUID()
            }
        )
    }

    /// 「我的计划」三点菜单「开始训练」：按计划展开草稿并推进执行页。
    private func startPlanDraft(_ plan: Plan) {
        guard !plan.exercises.isEmpty else {
            // 空计划没有可执行的组，直接进详情页让用户先加动作
            path.append(ProfileRoute.planDetail(plan.id))
            return
        }
        var draft = WorkoutSession.draft(from: plan)
        seedPrescribedWeights(in: &draft)
        try? repository.save(session: draft)

        var touched = plan
        touched.lastUsedAt = Date()
        _ = try? repository.replace(plan: touched)

        path.append(ProfileRoute.sessionDraft(draft.id))
    }

    /// 用历史记录里的最高重量预填未完成组的重量（与 TrainingTab 同逻辑）。
    private func seedPrescribedWeights(in draft: inout WorkoutSession) {
        guard ProfileSettings.prefillWeights else { return }
        guard let recent = try? repository.fetchRecentSessions(limit: 30) else { return }
        var bestWeight: [String: Double] = [:]
        for past in recent where past.id != draft.id && past.isFinished {
            for entry in past.completedEntries where entry.weight > 0 {
                bestWeight[entry.exerciseID] = max(bestWeight[entry.exerciseID] ?? 0, entry.weight)
            }
        }
        guard !bestWeight.isEmpty else { return }
        for index in draft.entries.indices where draft.entries[index].completedAt == nil {
            let id = draft.entries[index].exerciseID
            if let weight = bestWeight[id], draft.entries[index].weight <= 0 {
                draft.entries[index].weight = weight
            }
        }
    }

    /// 新建力量计划：写库后直接推入详情页编辑。
    private func createPlan(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let plan = try repository.createPlan(name: trimmed, trainingDays: [])
            showNewPlanSheet = false
            profileReloadToken = UUID()
            path.append(ProfileRoute.planDetail(plan.id))
        } catch {
            // 创建失败不打断列表，静默返回
        }
    }

    /// 处理「导入本地计划备份」的文件选择。
    private func handlePlanImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let imported = PlanListViewModel(repository: repository).importBackup(from: url)
            if imported >= 0 {
                profileReloadToken = UUID()
            }
        case .failure:
            // 用户取消或选错文件，静默返回
            break
        }
    }

    /// 动作选择器 sheet。与 TrainingTab 同构。
    private var exercisePickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") {
                    showExercisePicker = false
                }
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textSecondary)

                Spacer()

                Text(pickerContext?.pickerTitle ?? "选择动作")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer()

                Text("取消")
                    .font(DS.Typography.body)
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

            ExerciseLibraryView(
                viewModel: ExerciseLibraryViewModel(repository: repository),
                onOpenExercise: { item in
                    commitPick(item)
                },
                onNewCustomExercise: {},
                onEditCustomExercise: { _ in },
                onAddToWorkout: { item in
                    commitPick(item)
                },
                pickerTitle: pickerContext?.pickerTitle ?? "选择动作"
            )
        }
    }

    /// 选中动作后按上下文写库（追加 / 替换计划条目 / 替换训练中动作）。
    private func commitPick(_ item: ExerciseLibraryItem) {
        guard let context = pickerContext else { return }

        if let sessionID = context.sessionID, let oldExerciseID = context.replacingExerciseID {
            _ = try? repository.replaceExerciseInSession(
                sessionID: sessionID,
                fromExerciseID: oldExerciseID,
                toExerciseID: item.id
            )
            showExercisePicker = false
            return
        }

        guard let planID = context.planID else { return }

        if let entryID = context.replacingEntryID {
            try? repository.replacePlanExercise(entryID, inPlan: planID, withExerciseID: item.id)
        } else {
            try? repository.appendExercise(
                PlanExercise(exerciseID: item.id),
                toPlan: planID
            )
        }
        Haptics.success()
        showExercisePicker = false
    }

    private func lookupExercise(for entry: PlanExercise) -> ExerciseLibraryItem? {
        try? repository.fetchExercises(ids: [entry.exerciseID]).first
    }

    private func lookupPlanName(_ planID: UUID) -> String {
        (try? repository.fetchPlan(id: planID))?.name ?? "计划"
    }

    // MARK: 直接导出 / 导入

    private func exportBackup() {
        Task {
            await dataVM.load()
            if let url = dataVM.exportBackup() {
                exportedFile = ExportedFile(url: url)
            }
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingImportURL = url
            showImportPolicyPicker = true
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError { return }
        }
    }

    private func performPendingImport() {
        guard let url = pendingImportURL else { return }
        pendingImportURL = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        Task {
            await dataVM.load()
            if dataVM.importBackup(from: url) != nil {
                profileReloadToken = UUID()
            }
        }
    }

    private var importPolicyContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(WorkoutBackupMergePolicy.allCases.enumerated()), id: \.element.id) { index, policy in
                Button {
                    dataVM.mergePolicy = policy
                    showImportPolicyPicker = false
                    performPendingImport()
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        Image(systemName: policy.isDestructive ? "exclamationmark.triangle" : "square.stack.3d.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(policy.isDestructive ? DS.Palette.danger : DS.Palette.accent)
                            .frame(width: 26, alignment: .center)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(policy.title)
                                .font(DS.Typography.body)
                                .foregroundStyle(policy.isDestructive ? DS.Palette.danger : DS.Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            Text(policy.subtitle)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: DS.Spacing.tight)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("\(policy.title)。\(policy.subtitle)")

                if index < WorkoutBackupMergePolicy.allCases.count - 1 {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }
}

/// 我的 Tab 的导航目标
enum ProfileRoute: Hashable {
    /// 身体数据（页面 12）
    case bodyData
    /// 个人资料编辑（页面 13）
    case profileEdit
    /// 我的计划（页面 15）
    case planList
    /// 计划详情与编辑（页面 04）。从「我的计划」点入。
    case planDetail(UUID)
    /// 动作配置（页面 04 子页）。从计划详情「编辑动作配置」点入。
    case exerciseConfig(planID: UUID, entry: PlanExercise)
    /// 训练执行页（页面 05）。从「我的计划」三点菜单「开始训练」进入。
    case sessionDraft(UUID)
    /// 训练总结页（页面 07）。从「我的计划」进入的训练结束后推入。
    case sessionSummary(UUID)
    /// 动作收藏（页面 16）
    case favorites
    /// 训练偏好（页面 14）
    case trainingPreferences
    /// 应用设置（页面 22）
    case appSettings
    /// 单位设置（页面 42）。从「应用设置」点入。
    case unitSettings
    /// 声音与触感（页面 43）。从「应用设置」点入。
    case soundAndHaptics
    /// 减少动态效果（页面 44）。从「应用设置」点入。
    case reduceMotion
    /// 权限管理（页面 51）。从「应用设置」点入。
    case permissions
    /// 本地数据管理（复用页面 10）
    case dataManagement
    /// 导出本地备份（页面 19）。从「本地数据管理」点入。
    case exportBackup
    /// 导入本地备份（页面 20）。从「本地数据管理」点入。
    case importBackup
    /// 清除训练记录确认（页面 45）。从「本地数据管理」点入。
    case clearRecords
    /// 清除全部本地数据确认（页面 46）。从「本地数据管理」点入。
    case clearAllData
}

// MARK: - 历史 Tab

private struct HistoryTab: View {

    let repository: FitnessRepository
    /// 需要定位并展开的训练。来自训练总结页的「查看历史记录」。
    let highlightSessionID: UUID?
    let onConsumeHighlight: () -> Void
    /// 清除全部本地数据后重置到首次启动引导（页面 46）。
    let onClearedAllData: () -> Void

    @State private var path = NavigationPath()
    /// 已经为本轮 highlight 推过详情页，避免重复入栈
    @State private var didPushHighlight = false
    /// 详情页里发生了写操作（删除 / 复制 / 改名 / 改备注）就 +1。
    ///
    /// 为什么需要它：历史页的列表与日历标记来自 `HistoryViewModel.sessions`，
    /// 那是一份内存副本。从详情页返回时，历史页并不会重新加载 ——
    /// `onAppear` 在 NavigationStack 回退时**不会**触发（页面从未离开视图树）。
    /// 少了这个令牌，删掉一条记录返回后日历上还会留着那个绿点。
    ///
    /// 用 `.id()` 强制重建是项目里既有的做法（见首页的 `homeReloadID`）：
    /// 比在每个写操作后回着调 viewModel 更可靠，不会漏掉某条路径。
    @State private var historyReloadToken = UUID()

    var body: some View {
        // 与 TrainingTab / ProfileTab 同一个坑：原来把 NavigationStack +
        // HistoryView + 9 个 case 的 switch（内含 4 个闭包的执行页、趋势页）
        // 拼成一条约 7500 字符 / 38 层大括号的表达式。
        // 同一个文件的 1153 行已经因此被编译器拒过一次，这里一并拆开。
        navHost
            .task(id: highlightSessionID) {
                // 新的定位请求到来时重新放行，允许下一次「查看历史记录」再次入栈
                if highlightSessionID == nil { didPushHighlight = false }
                await handleHighlight()
            }
    }

    /// 历史页导航宿主。
    private var navHost: some View {
        NavigationStack(path: $path) {
            HistoryView(
                viewModel: HistoryViewModel(repository: repository),
                highlightSessionID: highlightSessionID,
                onOpenSession: { session in
                    pushDetail(session.id)
                },
                onOpenDraft: { draftID in
                    path.append(HistoryRoute.sessionDraft(draftID))
                },
                onOpenStats: {
                    path.append(HistoryRoute.stats)
                },
                onDataChanged: { historyReloadToken = UUID() }
            )
            .id(historyReloadToken)
            .navigationBarHidden(true)
            .navigationDestination(for: HistoryRoute.self) { route in
                historyDestination(for: route)
            }
        }
    }

    /// 历史页路由分派。
    @ViewBuilder
    private func historyDestination(for route: HistoryRoute) -> some View {
        switch route {
        case .sessionDetail(let sessionID):
            HistorySessionDetailView(
                viewModel: HistorySessionDetailViewModel(
                    repository: repository,
                    sessionID: sessionID
                ),
                // 返回时无条件刷新：详情页可能改过名、改过备注、
                // 或者已经删掉了这条记录，历史页的日历与列表都需要重读。
                // 不做「有没有真的改」的判断——一次多余的本地读盘
                // 远便宜于漏刷一次导致的错误标记。
                onBack: {
                    popOne()
                    historyReloadToken = UUID()
                },
                onOpenDraft: { draftID in
                    path.append(HistoryRoute.sessionDraft(draftID))
                }
            )
        case .sessionDraft(let draftID):
            WorkoutSessionView(
                repository: repository,
                sessionID: draftID,
                onFinished: { _ in
                    // 完成后退出执行页回到历史页。
                    // 不在这里自动跳总结页：从历史页补记训练的用户
                    // 想看到的是日历上多了一条记录，而不是被推到总结页。
                    historyPopToRoot()
                },
                onMinimize: {
                    // 草稿已实时落盘，退出页面后仍可从首页「继续训练」进入。
                    // 草稿是未结束状态，不进日历标记，但历史页的列表要重新读。
                    popOne()
                    historyReloadToken = UUID()
                },
                onEditConfig: { _ in
                    // 自由训练草稿没有关联计划，不提供动作配置编辑
                },
                onRequestReplace: { _ in
                    // 同上：自由训练从空开始，替换动作在训练页内完成
                }
            )
        case .stats:
            WorkoutStatisticsView(
                viewModel: WorkoutStatisticsViewModel(repository: repository),
                // 用 popOne() 而不是清空整个栈：统计页是从历史页的
                // 「统计」分段推上来的，清空会把历史页已经滚到的位置
                // 和分段选择一起丢掉（页面 09 已记录过这条）。
                onBack: { popOne() },
                onOpenDataManagement: {
                    path.append(HistoryRoute.statsDataManagement)
                },
                onOpenExerciseTrend: { stat in
                    path.append(HistoryRoute.exerciseTrend(stat.exerciseID))
                }
            )

        case .statsDataManagement:
            WorkoutDataManagementView(
                viewModel: WorkoutDataManagementViewModel(repository: repository),
                onBack: { popOne() },
                // 清除或导入后，历史页的日历标记、列表条数与统计数字
                // 都要重算。historyReloadToken 会强制重建历史页，
                // 而统计页在返回时会重新走 .task { load() }。
                onDataChanged: { historyReloadToken = UUID() },
                onOpenExportBackup: {
                    path.append(HistoryRoute.exportBackup)
                },
                onOpenImportBackup: {
                    path.append(HistoryRoute.importBackup)
                },
                onOpenClearRecords: {
                    path.append(HistoryRoute.clearRecords)
                },
                onOpenClearAll: {
                    path.append(HistoryRoute.clearAllData)
                }
            )

        case .exportBackup:
            ExportBackupView(
                viewModel: ExportBackupViewModel(repository: repository),
                onBack: { popOne() }
            )

        case .importBackup:
            ImportBackupView(
                viewModel: ImportBackupViewModel(repository: repository),
                onDone: {
                    popOne()
                    historyReloadToken = UUID()
                },
                onViewHistory: {
                    historyPopToRoot()
                }
            )

        case .clearRecords:
            ClearWorkoutRecordsView(
                repository: repository,
                onBack: {
                    popOne()
                    historyReloadToken = UUID()
                },
                onOpenExportBackup: {
                    path.append(HistoryRoute.exportBackup)
                }
            )

        case .clearAllData:
            ClearAllDataView(
                repository: repository,
                onBack: {
                    popOne()
                    historyReloadToken = UUID()
                },
                onOpenExportBackup: {
                    path.append(HistoryRoute.exportBackup)
                },
                onClearedAllData: {
                    path = NavigationPath()
                    onClearedAllData()
                }
            )

        case .exerciseTrend(let exerciseID):
            ExerciseTrendDetailView(
                viewModel: ExerciseTrendDetailViewModel(
                    exerciseID: exerciseID,
                    fallbackName: exerciseName(for: exerciseID),
                    repository: repository
                ),
                onBack: { popOne() },
                // 「最近记录」进的是历史训练详情页，和历史页里点某一天
                // 走同一个路由：返回栈因此是连贯的，用户不需要先退到
                // 趋势页再退一次才能回到历史页。
                onOpenSessionDetail: { sessionID in
                    path.append(HistoryRoute.sessionDetail(sessionID))
                },
                // 草稿在趋势页里已经落盘，交给执行页的只是一个 id。
                // 传内存对象的话执行页刷新一次就会丢掉未保存的组。
                onStartTraining: { draftID in
                    path.append(HistoryRoute.sessionDraft(draftID))
                }
            )
        }
    }

    /// 清空整栈 + 刷新历史页数据。
    ///
    /// 执行页完成 / 导入完成这两处需要「回到历史页并重新读盘」，
    /// 原来写的是 `path = NavigationPath()` 紧跟一行 `historyReloadToken = UUID()`，
    /// 两处重复。抽成方法是为了让「清栈」这件事只有一个写法 ——
    /// 注意这里**不用 `popOne()`**：草稿执行页是从列表推上来的，
    /// 但完成后要落回列表本身而不是中间层，且必须重新读盘。
    private func historyPopToRoot() {
        path = NavigationPath()
        historyReloadToken = UUID()
    }

    /// 「查看历史记录」的目标是历史页里的本次训练详情页，因此直接推入详情。
    ///
    /// 必须等训练读完盘再推：历史栏可能在本次训练写入前就已挂载，
    /// 此时 fetchSession 会失败，过早入栈会落到总结页的空状态。
    @MainActor
    private func handleHighlight() async {
        guard let target = highlightSessionID, !didPushHighlight else { return }
        didPushHighlight = true

        let hasRecord = (try? repository.fetchSession(id: target)) != nil
        guard hasRecord else {
            // 记录确实不存在：留在列表页，仅消费掉定位请求
            onConsumeHighlight()
            return
        }

        pushDetail(target)
        // 详情已入栈，列表页的滚动高亮不再需要，此时再消费掉
        onConsumeHighlight()
    }

    private func pushDetail(_ sessionID: UUID) {
        // 已经在详情页时不再叠加
        guard path.isEmpty else { return }
        path.append(HistoryRoute.sessionDetail(sessionID))
    }

    /// 返回上一页。
    ///
    /// 不用 `path = NavigationPath()`：详情页是从历史列表推上来的，
    /// 整体清空会把用户已经滚到的位置和列表状态一起丢掉。
    /// 只在栈非空时退一层。
    private func popOne() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: 动作信息
    //
    // 趋势子页要一个动作名，但路由里只存了 exerciseID
    // （Hashable 的路由值越简单越不容易出问题；整个 ExerciseLibraryItem
    // 塞进路由会让每次入栈都复制一遍指令数组与别名列表）。
    // 所以这里查一次库，把名字交给子页。查不到时子页会自己兜底。
    //
    // 页面 11 之前这里还查了肌群（旧的趋势占位页拿它画图标），真页面只
    // 显示动作名，肌群那一路就删了：留一个没人读的查询函数，下次改路由
    // 的人还得判断它是不是还在被用。

    private func exerciseName(for exerciseID: String) -> String {
        guard let item = try? repository.fetchExercises(ids: [exerciseID]).first else {
            return exerciseID
        }
        return item.displayName
    }
}

// MARK: - 历史页路由

enum HistoryRoute: Hashable {
    case sessionDetail(UUID)
    /// 从历史页新建的力量 / 有氧训练草稿
    case sessionDraft(UUID)
    /// 训练统计（页面 10）
    case stats
    /// 本地数据管理（页面 10 附页）：导出 / 导入备份、清除训练记录
    case statsDataManagement
    /// 导出本地备份（页面 19）。从历史页的数据管理点入。
    case exportBackup
    /// 导入本地备份（页面 20）。从历史页的数据管理点入。
    case importBackup
    /// 清除训练记录确认（页面 45）。从历史页的数据管理点入。
    case clearRecords
    /// 清除全部本地数据确认（页面 46）。从历史页的数据管理点入。
    case clearAllData
    /// 动作历史趋势（页面 10 子页）。从「常练动作」点入。
    case exerciseTrend(String)
}


// MARK: - 训练 Tab

private struct TrainingTab: View {

    let repository: FitnessRepository
    /// 变化时重新读取首页数据。训练结束后由此刷新「最近训练」。
    let reloadToken: UUID
    /// 训练总结页「查看历史记录」要跨 Tab 跳转：由 RootView 切 Tab 并定位本次训练。
    let onOpenHistory: (UUID) -> Void

    @State private var path = NavigationPath()
    @State private var pickerContext: ExercisePickerContext?
    @State private var showExercisePicker = false
    /// 用于强制重建首页视图模型，触发重新读盘
    @State private var homeReloadID = UUID()

    var body: some View {
        // 这个 body 原本是一整条表达式：NavigationStack + 一个带 8 个闭包的
        // TrainingHomeView + navigationDestination + id + onChange + sheet。
        // 单个表达式的规模超出类型检查器上限时，Swift 会以
        // `error: failed to produce diagnostic for expression` 直接放弃
        // （不是语法错，也没有具体报错点，只在 `var body` 那一行报）。
        //
        // 修法就是**把大表达式拆成若干小方法**，让每个方法的检查规模回到正常。
        // 拆成：导航宿主 / 首页 / 选动作 sheet 三块，各自独立可检查。
        navHost
            .sheet(isPresented: $showExercisePicker, onDismiss: {
                // 挑选动作会直接写入计划，但计划详情页此时仍在栈里、
                // 不会重新走 onAppear；必须显式刷新，否则返回后看不到新动作。
                pickerContext = nil
                planRefreshToken &+= 1
            }) {
                exercisePickerSheet
            }
    }

    /// 导航栈宿主：栈底是训练首页，注册全部训练路由。
    private var navHost: some View {
        NavigationStack(path: $path) {
            homeRoot
                .navigationDestination(for: TrainingRoute.self) { route in
                    destination(for: route)
                }
        }
        // 训练结束后首页已在栈底、不会重新走 onAppear，
        // 用 id 强制重建最内层视图，保证「最近训练」立刻反映本次训练。
        .id(homeReloadID)
        .onChange(of: reloadToken) { _ in
            homeReloadID = UUID()
        }
    }

    /// 栈底的训练首页。8 个闭包回调各自只有一两行，拆出来后
    /// TrainingHomeView 的构造不再是 `var body` 表达式的一部分。
    ///
    /// **两个让类型检查器能算得动的写法，缺一不可：**
    ///
    /// 1. **闭包参数显式标注类型**。`onStartTraining` 里要对枚举做 `switch`，
    ///    若靠推断（`{ state in ... }`）编译器要先反推 `state` 的类型才能解析
    ///    各个 `case`；`TrainingHomeView` 的构造又有 8 个闭包，推断规模叠加后
    ///    会报 `type of expression is ambiguous without a type annotation`。
    ///    写上 `(state: TodayTrainingState)` 就给了锚点。
    ///
    /// 2. **不在这 8 个闭包里塞重活**。`onOpenCalendar` / `onOpenMore` 的声明
    ///    类型是 `() -> Void`，闭包里只能放语句 —— 一旦把 `popOne` 改成
    ///    返回 `some View`（比如返回一个跳转用的视图），这 8 个闭包的外部
    ///    上下文就再也收敛不出 `Void`，整个构造报 ambiguous，
    ///    而错误只会指在链尾的 `.navigationBarHidden(true)` 上，
    ///    **看不见 `homeRoot` 这几个字**。保持 `{ }` 空实现 + 由
    ///    `popToRoot()` 单独负责返回栈底，就永远不会踩到这个坑。
    private var homeRoot: some View {
        TrainingHomeView(
            viewModel: TrainingHomeViewModel(repository: repository),
            onStartTraining: { (state: TodayTrainingState) in
                switch state {
                case .scheduled(let planID, _, _, _):
                    startDraft(forPlanID: planID)
                case .inProgress(let sessionID, _, _):
                    // App 被终止或用户最小化后重开：草稿还在磁盘上，
                    // 直接回到执行页接着练，不新建也不丢已完成的组。
                    path.append(TrainingRoute.sessionDraft(sessionID))
                case .loading, .empty:
                    break
                }
            },
            onNewStrength: { startFreeStrengthDraft() },
            onNewCardio: { path.append(TrainingRoute.newCardio) },
            onOpenPlan: { (plan: Plan) in
                path.append(TrainingRoute.planDetail(plan.id))
            },
            onOpenSession: { (session: WorkoutSession) in
                // 首页「最近训练」点进历史训练详情（页面 09）。
                // 规格里页面 09 的入口有两个：历史日历 / 训练列表，
                // 首页最近训练就是后者的一个具体位置。
                path.append(TrainingRoute.historyDetail(session.id))
            },
            // 日历页与「更多」菜单尚未接入，先留空实现。
            // 不要在这里调用 `popOne()` —— 见上面的注释 2。
            onOpenCalendar: { },
            onOpenMore: { },
            onResumeSession: { (session: WorkoutSession) in
                path.append(TrainingRoute.sessionDraft(session.id))
            },
            onOpenRecovery: {
                path.append(TrainingRoute.recovery)
            }
        )
        // 首页自带大标题导航栏，隐藏系统栏避免出现双层标题
        .navigationBarHidden(true)
    }

    /// 变化时让计划详情页重新拉数据。用 token 而不是通知，
    /// 是为了让刷新时机与 SwiftUI 的状态更新在同一帧内确定。
    @State private var planRefreshToken: Int = 0

    /// 动作配置页里「替换动作 / 递增规则」的目标上下文。
    @State private var configPlanID: UUID?
    @State private var configEntry: PlanExercise?
    @State private var showReplace = false
    @State private var showProgression = false

    @ViewBuilder
    private func destination(for route: TrainingRoute) -> some View {
        switch route {
        case .planDetail(let planID):
            planDetailView(planID: planID)

        case .exerciseConfig(let planID, let entry):
            // 这个分支自带 4 个闭包 + 2 个嵌套 sheet，内联进 switch 会让
            // 整个 `destination(for:)` 的检查规模爆炸。拆出去。
            exerciseConfigView(planID: planID, entry: entry)

        case .sessionDraft(let sessionID):
            // 力量 / 有氧两套执行页分派给独立方法。
            //
            // 内联在这里会让 `destination(for:)` 单个表达式里同时出现
            // 6 个闭包 + 泛型视图 + 分支，Swift 的类型检查器会直接放弃
            // （`failed to produce diagnostic for expression`）。
            // 拆出去后每个方法只负责一个页面，检查规模回到正常水平。
            sessionDraftView(sessionID: sessionID)

        case .sessionSummary(let sessionID):
            sessionSummaryView(sessionID: sessionID)

        case .historyDetail(let sessionID):
            HistorySessionDetailView(
                viewModel: HistorySessionDetailViewModel(
                    repository: repository,
                    sessionID: sessionID
                ),
                onBack: {
                    if !path.isEmpty { path.removeLast() }
                    // 详情页可能删了这条记录，首页「最近训练」要重新读盘。
                    // 这里用本 Tab 自己的 homeReloadID：它作用于 TrainingTab 内层，
                    // 会重建首页视图模型，而不会牵动 RootView 的 Tab 选择状态。
                    homeReloadID = UUID()
                },
                onOpenDraft: { draftID in
                    // 复制出的草稿直接进执行页。留在训练栏里推入，
                    // 用户练完点完成就会回到训练总结，路径与「新建训练」一致。
                    path.append(TrainingRoute.sessionDraft(draftID))
                }
            )

        case .newCardio:
            NewCardioView(
                repository: repository,
                onCancel: {
                    if !path.isEmpty { path.removeLast() }
                },
                onStart: { draftID in
                    path.append(TrainingRoute.sessionDraft(draftID))
                }
            )

        case .recovery:
            DataRecoveryView(
                repository: repository,
                onBack: { popExerciseOne() }
            )
        }
    }

    /// 动作配置页（页面 04 子页）。带两个嵌套 sheet：替换动作、递增规则。
    ///
    /// 单独成方法而不是内联在 `destination(for:)`：4 个闭包 + 2 层 `sheet`
    /// 内联会让整个 `switch` 的类型检查规模超出上限。
    private func exerciseConfigView(planID: UUID, entry: PlanExercise) -> some View {
        PlanExerciseConfigView(
            entry: entry,
            item: lookupItem(for: entry),
            planName: lookupPlanName(planID),
            onSave: { updated in
                // 计划详情页会在重新出现时读到最新数据，这里不必再回传
                try? repository.updatePlanExercise(updated, inPlan: planID)
            },
            onReplace: {
                configPlanID = planID
                configEntry = entry
                showReplace = true
            },
            onRemove: {
                try? repository.removePlanExercise(entry.id, fromPlan: planID)
                // 训练 Tab 里没有 `popOne`，只有 `popExerciseOne`（两者行为一致，
                // 区别只在于名字记录了这个 Tab 的用法来历）。别从别的 Tab 抄。
                popExerciseOne()
            },
            onOpenProgression: { _ in
                configPlanID = planID
                configEntry = entry
                showProgression = true
            }
        )
        .sheet(isPresented: $showReplace) {
            replaceExerciseSheet
        }
        .sheet(isPresented: $showProgression) {
            progressionSheet
        }
    }

    /// 替换动作 sheet。目标计划与条目从上一步的 `configPlanID` / `configEntry` 取，
    /// 用 sheet 的内容闭包读，保证拿到的是打开那一刻的值。
    @ViewBuilder
    private var replaceExerciseSheet: some View {
        if let planID = configPlanID, let entry = configEntry,
           let current = lookupItem(for: entry) {
            ReplaceExerciseView(
                current: current,
                repository: repository,
                existingIDsInPlan: planExerciseIDs(inPlan: planID),
                onConfirm: { newItem, _ in
                    try? repository.replacePlanExercise(
                        entry.id, inPlan: planID, withExerciseID: newItem.id
                    )
                    showReplace = false
                    planRefreshToken &+= 1
                },
                onCancel: { showReplace = false }
            )
        }
    }

    /// 递增规则 sheet。
    @ViewBuilder
    private var progressionSheet: some View {
        if let planID = configPlanID, let entry = configEntry {
            ProgressionRuleView(
                config: entry.progressionConfig,
                baseWeight: entry.defaultWeight ?? 40,
                onSave: { config in
                    var updated = entry
                    updated.progressionConfig = config
                    try? repository.updatePlanExercise(updated, inPlan: planID)
                    showProgression = false
                }
            )
        }
    }

    /// 训练草稿关联的计划 id。自由训练返回 nil，此时不允许跳配置页。
    private func draftPlanID(forSessionID sessionID: UUID) -> UUID? {
        (try? repository.fetchSession(id: sessionID))?.planID
    }

    /// 判断草稿是否是有氧训练。
    private func isCardio(sessionID: UUID) -> Bool {
        (try? repository.fetchSession(id: sessionID))?.kind == .cardio
    }

    /// 训练执行页。力量与有氧是两套完全独立的视图，按草稿的 `kind` 分派。
    ///
    /// 单独成方法而不是内联在 `destination(for:)`：这个分支有 6 个闭包回调，
    /// 内联会让整个 `switch` 的类型检查规模爆炸，编译器会以
    /// `failed to produce diagnostic for expression` 失败（不是代码错）。
    @ViewBuilder
    private func sessionDraftView(sessionID: UUID) -> some View {
        if isCardio(sessionID: sessionID) {
            CardioSessionView(
                repository: repository,
                sessionID: sessionID,
                onMinimize: {
                    // 有氧页没有「草稿」概念，最小化等于退出。
                    popExerciseOne()
                },
                onFinished: { finished in
                    path.append(TrainingRoute.sessionSummary(finished.id))
                }
            )
        } else {
            WorkoutSessionView(
                repository: repository,
                sessionID: sessionID,
                onFinished: { finished in
                    path.append(TrainingRoute.sessionSummary(finished.id))
                },
                onMinimize: {
                    // 最小化只是退出页面，草稿实时保存在磁盘上，
                    // 返回首页后「继续训练」能接着进入。
                    popToRoot()
                },
                onEditConfig: { entry in
                    guard let planID = draftPlanID(forSessionID: sessionID) else { return }
                    path.append(TrainingRoute.exerciseConfig(planID: planID, entry: entry))
                },
                onRequestReplace: { card in
                    // 替换进行中训练的动作：`planID` 留空是为了让挑选结果
                    // 走「替换训练」那条分支，而不是去改计划。
                    pickerContext = ExercisePickerContext(
                        planID: nil,
                        replacingEntryID: nil,
                        sessionID: sessionID,
                        replacingExerciseID: card.exerciseID
                    )
                    showExercisePicker = true
                }
            )
        }
    }

    /// 训练总结页：结束时展示结果，数据全部来自本地记录。
    private func sessionSummaryView(sessionID: UUID) -> some View {
        if isCardio(sessionID: sessionID) {
            return AnyView(
                CardioSummaryView(
                    repository: repository,
                    sessionID: sessionID,
                    onDone: {
                        popToRoot()
                        homeReloadID = UUID()
                    },
                    onOpenHistory: {
                        popToRoot()
                        homeReloadID = UUID()
                        onOpenHistory(sessionID)
                    }
                )
            )
        }
        return AnyView(
            SessionSummaryView(
                repository: repository,
                sessionID: sessionID,
                onDone: {
                    // 回到训练首页。总结页通常压在 计划详情 / 草稿 之上，
                    // 一次清空比逐层 removeLast 更能保证落回首页。
                    popToRoot()
                    // 首页的「最近训练」需要重新读盘才能看到刚结束的这次
                    homeReloadID = UUID()
                },
                onOpenHistory: {
                    // 「查看历史记录」要跨 Tab：清空训练栈后交给 RootView 切 Tab 定位。
                    popToRoot()
                    homeReloadID = UUID()
                    onOpenHistory(sessionID)
                }
            )
        )
    }

    /// 计划详情页。所有跳转都通过 path 完成，保证返回栈一致。
    private func planDetailView(planID: UUID) -> some View {
        PlanDetailView(
            repository: repository,
            planID: planID,
            refreshToken: planRefreshToken,
            onStartTraining: { session in
                path.append(TrainingRoute.sessionDraft(session.id))
            },
            onOpenExerciseConfig: { entry in
                path.append(TrainingRoute.exerciseConfig(planID: planID, entry: entry))
            },
            onAddExercise: { targetPlanID in
                pickerContext = ExercisePickerContext(planID: targetPlanID)
                showExercisePicker = true
            },
            onReplaceExercise: { entry in
                pickerContext = ExercisePickerContext(planID: planID, replacingEntryID: entry.id)
                showExercisePicker = true
            },
            onOpenPlan: { copyID in
                path.append(TrainingRoute.planDetail(copyID))
            },
            onDeleted: {
                if !path.isEmpty { path.removeLast() }
            }
        )
    }

    /// 从动作库挑动作：动作库处于「为计划挑选」模式，选中后写入计划。
    ///
    /// 自带一个顶部取消按钮：挑选模式下动作库的大标题行是自定义视图，
    /// 没有系统返回按钮，不给取消入口用户会被困在这个 sheet 里。
    private var exercisePickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") {
                    showExercisePicker = false
                }
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textSecondary)

                Spacer()

                Text(pickerContext?.pickerTitle ?? "选择动作")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer()

                // 与左侧「取消」等宽的占位，让标题真正居中
                Text("取消")
                    .font(DS.Typography.body)
                    .foregroundStyle(.clear)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

            ExerciseLibraryView(
                viewModel: ExerciseLibraryViewModel(repository: repository),
                onOpenExercise: { item in
                    // 挑选模式下点行进详情没有意义，直接视为选中，少一步操作
                    commitPick(item)
                },
                onNewCustomExercise: {},
                onEditCustomExercise: { _ in },
                onAddToWorkout: { item in
                    commitPick(item)
                },
                pickerTitle: pickerContext?.pickerTitle ?? "选择动作"
            )
        }
    }

    /// 选中后落库，按上下文分三种情况：
    /// 替换训练中的动作、替换计划条目、追加到计划末尾。
    private func commitPick(_ item: ExerciseLibraryItem) {
        guard let context = pickerContext else { return }

        if let sessionID = context.sessionID, let oldExerciseID = context.replacingExerciseID {
            // 替换进行中训练的动作：已完成组保留，后续组换成新动作。
            // 这里只负责写库；执行页从 sheet 收起后重新出现时会自己重读，
            // 由它给出更具体的提示（保留了几组）。
            _ = try? repository.replaceExerciseInSession(
                sessionID: sessionID,
                fromExerciseID: oldExerciseID,
                toExerciseID: item.id
            )
            showExercisePicker = false
            return
        }

        guard let planID = context.planID else { return }

        if let entryID = context.replacingEntryID {
            try? repository.replacePlanExercise(
                entryID,
                inPlan: planID,
                withExerciseID: item.id
            )
        } else {
            try? repository.appendExercise(
                PlanExercise(exerciseID: item.id),
                toPlan: planID
            )
        }
        Haptics.success()
        showExercisePicker = false
    }

    /// 首页「开始训练」：按计划展开草稿并推进执行页。
    ///
    /// 草稿会把计划里的每个动作展开成对应数量的「待完成组」，
    /// 并用上一次训练同一动作的最高重量预填重量，
    /// 这样执行页一进来就是一张可用的表格，而不是空壳。
    private func startDraft(forPlanID planID: UUID) {
        guard let plan = try? repository.fetchPlan(id: planID) else { return }
        var draft = WorkoutSession.draft(from: plan)
        seedPrescribedWeights(in: &draft)
        try? repository.save(session: draft)

        var touched = plan
        touched.lastUsedAt = Date()
        _ = try? repository.replace(plan: touched)

        path.append(TrainingRoute.sessionDraft(draft.id))
    }

    /// 快捷入口「新建力量训练」：建一个自由训练草稿
    private func startFreeStrengthDraft() {
        let draft = WorkoutSession(name: "新建力量训练", kind: .strength)
        try? repository.save(session: draft)
        path.append(TrainingRoute.sessionDraft(draft.id))
    }

    /// 用历史记录里的最高重量预填未完成组的重量。
    /// 只改 weight，不动 targetReps 与顺序，纯粹是为了让表格有参考值。
    ///
    /// 页面 14 训练偏好「自动复制上次记录」关闭时直接跳过。
    private func seedPrescribedWeights(in draft: inout WorkoutSession) {
        guard ProfileSettings.prefillWeights else { return }
        guard let recent = try? repository.fetchRecentSessions(limit: 30) else { return }
        var bestWeight: [String: Double] = [:]
        for past in recent where past.id != draft.id && past.isFinished {
            for entry in past.completedEntries where entry.weight > 0 {
                bestWeight[entry.exerciseID] = max(bestWeight[entry.exerciseID] ?? 0, entry.weight)
            }
        }
        guard !bestWeight.isEmpty else { return }
        for index in draft.entries.indices where draft.entries[index].completedAt == nil {
            let id = draft.entries[index].exerciseID
            if let weight = bestWeight[id], draft.entries[index].weight <= 0 {
                draft.entries[index].weight = weight
            }
        }
    }

    private func lookupItem(for entry: PlanExercise) -> ExerciseLibraryItem? {
        try? repository.fetchExercises(ids: [entry.exerciseID]).first
    }

    /// 某计划中已存在的动作 id 集合，供替换动作做重复检测。
    private func planExerciseIDs(inPlan planID: UUID) -> Set<String> {
        guard let plan = try? repository.fetchPlan(id: planID) else { return [] }
        return Set(plan.exercises.map(\.exerciseID))
    }

    private func lookupPlanName(_ planID: UUID) -> String {
        (try? repository.fetchPlan(id: planID))?.name ?? "计划"
    }

    private func popExerciseOne() {
        if !path.isEmpty { path.removeLast() }
    }

    /// 滚回当前 Tab 的栈底。
    ///
    /// 训练 Tab 里 `sessionSummaryView` 走的是 `path = NavigationPath()`，
    /// 而不是 `path.removeLast()`：总结页通常压在「计划详情 / 草稿」之上，
    /// 一次清空比逐层弹出更稳，也不会在中间层触发多余的 onAppear 读盘。
    private func popToRoot() {
        path = NavigationPath()
    }

    /// 趋势页标题的兜底名。查不到（动作已删除）时直接用 id：
    /// 页面 11 的三级兜底最后一档是「未知动作」，比一串 uuid 好看，
    /// 但这里传 id 能让趋势页知道「上游也没查到」，走自己的兜底链。
    private func lookupExerciseName(_ exerciseID: String) -> String {
        (try? repository.fetchExercises(ids: [exerciseID]).first)?.displayName ?? exerciseID
    }
}

/// 训练 Tab 的导航目标
enum TrainingRoute: Hashable {
    case planDetail(UUID)
    case exerciseConfig(planID: UUID, entry: PlanExercise)
    /// 训练执行页。草稿 id 指向本地已落盘的记录。
    case sessionDraft(UUID)
    /// 训练总结页。结束时写入 endedAt 之后进入。
    case sessionSummary(UUID)
    /// 历史训练详情（页面 09）。从首页「最近训练」点入。
    ///
    /// 与历史栏的 `HistoryRoute.sessionDetail` 分开：路由类型必须与它所在的
    /// `NavigationStack` 一一对应，混用会让 `navigationDestination` 找不到注册者。
    case historyDetail(UUID)
    /// 新建有氧训练设置（页面 30）。
    case newCardio
    /// 数据恢复页（页面 50）。草稿损坏 / 关键数据校验异常时进入。
    case recovery
}

/// 动作选择器的上下文，三种用途共用一个 sheet：
/// - 往计划追加动作（`replacingEntryID == nil`、`sessionID == nil`）
/// - 替换计划里的某一条（`replacingEntryID != nil`）
/// - 替换进行中训练里的某个动作（`sessionID != nil`，已完成组会保留）
struct ExercisePickerContext: Identifiable {
    var planID: UUID?
    var replacingEntryID: UUID?
    var sessionID: UUID?
    var replacingExerciseID: String?

    var id: String {
        [
            planID?.uuidString ?? "-",
            replacingEntryID?.uuidString ?? "-",
            sessionID?.uuidString ?? "-",
            replacingExerciseID ?? "-"
        ].joined(separator: "|")
    }

    /// 挑选模式下的标题
    var pickerTitle: String {
        replacingEntryID != nil || replacingExerciseID != nil
            ? "选择替换后的动作"
            : "选择要加入的动作"
    }

    /// 是否在替换进行中训练里的动作
    var isReplacingInSession: Bool { sessionID != nil && replacingExerciseID != nil }
}

// MARK: - 动作 Tab

/// 动作库及其子页面的导航栈。
private struct ExercisesTab: View {

    let repository: FitnessRepository
    /// 从「动作收藏」跨 Tab 进来时要打开的动作详情。非 nil 时出现即推入详情页。
    let pendingDetail: ExerciseLibraryItem?
    /// 消费掉 pendingDetail，避免反复推入
    let onConsumePendingDetail: () -> Void

    @State private var path = NavigationPath()
    /// 正在编辑的自定义动作，nil 表示新建
    @State private var editingCustom: ExerciseLibraryItem?
    @State private var showEditor = false

    /// 单一实例，避免每次 body 求值都新建 ViewModel 导致状态丢失
    @StateObject private var viewModel: ExerciseLibraryViewModel

    init(
        repository: FitnessRepository,
        pendingDetail: ExerciseLibraryItem?,
        onConsumePendingDetail: @escaping () -> Void
    ) {
        self.repository = repository
        self.pendingDetail = pendingDetail
        self.onConsumePendingDetail = onConsumePendingDetail
        _viewModel = StateObject(
            wrappedValue: ExerciseLibraryViewModel(repository: repository)
        )
    }

    var body: some View {
        // 四个 Tab 里最后一个大 body（约 6100 字符 / 35 层大括号），
        // 与另外三个 Tab 统一拆法，避免哪天编译器在这里也放弃。
        navHost
            .task {
                // 从「动作收藏」跨 Tab 进来：出现即推入该动作详情，
                // 然后消费掉待处理标记。
                if let item = pendingDetail {
                    path.append(ExerciseRoute.detail(item))
                    onConsumePendingDetail()
                }
            }
            .sheet(isPresented: $showEditor, onDismiss: {
                // 编辑器里可能顺手改了收藏 / 隐藏状态，回来时刷新一次
                viewModel.reloadAfterExternalChange()
            }) {
                CustomExerciseEditor(repository: repository, editing: editingCustom) { saved in
                    viewModel.upsertCustomExercise(saved)
                    // 新建后跳转到新动作详情页（页面 23）。
                    if editingCustom == nil {
                        path.append(ExerciseRoute.detail(saved))
                    }
                } onDeleted: {
                    viewModel.reloadAfterExternalChange()
                    // 编辑是从详情页进入的，删除后回到动作库根页。
                    exercisePopToRoot()
                }
            }
    }

    /// 动作库导航宿主。
    private var navHost: some View {
        NavigationStack(path: $path) {
            ExerciseLibraryView(
                viewModel: viewModel,
                onOpenExercise: { item in
                    path.append(ExerciseRoute.detail(item))
                },
                onNewCustomExercise: {
                    editingCustom = nil
                    showEditor = true
                },
                onEditCustomExercise: { item in
                    editingCustom = item
                    showEditor = true
                },
                onAddToWorkout: { _ in
                    // 待接入训练编辑页：把动作加入当前草稿
                }
            )
            // 动作库自带大标题导航栏，隐藏系统栏避免出现双层标题
            .navigationBarHidden(true)
            .navigationDestination(for: ExerciseRoute.self) { route in
                exerciseDestination(for: route)
            }
        }
    }

    /// 动作库路由分派。
    @ViewBuilder
    private func exerciseDestination(for route: ExerciseRoute) -> some View {
        switch route {
        case .detail(let item):
            ExerciseDetailView(
                item: item,
                repository: repository,
                onOpenMuscle: { muscle in
                    // 回到动作库根页并应用该肌群筛选
                    viewModel.applyMuscleFilterFromDetail(muscle)
                    path = NavigationPath()
                },
                onEditExercise: { item in
                    editingCustom = item
                    showEditor = true
                },
                onOpenPlan: { planID in
                    // 「添加到已有计划」保存成功后，直接推入计划详情页，
                    // 让用户马上看到动作已经落到计划里的什么位置。
                    viewModel.reloadAfterExternalChange()
                    path.append(ExerciseRoute.planDetail(planID))
                },
                onOpenHistory: {
                    // 动作 id 是本地库里的稳定主键，路由里只带它。
                    // 趋势页自己会查库拿名字，查不到时退回快照名/未知动作。
                    path.append(ExerciseRoute.exerciseTrend(item.id))
                }
            )

        case .exerciseTrend(let exerciseID):
            ExerciseTrendDetailView(
                viewModel: ExerciseTrendDetailViewModel(
                    exerciseID: exerciseID,
                    fallbackName: lookupExerciseName(exerciseID),
                    repository: repository
                ),
                onBack: { popExerciseOne() },
                onOpenSessionDetail: { sessionID in
                    path.append(ExerciseRoute.historyDetail(sessionID))
                },
                onStartTraining: { draftID in
                    path.append(ExerciseRoute.sessionDraft(draftID))
                }
            )

        case .historyDetail(let sessionID):
            HistorySessionDetailView(
                viewModel: HistorySessionDetailViewModel(
                    repository: repository,
                    sessionID: sessionID
                ),
                onBack: { popExerciseOne() },
                onOpenDraft: { draftID in
                    path.append(ExerciseRoute.sessionDraft(draftID))
                }
            )

        case .sessionDraft(let draftID):
            WorkoutSessionView(
                repository: repository,
                sessionID: draftID,
                onFinished: { _ in
                    // 训练结束后回到动作库根页：这条栈的起点不是历史页，
                    // 没有「日历上多一条记录」的上下文可回。
                    exercisePopToRoot()
                },
                onMinimize: { popExerciseOne() },
                onEditConfig: { _ in
                    // 自由训练草稿没有关联计划，不提供动作配置编辑
                },
                onRequestReplace: { _ in
                    // 同上：自由训练从空开始，替换动作在训练页内完成
                }
            )

        case .planDetail(let planID):
            PlanDetailView(
                repository: repository,
                planID: planID,
                onStartTraining: { _ in
                    // 训练执行页尚未实现。这一路是从动作库进来的，
                    // 保持留在计划详情页比跳到占位页更合理。
                },
                onOpenExerciseConfig: { entry in
                    try? repository.updatePlanExercise(entry, inPlan: planID)
                },
                onAddExercise: { _ in
                    viewModel.reloadAfterExternalChange()
                    exercisePopToRoot()
                },
                onReplaceExercise: { _ in },
                onOpenPlan: { copyID in
                    path.append(ExerciseRoute.planDetail(copyID))
                },
                onDeleted: {
                    popExerciseOne()
                }
            )
        }
    }

    /// 清空整栈 + 让动作库重新读盘。
    ///
    /// 「训练结束 / 删除自定义动作 / 从动作库往计划加动作」这三处都要
    /// 「回到动作库根页并刷新」。原来三处各自重复写
    /// `path = NavigationPath()` + `viewModel.reloadAfterExternalChange()`，
    /// 抽出来保证只有一个写法。
    private func exercisePopToRoot() {
        path = NavigationPath()
        viewModel.reloadAfterExternalChange()
    }

    /// 返回上一页。只弹一层，不清空整栈。
    ///
    /// 每个 Tab 各自持有一份，**不要跨 Tab 借用**：`private` 方法的作用域是
    /// 类型本身，`TrainingTab` 里同名的那个在这里不可见。
    /// （2026-09-20：这四个 Tab 的 `body` 拆开之前，编译器先被巨型表达式
    /// 挡住、没来得及报这些「方法不存在」，拆完才暴露出来。）
    private func popExerciseOne() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    /// 趋势页标题的兜底名。查不到（动作已删除）时直接用 id：
    /// 页面 11 的三级兜底最后一档是「未知动作」，比一串 uuid 好看，
    /// 但这里传 id 能让趋势页知道「上游也没查到」，走自己的兜底链。
    private func lookupExerciseName(_ exerciseID: String) -> String {
        (try? repository.fetchExercises(ids: [exerciseID]).first)?.displayName ?? exerciseID
    }
}

/// 动作 Tab 的导航目标
enum ExerciseRoute: Hashable {
    case detail(ExerciseLibraryItem)
    /// 从动作详情「添加到已有计划」进来
    case planDetail(UUID)
    /// 动作历史趋势（页面 11），从动作详情页「历史记录」进来
    case exerciseTrend(String)
    /// 历史训练详情（页面 09）。趋势页「最近记录」的下钻目标。
    ///
    /// 与 `HistoryRoute.sessionDetail` / `TrainingRoute.historyDetail` 分开：
    /// 路由类型必须与它所在的 `NavigationStack` 一一对应，`navigationDestination`
    /// 只认注册在自己这一条栈上的类型。三个枚举里出现同一个 UUID 不是重复，
    /// 而是三条进入同一张详情页的路径各自留的门。
    case historyDetail(UUID)
    /// 训练执行页。趋势页「开始练这个动作」先落盘草稿，再把这个 id 推进来。
    case sessionDraft(UUID)
}

// MARK: - Tab 切换容器

/// 把 Tab 切换的 220ms 横向淡入封装成一个容器，供根视图或预览复用
struct TabTransitionContainer<Content: View>: View {

    let tab: MainTab
    @ViewBuilder var content: Content

    var body: some View {
        content
            .id(tab)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 12)),
                    removal: .opacity
                )
            )
            .animation(DS.Motion.tabSwitch, value: tab)
    }
}

// MARK: - 预览

#Preview("四栏骨架") {
    RootView(repository: PreviewFitnessRepository())
        .preferredColorScheme(.dark)
}
