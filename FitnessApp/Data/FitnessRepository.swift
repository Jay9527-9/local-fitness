//
//  FitnessRepository.swift
//  数据层协议：首页等界面只依赖该协议，不直接接触存储实现。
//  这样可以注入内存桩做预览与单元测试，也便于将来替换持久化方案。
//

import Foundation

/// 所有方法均为同步抛出，具体实现内部负责落盘。
/// 标注 @MainActor 是因为实现持有可变缓存且非线程安全，UI 调用也在主线程。
@MainActor
protocol FitnessRepository {

    // MARK: - 计划

    /// 读取全部计划，按更新时间倒序
    func fetchPlans() throws -> [Plan]

    /// 按 id 读取单个计划
    func fetchPlan(id: UUID) throws -> Plan?

    /// 新增或更新计划
    func save(plan: Plan) throws

    /// 删除计划
    func delete(planID: UUID) throws

    /// 批量删除计划（页面 15 多选模式）。
    /// 只动 `plans.json`，不触碰 `sessions.json`——历史训练记录不受影响。
    func deletePlans(ids: [UUID]) throws

    /// 复制计划，返回新计划
    func duplicate(planID: UUID) throws -> Plan?

    /// 往计划末尾追加一个动作条目，返回追加后的条目。
    /// 计划不存在时返回 nil，由调用方决定如何提示。
    @discardableResult
    func appendExercise(
        _ entry: PlanExercise,
        toPlan planID: UUID
    ) throws -> PlanExercise?

    /// 新建一个空计划并返回，供「新建力量训练并添加」使用
    @discardableResult
    func createPlan(name: String, trainingDays: [Int]) throws -> Plan

    // MARK: - 计划内的动作条目（计划详情页）

    /// 计划详情页里改了单个动作的组数 / 次数 / 休息 / 备注等，只更新该条目。
    /// 找不到计划或条目时返回 nil，由调用方决定提示。
    @discardableResult
    func updatePlanExercise(
        _ entry: PlanExercise,
        inPlan planID: UUID
    ) throws -> PlanExercise?

    /// 拖拽排序后一次性写入新顺序，避免逐条保存产生中间态。
    /// `orderedIDs` 必须能覆盖计划内全部条目，否则忽略返回 nil。
    @discardableResult
    func reorderPlanExercises(
        inPlan planID: UUID,
        orderedIDs: [UUID]
    ) throws -> Plan?

    /// 从计划里移除一个动作。移除计划内的配置，不影响动作库本体，也不影响历史训练记录。
    @discardableResult
    func removePlanExercise(
        _ entryID: UUID,
        fromPlan planID: UUID
    ) throws -> Plan?

    /// 在计划内复制一份动作配置，插入到原条目下方，返回新条目。
    @discardableResult
    func duplicatePlanExercise(
        _ entryID: UUID,
        inPlan planID: UUID
    ) throws -> PlanExercise?

    /// 替换计划内某个动作指向的动作库条目，保留组数 / 次数 / 休息等配置。
    @discardableResult
    func replacePlanExercise(
        _ entryID: UUID,
        inPlan planID: UUID,
        withExerciseID exerciseID: String
    ) throws -> PlanExercise?

    /// 批量覆盖整个计划。计划详情页的「编辑训练日」等整体改动走这里，
    /// 便于实现层统一做排序与时间戳维护。
    @discardableResult
    func replace(plan: Plan) throws -> Plan?

    // MARK: - 训练记录

    /// 读取最近的训练记录
    func fetchRecentSessions(limit: Int) throws -> [WorkoutSession]

    /// 按 id 读取训练记录
    func fetchSession(id: UUID) throws -> WorkoutSession?

    /// 读取尚未结束的训练，用于「继续训练」
    func fetchActiveSession() throws -> WorkoutSession?

    /// 新增或更新训练记录
    func save(session: WorkoutSession) throws

    /// 删除训练记录
    func delete(sessionID: UUID) throws

    /// 往未结束的训练里追加一组，返回追加后的记录。
    /// 没有进行中的训练时返回 nil。
    @discardableResult
    func appendEntryToActiveSession(_ entry: SetEntry) throws -> WorkoutSession?

    // MARK: - 训练执行页的实时草稿写入

    /// 用整份会话覆盖存储中的同 id 记录。
    ///
    /// 训练执行页每次完成组、改重量次数、增删组、改备注都调它，一次原子落盘，
    /// 保证 App 被终止或最小化后重启还能恢复未结束训练。
    /// 会话不存在时按新增处理并返回写入后的记录。
    @discardableResult
    func updateSessionDraft(_ session: WorkoutSession) throws -> WorkoutSession?

