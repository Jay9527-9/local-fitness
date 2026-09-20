//
//  ExerciseDetailViewModel.swift
//  动作详情页的状态机：收藏、隐藏、复制为自定义、加入训练/计划。
//
//  所有写操作都只落到本地仓储，不发网络请求，也不需要账号。
//  收藏采用「乐观更新 + 失败回滚」，让星标点击立刻有反馈。
//

import Foundation

@MainActor
final class ExerciseDetailViewModel: ObservableObject {

    // MARK: - 状态

    /// 当前展示的动作。收藏 / 隐藏后本地同步更新这个副本。
    @Published private(set) var item: ExerciseLibraryItem

    /// 可加入的目标：进行中的训练（可能为 nil）
    @Published private(set) var activeSession: WorkoutSession?
    /// 可加入的目标：已有计划
    @Published private(set) var plans: [Plan] = []
    /// 全部未结束的训练（页面 29 选择菜单用）。
    @Published private(set) var unfinishedSessions: [WorkoutSession] = []

    /// 加入计划时预填的默认值，随动作类型变化
    @Published var draft = ExercisePrescription()

    /// 提示文案，nil 表示不提示
    @Published var toast: String?
    /// 错误文案，nil 表示不提示
    @Published var errorMessage: String?

    /// 隐藏动作的二次确认开关
    @Published var isConfirmingHide = false

    private let repository: FitnessRepository

    init(item: ExerciseLibraryItem, repository: FitnessRepository) {
        self.item = item
        self.repository = repository
        self.draft = ExercisePrescription.default(for: item)
    }

    // MARK: - 派生

    /// 内置导入的动作不可编辑、不可删除，只能收藏、隐藏或复制。
    var canEdit: Bool { item.isCustom }
    var canDelete: Bool { item.isCustom }
    /// 隐藏后可以再次显示，两个方向都允许
    var hideActionTitle: String { item.isHidden ? "取消隐藏" : "隐藏动作" }
    /// 是否还有可加入的目标
    var hasAnyTarget: Bool { activeSession != nil || !plans.isEmpty }

    /// 「添加到正在进行的训练」那一项的副标题
    var activeSessionSubtitle: String? {
        guard let session = activeSession else { return nil }
        return "\(session.name) · 已进行 \(FormatterKit.duration(seconds: session.durationSeconds))"
    }

    /// 展示用的肌群：主肌群置顶，其余按数据顺序去重。
    var muscleList: [ExerciseMuscleRef] {
        var result: [ExerciseMuscleRef] = []
        var seen = Set<String>()

        let primary = item.primaryMuscleText
        if !primary.isEmpty {
            result.append(ExerciseMuscleRef(name: primary, isPrimary: true))
            seen.insert(primary)
        }
        for name in MuscleName.zhGroups(item.secondaryMuscles) where !seen.contains(name) {
            result.append(ExerciseMuscleRef(name: name, isPrimary: false))
            seen.insert(name)
        }
        return result
    }

