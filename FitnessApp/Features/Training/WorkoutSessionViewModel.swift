//
//  WorkoutSessionViewModel.swift
//  训练执行页的状态机。
//
//  三条硬要求决定了这里的结构：
//  1. 草稿必须实时落盘 —— 每一处改动都立刻整份写入仓储，不做批量或延迟合并；
//  2. 计时器要持续运行 —— 用 startedAt 计算而不是累加秒数，这样最小化、
//     切后台、甚至 App 被终止后重启，时长都自动是对的；
//  3. 动作卡要显示「上一训练记录摘要」—— 需要额外查一次历史会话。
//

import AudioToolbox
import Foundation
import SwiftUI

@MainActor
final class WorkoutSessionViewModel: ObservableObject {

    // MARK: - 载入状态

    enum LoadState {
        case loading
        case loaded
        /// 会话不存在（例如已从历史里删除）
        case missing
        case failed(String)
    }

    // MARK: - 动作卡模型

    /// 执行页里的一张动作卡。由会话记录 + 动作库条目 + 历史记录拼出来。
    struct ExerciseCard: Identifiable {

        /// 动作在当前训练里指向的动作库 id。替换动作后这个值会变。
        var exerciseID: String
        /// 组表数据源，按组号升序
        var entries: [SetEntry]
        /// 动作库条目。动作已被删除时为 nil，卡片退化为只显示 id。
        var item: ExerciseLibraryItem?
        /// 计划内的配置条目，自由训练为 nil
        var planEntry: PlanExercise?
        /// 上一次训练里同一动作的记录摘要
        var lastTimeSummary: String?

        /// 卡片身份用动作 id + 计划条目 id。
        /// 同一个动作在一次训练里重复出现（超级组、补练）时不会撞在一起。
        var id: String {
            "\(exerciseID)#\(planEntry?.id.uuidString ?? "-")"
        }

        var name: String {
            item?.name ?? planEntry?.exerciseID ?? exerciseID
        }

        var muscleText: String {
            item?.target ?? ""
        }

        /// 已完成 / 总组数
        var completedCount: Int { entries.filter { $0.isCompleted }.count }
        var totalCount: Int { entries.count }
        var isAllCompleted: Bool { totalCount > 0 && completedCount == totalCount }

        /// 卡片内的完成进度，0…1
        var progress: Double {
            guard totalCount > 0 else { return 0 }
            return Double(completedCount) / Double(totalCount)
        }

        /// 计划目标次数，用于「新增一组」没有模板时的兜底
        var targetRepsLow: Int { entries.first?.targetRepsLow ?? planEntry?.repsLow ?? 8 }
        var targetRepsHigh: Int { entries.first?.targetRepsHigh ?? planEntry?.repsHigh ?? 12 }
        var isWarmup: Bool { planEntry?.isWarmup ?? entries.first?.isWarmup ?? false }
        var restSeconds: Int { planEntry?.restSeconds ?? 90 }

        /// 卡片副标题：计划配置或组数概览
        var configText: String {
            guard let planEntry else {
                return "\(totalCount) 组"
            }
            var parts = [planEntry.volumeText]
            if planEntry.restSeconds > 0 {
                parts.append("休息 \(FormatterKit.rest(seconds: planEntry.restSeconds))")
            }
            return parts.joined(separator: " · ")
        }

        /// 已完成组里的最大重量，用于「上一组 xx kg」这类提示
        var lastCompletedWeight: Double? {
            entries.last { $0.isCompleted }?.weight
        }
    }

    // MARK: - 休息计时状态

    /// 组间休息倒计时的视图状态。
    ///
    /// 秒数不在这里逐秒递减，而是每次求值时用 `record.startedAt` 现算——
    /// 这正是「切后台 / 被杀掉重启后剩余时间依然正确」的实现方式。
    /// `record` 会被原样落盘到 `restTimer.json`，所以它自身就够恢复。
    struct RestTimer {
        /// 持久化快照
        var record: RestTimerRecord
        /// 面板是否可见。用户点关闭或跳过时置 false。
        ///
        /// 注意：`isPresented == false` **不代表休息结束**。
        /// 关闭只收起面板，倒计时照走，再次进入执行页时接着显示剩余时间。
        var isPresented: Bool
        /// 本次求值时刻，由面板每秒刷新时传入，保证同一帧内所有数字一致
        var now: Date
        /// 归零反馈是否已经发过。防止每秒 tick 重复播提示音。
        var isFinishedAlertSent: Bool = false

