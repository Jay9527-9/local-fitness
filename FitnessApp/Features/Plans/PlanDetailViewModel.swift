//
//  PlanDetailViewModel.swift
//  计划详情页的状态与数据操作。
//
//  这一页的所有写入都走 FitnessRepository：
//    概览 / 训练日        → replace(plan:)
//    单个动作配置          → updatePlanExercise(_:inPlan:)
//    拖拽排序              → reorderPlanExercises(inPlan:orderedIDs:)
//    移除动作              → removePlanExercise(_:fromPlan:)
//    复制本动作配置         → duplicatePlanExercise(_:inPlan:)
//    替换动作              → replacePlanExercise(_:inPlan:withExerciseID:)
//    添加动作 / 追加末尾    → appendExercise(_:toPlan:)
//    更多菜单里的复制计划   → duplicate(planID:)
//    更多菜单里的删除计划   → delete(planID:)
//

import Foundation

@MainActor
final class PlanDetailViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    /// 长按菜单里可用的操作。上移 / 下移在首尾位置会被禁用。
    enum RowAction: String, Identifiable {
        case moveUp
        case moveDown
        case duplicate
        case replace
        case remove

        var id: String { rawValue }

        var title: String {
            switch self {
            case .moveUp: return "上移"
            case .moveDown: return "下移"
            case .duplicate: return "复制本动作配置"
            case .replace: return "替换动作"
            case .remove: return "从计划移除"
            }
        }

        var symbol: String {
            switch self {
            case .moveUp: return "arrow.up"
            case .moveDown: return "arrow.down"
            case .duplicate: return "doc.on.doc"
            case .replace: return "arrow.triangle.2.circlepath"
            case .remove: return "trash"
            }
        }

        var isDestructive: Bool { self == .remove }
    }

    // MARK: - 输出状态

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var plan: Plan?
    /// 计划内动作对应的动作库条目，key 是动作库 id。
    /// 用字典而不是数组，是因为计划顺序可能与动作库返回顺序不一致。
    @Published private(set) var exerciseLookup: [String: ExerciseLibraryItem] = [:]
    @Published var errorMessage: String?
    /// 轻量提示，例如「已复制到计划末尾」
    @Published var toast: String?

    /// 通过 repository 查出计划后推送出去，供上层决定是否继续停留在本页。
    @Published private(set) var didDeletePlan = false

    // MARK: - 依赖

    private let repository: FitnessRepository
    private var planID: UUID

    init(repository: FitnessRepository, planID: UUID) {
        self.repository = repository
        self.planID = planID
    }

    // MARK: - 读取

    func load() {
        loadState = .loading
        do {
            guard let fetched = try repository.fetchPlan(id: planID) else {
                loadState = .failed("这个计划已经不存在了")
                return
            }
            plan = fetched
            exerciseLookup = try makeLookup(for: fetched)
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// 计划详情页被重新展示时刷新（例如从动作库添加动作后返回）
    func refresh() {
        guard loadState == .loaded else { return }
        do {
            guard let fetched = try repository.fetchPlan(id: planID) else {
                loadState = .failed("这个计划已经不存在了")
                return
            }
            plan = fetched
            exerciseLookup = try makeLookup(for: fetched)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 一次性批量取动作，比逐个 fetch 更省 IO
    private func makeLookup(for plan: Plan) throws -> [String: ExerciseLibraryItem] {
        let ids = Array(Set(plan.exercises.map { $0.exerciseID }))
        guard !ids.isEmpty else { return [:] }
        let items = try repository.fetchExercises(ids: ids)
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    // MARK: - 概览

    var planName: String { plan?.name ?? "计划" }

    var isEmpty: Bool { (plan?.exercises.count ?? 0) == 0 }

    /// 「开始训练」在没有动作时置灰，避免创建空训练
    var canStartTraining: Bool { !isEmpty && loadState == .loaded }

    /// 动作总数
    var exerciseCountText: String {
        let count = plan?.exerciseCount ?? 0
        return count == 0 ? "暂无动作" : "\(count) 个动作"
    }

    /// 每周训练天数
    var trainingDaysText: String {
        guard let plan else { return "未设置" }
        return plan.trainingDays.isEmpty ? "未设置" : "每周 \(plan.trainingDays.count) 天"
    }

    /// 预计训练时长
    var estimatedDurationText: String {
        let minutes = plan?.estimatedMinutes ?? 0
        return minutes == 0 ? "—" : "约 \(minutes) 分钟"
    }

    /// 上次训练日期
    var lastTrainedText: String {
        guard let lastUsedAt = plan?.lastUsedAt else { return "还没有训练记录" }
        return FormatterKit.shortDate.string(from: lastUsedAt)
    }

    /// 概览卡上的四项指标
    var overviewItems: [(title: String, value: String)] {
        [
            ("每周训练", trainingDaysText),
            ("动作总数", exerciseCountText),
            ("预计时长", estimatedDurationText),
            ("上次训练", lastTrainedText)
        ]
    }

    // MARK: - 动作列表

    /// 列表行数据。把展示所需的内容一次算好，避免 View 里反复查字典。
    struct Row: Identifiable {
        var id: UUID
        var index: Int
        var entry: PlanExercise
        var item: ExerciseLibraryItem?

        var name: String {
            item?.displayName ?? "动作已从动作库移除"
        }

        var muscleText: String {
            item?.primaryMuscleText ?? "未知肌群"
        }

        var equipmentText: String {
            item?.equipmentText ?? "—"
        }

        var volumeText: String { entry.volumeText }

        var restText: String { "休息 \(FormatterKit.rest(seconds: entry.restSeconds))" }

        var isMissing: Bool { item == nil }
    }

    var rows: [Row] {
        guard let plan else { return [] }
        return plan.exercises.enumerated().map { offset, entry in
            Row(
                id: entry.id,
                index: offset + 1,
                entry: entry,
                item: exerciseLookup[entry.exerciseID]
            )
        }
    }

    func row(for entryID: UUID) -> Row? {
        rows.first { $0.id == entryID }
    }

    /// 长按某个动作时，哪些操作可用
    func availableActions(for entryID: UUID) -> [RowAction] {
        guard let plan, let index = plan.index(ofPlanExercise: entryID) else { return [] }
        var result: [RowAction] = []
        if index > 0 { result.append(.moveUp) }
        if index < plan.exercises.count - 1 { result.append(.moveDown) }
        result.append(.duplicate)
        result.append(.replace)
        result.append(.remove)
        return result
    }

    // MARK: - 计划名称

    /// 保存新名称。空白名不接受，返回 false 让调用方保持输入框打开。
    @discardableResult
    func rename(to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "计划名称不能为空"
            return false
        }
        guard var current = plan else { return false }
        guard trimmed != current.name else { return true }

        current.name = trimmed
        return persist(current, successMessage: nil)
    }

    // MARK: - 训练日

    func saveTrainingDays(_ days: [Int]) {
        guard var current = plan else { return }
        let normalized = WeekdayLabel.ordered(days)
        guard normalized != current.trainingDays else { return }
        current.trainingDays = normalized
        persist(current, successMessage: nil)
    }

    // MARK: - 动作条目

    func save(_ entry: PlanExercise) {
        do {
            guard let updated = try repository.updatePlanExercise(entry, inPlan: planID) else {
                errorMessage = "没有找到这个动作，可能已被移除"
                return
            }
            // 本地同步，避免为一处改动整页重读
            applyLocalChange { plan in
                guard let index = plan.index(ofPlanExercise: updated.id) else { return }
                plan.exercises[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 拖拽排序落位后立即持久化。
    /// 传入的是 SwiftUI `onMove` 给的 IndexSet / Int，先本地重排再整体写盘，
    /// 这样即使写盘失败界面也不会跳回旧顺序。
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard var current = plan else { return }
        var reordered = current.exercises
        reordered.move(fromOffsets: source, toOffset: destination)
        guard reordered.map({ $0.id }) != current.exercises.map({ $0.id }) else { return }

        current.exercises = reordered
        plan = current
        Haptics.medium()

        do {
            guard let saved = try repository.reorderPlanExercises(
                inPlan: planID,
                orderedIDs: reordered.map { $0.id }
            ) else {
                // 写盘被拒绝（例如顺序表不完整），回读真实数据兜底
                refresh()
                errorMessage = "排序保存失败，已恢复原顺序"
                return
            }
            plan = saved
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    func moveUp(_ entryID: UUID) {
        guard let plan, let index = plan.index(ofPlanExercise: entryID), index > 0 else { return }
        move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
    }

    func moveDown(_ entryID: UUID) {
        guard let plan, let index = plan.index(ofPlanExercise: entryID),
              index < plan.exercises.count - 1 else { return }
        // onMove 的目标下标语义是「插入点」，向后移动要 +2 才会落到下一位之后
        move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
    }

    func duplicate(_ entryID: UUID) {
        do {
            guard let copy = try repository.duplicatePlanExercise(entryID, inPlan: planID) else {
                errorMessage = "复制失败，动作可能已被移除"
                return
            }
            applyLocalChange { plan in
                guard let index = plan.index(ofPlanExercise: entryID) else { return }
                plan.exercises.insert(copy, at: index + 1)
            }
            toast = "已复制「\(row(for: copy.id)?.name ?? "动作")」配置"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func replace(_ entryID: UUID, with exerciseID: String) {
        do {
            guard let updated = try repository.replacePlanExercise(
                entryID,
                inPlan: planID,
                withExerciseID: exerciseID
            ) else {
                errorMessage = "替换失败，动作可能已被移除"
                return
            }
            if let item = try repository.fetchExercises(ids: [exerciseID]).first {
                exerciseLookup[item.id] = item
            }
            applyLocalChange { plan in
                guard let index = plan.index(ofPlanExercise: updated.id) else { return }
                plan.exercises[index] = updated
            }
            toast = "已替换为「\(exerciseLookup[exerciseID]?.displayName ?? "新动作")」"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 从计划移除。只摘掉计划里的配置，动作库条目与已完成的历史训练都不受影响。
    func remove(_ entryID: UUID) {
        do {
            guard let updated = try repository.removePlanExercise(entryID, fromPlan: planID) else {
                errorMessage = "移除失败，动作可能已被移除"
                return
            }
            plan = updated
            Haptics.medium()
            toast = "已从计划移除"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 动作库选中一个动作后，按配置追加到计划末尾
    @discardableResult
    func append(exerciseID: String, prescription: ExerciseDraft) -> Bool {
        let entry = prescription.makePlanExercise(exerciseID: exerciseID)
        do {
            guard let added = try repository.appendExercise(entry, toPlan: planID) else {
                errorMessage = "添加失败，计划可能已被删除"
                return false
            }
            if let item = try repository.fetchExercises(ids: [exerciseID]).first {
                exerciseLookup[item.id] = item
            }
            applyLocalChange { plan in
                plan.exercises.append(added)
            }
            toast = "已添加到计划末尾"
            Haptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 更多菜单

    func duplicatePlan() -> Plan? {
        do {
            guard let copy = try repository.duplicate(planID: planID) else {
                errorMessage = "复制失败"
                return nil
            }
            toast = "已创建副本「\(copy.name)」"
            Haptics.success()
            return copy
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// 导出本地备份：把当前计划序列化成 JSON 文件，交给系统分享面板。
    /// 返回文件 URL 供上层弹出 share sheet。
    func exportBackup() -> URL? {
        guard let plan else { return nil }
        do {
            return try PlanBackupWriter.write(plan: plan, exercises: exerciseLookup)
        } catch {
            errorMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 删除计划。不触碰 sessions.json，已完成的历史训练记录保留。
    @discardableResult
    func deletePlan() -> Bool {
        do {
            try repository.delete(planID: planID)
            didDeletePlan = true
            Haptics.warning()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - 开始训练

    /// 创建草稿训练并写入本地。
    /// 草稿会把计划里的每个动作展开成对应数量的「待完成组」（`completedAt == nil`），
    /// 再用历史最高重量预填重量，让执行页一进来就是一张可用的目标表格。
    func makeSessionDraft() -> WorkoutSession? {
        guard let plan, !plan.exercises.isEmpty else {
            errorMessage = "这个计划还没有动作，先添加动作再开始训练"
            return nil
        }
        // 用统一的展开工厂把计划的每个动作变成对应数量的「待完成组」，
        // 执行页一进来就是完整的目标表格。
        var draft = WorkoutSession.draft(from: plan)
        seedPrescribedWeights(in: &draft)
        do {
            try repository.save(session: draft)
            // 记录最后一次使用时间，供首页计划卡展示
            var touched = plan
            touched.lastUsedAt = Date()
            _ = persist(touched, successMessage: nil)
            return draft
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// 用历史记录里的最高重量预填未完成组的重量，让执行页的表格有参考值。
    /// 只改 weight，不动目标次数与顺序。
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

    // MARK: - 内部

    /// 本地增量修改 + 整体写盘。用于避免每次点击都重读一遍全部数据。
    private func applyLocalChange(_ mutate: (inout Plan) -> Void) {
        guard var current = plan else { return }
        mutate(&current)
        plan = current
    }

    @discardableResult
    private func persist(_ next: Plan, successMessage: String?) -> Bool {
        do {
            guard let saved = try repository.replace(plan: next) else {
                errorMessage = "计划已不存在"
                return false
            }
            plan = saved
            if let successMessage { toast = successMessage }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - 新建 / 编辑动作时的配置草稿

/// 「添加动作」「编辑动作配置」共用的配置载体。
/// 与 `ExercisePrescription` 的区别：这里带备注与递增规则，且能直接转成 `PlanExercise`。
struct ExerciseDraft: Equatable {

    var sets: Int = 3
    var repsLow: Int = 8
    var repsHigh: Int = 12
    var restSeconds: Int = 90
    var isWarmup: Bool = false
    var defaultWeight: Double?
    var warmupCount: Int = 1
    var warmupPercent: Double = 50
    var note: String = ""
    var progression: ProgressionRule = .none
    var progressionConfig: ProgressionConfig?

    init() {}

    /// 从已有条目回填，用于「编辑动作配置」
    init(entry: PlanExercise) {
        self.sets = entry.sets
        self.repsLow = entry.repsLow
        self.repsHigh = entry.repsHigh
        self.restSeconds = entry.restSeconds
        self.isWarmup = entry.isWarmup
        self.defaultWeight = entry.defaultWeight
        self.warmupCount = entry.warmupCount
        self.warmupPercent = entry.warmupPercent
        self.note = entry.note ?? ""
        self.progression = entry.progression
        self.progressionConfig = entry.progressionConfig
    }

    var repsText: String {
        repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
    }

    var summaryText: String {
        var parts = ["\(sets) 组 × \(repsText) 次"]
        parts.append("休息 \(FormatterKit.rest(seconds: restSeconds))")
        if isWarmup { parts.append("热身") }
        return parts.joined(separator: " · ")
    }

    /// 转成计划内条目。备注留空时写 nil，避免存一堆空字符串。
    func makePlanExercise(exerciseID: String) -> PlanExercise {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlanExercise(
            exerciseID: exerciseID,
            sets: sets,
            repsLow: repsLow,
            repsHigh: repsHigh,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            defaultWeight: defaultWeight,
            warmupCount: warmupCount,
            warmupPercent: warmupPercent,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            progression: progression,
            progressionConfig: progressionConfig
        )
    }

    /// 覆盖到一个已有条目上，保留 id 与指向的动作
    func applied(to entry: PlanExercise) -> PlanExercise {
        var updated = entry
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sets = sets
        updated.repsLow = repsLow
        updated.repsHigh = repsHigh
        updated.restSeconds = restSeconds
        updated.isWarmup = isWarmup
        updated.defaultWeight = defaultWeight
        updated.warmupCount = warmupCount
        updated.warmupPercent = warmupPercent
        updated.note = trimmedNote.isEmpty ? nil : trimmedNote
        updated.progression = progression
        updated.progressionConfig = progressionConfig
        return updated
    }
}

// MARK: - 导出本地备份

enum PlanBackupWriter {

    struct Error: LocalizedError {
        var message: String
        var errorDescription: String? { message }
    }

    /// 把计划连同所引用动作的名称写进一个 JSON 文件，输出到临时目录。
    /// 只导出与计划有关的内容，不含账号、训练历史等其他数据。
    static func write(
        plan: Plan,
        exercises: [String: ExerciseLibraryItem]
    ) throws -> URL {
        struct Entry: Encodable {
            var exerciseID: String
            var name: String
            var primaryMuscle: String
            var equipment: String
            var sets: Int
            var repsLow: Int
            var repsHigh: Int
            var restSeconds: Int
            var isWarmup: Bool
            var note: String?
            var progression: String
        }
        struct Backup: Encodable {
            var format: String
            var version: Int
            var exportedAt: Date
            var plan: Payload

            struct Payload: Encodable {
                var name: String
                var trainingDays: [Int]
                var trainingDaysText: String
                var exerciseCount: Int
                var estimatedMinutes: Int
                var exercises: [Entry]
            }
        }

        let entries = plan.exercises.map { item -> Entry in
            let libraryItem = exercises[item.exerciseID]
            return Entry(
                exerciseID: item.exerciseID,
                name: libraryItem?.displayName ?? item.exerciseID,
                primaryMuscle: libraryItem?.primaryMuscleText ?? "",
                equipment: libraryItem?.equipmentText ?? "",
                sets: item.sets,
                repsLow: item.repsLow,
                repsHigh: item.repsHigh,
                restSeconds: item.restSeconds,
                isWarmup: item.isWarmup,
                note: item.note,
                progression: item.progression.rawValue
            )
        }

        let backup = Backup(
            format: "fitness-plan-backup",
            version: 1,
            exportedAt: Date(),
            plan: .init(
                name: plan.name,
                trainingDays: plan.trainingDays,
                trainingDaysText: plan.trainingDaysText,
                exerciseCount: plan.exerciseCount,
                estimatedMinutes: plan.estimatedMinutes,
                exercises: entries
            )
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data: Data
        do {
            data = try encoder.encode(backup)
        } catch {
            throw Error(message: "内容编码失败")
        }

        let safeName = plan.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(safeName.isEmpty ? "计划" : safeName)-备份.json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw Error(message: "文件写入失败")
        }
        return url
    }
}