    /// 动作要点。数据源缺说明时返回空数组，由界面走兜底文案。
    var steps: [String] {
        item.stepsZh.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - 加载

    func load() async {
        plans = (try? repository.fetchPlans()) ?? []
        activeSession = try? repository.fetchActiveSession()
        unfinishedSessions = ((try? repository.fetchRecentSessions(limit: 50)) ?? [])
            .filter { !$0.isFinished }
            .sorted { $0.startedAt > $1.startedAt }
    }

    // MARK: - 收藏

    /// 切换收藏。先改本地状态让星标立刻响应，落盘失败再回滚。
    func toggleFavorite() {
        let previous = item.isFavorite
        item.isFavorite.toggle()

        do {
            let stored = try repository.toggleFavorite(exerciseID: item.id)
            if stored != item.isFavorite { item.isFavorite = stored }
        } catch {
            item.isFavorite = previous
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: - 隐藏

    /// 隐藏必须二次确认，由界面把 isConfirmingHide 置 true 后调用 confirmHide()
    func requestHide() {
        isConfirmingHide = true
    }

    func confirmHide() {
        isConfirmingHide = false
        do {
            let stored = try repository.toggleHidden(exerciseID: item.id)
            item.isHidden = stored
            toast = stored ? "已隐藏，可在动作库的高级筛选里找回" : "已取消隐藏"
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: - 复制为自定义动作

    /// 复制当前动作为用户自己的自定义动作，返回新条目供界面跳转编辑。
    func copyAsCustom() -> ExerciseLibraryItem? {
        do {
            guard let copy = try repository.copyAsCustomExercise(id: item.id) else {
                errorMessage = "复制失败：找不到这个动作。"
                return nil
            }
            plans = (try? repository.fetchPlans()) ?? plans
            toast = "已复制为「\(copy.name)」"
            return copy
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    // MARK: - 加入训练

    /// 该动作最近一次完成的组记录（用于「上次记录」摘要与「使用上次参数」）。
    @Published private(set) var lastRecord: SetEntry?

    /// 加载时顺带取该动作最近一次完成记录。
    func loadLastRecord() {
        guard let sessions = try? repository.fetchRecentSessions(limit: 50) else { return }
        for session in sessions.sorted(by: { $0.startedAt > $1.startedAt }) {
            if let entry = session.lastCompletedEntry(forExercise: item.id) {
                lastRecord = entry
                return
            }
        }
        lastRecord = nil
    }

    /// 「上次记录」的可读摘要。
    var lastRecordSummary: String? {
        guard let record = lastRecord else { return nil }
        return "上次 \(FormatterKit.weight(record.weight)) × \(record.reps) 次"
    }

    /// 用上次完成的组参数填入当前处方（只填参数，不标记已完成）。
    func applyLastRecord() {
        guard let record = lastRecord else { return }
        draft.repsLow = record.reps
        draft.repsHigh = record.reps
        draft.usesRepRange = false
        if record.weight > 0 { draft.weight = record.weight }
    }

    /// 加入指定的训练：按处方展开成若干「未完成组」追加到草稿末尾。
    /// `sessionID` 为 nil 时使用「当前进行中的训练」。
    func addToActiveSession(sessionID: UUID? = nil) {
        let target: WorkoutSession?
        if let sessionID {
            target = try? repository.fetchSession(id: sessionID)
        } else {
            target = activeSession
        }
        guard var session = target else {
            errorMessage = "当前没有进行中的训练。"
            return
        }
        do {
            let entries = Self.expandEntries(from: draft, exerciseID: item.id, startIndex: session.nextSetIndex(forExercise: item.id))
            session.entries.append(contentsOf: entries)
            guard let updated = try repository.updateSessionDraft(session) else {
                errorMessage = "加入失败：进行中的训练已结束。"
                return
            }
            activeSession = updated
            try? repository.recordExerciseUsage(id: item.id)
            toast = "已加入「\(updated.name)」"
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 把处方展开成若干组：热身组在前（按百分比计重量），正式组在后。
    private static func expandEntries(
        from prescription: ExercisePrescription,
        exerciseID: String,
        startIndex: Int
    ) -> [SetEntry] {
        var entries: [SetEntry] = []
        var index = startIndex

        if prescription.isWarmup {
            for _ in 0..<max(1, prescription.warmupCount) {
                let warmWeight = (prescription.weight ?? 0) * prescription.warmupPercent / 100
                entries.append(
                    SetEntry(
                        exerciseID: exerciseID,
                        index: index,
                        weight: warmWeight,
                        reps: prescription.repsLow,
                        isWarmup: true,
                        completedAt: nil
                    )
                )
                index += 1
            }
        }

        for _ in 0..<max(1, prescription.sets) {
            entries.append(
                SetEntry(
                    exerciseID: exerciseID,
                    index: index,
                    weight: prescription.weight ?? 0,
                    reps: prescription.repsLow,
                    isWarmup: false,
                    completedAt: nil
                )
            )
            index += 1
        }

        return entries
    }

    /// 加入已有计划
    func add(toPlan planID: UUID) {
        let entry = PlanExercise(
            exerciseID: item.id,
            sets: draft.sets,
            repsLow: draft.repsLow,
            repsHigh: draft.repsHigh,
            restSeconds: draft.restSeconds,
            isWarmup: draft.isWarmup,
            defaultWeight: draft.weight,
            warmupCount: draft.warmupCount,
            warmupPercent: draft.warmupPercent,
            note: draft.note
        )
        do {
            guard try repository.appendExercise(entry, toPlan: planID) != nil else {
                errorMessage = "加入失败：计划已不存在。"
                return
            }
            plans = (try? repository.fetchPlans()) ?? plans
            try? repository.recordExerciseUsage(id: item.id)
            let name = plans.first { $0.id == planID }?.name ?? "计划"
            toast = "已加入「\(name)」"
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// 新建一个力量训练计划并把当前动作放进去，返回新计划
    @discardableResult
    func createPlanAndAdd(name: String, trainingDays: [Int] = []) -> Plan? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let planName = trimmed.isEmpty ? "\(item.displayName)训练" : trimmed
        do {
            let plan = try repository.createPlan(name: planName, trainingDays: trainingDays)
            let entry = PlanExercise(
                exerciseID: item.id,
                sets: draft.sets,
                repsLow: draft.repsLow,
                repsHigh: draft.repsHigh,
                restSeconds: draft.restSeconds,
                isWarmup: draft.isWarmup,
                defaultWeight: draft.weight,
                warmupCount: draft.warmupCount,
                warmupPercent: draft.warmupPercent,
                note: draft.note
            )
            try repository.appendExercise(entry, toPlan: plan.id)
            plans = (try? repository.fetchPlans()) ?? plans
            try? repository.recordExerciseUsage(id: item.id)
            toast = "已新建「\(planName)」并添加"
            return plan
        } catch {
            errorMessage = Self.message(for: error)
            return nil
        }
    }

    /// 「替换原配置」：移除计划内该动作的既有条目，再按当前处方追加。
    func replaceInPlan(planID: UUID) {
        guard let plan = plans.first(where: { $0.id == planID }) else {
            add(toPlan: planID)
            return
        }
        let existing = plan.exercises.filter { $0.exerciseID == item.id }
        for entry in existing {
            try? repository.removePlanExercise(entry.id, fromPlan: planID)
        }
        add(toPlan: planID)
    }

    // MARK: - 内部

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "操作失败：\(error.localizedDescription)"
    }
}

// MARK: - 肌群引用

/// 详情页「涉及肌群」里的一个标签。主肌群置顶并高亮。
struct ExerciseMuscleRef: Identifiable, Hashable {
    var name: String
    var isPrimary: Bool

    var id: String { name }
}

// MARK: - 训练处方

/// 加入训练 / 计划时填写的组数、次数、重量、休息与热身标记。
/// 默认值由动作的负重性质推导，用户可在设置面板里改。
struct ExercisePrescription: Equatable {
    var sets: Int = 3
    var repsLow: Int = 8
    var repsHigh: Int = 12
    /// 自定义次数时把上下限设为同一个值
    var usesRepRange: Bool = true
    /// 默认重量（可选）。nil 表示自重 / 未填。内部始终按 kg 存。
    var weight: Double?
    var restSeconds: Int = 90
    var isWarmup: Bool = false
    /// 热身组数量（开启热身组后有效）
    var warmupCount: Int = 1
    /// 热身组重量百分比（0…100）
    var warmupPercent: Double = 50
    /// 训练备注（可选多行）
    var note: String?

    /// 次数文案，如 "8-12" 或 "10"
    var repsText: String {
        repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
    }

    /// 该组方案的大致耗时（秒），用于在面板上给出提示
    var estimatedSeconds: Int {
        let perSet = 40 + restSeconds
        return max(0, (perSet * sets) - restSeconds)
    }

    /// 按动作推导默认处方。
    /// 自重与有氧动作次数放宽、休息缩短；复合负重动作组数多、休息长。
    static func `default`(for item: ExerciseLibraryItem) -> ExercisePrescription {
        var value = ExercisePrescription()

        switch item.loadKind {
        case .bodyweight:
            value.sets = 3
            value.repsLow = 12
            value.repsHigh = 20
            value.restSeconds = 60
        case .machine:
            value.sets = 3
            value.repsLow = 10
            value.repsHigh = 15
            value.restSeconds = 75
        case .weighted:
            value.sets = 4
            value.repsLow = 8
            value.repsHigh = 12
            value.restSeconds = 90
        }

        // 难度高的动作少组数、长休息，避免默认处方过于激进
        if item.difficulty == .advanced {
            value.restSeconds += 30
        }
        // 动作自带默认休息时间时优先采用（页面 23/24 编辑时写入）
        if let rest = item.defaultRestSeconds {
            value.restSeconds = rest
        }
        return value
    }
}