        var remainingSeconds: Int { record.remainingSeconds(at: now) }
        var durationSeconds: Int { record.durationSeconds }
        var isPaused: Bool { record.isPaused }
        var exerciseName: String { record.exerciseName }
        var progress: Double { record.progress(at: now) }
        var isFinished: Bool { remainingSeconds <= 0 }

        /// 最后 10 秒改用荧光绿强调
        var isFinalCountdown: Bool { remainingSeconds <= 10 && remainingSeconds > 0 }
        /// 最后 3 秒做轻微缩放提示
        var isFinalPulse: Bool { remainingSeconds <= 3 && remainingSeconds > 0 }

        /// 面板标题：暂停优先，其次结束
        var statusText: String {
            if isFinished { return "休息结束" }
            if isPaused { return "已暂停" }
            return "组间休息"
        }
    }

    /// 从「更多」菜单里触发的动作卡操作
    enum CardAction {
        case editConfig
        case replace
        case note
        case delete
    }

    // MARK: - 输出属性

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var cards: [ExerciseCard] = []

    /// 休息倒计时。为 nil 表示当前没有休息。
    @Published var restTimer: RestTimer?

    /// 休息刚结束、需要提示「休息结束，开始下一组」。
    /// 与 `restTimer` 分开存：状态清掉之后提示还要在页面上留一会。
    @Published private(set) var pendingRestAttention = false

    /// 组表里正在编辑的单元格。同一时刻只允许编辑一个，避免多个键盘抢焦点。
    @Published var editingCell: SetEntryCell?

    /// 当前打开的动作卡菜单
    @Published var menuCardID: String?
    /// 当前打开只读说明抽屉的动作
    @Published var infoCard: ExerciseCard?
    /// 待删除二次确认的动作卡
    @Published var pendingDeleteCard: ExerciseCard?
    /// 完成确认抽屉
    @Published var isFinishDrawerPresented = false
    /// 完成抽屉里的备注草稿
    @Published var finishNote: String = ""
    /// 备注编辑抽屉
    @Published var noteCard: ExerciseCard?
    @Published var noteDraft: String = ""
    /// 提示条文案
    @Published var toast: String?

    /// 完成当前动作后自动定位下一动作（页面 14 训练偏好）。完成最后剩余组时置成
    /// 下一张未完成动作卡的 id，由页面层的 ScrollViewReader 消费后清空。
    @Published var advanceTargetID: String?

    /// 用户主动最小化时置 true，返回 App 后由页面复位
    @Published private(set) var isMinimized = false

    // MARK: - 依赖

    private let repository: FitnessRepository
    private let sessionID: UUID
    /// 动作库缓存，避免每次重算卡片都全量查询
    private var exerciseIndex: [String: ExerciseLibraryItem] = [:]
    /// 上一次训练的 entries，按动作 id 分组，用于生成摘要
    private var historyIndex: [String: [SetEntry]] = [:]
    private var timerCancellable: Any?

    // MARK: - 初始化

    init(repository: FitnessRepository, sessionID: UUID) {
        self.repository = repository
        self.sessionID = sessionID
    }

    // MARK: - 生命周期

    /// 首次进入时加载。已经加载过就只做一次轻量同步，
    /// 避免从配置子页返回时又走一遍骨架屏、丢掉滚动位置。
    func load() {
        guard case .loaded = state else { return loadFull() }
        refreshSession()
        restoreRestTimerIfNeeded()
        startTicking()
    }