    /// 把某一组标记为完成或撤销完成，返回更新后的会话。
    /// `completedAt` 传 nil 表示撤销。
    @discardableResult
    func markSetCompleted(
        sessionID: UUID,
        entryID: UUID,
        completedAt: Date?
    ) throws -> WorkoutSession?

    /// 修改某一组的重量与次数，返回更新后的会话。
    @discardableResult
    func updateSetEntry(
        sessionID: UUID,
        entryID: UUID,
        weight: Double,
        reps: Int
    ) throws -> WorkoutSession?

    /// 在指定动作末尾插入一组，数值复制该动作最后一组；没有历史组时用给定的默认值。
    /// 返回新插入的那一组。
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
    ) throws -> SetEntry?

    /// 删除某一组，并把同一动作后面的组号顺次前移。
    @discardableResult
    func removeSetEntry(
        sessionID: UUID,
        entryID: UUID
    ) throws -> WorkoutSession?

    /// 替换某个动作在当前训练里指向的动作库条目。
    ///
    /// 已完成的组保持原有 exerciseID 不动，只把未完成的组的 exerciseID 换成新动作，
    /// 这样「替换动作保留已完成组记录」成立。
    @discardableResult
    func replaceExerciseInSession(
        sessionID: UUID,
        fromExerciseID: String,
        toExerciseID: String
    ) throws -> WorkoutSession?

    /// 修改训练备注
    @discardableResult
    func updateSessionNote(
        sessionID: UUID,
        note: String?
    ) throws -> WorkoutSession?

    /// 结束训练：写入 endedAt 并把进行中状态清掉。已经是结束状态时直接返回原记录。
    @discardableResult
    func finishSession(
        sessionID: UUID,
        endedAt: Date,
        note: String?
    ) throws -> WorkoutSession?

    // MARK: - 组间休息状态

    /// 读取当前未结束的组间休息快照。没有休息在进行时返回 nil。
    ///
    /// 只存一条：全局同时只可能有一次组间休息。
    /// 剩余时间不落盘为「已递减的秒数」，而是靠 `startedAt` + `durationSeconds`
    /// 在读取时现算，这样 App 被最小化或杀掉重启后剩余值依然正确。
    func fetchRestTimer() throws -> RestTimerRecord?

    /// 写入或覆盖当前组间休息快照。完成一组、暂停、继续、加减时间都走这里。
    func save(restTimer: RestTimerRecord) throws

    /// 清除组间休息状态。倒计时结束、用户跳过、或训练结束时调用。
    func clearRestTimer() throws

    // MARK: - 动作库

    /// 读取全部动作。`includeHidden == false` 时不含已隐藏条目。
    func fetchExercises(includeHidden: Bool) throws -> [ExerciseLibraryItem]

    /// 按 id 集合批量读取动作
    func fetchExercises(ids: [String]) throws -> [ExerciseLibraryItem]

    /// 新增或更新一条动作。可用于新建自定义动作，也可用于切换收藏 / 隐藏。
    func save(exercise: ExerciseLibraryItem) throws

    /// 删除一条动作。仅允许删除自定义动作，导入数据抛错。
    func deleteExercise(id: String) throws

    /// 切换收藏状态，返回切换后的值
    @discardableResult
    func toggleFavorite(exerciseID: String) throws -> Bool

    /// 切换隐藏状态，返回切换后的值
    @discardableResult
    func toggleHidden(exerciseID: String) throws -> Bool

    /// 首次启动时导入动作库种子数据，返回导入条数
    @discardableResult
    func seedExerciseLibraryIfNeeded() throws -> Int

    /// 把一个导入动作复制成用户自己的自定义动作，返回新条目。
    /// 原动作保持不动；新条目 id 形如 `custom-<UUID>`，携带同一套说明与媒体引用。
    @discardableResult
    func copyAsCustomExercise(id: String) throws -> ExerciseLibraryItem?

    // MARK: - 最近使用的动作

    /// 记录一次动作使用。同一动作重复使用时只更新时间，不产生重复条目。
    func recordExerciseUsage(id: String) throws

    /// 读取最近使用的动作，按时间倒序
    func fetchRecentExercises(limit: Int) throws -> [ExerciseLibraryItem]

    /// 清空最近使用记录
    func clearRecentExercises() throws

    // MARK: - 身体数据

    func fetchBodyMeasurements(limit: Int) throws -> [BodyMeasurement]
    func save(measurement: BodyMeasurement) throws
    func delete(measurementID: UUID) throws

    // MARK: - 个人资料（页面 13）

    /// 读取本地个人资料。尚未创建时返回 nil，由调用方决定是否新建。
    func fetchProfile() throws -> UserProfile?

    /// 写入或覆盖个人资料。
    func save(profile: UserProfile) throws

    // MARK: - 休息日

    /// 读取全部休息日，按日期倒序
    func fetchRestDays() throws -> [RestDay]

    /// 新增或更新一个休息日。
    ///
    /// 同一天只保留一条：保存前会先移除同一自然日上的旧记录，
    /// 这样长按日期重复标记不会堆出多条，日历上的灰色点也不会重复。
    func save(restDay: RestDay) throws

    /// 删除休息日
    func delete(restDayID: UUID) throws

    // MARK: - 有氧模板（页面 32）

    /// 读取全部本地有氧模板，按创建时间倒序
    func fetchCardioTemplates() throws -> [CardioTemplate]

    /// 新增一个本地有氧模板
    func save(cardioTemplate: CardioTemplate) throws

    /// 删除有氧模板
    func delete(cardioTemplateID: UUID) throws

    // MARK: - 数据管理（页面 10）

    /// 批量写入训练记录。导入备份用。
    ///
    /// 传的是**合并后的完整集合**而不是增量：合并逻辑在纯值层算好，
    /// 仓储只负责落盘，这样「哪些该覆盖、哪些该跳过」的规则
    /// 能被推演脚本完整验证，不必依赖实现层的判断。
    func replaceAllSessions(_ sessions: [WorkoutSession]) throws

    /// 批量写入休息日标记。导入备份时的同理。
    func replaceAllRestDays(_ restDays: [RestDay]) throws

    /// 批量写入全部计划。页面 18 完整备份导入用。
    func replaceAllPlans(_ plans: [Plan]) throws

    /// 批量写入全部身体数据。页面 18 完整备份导入用。
    func replaceAllMeasurements(_ measurements: [BodyMeasurement]) throws

    /// 批量写入整个动作库。页面 20 导入备份时整库原子落盘，
    /// 也是「保护备份回滚」恢复动作库的手段。
    func replaceAllExercises(_ exercises: [ExerciseLibraryItem]) throws

    /// 只清除训练记录与休息日标记，**不动动作库、计划、身体数据与偏好**。
    ///
    /// 与 `deleteAllData()` 的区别是范围：后者是整库重置（含动作库），
    /// 只在「我的」页做彻底的本地数据清空时才用。
    /// 页面 10 的「清除全部训练记录」必须用这一个，规格明确要求
    /// 不得删除动作库与 App 设置。
    func clearWorkoutRecords() throws

    // MARK: - 本地数据管理（页面 18）

    /// 删除全部个人计划。保留历史训练记录与动作库。
    func deleteAllPlans() throws

    /// 删除全部身体数据。
    func deleteAllMeasurements() throws

    /// 清空全部本地数据（训练 / 计划 / 动作库 / 身体数据 / 最近使用 / 休息日 / 个人资料 / 本地媒体）。
    /// 页面 18「清除全部本地数据」用；偏好的清理由调用方通过 `ProfileSettings.resetAll()` 完成。
    func deleteAllData() throws

    /// 重新导入动作库种子，返回新增条数。保留自定义动作与已有的收藏 / 隐藏状态。
    @discardableResult
    func reseedExerciseLibrary() throws -> Int

    /// 估算本地数据目录占用（字节）。用于「本地数据管理」概览卡。
    func localDataSizeBytes() throws -> Int64

    /// 清理未使用的本地媒体（孤儿头像文件等），返回清理的文件数。
    @discardableResult
    func clearUnusedMediaCache() throws -> Int
}

// MARK: - 便捷扩展

extension FitnessRepository {
    /// 读取全部计划时常用的无参重载
    func fetchRecentSessions() throws -> [WorkoutSession] {
        try fetchRecentSessions(limit: 20)
    }

    /// 当前是否已有训练计划
    func hasAnyPlan() throws -> Bool {
        try !fetchPlans().isEmpty
    }

    /// 默认不返回隐藏条目
    func fetchExercises() throws -> [ExerciseLibraryItem] {
        try fetchExercises(includeHidden: false)
    }

    /// 最近使用的动作默认数量
    func fetchRecentExercises() throws -> [ExerciseLibraryItem] {
        try fetchRecentExercises(limit: 6)
    }

    /// 某个自然日是否已标记为休息日
    func isRestDay(_ date: Date, calendar: Calendar = .current) throws -> Bool {
        try fetchRestDays().contains { calendar.isDate($0.date, inSameDayAs: date) }
    }
}
