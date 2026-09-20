//
//  PreviewFitnessRepository.swift
//  预览与测试用的内存桩实现，让界面可脱离真实存储独立运行。
//

import Foundation
import SwiftUI

@MainActor
final class PreviewFitnessRepository: FitnessRepository {

    private var plans: [Plan]
    private var sessions: [WorkoutSession]
    private var exercises: [ExerciseLibraryItem]
    private var measurements: [BodyMeasurement]
    private var recentExercises: [RecentExerciseRef] = []
    private var restDays: [RestDay] = []
    private var cardioTemplates: [CardioTemplate] = []
    /// 当前组间休息。预览里只放内存，不落盘。
    private var restTimer: RestTimerRecord?
    /// 本地个人资料。预览里给一个示例昵称，便于直接看到概览卡。
    private var profile: UserProfile?
    private var activeSession: WorkoutSession?
    /// 内存桩中动作库视为已导入，避免每次加载都重复注入
    private var seeded = true

    /// 有数据版本：用于预览「有计划 + 有记录 + 进行中」的完整首页
    init() {
        let today = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: today) ?? today
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: today) ?? today

        let bench = PlanExercise(exerciseID: "0025", sets: 4, repsLow: 6, repsHigh: 8, restSeconds: 120)
        let incline = PlanExercise(exerciseID: "0314", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90)
        let fly = PlanExercise(exerciseID: "0308", sets: 3, repsLow: 12, repsHigh: 15, restSeconds: 60)
        let dip = PlanExercise(exerciseID: "0251", sets: 3, repsLow: 8, repsHigh: 12, restSeconds: 90)
        let pushdown = PlanExercise(exerciseID: "0241", sets: 3, repsLow: 10, repsHigh: 15, restSeconds: 60)
        let overhead = PlanExercise(exerciseID: "2187", sets: 3, repsLow: 10, repsHigh: 12, restSeconds: 60)

        plans = [
            Plan(
                name: "推拉腿 · 三日",
                trainingDays: [1, 3, 5],
                exercises: [bench, incline, fly, dip, pushdown, overhead],
                createdAt: fiveDaysAgo,
                updatedAt: yesterday,
                lastUsedAt: yesterday
            ),
            Plan(
                name: "上肢强化",
                trainingDays: [2, 4],
                exercises: [bench, incline, dip, overhead],
                createdAt: threeDaysAgo,
                updatedAt: threeDaysAgo,
                lastUsedAt: threeDaysAgo
            ),
            Plan(
                name: "核心与稳定性",
                trainingDays: [6],
                exercises: [fly, pushdown],
                createdAt: today,
                updatedAt: today,
                lastUsedAt: nil
            ),
        ]

        sessions = [
            WorkoutSession(
                name: "推力训练 · 胸肩三头",
                kind: .strength,
                startedAt: yesterday,
                endedAt: yesterday.addingTimeInterval(4_200),
                entries: [
                    SetEntry(exerciseID: "0025", weight: 70, reps: 8),
                    SetEntry(exerciseID: "0025", weight: 70, reps: 8),
                    SetEntry(exerciseID: "0025", weight: 72.5, reps: 6),
                    SetEntry(exerciseID: "0314", weight: 24, reps: 12),
                    SetEntry(exerciseID: "0314", weight: 24, reps: 10),
                    SetEntry(exerciseID: "0241", weight: 20, reps: 15),
                ]
            ),
            WorkoutSession(
                name: "跑步机 · 稳态有氧",
                kind: .cardio,
                startedAt: threeDaysAgo,
                endedAt: threeDaysAgo.addingTimeInterval(2_100),
                entries: [],
                distanceMeters: 5_200
            ),
            WorkoutSession(
                name: "拉伸恢复",
                kind: .strength,
                startedAt: fiveDaysAgo,
                endedAt: fiveDaysAgo.addingTimeInterval(1_200),
                entries: [
                    SetEntry(exerciseID: "0251", weight: 0, reps: 12),
                    SetEntry(exerciseID: "0251", weight: 0, reps: 12),
                ]
            ),
        ]

        exercises = [
            ExerciseLibraryItem(
                id: "0025", name: "Barbell Bench Press",
                aliases: ["卧推", "平板卧推", "杠铃"],
                category: "chest", categoryZh: "胸",
                equipment: "barbell", equipmentZh: "杠铃",
                target: "pectorals", primaryMuscle: "胸大肌", muscleGroup: "triceps",
                secondaryMuscles: ["triceps", "shoulders"],
                difficulty: .advanced,
                instructionsZh: "仰卧于平板凳上，双手略宽于肩握杠，控制杠铃下放至胸部中段，再推起至手臂伸直。",
                stepsZh: ["调整握距略宽于肩", "肩胛后缩下沉", "下放至胸中部", "推起至手臂伸直"],
                image: "images/0025-EIeI8Vf.jpg",
                gifURL: "videos/0025-EIeI8Vf.gif",
                attribution: "© Gym visual — https://gymvisual.com/",
                mediaID: "EIeI8Vf",
                isFavorite: true,
                favoritedAt: today.addingTimeInterval(-86_400)
            ),
            ExerciseLibraryItem(
                id: "0314", name: "Dumbbell Incline Bench Press",
                aliases: ["上斜卧推", "哑铃"],
                category: "chest", categoryZh: "胸",
                equipment: "dumbbell", equipmentZh: "哑铃",
                target: "pectorals", primaryMuscle: "胸大肌", muscleGroup: "triceps",
                secondaryMuscles: ["shoulders"],
                difficulty: .intermediate,
                instructionsZh: "上斜凳约 30 度，双手持哑铃于胸部上方，向上推起至手臂伸直后缓慢下放。",
                stepsZh: ["调整上斜角度约 30 度", "哑铃置于胸部上方", "向上推起", "缓慢控制下放"],
                image: "images/0314-x.jpg",
                gifURL: "videos/0314-x.gif",
                attribution: "© Gym visual — https://gymvisual.com/",
                mediaID: "x"
            ),
            ExerciseLibraryItem(
                id: "0025b", name: "Barbell Deadlift",
                aliases: ["硬拉", "杠铃"],
                category: "back", categoryZh: "背",
                equipment: "barbell", equipmentZh: "杠铃",
                target: "glutes", primaryMuscle: "臀大肌", muscleGroup: "hamstrings",
                secondaryMuscles: ["lower back", "traps"],
                difficulty: .advanced,
                instructionsZh: "双脚与髋同宽站于杠下，屈髋屈膝握杠，保持背部中立，伸髋伸膝将杠拉起至站直。",
                stepsZh: ["站于杠前，双脚与髋同宽", "屈髋屈膝握杠", "保持背部中立", "伸髋伸膝站直"],
                image: "images/0032-ila4NZS.jpg",
                gifURL: "videos/0032-ila4NZS.gif",
                attribution: "© Gym visual — https://gymvisual.com/",
                mediaID: "ila4NZS",
                isFavorite: true,
                favoritedAt: today.addingTimeInterval(-7_200)
            ),
            // 自定义动作示例，用于验证「仅看自定义」筛选项与编辑 / 删除菜单
            ExerciseLibraryItem(
                id: "custom-1", name: "自创 · 单臂哑铃划船停顿版",
                aliases: ["划船", "哑铃", "单臂"],
                category: "back", categoryZh: "背",
                equipment: "dumbbell", equipmentZh: "哑铃",
                target: "lats", primaryMuscle: "背阔肌", muscleGroup: "biceps",
                secondaryMuscles: ["rhomboids"],
                difficulty: .intermediate,
                instructionsZh: "单臂撑凳，拉至腹部后在最上端停顿两秒，再缓慢下放。",
                stepsZh: ["单臂撑于平凳", "拉至腹部", "顶端停顿两秒", "缓慢下放"],
                isCustom: true,
                isFavorite: true,
                favoritedAt: today.addingTimeInterval(-3_600)
            ),
        ]

        // 最近使用：预览时给两条，用于验证顶部紧凑区
        recentExercises = [
            RecentExerciseRef(id: "0025", usedAt: today.addingTimeInterval(-3_600)),
            RecentExerciseRef(id: "0025b", usedAt: today.addingTimeInterval(-7_200)),
        ]

        measurements = [
            BodyMeasurement(
                date: today,
                weightKg: 74.2,
                bodyFatPercent: 16.4,
                waistCm: 80.5
            )
        ]

        // 进行中的训练，用于验证「继续训练」分支。
        // 用 WorkoutSession.draft(from:) 展开计划的全部目标组，
        // 再把前几组标成已完成——这样训练执行页预览里既有已完成的组，
        // 也有待完成的目标组，和真实使用中的状态一致。
        var draft = WorkoutSession.draft(from: plans[0], startedAt: today.addingTimeInterval(-1_800))
        let completedPrefix: [(weight: Double, reps: Int)] = [
            (70, 8), (70, 8), (72.5, 6),   // 杠铃卧推前 3 组
            (24, 12), (24, 10)             // 上斜哑铃卧推前 2 组
        ]
        var remainingPrefix = completedPrefix
        for index in draft.entries.indices {
            guard !remainingPrefix.isEmpty else { break }
            let next = remainingPrefix.removeFirst()
            draft.entries[index].weight = next.weight
            draft.entries[index].reps = next.reps
            draft.entries[index].completedAt = today.addingTimeInterval(-1_500 + Double(index) * 120)
        }
        // 再补一个打叉示例：已完成但次数没到目标下限
        if let last = draft.entries.lastIndex(where: { $0.isCompleted }) {
            draft.entries[last].reps = 4
        }
        draft.note = nil
        activeSession = draft

        // 休息日样例：昨天与四天前，用于验证日历上的灰色标记
        restDays = [
            RestDay(date: Calendar.current.startOfDay(for: yesterday), note: "主动恢复"),
            RestDay(date: Calendar.current.startOfDay(
                for: Calendar.current.date(byAdding: .day, value: -4, to: today) ?? today
            )),
        ]

        // 个人资料样例：有昵称 + 60 天前开始使用，便于预览概览卡与「已使用 N 天」。
        profile = UserProfile(
            nickname: "健身爱好者",
            startedAt: Calendar.current.date(byAdding: .day, value: -60, to: today) ?? today
        )
    }

    private init(plans: [Plan], sessions: [WorkoutSession], exercises: [ExerciseLibraryItem],
                 measurements: [BodyMeasurement], active: WorkoutSession?) {
        self.plans = plans
        self.sessions = sessions
        self.exercises = exercises
        self.measurements = measurements
        self.activeSession = active
    }
    /// 全空版本：用于预览空状态与引导
    static func makeEmpty() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository(
            plans: [], sessions: [], exercises: [], measurements: [], active: nil
        )
        repo.restDays = []
        return repo
    }

    /// 有计划无记录：用于预览「今日已安排」
    static func makeScheduledOnly() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository()
        repo.sessions = []
        repo.activeSession = nil
        return repo
    }

    /// 无动作库：用于预览动作库页的空状态与首次导入
    static func makeNoExercises() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository()
        repo.exercises = []
        repo.recentExercises = []
        repo.seeded = false
        return repo
    }

    /// 空计划版本：用于预览「这个计划还没有动作」的空状态与置灰的开始按钮
    static func makeEmptyPlan() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository()
        repo.plans = [Plan(name: "新计划", trainingDays: [])]
        return repo
    }

    /// 有历史但全是力量训练：用于预览「总容量」有值、但没有有氧距离那一格
    static func makeStrengthHistory() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository()
        repo.sessions = PreviewFitnessRepository.statisticsSampleSessions(cardioCount: 0)
        repo.activeSession = nil
        return repo
    }

    /// 只有有氧训练：用于预览「总容量算不出来 → 显示 —」的降级分支。
    /// 这是统计页最容易漏的一条路径 —— 只练有氧的用户容量恒为 0，
    /// 显示「0 kg」会让他以为数据错了。
    static func makeCardioOnlyHistory() -> PreviewFitnessRepository {
        let repo = PreviewFitnessRepository()
        repo.sessions = PreviewFitnessRepository.statisticsSampleSessions(
            strengthCount: 0,
            cardioCount: 5
        )
        repo.activeSession = nil
        return repo
    }

    /// 统计页样例训练序列：跨约 3 个月、混合力量与有氧、容量逐周上升。
    ///
    /// 数据刻意造成「有几周空白」和「同一动作在多次训练里重复出现」，
    /// 这样预览里能直接看到频率图的空柱、常练动作的排序、以及容量折线的走势。
    static func statisticsSampleSessions(
        strengthCount: Int = 14,
        cardioCount: Int = 4,
        now: Date = .now
    ) -> [WorkoutSession] {
        let calendar = Calendar.current
        let exerciseIDs = ["0025", "0043", "0072", "0151", "0265"]
        var result: [WorkoutSession] = []

        // 力量训练：从 80 天前开始，大约每 5 天一次，重量递增
        for index in 0..<max(0, strengthCount) {
            let daysAgo = 80 - index * 5
            guard let start = calendar.date(
                byAdding: .day,
                value: -daysAgo,
                to: calendar.date(byAdding: .hour, value: 19, to: calendar.startOfDay(for: now)) ?? now
            ) else { continue }

            let baseWeight = 40.0 + Double(index) * 2.5
            var entries: [SetEntry] = []
            for (order, exerciseID) in exerciseIDs.enumerated() where order < 3 {
                for setIndex in 1...3 {
                    entries.append(
                        SetEntry(
                            exerciseID: exerciseID,
                            index: setIndex,
                            weight: baseWeight + Double(order) * 5,
                            reps: 10 - setIndex / 2,
                            targetRepsLow: 8,
                            targetRepsHigh: 12,
                            isWarmup: false,
                            // 完成时间跟开始时错开，避免同秒
                            completedAt: start.addingTimeInterval(Double(setIndex) * 90)
                        )
                    )
                }
            }

            result.append(
                WorkoutSession(
                    name: "推拉腿 · 第 \(index + 1) 次",
                    kind: .strength,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(3600),
                    entries: entries
                )
            )
        }

        // 有氧训练：间隔更大，距离递增
        for index in 0..<max(0, cardioCount) {
            let daysAgo = 75 - index * 12
            guard let start = calendar.date(
                byAdding: .day,
                value: -daysAgo,
                to: calendar.date(byAdding: .hour, value: 7, to: calendar.startOfDay(for: now)) ?? now
            ) else { continue }

            result.append(
                WorkoutSession(
                    name: "晨跑 \(index + 1)",
                    kind: .cardio,
                    startedAt: start,
                    endedAt: start.addingTimeInterval(1800),
                    distanceMeters: 4000 + Double(index) * 500
                )
            )
        }

        return result.sorted { $0.startedAt < $1.startedAt }
    }

    // MARK: - 预览辅助

    /// 当前实例第一个计划的 id。
    /// 实例属性而不是 `static let`：静态常量要在类型初始化时新建实例，
    /// 会与实例初始化形成循环依赖，Swift 会直接报错。
    var previewOwnPlanID: UUID { plans.first?.id ?? UUID() }

    /// 当前实例的动作库样例
    var previewOwnExercises: [ExerciseLibraryItem] { exercises }

    /// 当前实例里那个未结束训练的 id，供训练执行页预览使用
    var previewActiveSessionID: UUID {
        activeSession?.id ?? sessions.first?.id ?? UUID()
    }

    /// 当前实例里最近一次已结束训练的 id，供训练总结页预览使用
    var previewFinishedSessionID: UUID {
        let finished = sessions.filter { $0.isFinished }.sorted { $0.startedAt > $1.startedAt }
        return finished.first?.id ?? UUID()
    }

    /// 从指定的计划展开一份带目标组的训练草稿并写入，返回它的 id。
    /// 预览与「开始训练」都走同一条展开逻辑，保证两边看到的一模一样。
    func previewStartSession(fromPlan planID: UUID, startedAt: Date = .now) -> UUID? {
        guard let plan = plans.first(where: { $0.id == planID }) else { return nil }
        let draft = WorkoutSession.draft(from: plan, startedAt: startedAt)
        try? save(session: draft)
        if let index = plans.firstIndex(where: { $0.id == planID }) {
            plans[index].lastUsedAt = startedAt
        }
        return draft.id
    }

    // MARK: - FitnessRepository

    func fetchPlans() throws -> [Plan] { plans }

    func fetchPlan(id: UUID) throws -> Plan? { plans.first { $0.id == id } }

    func save(plan: Plan) throws {
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
    }

    func delete(planID: UUID) throws { plans.removeAll { $0.id == planID } }

    func deletePlans(ids: [UUID]) throws {
        let idSet = Set(ids)
        plans.removeAll { idSet.contains($0.id) }
    }

    func duplicate(planID: UUID) throws -> Plan? {
        guard var copy = plans.first(where: { $0.id == planID }) else { return nil }
        copy.id = UUID()
        copy.name = PlanCopyName.makeCopyName(for: copy.name)
        copy.createdAt = .now
        copy.updatedAt = .now
        copy.lastUsedAt = nil
        // 动作条目换新 id，避免与源计划共享引用
        copy.exercises = copy.exercises.map {
            var item = $0
            item.id = UUID()
            return item
        }
        plans.insert(copy, at: 0)
        return copy
    }

    @discardableResult
    func appendExercise(_ entry: PlanExercise, toPlan planID: UUID) throws -> PlanExercise? {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        plans[index].exercises.append(entry)
        plans[index].updatedAt = .now
        return entry
    }

    @discardableResult
    func createPlan(name: String, trainingDays: [Int]) throws -> Plan {
        let plan = Plan(name: name, trainingDays: trainingDays)
        plans.append(plan)
        return plan
    }

    @discardableResult
    func updatePlanExercise(_ entry: PlanExercise, inPlan planID: UUID) throws -> PlanExercise? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entry.id })
        else { return nil }
        plans[planIndex].exercises[entryIndex] = entry
        plans[planIndex].updatedAt = .now
        return entry
    }

    @discardableResult
    func reorderPlanExercises(inPlan planID: UUID, orderedIDs: [UUID]) throws -> Plan? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        let current = plans[planIndex].exercises
        guard orderedIDs.count == current.count,
              Set(orderedIDs) == Set(current.map { $0.id })
        else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        plans[planIndex].exercises = orderedIDs.compactMap { byID[$0] }
        plans[planIndex].updatedAt = .now
        return plans[planIndex]
    }

    @discardableResult
    func removePlanExercise(_ entryID: UUID, fromPlan planID: UUID) throws -> Plan? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        guard plans[planIndex].exercises.contains(where: { $0.id == entryID }) else { return nil }
        plans[planIndex].exercises.removeAll { $0.id == entryID }
        plans[planIndex].updatedAt = .now
        return plans[planIndex]
    }

    @discardableResult
    func duplicatePlanExercise(_ entryID: UUID, inPlan planID: UUID) throws -> PlanExercise? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entryID })
        else { return nil }
        let copy = plans[planIndex].exercises[entryIndex].duplicated()
        plans[planIndex].exercises.insert(copy, at: entryIndex + 1)
        plans[planIndex].updatedAt = .now
        return copy
    }

    @discardableResult
    func replacePlanExercise(
        _ entryID: UUID,
        inPlan planID: UUID,
        withExerciseID exerciseID: String
    ) throws -> PlanExercise? {
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entryID })
        else { return nil }
        plans[planIndex].exercises[entryIndex].exerciseID = exerciseID
        plans[planIndex].updatedAt = .now
        return plans[planIndex].exercises[entryIndex]
    }

    @discardableResult
    func replace(plan: Plan) throws -> Plan? {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return nil }
        var updated = plan
        updated.updatedAt = .now
        plans[index] = updated
        return updated
    }

    func fetchRecentSessions(limit: Int) throws -> [WorkoutSession] {
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        return Array(sorted.prefix(limit))
    }

    func fetchSession(id: UUID) throws -> WorkoutSession? { sessions.first { $0.id == id } }

    func fetchActiveSession() throws -> WorkoutSession? { activeSession }

    func save(session: WorkoutSession) throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        if session.endedAt == nil { activeSession = session }
        else if activeSession?.id == session.id { activeSession = nil }
    }

    func delete(sessionID: UUID) throws { sessions.removeAll { $0.id == sessionID } }

    @discardableResult
    func appendEntryToActiveSession(_ entry: SetEntry) throws -> WorkoutSession? {
        guard let active = activeSession else { return nil }
        var updated = active
        updated.entries.append(entry)
        activeSession = updated
        if let index = sessions.firstIndex(where: { $0.id == updated.id }) {
            sessions[index] = updated
        } else {
            sessions.append(updated)
        }
        return updated
    }

    // MARK: - 训练执行页的实时草稿写入

    @discardableResult
    func updateSessionDraft(_ session: WorkoutSession) throws -> WorkoutSession? {
        try save(session: session)
        return try fetchSession(id: session.id)
    }

    @discardableResult
    func markSetCompleted(
        sessionID: UUID,
        entryID: UUID,
        completedAt: Date?
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            guard let index = session.entries.firstIndex(where: { $0.id == entryID }) else {
                return false
            }
            session.entries[index].completedAt = completedAt
            return true
        }
    }

    @discardableResult
    func updateSetEntry(
        sessionID: UUID,
        entryID: UUID,
        weight: Double,
        reps: Int
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            guard let index = session.entries.firstIndex(where: { $0.id == entryID }) else {
                return false
            }
            session.entries[index].weight = max(0, weight)
            session.entries[index].reps = max(0, reps)
            return true
        }
    }

    @discardableResult
    func insertSetEntry(
        sessionID: UUID,
        exerciseID: String,
        planEntryID: UUID?,
        fallbackWeight: Double,
        fallbackReps: Int,
        fallbackTargetLow: Int,
        fallbackTargetHigh: Int,
        isWarmup: Bool
    ) throws -> SetEntry? {
        var created: SetEntry?
        _ = mutateSession(sessionID) { session in
            let template = session.lastCompletedEntry(forExercise: exerciseID)
                ?? session.entries.last { $0.exerciseID == exerciseID }
            let newIndex = session.nextSetIndex(forExercise: exerciseID)
            var entry: SetEntry
            if let template {
                entry = template.duplicatedTarget(at: newIndex)
                entry.planEntryID = planEntryID ?? template.planEntryID
            } else {
                entry = SetEntry(
                    exerciseID: exerciseID,
                    planEntryID: planEntryID,
                    index: newIndex,
                    weight: max(0, fallbackWeight),
                    reps: max(0, fallbackReps),
                    targetRepsLow: fallbackTargetLow,
                    targetRepsHigh: fallbackTargetHigh,
                    isWarmup: isWarmup,
                    completedAt: nil
                )
            }
            if let last = session.entries.lastIndex(where: { $0.exerciseID == exerciseID }) {
                session.entries.insert(entry, at: last + 1)
            } else {
                session.entries.append(entry)
            }
            created = entry
            return true
        }
        return created
    }

    @discardableResult
    func removeSetEntry(
        sessionID: UUID,
        entryID: UUID
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            guard let target = session.entries.first(where: { $0.id == entryID }) else {
                return false
            }
            let siblings = session.entries.filter { $0.exerciseID == target.exerciseID }
            guard siblings.count > 1 else { return false }
            session.entries.removeAll { $0.id == entryID }
            var counter = 0
            for index in session.entries.indices
            where session.entries[index].exerciseID == target.exerciseID {
                counter += 1
                session.entries[index].index = counter
            }
            return true
        }
    }

    @discardableResult
    func replaceExerciseInSession(
        sessionID: UUID,
        fromExerciseID: String,
        toExerciseID: String
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            var changed = false
            for index in session.entries.indices {
                let entry = session.entries[index]
                guard entry.exerciseID == fromExerciseID, !entry.isCompleted else { continue }
                session.entries[index].exerciseID = toExerciseID
                changed = true
            }
            return changed
        }
    }

    @discardableResult
    func updateSessionNote(
        sessionID: UUID,
        note: String?
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return true
        }
    }

    @discardableResult
    func finishSession(
        sessionID: UUID,
        endedAt: Date,
        note: String?
    ) throws -> WorkoutSession? {
        mutateSession(sessionID) { session in
            if session.endedAt == nil {
                session.endedAt = max(endedAt, session.startedAt)
            }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return true
        }
    }

    /// 与 JSON 实现同语义：定位会话 → 改 → 写回内存并同步 activeSession。
    @discardableResult
    private func mutateSession(
        _ sessionID: UUID,
        _ body: (inout WorkoutSession) -> Bool
    ) -> WorkoutSession? {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        var session = sessions[index]
        guard body(&session) else { return session }
        try? save(session: session)
        return session
    }

    // MARK: - 组间休息状态

    func fetchRestTimer() throws -> RestTimerRecord? {
        restTimer
    }

    func save(restTimer record: RestTimerRecord) throws {
        restTimer = record
    }

    func clearRestTimer() throws {
        restTimer = nil
    }

    /// 预览里让休息计时可以「接着走」：把起点往前挪，供截图直接看到中段进度。
    func previewSeedRestTimer(
        exerciseName: String,
        durationSeconds: Int,
        elapsedSeconds: Int,
        isPaused: Bool = false,
        sessionID: UUID? = nil
    ) {
        let seconds = max(1, durationSeconds)
        restTimer = RestTimerRecord(
            sessionID: sessionID ?? previewActiveSessionID,
            startedAt: Date().addingTimeInterval(-Double(max(0, elapsedSeconds))),
            durationSeconds: seconds,
            isPaused: isPaused,
            remainingSeconds: isPaused ? max(1, seconds - elapsedSeconds) : nil,
            exerciseName: exerciseName
        )
    }

    func fetchExercises(includeHidden: Bool) throws -> [ExerciseLibraryItem] {
        let list = includeHidden ? exercises : exercises.filter { !$0.isHidden }
        return list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func fetchExercises(ids: [String]) throws -> [ExerciseLibraryItem] {
        exercises.filter { ids.contains($0.id) }
    }

    func save(exercise: ExerciseLibraryItem) throws {
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            var merged = exercise
            if !exercises[index].isCustom { merged.isCustom = false }
            exercises[index] = merged
        } else {
            exercises.append(exercise)
        }
    }

    func deleteExercise(id: String) throws {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        guard exercises[index].isCustom else {
            throw StubError.notDeletable(name: exercises[index].name)
        }
        exercises.remove(at: index)
        recentExercises.removeAll { $0.id == id }
    }

    @discardableResult
    func toggleFavorite(exerciseID: String) throws -> Bool {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return false }
        exercises[index].isFavorite.toggle()
        // 收藏时记录时间（「最近收藏」排序依据），取消收藏时清空。
        exercises[index].favoritedAt = exercises[index].isFavorite ? Date() : nil
        return exercises[index].isFavorite
    }

    @discardableResult
    func toggleHidden(exerciseID: String) throws -> Bool {
        guard let index = exercises.firstIndex(where: { $0.id == exerciseID }) else { return false }
        exercises[index].isHidden.toggle()
        return exercises[index].isHidden
    }

    enum StubError: LocalizedError {
        case notDeletable(name: String)

        var errorDescription: String? {
            switch self {
            case .notDeletable(let name):
                return "「\(name)」来自内置动作库，不能删除。可以改为收藏或隐藏。"
            }
        }
    }

    func seedExerciseLibraryIfNeeded() throws -> Int {
        guard !seeded else { return 0 }
        seeded = true
        return exercises.count
    }

    @discardableResult
    func copyAsCustomExercise(id: String) throws -> ExerciseLibraryItem? {
        guard let source = exercises.first(where: { $0.id == id }) else { return nil }
        var copy = source
        copy.id = "custom-\(UUID().uuidString)"
        copy.name = source.name.hasSuffix("（副本）") ? source.name : "\(source.name)（副本）"
        copy.isCustom = true
        copy.isFavorite = false
        copy.favoritedAt = nil
        copy.isHidden = false
        exercises.append(copy)
        return copy
    }

    func recordExerciseUsage(id: String) throws {
        guard exercises.contains(where: { $0.id == id }) else { return }
        recentExercises.removeAll { $0.id == id }
        recentExercises.insert(RecentExerciseRef(id: id, usedAt: Date()), at: 0)
        if recentExercises.count > 30 {
            recentExercises = Array(recentExercises.prefix(30))
        }
    }

    func fetchRecentExercises(limit: Int) throws -> [ExerciseLibraryItem] {
        let byID = Dictionary(
            exercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let ordered = recentExercises
            .sorted { $0.usedAt > $1.usedAt }
            .compactMap { byID[$0.id] }
            .filter { !$0.isHidden }
        guard limit > 0 else { return ordered }
        return Array(ordered.prefix(limit))
    }

    func clearRecentExercises() throws {
        recentExercises = []
    }

    func fetchBodyMeasurements(limit: Int) throws -> [BodyMeasurement] {
        let sorted = measurements.sorted { $0.date > $1.date }
        return Array(sorted.prefix(limit))
    }

    func save(measurement: BodyMeasurement) throws {
        // 与 JSON 实现同一契约：本地自然日为唯一键，同一天只留一条。
        let calendar = Calendar.current
        measurements.removeAll {
            $0.id != measurement.id && calendar.isDate($0.date, inSameDayAs: measurement.date)
        }
        if let index = measurements.firstIndex(where: { $0.id == measurement.id }) {
            measurements[index] = measurement
        } else {
            measurements.append(measurement)
        }
    }

    func delete(measurementID: UUID) throws {
        measurements.removeAll { $0.id == measurementID }
    }

    // MARK: - 个人资料

    func fetchProfile() throws -> UserProfile? {
        profile
    }

    func save(profile newProfile: UserProfile) throws {
        profile = newProfile
    }

    // MARK: - 休息日

    func fetchRestDays() throws -> [RestDay] {
        restDays.sorted { $0.date > $1.date }
    }

    func save(restDay: RestDay) throws {
        let calendar = Calendar.current
        restDays.removeAll {
            $0.id != restDay.id && calendar.isDate($0.date, inSameDayAs: restDay.date)
        }
        if let index = restDays.firstIndex(where: { $0.id == restDay.id }) {
            restDays[index] = restDay
        } else {
            restDays.append(restDay)
        }
    }

    func delete(restDayID: UUID) throws {
        restDays.removeAll { $0.id == restDayID }
    }

    // MARK: - 有氧模板（页面 32）

    func fetchCardioTemplates() throws -> [CardioTemplate] {
        cardioTemplates.sorted { $0.createdAt > $1.createdAt }
    }

    func save(cardioTemplate: CardioTemplate) throws {
        if let index = cardioTemplates.firstIndex(where: { $0.id == cardioTemplate.id }) {
            cardioTemplates[index] = cardioTemplate
        } else {
            cardioTemplates.append(cardioTemplate)
        }
    }

    func delete(cardioTemplateID: UUID) throws {
        cardioTemplates.removeAll { $0.id == cardioTemplateID }
    }

    // MARK: - 数据管理（页面 10）

    func replaceAllSessions(_ records: [WorkoutSession]) throws {
        sessions = records
    }

    func replaceAllRestDays(_ records: [RestDay]) throws {
        restDays = records
    }

    func replaceAllPlans(_ records: [Plan]) throws {
        plans = records
    }

    func replaceAllMeasurements(_ records: [BodyMeasurement]) throws {
        measurements = records
    }

    func replaceAllExercises(_ records: [ExerciseLibraryItem]) throws {
        exercises = records
    }

    /// 与 JSON 实现保持同一范围：只清训练记录与休息日。
    /// 预览桩也要守住这条边界，否则预览里看不出「清除后动作库还在」。
    func clearWorkoutRecords() throws {
        sessions = []
        restDays = []
        restTimer = nil
    }

    // MARK: - 本地数据管理（页面 18）

    func deleteAllPlans() throws {
        plans = []
    }

    func deleteAllMeasurements() throws {
        measurements = []
    }

    func deleteAllData() throws {
        plans = []
        sessions = []
        exercises = []
        measurements = []
        recentExercises = []
        restDays = []
        restTimer = nil
        profile = nil
        seeded = false
    }

    func reseedExerciseLibrary() throws -> Int {
        seeded = true
        return 0
    }

    func localDataSizeBytes() throws -> Int64 {
        // 预览桩没有真实磁盘占用，返回一个非零的合理值即可
        0
    }

    func clearUnusedMediaCache() throws -> Int {
        // 预览桩没有头像文件可清理
        0
    }
}