    private func loadFull() {
        state = .loading
        do {
            guard let found = try repository.fetchSession(id: sessionID) else {
                state = .missing
                return
            }
            exerciseIndex = Dictionary(
                (try repository.fetchExercises(includeHidden: true)).map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            buildHistoryIndex(excludingSessionID: found.id)
            session = found
            finishNote = found.note ?? ""
            rebuildCards()
            state = .loaded
            restoreRestTimerIfNeeded()
            startTicking()
        } catch {
            state = .failed("训练记录读取失败：\(error.localizedDescription)")
        }
    }

    /// 从磁盘恢复组间休息状态。
    ///
    /// 三种情况要区分开：
    /// - 属于别的训练草稿 → 与本页无关，忽略（但不清盘，那个页面自己会读）；
    /// - 已经走完 → 直接清掉，不弹面板；
    /// - 还没走完 → 恢复出来并展开面板，剩余时间按 `startedAt` 现算，天然是准的。
    private func restoreRestTimerIfNeeded() {
        guard restTimer == nil else { return }
        guard let saved = try? repository.fetchRestTimer() else { return }
        guard saved.sessionID == sessionID else { return }

        if saved.isFinished(at: .now) {
            persistRestTimer(nil)
            return
        }
        // 训练已经结束了就别再恢复倒计时
        guard session?.isFinished != true else {
            persistRestTimer(nil)
            return
        }
        restTimer = RestTimer(record: saved, isPresented: true, now: .now)
    }

    func onDisappear() {
        stopTicking()
    }

    /// 最小化：只标记状态并停止秒表刷新，草稿早已落盘，无需额外保存。
    ///
    /// 页面 14 训练偏好「最小化训练后保留计时器」关闭时，连组间休息倒计时
    /// 也一并停掉（草稿仍保留），回到 App 后不再恢复出后台计时。
    func minimize() {
        isMinimized = true
        stopTicking()
        if !ProfileSettings.keepTimerOnMinimize {
            restTimer = nil
            persistRestTimer(nil)
            pendingRestAttention = false
            RestNotification.cancelPending()
        }
    }

    /// 返回前台时恢复。计时按 startedAt 计算，所以不需要补算任何东西。
    /// 训练已结束时不再启动秒表，否则结束后的页面还在空转。
    func resumeFromMinimize() {
        isMinimized = false
        refreshSession()
        guard session?.isFinished != true else { return }
        // 回到前台先按墙钟重算一次：后台期间可能已经走完了，
        // 这时要补上提示音和「休息结束」，而不是等到下一次 tick。
        handleTick()
        startTicking()
    }

    /// 重新从仓储读一次会话。用于从子页面（替换动作、配置编辑）返回后同步。
    ///
    /// 会对比记住的动作集合，发现「多了新动作 / 少了旧动作」时给出提示——
    /// 替换动作是在动作选择器里写库的，ViewModel 看不到操作本身，
    /// 只能靠这次对比把结果讲清楚。
    ///
    /// 注意：这里只同步动作的增删，不会按新的组数重新展开草稿。
    /// 已经开工的训练，组数由用户用「新增一组」自己加，
    /// 不会被计划改动偷偷改写已经完成或正在进行的组。
    func refreshSession() {
        guard let found = try? repository.fetchSession(id: sessionID) else { return }
        let before = Set(cards.map { $0.exerciseID })
        session = found
        rebuildCards()
        reportExerciseDiff(from: before)
    }

    /// 记住上一次的组表快照，用来判断是不是刚发生过替换
    private var pendingReplaceToast = false

    private func reportExerciseDiff(from before: Set<String>) {
        let after = Set(cards.map { $0.exerciseID })
        guard pendingReplaceToast else { return }
        pendingReplaceToast = false

        let added = after.subtracting(before)
        let removed = before.subtracting(after)
        guard !added.isEmpty, !removed.isEmpty else {
            if !added.isEmpty {
                showToast("已添加「\(name(for: added.first ?? ""))」")
            }
            return
        }
        let newName = name(for: added.first ?? "")
        showToast("已替换为「\(newName)」，已完成的组记录保留")
    }

    private func name(for exerciseID: String) -> String {
        exerciseIndex[exerciseID]?.name ?? exerciseID
    }

    /// 页面在打开动作选择器之前调用，标记下一次刷新要报告替换结果
    func willReplaceExercise() {
        pendingReplaceToast = true
    }

    // MARK: - 计时

    private func startTicking() {
        stopTicking()
        // 每秒一次。用 Timer.publish 会随视图重建丢失，这里用 Timer 实例自己持有。
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.handleTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timerCancellable = timer
    }

    private func stopTicking() {
        (timerCancellable as? Timer)?.invalidate()
        timerCancellable = nil
    }

    /// 每秒推进一次。
    ///
    /// 这里不做「递减」——只把求值时刻更新到当前，剩余秒数由 `startedAt` 推导。
    /// 好处有两个：切后台期间「什么都不会丢」（回来一算就是对的），
    /// 以及每秒只改 `now` 一个字段，不会触发已完成组的重绘。
    private func handleTick() {
        guard var timer = restTimer else { return }
        timer.now = .now
        // 归零检查必须放在这里而不是面板里：面板关掉时倒计时也在走，
        // 提示音和「休息结束」必须照样触发。
        if !timer.record.isPaused, timer.record.isFinished(at: timer.now) {
            restTimer = timer
            completeRest()
            scheduleRestPanelAutoDismiss()
            return
        }
        restTimer = timer
    }

    /// 倒计时结束后面板再停留一小会展示 0，然后自动收起。
    private func scheduleRestPanelAutoDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, let current = self.restTimer, current.isFinished else { return }
            withAnimation(DS.Motion.drawer) {
                self.restTimer = nil
            }
            self.pendingRestAttention = false
        }
    }

    /// 顶部计时器文案。按 startedAt 计算而非累加，切后台回来不会少算。
    var elapsedSeconds: Int {
        guard let session else { return 0 }
        let end = session.endedAt ?? .now
        return max(0, Int(end.timeIntervalSince(session.startedAt)))
    }

    /// 会话开始时间。头部时钟用它自己算秒数，不订阅任何 @Published。
    var sessionStartedAt: Date? { session?.startedAt }

    /// 训练是否已结束。结束后头部时钟停表。
    var isSessionFinished: Bool { session?.isFinished ?? false }

    var elapsedText: String { FormatterKit.stopwatch(seconds: elapsedSeconds) }

    // MARK: - 概览数字

    var completedExerciseCount: Int { session?.completedExerciseCount ?? 0 }
    var completedSetCount: Int { session?.completedSetCount ?? 0 }
    var totalVolume: Double { session?.totalVolume ?? 0 }
    var progress: Double { session?.progress ?? 0 }
    var isCardio: Bool { session?.kind == .cardio }
    var distanceMeters: Double { session?.distanceMeters ?? 0 }
    var kilocalories: Double { session?.kilocalories ?? 0 }

    var sessionName: String { session?.name ?? "训练" }

    /// 有氧训练的概览数字（时长 / 距离 / 消耗），力量训练返回空数组
    var cardioMetrics: [(title: String, value: String)] {
        guard isCardio else { return [] }
        return [
            ("时长", FormatterKit.stopwatch(seconds: elapsedSeconds)),
            ("距离", FormatterKit.distance(meters: distanceMeters)),
            ("消耗", FormatterKit.kilocalories(kilocalories))
        ]
    }

    /// 力量训练的概览数字（已完成动作 / 已完成组 / 总容量）
    ///
    /// 「显示训练容量」关闭时（页面 14 训练偏好）只给前两项，
    /// 但 `totalVolume` 照常由仓储计算，历史统计不受影响。
    var strengthMetrics: [(title: String, value: String)] {
        var metrics: [(title: String, value: String)] = [
            ("已完成动作", "\(completedExerciseCount)"),
            ("已完成组", "\(completedSetCount)"),
        ]
        if ProfileSettings.showVolume {
            metrics.append(("总训练容量", "\(Int(totalVolume.rounded())) kg"))
        }
        return metrics
    }

    // MARK: - 卡片构造

    private func rebuildCards() {
        guard let session else {
            cards = []
            return
        }
        cards = session.entriesByExercise.map { bucket in
            let planEntry = session.planID
                .flatMap { try? repository.fetchPlan(id: $0) }?
                .exercises
                .first { item in
                    bucket.entries.contains { $0.planEntryID == item.id }
                }
            return ExerciseCard(
                exerciseID: bucket.exerciseID,
                entries: bucket.entries,
                item: exerciseIndex[bucket.exerciseID],
                planEntry: planEntry,
                lastTimeSummary: historySummary(for: bucket.exerciseID)
            )
        }
    }

    /// 把除当前会话外的最近几次训练按动作归档，供摘要查询
    private func buildHistoryIndex(excludingSessionID: UUID) {
        historyIndex = [:]
        let recent = (try? repository.fetchRecentSessions(limit: 30)) ?? []
        for past in recent where past.id != excludingSessionID && past.isFinished {
            for entry in past.completedEntries where !entry.isWarmup {
                historyIndex[entry.exerciseID, default: []].append(entry)
            }
        }
    }

    /// 上一次训练记录摘要，如「上次 80 kg × 8 × 3 组」
    private func historySummary(for exerciseID: String) -> String? {
        guard let entries = historyIndex[exerciseID], !entries.isEmpty else { return nil }
        let topWeight = entries.map { $0.weight }.max() ?? 0
        let bestEntry = entries.last { $0.weight == topWeight } ?? entries[entries.count - 1]
        let count = entries.count
        if topWeight <= 0 {
            return "上次 \(bestEntry.reps) 次 × \(count) 组"
        }
        return "上次 \(FormatterKit.weight(topWeight)) × \(bestEntry.reps) 次 · \(count) 组"
    }

    /// 目标肌肉文案，卡片副标题用
    func muscleText(for item: ExerciseLibraryItem?) -> String {
        item?.target ?? ""
    }

    // MARK: - 组表交互

    /// 组表里正在编辑的单元格位置
    struct SetEntryCell: Equatable, Identifiable {
        var entryID: UUID
        var field: Field

        enum Field: String {
            case weight
            case reps
        }

        var id: String { "\(entryID)-\(field.rawValue)" }
    }

    /// 完成 / 撤销完成一组
    func toggleCompletion(card: ExerciseCard, entry: SetEntry) {
        let willComplete = !entry.isCompleted
        do {
            if let updated = try repository.markSetCompleted(
                sessionID: sessionID,
                entryID: entry.id,
                completedAt: willComplete ? .now : nil
            ) {
                session = updated
                rebuildCards()
            }
            if willComplete {
                Haptics.medium()
                // 完成一组后自动触发组间休息倒计时（页面 14 训练偏好可关）
                if ProfileSettings.autoStartRest {
                    startRest(card: card, seconds: card.restSeconds)
                }
                scheduleAdvanceIfNeeded(cardID: card.id)
            } else {
                Haptics.light()
                // 撤销完成时把休息停掉并清盘，避免这条状态下次启动又被恢复出来
                if restTimer != nil {
                    restTimer = nil
                    persistRestTimer(nil)
                    pendingRestAttention = false
                }
            }
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    /// 完成当前动作后自动定位下一动作（页面 14 训练偏好）。
    ///
    /// 只有当刚完成的那张卡**整卡完成**、且还有下一张未完成的卡时才置
    /// `advanceTargetID`。页面层的 ScrollViewReader 消费后会把值清空。
    private func scheduleAdvanceIfNeeded(cardID: String) {
        guard ProfileSettings.autoAdvanceExercise else { return }
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        // 刚完成的卡此刻必须已经是「全完成」状态，否则不推进
        guard cards[index].isAllCompleted else { return }
        // 找它之后第一张还没完成的卡；后面全完成则不动
        let remainder = cards[(index + 1)...]
        guard let next = remainder.first(where: { !$0.isAllCompleted }) else { return }
        advanceTargetID = next.id
    }

    /// 修改重量或次数
    func updateValue(card: ExerciseCard, entry: SetEntry, weight: Double? = nil, reps: Int? = nil) {
        do {
            if let updated = try repository.updateSetEntry(
                sessionID: sessionID,
                entryID: entry.id,
                weight: weight ?? entry.weight,
                reps: reps ?? entry.reps
            ) {
                session = updated
                rebuildCards()
            }
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    /// 新增一组：默认复制同一动作最后一组的数值（页面 14 训练偏好可关）
    func addSet(card: ExerciseCard) {
        // 「新增组时复制上一组数值」关闭时，重量从 0 起填，
        // 只保留计划目标次数，不继承上一组重量。
        let copiedWeight = ProfileSettings.copyPreviousSet
            ? (card.entries.last?.weight ?? 0)
            : 0
        do {
            if try repository.insertSetEntry(
                sessionID: sessionID,
                exerciseID: card.exerciseID,
                planEntryID: card.planEntry?.id,
                fallbackWeight: copiedWeight,
                fallbackReps: card.targetRepsLow,
                fallbackTargetLow: card.targetRepsLow,
                fallbackTargetHigh: card.targetRepsHigh,
                isWarmup: card.isWarmup
            ) != nil {
                refreshSession()
                Haptics.light()
            }
        } catch {
            showToast("新增失败：\(error.localizedDescription)")
        }
    }

    /// 删除一组。同一动作只剩一组时拒绝，避免动作卡消失。
    func removeSet(card: ExerciseCard, entry: SetEntry) {
        do {
            if let updated = try repository.removeSetEntry(
                sessionID: sessionID,
                entryID: entry.id
            ) {
                session = updated
                rebuildCards()
                Haptics.light()
            }
        } catch {
            showToast("删除失败：\(error.localizedDescription)")
        }
    }

    /// 该组能否删除：同一动作至少保留一组
    func canRemoveSet(card: ExerciseCard) -> Bool {
        card.totalCount > 1
    }

    /// 手动开启休息计时
    func startManualRest(card: ExerciseCard) {
        startRest(card: card, seconds: card.restSeconds)
    }

    // MARK: - 设为默认休息时间

    /// 当前休息是否关联到计划里的动作条目。自由训练没有计划，此时入口不可用。
    var canSetDefaultRest: Bool {
        restTimer?.record.planEntryID != nil && restTimer?.record.planID != nil
    }

    /// 面板上「设为默认休息时间」的回显值
    var currentDefaultRestSeconds: Int? {
        guard let record = restTimer?.record,
              let planID = record.planID,
              let entryID = record.planEntryID,
              let plan = try? repository.fetchPlan(id: planID),
              let entry = plan.exercises.first(where: { $0.id == entryID })
        else { return nil }
        return entry.restSeconds
    }

    /// 把某个秒数设为该动作在当前计划里的默认休息时间。
    ///
    /// 只改计划内这一条配置，**不回写动作库本体**——
    /// 同一个动作在不同计划里可以有完全不同的休息时长，动作库不该被单次训练改写。
    func setDefaultRest(seconds: Int) {
        guard let record = restTimer?.record,
              let planID = record.planID,
              let entryID = record.planEntryID
        else {
            showToast("自由训练没有计划，无法设为默认")
            return
        }
        do {
            guard let plan = try repository.fetchPlan(id: planID),
                  var entry = plan.exercises.first(where: { $0.id == entryID })
            else {
                showToast("计划条目已不存在")
                return
            }
            entry.restSeconds = max(5, seconds)
            if try repository.updatePlanExercise(entry, inPlan: planID) != nil {
                // 当前这次休息也顺手对齐到新时长，用户不用再手动加减
                if var timer = restTimer {
                    let now = Date()
                    timer.now = now
                    timer.record = timer.record.adjusting(
                        by: entry.restSeconds - timer.record.remainingSeconds(at: now),
                        at: now
                    )
                    restTimer = timer
                    persistRestTimer(timer.record)
                }
                Haptics.success()
                showToast("已将「\(record.exerciseName)」的默认休息设为 \(FormatterKit.rest(seconds: entry.restSeconds))")
            }
        } catch {
            showToast("保存失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 休息倒计时

    /// 开启一次组间休息。完成一组后自动触发，也可从卡片底部手动开启。
    ///
    /// 记录里带上 `planEntryID` / `planID`，是为了让面板上的
    /// 「设为默认休息时间」知道该回写到计划里的哪一条；自由训练没有计划，两者为 nil。
    private func startRest(card: ExerciseCard, seconds: Int) {
        let total = max(5, seconds)
        let record = RestTimerRecord(
            sessionID: sessionID,
            startedAt: .now,
            durationSeconds: total,
            isPaused: false,
            remainingSeconds: total,
            exerciseName: card.name,
            planEntryID: card.planEntry?.id,
            planID: session?.planID
        )
        restTimer = RestTimer(record: record, isPresented: true, now: .now)
        persistRestTimer(record)
        // 可选的本地通知：用户没开就什么都不做，开了就预约一条。
        // 前台运行时系统同样会展示，这对「手机放在架子上」的场景更实用。
        RestNotification.notifyRestFinished(
            after: TimeInterval(total),
            exerciseName: card.name
        )
    }

    /// 把快照写盘。失败不打断倒计时——休息状态丢了只影响恢复，不该影响当下这一组。
    private func persistRestTimer(_ record: RestTimerRecord?) {
        do {
            if let record {
                try repository.save(restTimer: record)
            } else {
                try repository.clearRestTimer()
            }
        } catch {
            // 静默：这是可恢复的临时状态，提示条反而干扰训练
        }
    }

    /// 刷新求值时刻。面板每秒调一次，让数字与进度环往前走。
    ///
    /// 刻意不做「递减」：只更新 `now`，剩余值由 `startedAt` 推导。
    /// 这样从后台回来时不需要补算任何丢失的秒数。
    func refreshRestClock(_ now: Date = .now) {
        guard var timer = restTimer else { return }
        timer.now = now
        restTimer = timer
    }

    /// 暂停 / 继续。暂停把剩余冻结进字段，继续把起点挪到现在。
    func toggleRestPause() {
        guard var timer = restTimer else { return }
        let now = Date()
        timer.now = now
        timer.record = timer.record.isPaused
            ? timer.record.resumed(at: now)
            : timer.record.paused(at: now)
        restTimer = timer
        persistRestTimer(timer.record)
        rescheduleRestNotification()
        Haptics.light()
    }

    /// 调整本次休息时间（−15 / +15 / +30）。
    func adjustRest(by delta: Int) {
        guard var timer = restTimer else { return }
        let now = Date()
        timer.now = now
        timer.record = timer.record.adjusting(by: delta, at: now)
        restTimer = timer
        persistRestTimer(timer.record)
        rescheduleRestNotification()
        Haptics.light()
    }

    /// 按当前剩余时间重排本地通知。
    ///
    /// 暂停/继续、加减时间都会改变剩余时长，通知的触发点必须跟着变，
    /// 否则会在错误的时间提醒。撤销旧的再排新的，避免留下多条。
    private func rescheduleRestNotification() {
        RestNotification.cancelPending()
        guard let timer = restTimer, !timer.isPaused, !timer.isFinished else { return }
        RestNotification.notifyRestFinished(
            after: TimeInterval(timer.remainingSeconds),
            exerciseName: timer.exerciseName
        )
    }

    /// 关闭面板。**只收起 UI，不停止倒计时**——
    /// 用户把面板关掉接着练，再次进入执行页时剩余时间照原样显示。
    func dismissRestPanel() {
        guard var timer = restTimer else { return }
        timer.isPresented = false
        restTimer = timer
        Haptics.light()
    }

    /// 重新展开面板（再次进入执行页，或用户手动点「休息计时」时调用）。
    func presentRestPanel() {
        guard var timer = restTimer else { return }
        timer.isPresented = true
        timer.now = .now
        restTimer = timer
    }

    /// 跳过休息：停止计时、关闭面板、清除持久化状态，焦点回到下一组。
    func skipRest() {
        skipRest(reason: .skipped)
    }

    private enum RestEndReason {
        case skipped
        case finished
    }

    private func skipRest(reason: RestEndReason) {
        restTimer = nil
        persistRestTimer(nil)
        pendingRestAttention = false
        RestNotification.cancelPending()
        Haptics.light()
    }

    /// 倒计时归零。播放提示音 + 触感，显示「休息结束，开始下一组」，
    /// 并把持久化状态清掉；面板再停留一小会展示 0 之后自动收起。
    private func completeRest() {
        guard var timer = restTimer, !timer.isFinishedAlertSent else { return }
        timer.isFinishedAlertSent = true
        timer.now = .now
        restTimer = timer
        // 结束后立刻清除状态：App 此时被切到后台也不会再恢复出一次已完成的休息
        persistRestTimer(nil)
        // 通知由系统在触发后自动消失，这里撤掉的是「还没到点」的那条，
        // 避免用户手动停表后还收到一条迟到提醒。
        RestNotification.cancelPending()
        playRestFinishedFeedback()
        pendingRestAttention = true
    }

    private func playRestFinishedFeedback() {
        Haptics.success()
        RestAlertSound.play()
    }

    /// 休息结束的本地提示音。题目要求「播放 App 包内短提示音」，
    /// 系统音随 iOS 自带，不引入任何第三方音频文件。
    ///
    /// 页面 13 起受全局开关 `ProfileSettings.soundEnabled` 控制，
    /// 「我的 → 应用设置 → 声音」关闭后这里静默返回。
    private enum RestAlertSound {
        static func play() {
            guard ProfileSettings.soundEnabled else { return }
            AudioServicesPlaySystemSound(1057)
        }
    }

    // MARK: - 动作卡菜单

    func perform(_ action: CardAction, on card: ExerciseCard) {
        switch action {
        case .editConfig:
            menuCardID = nil
            // 页面层通过 onEditConfig 回调跳转到计划内的动作配置页
            onEditConfig?(card)
        case .replace:
            menuCardID = nil
            onReplaceExercise?(card)
        case .note:
            menuCardID = nil
            noteCard = card
            noteDraft = session?.note ?? ""
        case .delete:
            menuCardID = nil
            pendingDeleteCard = card
        }
    }

    /// 删除动作卡：把该动作的全部组从当前训练里移除。
    /// 只动当前草稿，不影响计划配置，也不影响历史记录。
    func confirmDeleteCard(_ card: ExerciseCard) {
        guard var updated = session else { return }
        updated.entries.removeAll { $0.exerciseID == card.exerciseID }
        do {
            if let saved = try repository.updateSessionDraft(updated) {
                session = saved
                rebuildCards()
                Haptics.warning()
                showToast("已删除「\(card.name)」")
            }
        } catch {
            showToast("删除失败：\(error.localizedDescription)")
        }
    }

    /// 保存动作卡备注。备注写在会话上，不写回计划。
    func saveNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let updated = try repository.updateSessionNote(
                sessionID: sessionID,
                note: trimmed.isEmpty ? nil : trimmed
            ) {
                session = updated
                finishNote = updated.note ?? ""
                noteCard = nil
                Haptics.success()
            }
        } catch {
            showToast("备注保存失败：\(error.localizedDescription)")
        }
    }

    // MARK: - 页面回调

    /// 「编辑动作配置」跳转到计划内的配置页；自由训练没有计划，页面改为提示。
    var onEditConfig: ((ExerciseCard) -> Void)?
    /// 「替换动作」打开动作选择器
    var onReplaceExercise: ((ExerciseCard) -> Void)?

    // MARK: - 结束训练

    /// 打开完成确认抽屉，把当前备注带上
    func presentFinishDrawer() {
        finishNote = session?.note ?? ""
        isFinishDrawerPresented = true
        Haptics.light()
    }

    /// 确认完成：写入 endedAt、停表、返回写入后的会话供页面跳转总结页。
    func confirmFinish() -> WorkoutSession? {
        let trimmed = finishNote.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            guard let finished = try repository.finishSession(
                sessionID: sessionID,
                endedAt: .now,
                note: trimmed.isEmpty ? nil : trimmed
            ) else {
                showToast("训练记录不存在，无法完成")
                return nil
            }
            session = finished
            isFinishDrawerPresented = false
            restTimer = nil
            pendingRestAttention = false
            persistRestTimer(nil)
            RestNotification.cancelPending()
            stopTicking()
            Haptics.success()
            return finished
        } catch {
            showToast("完成失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - 提示条

    func showToast(_ message: String) {
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self, self.toast == message else { return }
            self.toast = nil
        }
    }

    // MARK: - 无障碍

    /// 概览区整体的可访问文案
    var accessibilityOverview: String {
        if isCardio {
            return "有氧训练，时长 \(FormatterKit.stopwatch(seconds: elapsedSeconds))，"
                + "距离 \(FormatterKit.distance(meters: distanceMeters))，"
                + "消耗 \(FormatterKit.kilocalories(kilocalories))"
        }
        var parts = [
            "已完成 \(completedExerciseCount) 个动作，\(completedSetCount) 组",
        ]
        if ProfileSettings.showVolume {
            parts.append("总训练容量 \(Int(totalVolume.rounded())) 公斤")
        }
        return parts.joined(separator: "，")
    }
}
