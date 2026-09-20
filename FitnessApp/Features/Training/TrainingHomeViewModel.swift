//
//  TrainingHomeViewModel.swift
//  首页状态机。只依赖 FitnessRepository 协议，便于预览与测试注入桩实现。
//

import Foundation
import Combine

@MainActor
final class TrainingHomeViewModel: ObservableObject {

    // MARK: - 输出状态

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var todayState: TodayTrainingState = .loading
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var recentSessions: [WorkoutSession] = []
    @Published private(set) var activeSession: WorkoutSession?
    /// 所有未结束的训练草稿（页面 49 恢复训练用）。
    @Published private(set) var unfinishedDrafts: [WorkoutSession] = []

    /// 计划列表最多展示数量
    private let planPreviewLimit = 10
    /// 最近训练最多展示数量
    private let recentSessionLimit = 5

    private let repository: FitnessRepository
    private let calendar: Calendar
    private let now: () -> Date

    init(
        repository: FitnessRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    // MARK: - 加载

    func load() async {
        loadState = .loading
        todayState = .loading

        do {
            // 首次启动导入动作库；失败不阻断首页渲染
            _ = try? repository.seedExerciseLibraryIfNeeded()

            let allPlans = try repository.fetchPlans()
            let sessions = try repository.fetchRecentSessions(limit: recentSessionLimit)
            let active = try repository.fetchActiveSession()
            let allDrafts = try repository.fetchRecentSessions(limit: 1000)
                .filter { !$0.isFinished }

            self.plans = Array(allPlans.prefix(planPreviewLimit))
            self.recentSessions = sessions
            self.activeSession = active
            self.unfinishedDrafts = allDrafts
            self.todayState = Self.resolveTodayState(
                active: active,
                plans: allPlans,
                calendar: calendar,
                date: now()
            )
            self.loadState = .loaded
        } catch {
            self.loadState = .failed(Self.message(for: error))
        }
    }

    func refresh() async {
        await load()
    }

    // MARK: - 今日状态推导

    /// 优先级：进行中的训练 > 今日计划 > 空
    static func resolveTodayState(
        active: WorkoutSession?,
        plans: [Plan],
        calendar: Calendar,
        date: Date
    ) -> TodayTrainingState {
        if let active {
            return .inProgress(
                sessionID: active.id,
                name: active.name,
                completedSets: active.totalSets,
                totalSets: max(active.totalSets, plannedSets(for: active)),
                elapsedSeconds: active.durationSeconds
            )
        }

        guard let plan = todayPlan(from: plans, calendar: calendar, date: date) else {
            return .empty
        }

        return .scheduled(
            planID: plan.id,
            name: plan.name,
            exerciseCount: plan.exerciseCount,
            estimatedMinutes: plan.estimatedMinutes
        )
    }

    /// 取今日应执行的计划。优先级：训练日命中今日 > 最近使用
    static func todayPlan(from plans: [Plan], calendar: Calendar, date: Date) -> Plan? {
        let weekday = calendar.component(.weekday, from: date)
        // Calendar 的 weekday 是 1=周日，转换为 1=周一…7=周日
        let normalized = weekday == 1 ? 7 : weekday - 1

        if let matched = plans.first(where: { $0.trainingDays.contains(normalized) }) {
            return matched
        }
        return plans.first
    }

    /// 进行中训练的总组数目标。
    ///
    /// 草稿在创建时已经把计划展开成一列待完成组，所以 `plannedSetCount`
    /// 就是真实的分母，不必再回查计划（也避免计划被改名改动作后分母漂移）。
    private static func plannedSets(for session: WorkoutSession) -> Int {
        // 至少要等于已完成组数，否则老数据（草稿没展开过）会算出分母小于分子
        max(session.plannedSetCount, session.totalSets)
    }

    // MARK: - 计划操作

    func deletePlan(_ plan: Plan) {
        do {
            try repository.delete(planID: plan.id)
            plans.removeAll { $0.id == plan.id }
            try reloadTodayState()
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    func duplicatePlan(_ plan: Plan) {
        do {
            guard let copy = try repository.duplicate(planID: plan.id) else { return }
            plans.insert(copy, at: 0)
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - 恢复训练（页面 49）

    /// 放弃一条未完成草稿，只删除草稿与未完成组，不影响历史记录。
    func abandonDraft(_ session: WorkoutSession) {
        do {
            try repository.delete(sessionID: session.id)
            unfinishedDrafts.removeAll { $0.id == session.id }
            try reloadTodayState()
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    private func reloadTodayState() throws {
        let all = try repository.fetchPlans()
        let active = try repository.fetchActiveSession()
        todayState = Self.resolveTodayState(
            active: active,
            plans: all,
            calendar: calendar,
            date: now()
        )
    }

    // MARK: - 新建草稿

    /// 新建力量训练草稿，返回草稿对象供编辑页使用
    func makeStrengthDraft() -> WorkoutSession {
        WorkoutSession(name: "新建力量训练", kind: .strength)
    }

    /// 新建有氧训练草稿
    func makeCardioDraft() -> WorkoutSession {
        WorkoutSession(name: "新建有氧训练", kind: .cardio)
    }

    // MARK: - 错误文案

    private static func message(for error: Error) -> String {
        "数据读取失败：\(error.localizedDescription)"
    }
}

// MARK: - 展示辅助

extension TrainingHomeViewModel {

    /// 今日日期标题，如「9月19日 星期六」
    var todayDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: now())
    }

    /// 有氧训练与力量训练的动作数文案
    func exerciseCountText(_ count: Int) -> String {
        "\(count) 个动作"
    }

    /// 时长文案
    func durationText(minutes: Int) -> String {
        minutes >= 60
            ? "\(minutes / 60) 小时 \(minutes % 60) 分"
            : "\(minutes) 分钟"
    }
}
