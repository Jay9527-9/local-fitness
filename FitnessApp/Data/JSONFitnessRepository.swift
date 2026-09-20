//
//  JSONFitnessRepository.swift
//  FitnessRepository 的本地 JSON 实现，兼容 iOS 16。
//
//  为什么不用 SwiftData：SwiftData 要求 iOS 17+，而目标设备是 iOS 16.3.1。
//  本实现把四个集合各存成一个 JSON 文件，写入 Application Support 目录：
//
//      <AppSupport>/FitnessData/plans.json
//      <AppSupport>/FitnessData/sessions.json
//      <AppSupport>/FitnessData/measurements.json
//      <AppSupport>/FitnessData/exercises.json
//
//  Application Support 不会被系统清理（Caches 会被清理），符合「数据只保存在本机」的要求。
//  全部写入走原子写（.atomic），避免中途崩溃导致文件截断。
//  无任何网络、账号、同步依赖。
//

import Foundation

@MainActor
final class JSONFitnessRepository: FitnessRepository {

    // MARK: - 错误

    enum StorageError: LocalizedError {
        case directoryUnavailable(underlying: Error)
        case decodeFailed(file: String, underlying: Error)
        case notDeletable(name: String)

        var errorDescription: String? {
            switch self {
            case .directoryUnavailable(let underlying):
                return "无法创建本地数据目录：\(underlying.localizedDescription)"
            case .decodeFailed(let file, let underlying):
                return "本地文件 \(file) 解析失败：\(underlying.localizedDescription)"
            case .notDeletable(let name):
                return "「\(name)」来自内置动作库，不能删除。可以改为收藏或隐藏。"
            }
        }
    }

    // MARK: - 属性

    private let fileManager: FileManager
    private let bundle: Bundle
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// 内存缓存：读操作直接返回，写操作同步回写磁盘
    private var plans: [Plan] = []
    private var sessions: [WorkoutSession] = []
    private var exercises: [ExerciseLibraryItem] = []
    private var measurements: [BodyMeasurement] = []
    private var recentExercises: [RecentExerciseRef] = []
    private var restDays: [RestDay] = []
    /// 本地有氧模板（页面 32）
    private var cardioTemplates: [CardioTemplate] = []
    /// 当前组间休息，nil 表示没有休息在进行
    private var restTimer: RestTimerRecord?
    /// 本地个人资料。nil 表示尚未创建。
    private var profile: UserProfile?

    private var isLoaded = false
    /// 动作库是否已导入种子数据，避免每次启动重复读 1.4 MB JSON
    private var isExerciseSeeded = false

    // MARK: - 初始化

    init(
        directory: URL? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.bundle = bundle

        let base = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.directory = base

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    /// 默认落盘位置：Application Support/FitnessData
    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root.appendingPathComponent("FitnessData", isDirectory: true)
    }

    // MARK: - 文件读写

    private var plansURL: URL { directory.appendingPathComponent("plans.json") }
    private var sessionsURL: URL { directory.appendingPathComponent("sessions.json") }
    private var exercisesURL: URL { directory.appendingPathComponent("exercises.json") }
    private var measurementsURL: URL { directory.appendingPathComponent("measurements.json") }
    private var recentExercisesURL: URL { directory.appendingPathComponent("recentExercises.json") }
    /// 休息日。独立文件，与训练记录的聚合统计完全隔离。
    private var restDaysURL: URL { directory.appendingPathComponent("restDays.json") }
    /// 组间休息状态。全局只存一条，所以是单个对象而不是数组。
    private var restTimerURL: URL { directory.appendingPathComponent("restTimer.json") }
    /// 个人资料。单个对象。
    private var profileURL: URL { directory.appendingPathComponent("profile.json") }
    /// 有氧模板。数组。
    private var cardioTemplatesURL: URL { directory.appendingPathComponent("cardioTemplates.json") }

    /// 首次访问时把磁盘内容读进内存
    private func loadIfNeeded() throws {
        guard !isLoaded else { return }
        try ensureDirectory()

        plans = try read(plansURL)
        sessions = try read(sessionsURL)
        exercises = try read(exercisesURL)
        measurements = try read(measurementsURL)
        recentExercises = try read(recentExercisesURL)
        restDays = try read(restDaysURL)
        cardioTemplates = try read(cardioTemplatesURL)
        restTimer = try readSingle(restTimerURL)
        profile = try readSingle(profileURL)

        // 动作库文件存在即视为已导入
        isExerciseSeeded = !exercises.isEmpty
        isLoaded = true
    }

    private func ensureDirectory() throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw StorageError.directoryUnavailable(underlying: error)
        }
    }

    /// 读文件。文件不存在返回空数组，属于正常首次启动。
    private func read<T: Decodable>(_ url: URL) throws -> [T] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            guard !data.isEmpty else { return [] }
            return try decoder.decode([T].self, from: data)
        } catch {
            throw StorageError.decodeFailed(
                file: url.lastPathComponent,
                underlying: error
            )
        }
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try ensureDirectory()
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// 读单个对象。文件不存在或内容已损坏时都返回 nil，
    /// 让调用方退化成「当前没有休息状态」，而不是因为一条临时状态把整页读崩。
    private func readSingle<T: Decodable>(_ url: URL) throws -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    // MARK: - 计划

    func fetchPlans() throws -> [Plan] {
        try loadIfNeeded()
        return plans.sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchPlan(id: UUID) throws -> Plan? {
        try loadIfNeeded()
        return plans.first { $0.id == id }
    }

    func save(plan: Plan) throws {
        try loadIfNeeded()
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index] = plan
        } else {
            plans.append(plan)
        }
        try persistPlans()
    }

    func delete(planID: UUID) throws {
        try loadIfNeeded()
        guard plans.contains(where: { $0.id == planID }) else { return }
        plans.removeAll { $0.id == planID }
        try persistPlans()
    }

    func deletePlans(ids: [UUID]) throws {
        try loadIfNeeded()
        let idSet = Set(ids)
        guard plans.contains(where: { idSet.contains($0.id) }) else { return }
        plans.removeAll { idSet.contains($0.id) }
        try persistPlans()
    }

    func duplicate(planID: UUID) throws -> Plan? {
        try loadIfNeeded()
        guard let source = plans.first(where: { $0.id == planID }) else { return nil }

        var copy = source
        copy.id = UUID()
        copy.name = PlanCopyName.makeCopyName(for: source.name)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.lastUsedAt = nil
        // 动作条目也要换新 id，避免与源计划共享引用
        copy.exercises = source.exercises.map {
            var item = $0
            item.id = UUID()
            return item
        }
        plans.append(copy)
        try persistPlans()
        return copy
    }

    @discardableResult
    func appendExercise(_ entry: PlanExercise, toPlan planID: UUID) throws -> PlanExercise? {
        try loadIfNeeded()
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        plans[index].exercises.append(entry)
        plans[index].updatedAt = Date()
        try persistPlans()
        return entry
    }

    @discardableResult
    func createPlan(name: String, trainingDays: [Int]) throws -> Plan {
        try loadIfNeeded()
        let plan = Plan(name: name, trainingDays: trainingDays)
        plans.append(plan)
        try persistPlans()
        return plan
    }

    // MARK: - 计划内的动作条目

    @discardableResult
    func updatePlanExercise(_ entry: PlanExercise, inPlan planID: UUID) throws -> PlanExercise? {
        try loadIfNeeded()
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entry.id })
        else { return nil }

        // 保留数组位置，只覆盖配置字段，避免编辑后顺序被打乱。
        plans[planIndex].exercises[entryIndex] = entry
        plans[planIndex].updatedAt = Date()
        try persistPlans()
        return entry
    }

    @discardableResult
    func reorderPlanExercises(inPlan planID: UUID, orderedIDs: [UUID]) throws -> Plan? {
        try loadIfNeeded()
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }) else { return nil }

        let current = plans[planIndex].exercises
        // 只有顺序表恰好覆盖全部条目时才写盘，防止半截数据把计划改坏。
        guard orderedIDs.count == current.count,
              Set(orderedIDs) == Set(current.map { $0.id })
        else { return nil }

        let byID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        plans[planIndex].exercises = orderedIDs.compactMap { byID[$0] }
        plans[planIndex].updatedAt = Date()
        try persistPlans()
        return plans[planIndex]
    }

    @discardableResult
    func removePlanExercise(_ entryID: UUID, fromPlan planID: UUID) throws -> Plan? {
        try loadIfNeeded()
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        guard plans[planIndex].exercises.contains(where: { $0.id == entryID }) else { return nil }

        // 只摘掉计划里的配置；动作库条目与已完成的训练记录都不动。
        plans[planIndex].exercises.removeAll { $0.id == entryID }
        plans[planIndex].updatedAt = Date()
        try persistPlans()
        return plans[planIndex]
    }

    @discardableResult
    func duplicatePlanExercise(_ entryID: UUID, inPlan planID: UUID) throws -> PlanExercise? {
        try loadIfNeeded()
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entryID })
        else { return nil }

        let copy = plans[planIndex].exercises[entryIndex].duplicated()
        plans[planIndex].exercises.insert(copy, at: entryIndex + 1)
        plans[planIndex].updatedAt = Date()
        try persistPlans()
        return copy
    }

    @discardableResult
    func replacePlanExercise(
        _ entryID: UUID,
        inPlan planID: UUID,
        withExerciseID exerciseID: String
    ) throws -> PlanExercise? {
        try loadIfNeeded()
        guard let planIndex = plans.firstIndex(where: { $0.id == planID }),
              let entryIndex = plans[planIndex].exercises.firstIndex(where: { $0.id == entryID })
        else { return nil }

        // 只换指向的动作，组数 / 次数 / 休息 / 备注等配置保留，用户不用重填。
        plans[planIndex].exercises[entryIndex].exerciseID = exerciseID
        plans[planIndex].updatedAt = Date()
        try persistPlans()
        return plans[planIndex].exercises[entryIndex]
    }

    @discardableResult
    func replace(plan: Plan) throws -> Plan? {
        try loadIfNeeded()
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return nil }
        var updated = plan
        updated.updatedAt = Date()
        plans[index] = updated
        try persistPlans()
        return updated
    }

    private func persistPlans() throws {
        try write(plans, to: plansURL)
    }

    // MARK: - 训练记录

    func fetchRecentSessions(limit: Int) throws -> [WorkoutSession] {
        try loadIfNeeded()
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        guard limit > 0 else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func fetchSession(id: UUID) throws -> WorkoutSession? {
        try loadIfNeeded()
        return sessions.first { $0.id == id }
    }

    func fetchActiveSession() throws -> WorkoutSession? {
        try loadIfNeeded()
        return sessions
            .filter { $0.endedAt == nil }
            .max { $0.startedAt < $1.startedAt }
    }

    func save(session: WorkoutSession) throws {
        try loadIfNeeded()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        try write(sessions, to: sessionsURL)
    }

    func delete(sessionID: UUID) throws {
        try loadIfNeeded()
        guard sessions.contains(where: { $0.id == sessionID }) else { return }
        sessions.removeAll { $0.id == sessionID }
        try write(sessions, to: sessionsURL)
    }

    @discardableResult
    func appendEntryToActiveSession(_ entry: SetEntry) throws -> WorkoutSession? {
        try loadIfNeeded()
        guard let index = sessions.firstIndex(where: { $0.endedAt == nil }) else { return nil }
        sessions[index].entries.append(entry)
        try write(sessions, to: sessionsURL)
        return sessions[index]
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
        try mutateSession(sessionID) { session in
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
        try mutateSession(sessionID) { session in
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
        try loadIfNeeded()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }

        // 复制同一动作最后一组的数值；没有历史组时用调用方给的默认值。
        let template = sessions[index].lastCompletedEntry(forExercise: exerciseID)
            ?? sessions[index].entries.last { $0.exerciseID == exerciseID }

        let newIndex = sessions[index].nextSetIndex(forExercise: exerciseID)
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

        // 插到该动作所有组的末尾，而不是整个数组的末尾，保证表格按动作聚合时不串行。
        let insertionIndex: Int
        if let last = sessions[index].entries.lastIndex(where: { $0.exerciseID == exerciseID }) {
            insertionIndex = last + 1
        } else {
            insertionIndex = sessions[index].entries.count
        }
        sessions[index].entries.insert(entry, at: insertionIndex)
        try write(sessions, to: sessionsURL)
        return entry
    }

    @discardableResult
    func removeSetEntry(
        sessionID: UUID,
        entryID: UUID
    ) throws -> WorkoutSession? {
        try loadIfNeeded()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        guard let target = sessions[index].entries.first(where: { $0.id == entryID }) else {
            return sessions[index]
        }

        // 同一动作至少留一组，否则动作卡会整个消失，用户无从恢复。
        let siblings = sessions[index].entries.filter { $0.exerciseID == target.exerciseID }
        guard siblings.count > 1 else { return sessions[index] }

        sessions[index].entries.removeAll { $0.id == entryID }
        // 重排该动作的组号，保证表格左侧从 1 连续计数
        var counter = 0
        for entryIndex in sessions[index].entries.indices
        where sessions[index].entries[entryIndex].exerciseID == target.exerciseID {
            counter += 1
            sessions[index].entries[entryIndex].index = counter
        }
        try write(sessions, to: sessionsURL)
        return sessions[index]
    }

    @discardableResult
    func replaceExerciseInSession(
        sessionID: UUID,
        fromExerciseID: String,
        toExerciseID: String
    ) throws -> WorkoutSession? {
        try mutateSession(sessionID) { session in
            var changed = false
            for index in session.entries.indices {
                let entry = session.entries[index]
                guard entry.exerciseID == fromExerciseID else { continue }
                // 已完成的组保持原动作，只把后续未完成的组换成新动作
                guard !entry.isCompleted else { continue }
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
        try mutateSession(sessionID) { session in
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
        try mutateSession(sessionID) { session in
            if session.endedAt == nil {
                // 结束时间不能早于开始时间，避免时钟回拨导致负时长
                session.endedAt = max(endedAt, session.startedAt)
            }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
            return true
        }
    }

    /// 训练执行页所有改动都走这里：定位会话 → 改 → 整份原子落盘。
    /// 闭包返回 false 表示没有需要写入的变化，此时不落盘。
    @discardableResult
    private func mutateSession(
        _ sessionID: UUID,
        _ body: (inout WorkoutSession) -> Bool
    ) throws -> WorkoutSession? {
        try loadIfNeeded()
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
        var session = sessions[index]
        guard body(&session) else { return session }
        sessions[index] = session
        try write(sessions, to: sessionsURL)
        return session
    }

    // MARK: - 组间休息状态

    func fetchRestTimer() throws -> RestTimerRecord? {
        try loadIfNeeded()
        return restTimer
    }

    func save(restTimer record: RestTimerRecord) throws {
        try loadIfNeeded()
        restTimer = record
        try write(record, to: restTimerURL)
    }

    func clearRestTimer() throws {
        try loadIfNeeded()
        guard restTimer != nil else { return }
        restTimer = nil
        // 文件还在会让下次启动又「恢复」出一次早就结束的休息，所以直接删掉。
        if fileManager.fileExists(atPath: restTimerURL.path) {
            do {
                try fileManager.removeItem(at: restTimerURL)
            } catch {
                throw StorageError.notDeletable(name: restTimerURL.lastPathComponent)
            }
        }
    }

    // MARK: - 动作库

    func fetchExercises(includeHidden: Bool) throws -> [ExerciseLibraryItem] {
        try loadIfNeeded()
        let list = includeHidden ? exercises : exercises.filter { !$0.isHidden }
        return sortedByName(list)
    }

    func fetchExercises(ids: [String]) throws -> [ExerciseLibraryItem] {
        try loadIfNeeded()
        guard !ids.isEmpty else { return [] }
        let wanted = Set(ids)
        return sortedByName(exercises.filter { wanted.contains($0.id) })
    }

    func save(exercise: ExerciseLibraryItem) throws {
        try loadIfNeeded()
        if let index = exercises.firstIndex(where: { $0.id == exercise.id }) {
            // 导入的动作不允许被改名或改分类，只允许改收藏 / 隐藏
            var merged = exercise
            if !exercises[index].isCustom {
                merged.isCustom = false
            }
            exercises[index] = merged
        } else {
            exercises.append(exercise)
        }
        try write(exercises, to: exercisesURL)
    }

    func deleteExercise(id: String) throws {
        try loadIfNeeded()
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        guard exercises[index].isCustom else {
            throw StorageError.notDeletable(name: exercises[index].name)
        }
        exercises.remove(at: index)
        try write(exercises, to: exercisesURL)

        // 顺带清掉最近使用里的引用，避免出现打不开的条目
        let before = recentExercises.count
        recentExercises.removeAll { $0.id == id }
        if recentExercises.count != before {
            try write(recentExercises, to: recentExercisesURL)
        }
    }

    @discardableResult
    func toggleFavorite(exerciseID: String) throws -> Bool {
        try mutateExercise(id: exerciseID) { item in
            item.isFavorite.toggle()
            // 收藏时记录时间（「最近收藏」排序依据），取消收藏时清空。
            item.favoritedAt = item.isFavorite ? Date() : nil
        }.map { $0.isFavorite } ?? false
    }

    @discardableResult
    func toggleHidden(exerciseID: String) throws -> Bool {
        try mutateExercise(id: exerciseID) { $0.isHidden.toggle() }
            .map { $0.isHidden } ?? false
    }

    /// 就地修改一条动作并落盘，返回修改后的对象
    @discardableResult
    private func mutateExercise(
        id: String,
        _ change: (inout ExerciseLibraryItem) -> Void
    ) throws -> ExerciseLibraryItem? {
        try loadIfNeeded()
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return nil }
        change(&exercises[index])
        try write(exercises, to: exercisesURL)
        return exercises[index]
    }

    private func sortedByName(_ list: [ExerciseLibraryItem]) -> [ExerciseLibraryItem] {
        list.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    @discardableResult
    func seedExerciseLibraryIfNeeded() throws -> Int {
        try loadIfNeeded()
        guard !isExerciseSeeded else { return 0 }
        let added = try importSeedAdditions()
        isExerciseSeeded = true
        return added
    }

    /// 重新导入动作库种子。与首次导入共用同一份合并逻辑，
    /// 只补缺失的导入条目，返回新增条数；自定义动作与收藏 / 隐藏状态原样保留。
    @discardableResult
    func reseedExerciseLibrary() throws -> Int {
        try loadIfNeeded()
        return try importSeedAdditions()
    }

    /// 读取种子，把缺失的导入条目并入动作库，返回新增条数。
    private func importSeedAdditions() throws -> Int {
        guard let url = bundle.url(forResource: "exerciseLibrary.seed", withExtension: "json") else {
            // 资源缺失不抛错，界面会走空状态，避免首启崩溃
            return 0
        }

        let data = try Data(contentsOf: url)
        let seeds = try decoder.decode([ExerciseSeed].self, from: data)

        let imported: [ExerciseLibraryItem] = seeds.map { seed in
            ExerciseLibraryItem(
                id: seed.id,
                name: seed.name,
                aliases: ExerciseAliases.aliases(forName: seed.name),
                category: seed.category,
                categoryZh: seed.categoryZh,
                equipment: seed.equipment,
                equipmentZh: seed.equipmentZh,
                target: seed.target,
                primaryMuscle: MuscleName.zh(for: seed.target),
                muscleGroup: seed.muscleGroup,
                secondaryMuscles: seed.secondaryMuscles,
                difficulty: ExerciseDifficulty.infer(equipment: seed.equipment),
                instructionsZh: seed.instructionsZh,
                stepsZh: seed.stepsZh,
                image: seed.image,
                gifURL: seed.gifUrl,
                attribution: seed.attribution,
                mediaID: seed.mediaId,
                isCustom: false,
                isFavorite: false,
                isHidden: false
            )
        }

        if exercises.isEmpty {
            exercises = imported
            try write(exercises, to: exercisesURL)
            return imported.count
        }

        // 保留已有的收藏 / 隐藏状态与用户自建动作，只补新增的导入条目。
        let existingImportIDs = Set(exercises.filter { !$0.isCustom }.map(\.id))
        let additions = imported.filter { !existingImportIDs.contains($0.id) }
        guard !additions.isEmpty else { return 0 }
        exercises.append(contentsOf: additions)
        try write(exercises, to: exercisesURL)
        return additions.count
    }

    @discardableResult
    func copyAsCustomExercise(id: String) throws -> ExerciseLibraryItem? {
        try loadIfNeeded()
        guard let source = exercises.first(where: { $0.id == id }) else { return nil }

        var copy = source
        copy.id = "custom-\(UUID().uuidString)"
        copy.name = Self.customCopyName(for: source)
        copy.isCustom = true
        // 复制品是全新的条目，收藏与隐藏状态不继承
        copy.isFavorite = false
        copy.favoritedAt = nil
        copy.isHidden = false

        exercises.append(copy)
        try write(exercises, to: exercisesURL)
        return copy
    }

    /// 自定义副本名。已经是自定义动作时避免叠加出「…（副本）（副本）」。
    private static func customCopyName(for source: ExerciseLibraryItem) -> String {
        let base = source.name.hasSuffix("（副本）")
            ? source.name
            : "\(source.name)（副本）"
        return base
    }

    // MARK: - 最近使用的动作

    func recordExerciseUsage(id: String) throws {
        try loadIfNeeded()
        guard exercises.contains(where: { $0.id == id }) else { return }

        // 同一动作只保留一条，更新时间后置顶
        recentExercises.removeAll { $0.id == id }
        recentExercises.insert(RecentExerciseRef(id: id, usedAt: Date()), at: 0)

        // 只留最近 30 条，避免无限增长
        if recentExercises.count > 30 {
            recentExercises = Array(recentExercises.prefix(30))
        }
        try write(recentExercises, to: recentExercisesURL)
    }

    func fetchRecentExercises(limit: Int) throws -> [ExerciseLibraryItem] {
        try loadIfNeeded()
        guard !recentExercises.isEmpty else { return [] }

        let byID = Dictionary(
            exercises.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        // 已隐藏或已删除的条目不进最近使用
        let ordered = recentExercises
            .sorted { $0.usedAt > $1.usedAt }
            .compactMap { ref -> ExerciseLibraryItem? in
                guard let item = byID[ref.id], !item.isHidden else { return nil }
                return item
            }

        guard limit > 0 else { return ordered }
        return Array(ordered.prefix(limit))
    }

    func clearRecentExercises() throws {
        try loadIfNeeded()
        guard !recentExercises.isEmpty else { return }
        recentExercises = []
        try write(recentExercises, to: recentExercisesURL)
    }

    // MARK: - 身体数据

    func fetchBodyMeasurements(limit: Int) throws -> [BodyMeasurement] {
        try loadIfNeeded()
        let sorted = measurements.sorted { $0.date > $1.date }
        guard limit > 0 else { return sorted }
        return Array(sorted.prefix(limit))
    }

    func save(measurement: BodyMeasurement) throws {
        try loadIfNeeded()
        let calendar = Calendar.current
        // 本地自然日为唯一键：同一天只保留一条。保存前先剔除同一自然日上的
        // 其他记录，再处理同 id 覆盖——否则同一天会出现多条记录，
        // 趋势图横轴就会在同一个日期上出现两个点，产生歧义（页面 12 契约）。
        measurements.removeAll {
            $0.id != measurement.id && calendar.isDate($0.date, inSameDayAs: measurement.date)
        }
        if let index = measurements.firstIndex(where: { $0.id == measurement.id }) {
            measurements[index] = measurement
        } else {
            measurements.append(measurement)
        }
        try write(measurements, to: measurementsURL)
    }

    func delete(measurementID: UUID) throws {
        try loadIfNeeded()
        guard measurements.contains(where: { $0.id == measurementID }) else { return }
        measurements.removeAll { $0.id == measurementID }
        try write(measurements, to: measurementsURL)
    }

    // MARK: - 个人资料

    func fetchProfile() throws -> UserProfile? {
        try loadIfNeeded()
        return profile
    }

    func save(profile newProfile: UserProfile) throws {
        try loadIfNeeded()
        profile = newProfile
        try write(newProfile, to: profileURL)
    }

    // MARK: - 休息日

    func fetchRestDays() throws -> [RestDay] {
        try loadIfNeeded()
        return restDays.sorted { $0.date > $1.date }
    }

    func save(restDay: RestDay) throws {
        try loadIfNeeded()
        let calendar = Calendar.current
        // 同一天只留一条：先按自然日剔除旧记录，再处理同 id 覆盖
        restDays.removeAll {
            $0.id != restDay.id && calendar.isDate($0.date, inSameDayAs: restDay.date)
        }
        if let index = restDays.firstIndex(where: { $0.id == restDay.id }) {
            restDays[index] = restDay
        } else {
            restDays.append(restDay)
        }
        try write(restDays, to: restDaysURL)
    }

    func delete(restDayID: UUID) throws {
        try loadIfNeeded()
        guard restDays.contains(where: { $0.id == restDayID }) else { return }
        restDays.removeAll { $0.id == restDayID }
        try write(restDays, to: restDaysURL)
    }

    // MARK: - 有氧模板（页面 32）

    func fetchCardioTemplates() throws -> [CardioTemplate] {
        try loadIfNeeded()
        return cardioTemplates.sorted { $0.createdAt > $1.createdAt }
    }

    func save(cardioTemplate: CardioTemplate) throws {
        try loadIfNeeded()
        if let index = cardioTemplates.firstIndex(where: { $0.id == cardioTemplate.id }) {
            cardioTemplates[index] = cardioTemplate
        } else {
            cardioTemplates.append(cardioTemplate)
        }
        try write(cardioTemplates, to: cardioTemplatesURL)
    }

    func delete(cardioTemplateID: UUID) throws {
        try loadIfNeeded()
        guard cardioTemplates.contains(where: { $0.id == cardioTemplateID }) else { return }
        cardioTemplates.removeAll { $0.id == cardioTemplateID }
        try write(cardioTemplates, to: cardioTemplatesURL)
    }

    // MARK: - 数据管理（页面 10）

    func replaceAllSessions(_ records: [WorkoutSession]) throws {
        try loadIfNeeded()
        sessions = records
        try write(sessions, to: sessionsURL)
    }

    func replaceAllRestDays(_ records: [RestDay]) throws {
        try loadIfNeeded()
        restDays = records
        try write(restDays, to: restDaysURL)
    }

    func replaceAllPlans(_ records: [Plan]) throws {
        try loadIfNeeded()
        plans = records
        try write(plans, to: plansURL)
    }

    func replaceAllMeasurements(_ records: [BodyMeasurement]) throws {
        try loadIfNeeded()
        measurements = records
        try write(measurements, to: measurementsURL)
    }

    func replaceAllExercises(_ records: [ExerciseLibraryItem]) throws {
        try loadIfNeeded()
        exercises = records
        try write(exercises, to: exercisesURL)
    }

    /// 只清除训练记录与休息日标记。
    ///
    /// 刻意逐项列出要清的东西，而不是复制 `deleteAllData()` 再删几行 ——
    /// 那样将来给 `deleteAllData()` 加一个集合，这里会不知不觉跟着清掉，
    /// 而规格明确要求动作库与设置不受影响。逐项列写让「清什么」一眼可查。
    func clearWorkoutRecords() throws {
        try loadIfNeeded()

        sessions = []
        restDays = []
        restTimer = nil

        try write(sessions, to: sessionsURL)
        try write(restDays, to: restDaysURL)
        // 休息状态是单文件，清空时把文件一并删掉，
        // 否则下次启动会从旧文件里恢复出一个早已过期的倒计时。
        if fileManager.fileExists(atPath: restTimerURL.path) {
            try? fileManager.removeItem(at: restTimerURL)
        }
        // 注意这里没有触碰：plans / exercises / measurements /
        // recentExercises / isExerciseSeeded
    }

    // MARK: - 维护

    /// 当前数据目录，供「我的」页展示或整库导出
    var storageDirectory: URL { directory }

    /// 清空全部本地数据
    func deleteAllData() throws {
        try ensureDirectory()
        plans = []; sessions = []; exercises = []; measurements = []
        recentExercises = []; restDays = []
        restTimer = nil
        profile = nil
        isExerciseSeeded = false
        try write(plans, to: plansURL)
        try write(sessions, to: sessionsURL)
        try write(exercises, to: exercisesURL)
        try write(measurements, to: measurementsURL)
        try write(recentExercises, to: recentExercisesURL)
        try write(restDays, to: restDaysURL)
        // 休息状态是单文件，清空时把文件一并删掉，避免下次启动又恢复出旧倒计时
        if fileManager.fileExists(atPath: restTimerURL.path) {
            try? fileManager.removeItem(at: restTimerURL)
        }
        // 个人资料也是单文件，同样删掉
        if fileManager.fileExists(atPath: profileURL.path) {
            try? fileManager.removeItem(at: profileURL)
        }
        // 本地头像文件一并清除（本地媒体）
        let avatarDir = directory.appendingPathComponent("avatars", isDirectory: true)
        if fileManager.fileExists(atPath: avatarDir.path) {
            try? fileManager.removeItem(at: avatarDir)
        }
    }

    // MARK: - 本地数据管理（页面 18）

    func deleteAllPlans() throws {
        try loadIfNeeded()
        plans = []
        try write(plans, to: plansURL)
    }

    func deleteAllMeasurements() throws {
        try loadIfNeeded()
        measurements = []
        try write(measurements, to: measurementsURL)
    }

    /// 估算本地数据目录占用。只算文件大小。
    func localDataSizeBytes() throws -> Int64 {
        try loadIfNeeded()
        return Self.directorySize(at: directory, fileManager: fileManager)
    }

    private static func directorySize(at url: URL, fileManager: FileManager) -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// 清理未使用的本地媒体（孤儿头像文件），返回清理的文件数。
    @discardableResult
    func clearUnusedMediaCache() throws -> Int {
        try loadIfNeeded()
        let kept = profile?.avatarFileName
        let avatarDir = directory.appendingPathComponent("avatars", isDirectory: true)
        guard fileManager.fileExists(atPath: avatarDir.path) else { return 0 }
        guard let files = try? fileManager.contentsOfDirectory(at: avatarDir, includingPropertiesForKeys: nil) else {
            return 0
        }
        var removed = 0
        for file in files where file.lastPathComponent != kept {
            do {
                try fileManager.removeItem(at: file)
                removed += 1
            } catch {
                // 单个文件失败不阻断整体清理
            }
        }
        return removed
    }
}

// MARK: - 种子解码结构

/// 对应 Resources/exerciseLibrary.seed.json 的结构。
/// 所有字段都用 `try?` 兜底，避免单条脏数据导致整库导入失败。
struct ExerciseSeed: Codable {
    var id: String
    var name: String
    var category: String
    var categoryZh: String
    var equipment: String
    var equipmentZh: String
    var target: String
    var muscleGroup: String
    var secondaryMuscles: [String]
    var instructionsZh: String
    var stepsZh: [String]
    var image: String
    var gifUrl: String
    var attribution: String
    var mediaId: String

    private enum CodingKeys: String, CodingKey {
        case id, name, category, categoryZh, equipment, equipmentZh
        case target, muscleGroup, secondaryMuscles, instructionsZh, stepsZh
        case image, gifUrl, attribution, mediaId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        category = (try? c.decode(String.self, forKey: .category)) ?? ""
        categoryZh = (try? c.decode(String.self, forKey: .categoryZh)) ?? ""
        equipment = (try? c.decode(String.self, forKey: .equipment)) ?? ""
        equipmentZh = (try? c.decode(String.self, forKey: .equipmentZh)) ?? ""
        target = (try? c.decode(String.self, forKey: .target)) ?? ""
        muscleGroup = (try? c.decode(String.self, forKey: .muscleGroup)) ?? ""
        secondaryMuscles = (try? c.decode([String].self, forKey: .secondaryMuscles)) ?? []
        instructionsZh = (try? c.decode(String.self, forKey: .instructionsZh)) ?? ""
        stepsZh = (try? c.decode([String].self, forKey: .stepsZh)) ?? []
        image = (try? c.decode(String.self, forKey: .image)) ?? ""
        gifUrl = (try? c.decode(String.self, forKey: .gifUrl)) ?? ""
        attribution = (try? c.decode(String.self, forKey: .attribution))
            ?? "© Gym visual — https://gymvisual.com/"
        mediaId = (try? c.decode(String.self, forKey: .mediaId)) ?? ""
    }
}
