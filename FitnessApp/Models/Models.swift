//
//  Models.swift
//  领域模型：全部 Codable，纯本地存储，无任何网络或账号字段。
//

import Foundation

// MARK: - 训练计划

/// 一个训练计划（用户自建或从模板复制而来）
struct Plan: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    /// 训练日，1 = 周一 … 7 = 周日
    var trainingDays: [Int]
    var exercises: [PlanExercise]
    var createdAt: Date
    var updatedAt: Date
    /// 最后一次开始训练的时间，用于「我的计划」卡片展示
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        trainingDays: [Int] = [],
        exercises: [PlanExercise] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.trainingDays = trainingDays
        self.exercises = exercises
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
    }

    /// 计划中的正式动作数量（不含热身）
    var exerciseCount: Int { exercises.filter { !$0.isWarmup }.count }

    /// 总组数
    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    /// 预计时长（分钟）。按每组有效训练时间 + 组间休息累加后留出热身余量。
    var estimatedMinutes: Int {
        let work = exercises.reduce(0.0) { partial, item in
            let setSeconds = 40.0 + Double(item.restSeconds)
            return partial + setSeconds * Double(item.sets)
        }
        guard work > 0 else { return 0 }
        let minutes = Int((work / 60.0 * 1.15).rounded())
        return max(5, minutes)
    }

    /// 每周训练天数文案
    var frequencyText: String {
        trainingDays.isEmpty ? "未设置训练日" : "每周 \(trainingDays.count) 天"
    }

    /// 计划详情概览卡上的训练日文案，如 "周一、周三、周五"
    var trainingDaysText: String {
        guard !trainingDays.isEmpty else { return "未设置" }
        return WeekdayLabel.ordered(trainingDays)
            .map { WeekdayLabel.short($0) }
            .joined(separator: "、")
    }

    /// 列表里按顺序取第 index 个动作；越界返回 nil，避免拖拽过程中下标错位崩溃。
    func exercise(at index: Int) -> PlanExercise? {
        guard exercises.indices.contains(index) else { return nil }
        return exercises[index]
    }

    /// 按 id 找动作在列表中的位置
    func index(ofPlanExercise id: UUID) -> Int? {
        exercises.firstIndex { $0.id == id }
    }
}

// MARK: - 训练日文案

/// 训练日是 Int（1 = 周一 … 7 = 周日），这里集中处理排序与文案，避免各处重复。
enum WeekdayLabel {

    /// 全部星期，固定周一开头，用于「训练日」选择器
    static let all: [Int] = [1, 2, 3, 4, 5, 6, 7]

    /// 单字，用于圆形按钮，如 "一"
    static func symbol(_ day: Int) -> String {
        switch day {
        case 1: return "一"
        case 2: return "二"
        case 3: return "三"
        case 4: return "四"
        case 5: return "五"
        case 6: return "六"
        case 7: return "日"
        default: return "?"
        }
    }

    /// 全称，如 "周一"
    static func short(_ day: Int) -> String {
        "周" + symbol(day)
    }

    /// 去重并按周一开头升序排列
    static func ordered(_ days: [Int]) -> [Int] {
        Array(Set(days)).filter { all.contains($0) }.sorted()
    }

    /// 把日历的 weekday（1 = 周日）换算成 1 = 周一 … 7 = 周日
    static func normalize(calendarWeekday: Int) -> Int {
        calendarWeekday == 1 ? 7 : calendarWeekday - 1
    }
}

/// 计划的动作条目里保存的「递增规则」。
/// 只描述「下一次该练多少」的意图，不参与任何自动计算，训练时由用户自行判断。
enum ProgressionRule: String, Codable, CaseIterable {
    /// 不设置
    case none
    /// 加重量：先加重，次数回落
    case addWeight
    /// 加次数：先冲次数上限，再加重量
    case addReps
    /// 加组数
    case addSet

    var title: String {
        switch self {
        case .none: return "不设置"
        case .addWeight: return "加重量"
        case .addReps: return "加次数"
        case .addSet: return "加组数"
        }
    }

    /// 配置页里的说明文案
    var detail: String {
        switch self {
        case .none: return "保持不变"
        case .addWeight: return "能完成上限次数时，下次加重量"
        case .addReps: return "先完成更多次数，再加重量"
        case .addSet: return "稳定后增加一组"
        }
    }
}

// MARK: - 递增规则（页面 40 的富配置）

/// 达标条件：什么时候算「达标」从而触发递增建议。
enum ProgressionCondition: String, Codable, CaseIterable, Identifiable {
    case allSetsComplete
    case hitUpperReps
    case consecutiveCompletions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allSetsComplete: return "完成全部正式组"
        case .hitUpperReps: return "达到目标次数上限"
        case .consecutiveCompletions: return "连续完成次数"
        }
    }
}

/// 递增方式：达标后优先加什么。
enum ProgressionMethod: String, Codable, CaseIterable, Identifiable {
    case addWeight
    case addReps
    case weightFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addWeight: return "增加重量"
        case .addReps: return "增加次数"
        case .weightFirst: return "二者优先级"
        }
    }
}

/// 未达标处理。
enum MissedTargetAction: String, Codable, CaseIterable, Identifiable {
    case keep
    case deload
    case retry

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keep: return "保持不变"
        case .deload: return "降低建议重量"
        case .retry: return "下次继续当前目标"
        }
    }
}

/// 计划动作的递增规则富配置。只用于给「下一次训练」提供建议，不自动改已完成记录。
struct ProgressionConfig: Codable, Equatable, Hashable {
    var isEnabled: Bool
    var condition: ProgressionCondition
    var method: ProgressionMethod
    /// 重量增幅（kg），范围 0.5–20
    var weightIncrementKg: Double
    /// 次数增幅，范围 1–10
    var repsIncrement: Int
    var missedAction: MissedTargetAction
    var deloadEnabled: Bool
    /// 每 N 次训练后降载
    var deloadInterval: Int
    /// 降载百分比（0–100）
    var deloadPercent: Double

    init(
        isEnabled: Bool = true,
        condition: ProgressionCondition = .allSetsComplete,
        method: ProgressionMethod = .addWeight,
        weightIncrementKg: Double = 2.5,
        repsIncrement: Int = 2,
        missedAction: MissedTargetAction = .keep,
        deloadEnabled: Bool = false,
        deloadInterval: Int = 4,
        deloadPercent: Double = 10
    ) {
        self.isEnabled = isEnabled
        self.condition = condition
        self.method = method
        self.weightIncrementKg = weightIncrementKg
        self.repsIncrement = repsIncrement
        self.missedAction = missedAction
        self.deloadEnabled = deloadEnabled
        self.deloadInterval = deloadInterval
        self.deloadPercent = deloadPercent
    }

    /// 校验：返回 nil 表示通过，否则返回中文字段级错误。
    var validationError: String? {
        guard isEnabled else { return nil }
        if weightIncrementKg < 0.5 || weightIncrementKg > 20 {
            return "重量增幅需在 0.5–20 kg 之间。"
        }
        if repsIncrement < 1 || repsIncrement > 10 {
            return "次数增幅需在 1–10 次之间。"
        }
        if deloadEnabled {
            if deloadInterval < 1 {
                return "降载间隔需至少为 1 次训练。"
            }
            if deloadPercent <= 0 || deloadPercent > 100 {
                return "降载百分比需在 0–100 之间。"
            }
        }
        return nil
    }
}

/// 计划中的一个动作条目
struct PlanExercise: Identifiable, Codable, Hashable {
    var id: UUID
    /// 指向动作库中的动作，使用动作库的字符串 id
    var exerciseID: String
    /// 组数
    var sets: Int
    /// 次数下限
    var repsLow: Int
    /// 次数上限，等于 repsLow 时表示固定次数
    var repsHigh: Int
    /// 组间休息秒数
    var restSeconds: Int
    /// 是否为热身动作，热身不纳入容量统计
    var isWarmup: Bool
    /// 默认重量（可选）。nil 表示自重 / 未填，内部始终按 kg 存。
    var defaultWeight: Double?
    /// 热身组数量（开启热身组后有效）
    var warmupCount: Int
    /// 热身组重量百分比（0…100）
    var warmupPercent: Double
    /// 仅在本计划内生效的备注，不写回动作库
    var note: String?
    /// 递增规则（旧枚举，保留兼容）
    var progression: ProgressionRule
    /// 递增规则富配置（页面 40）。nil 表示未配置。
    var progressionConfig: ProgressionConfig?

    init(
        id: UUID = UUID(),
        exerciseID: String,
        sets: Int = 3,
        repsLow: Int = 8,
        repsHigh: Int = 12,
        restSeconds: Int = 90,
        isWarmup: Bool = false,
        defaultWeight: Double? = nil,
        warmupCount: Int = 1,
        warmupPercent: Double = 50,
        note: String? = nil,
        progression: ProgressionRule = .none,
        progressionConfig: ProgressionConfig? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.repsLow = repsLow
        self.repsHigh = repsHigh
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.defaultWeight = defaultWeight
        self.warmupCount = warmupCount
        self.warmupPercent = warmupPercent
        self.note = note
        self.progression = progression
        self.progressionConfig = progressionConfig
    }

    // 旧版本 plans.json 没有 note / progression / defaultWeight / warmup 字段，用容错解码保证升级后仍能读。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseID = try container.decode(String.self, forKey: .exerciseID)
        sets = try container.decodeIfPresent(Int.self, forKey: .sets) ?? 3
        repsLow = try container.decodeIfPresent(Int.self, forKey: .repsLow) ?? 8
        repsHigh = try container.decodeIfPresent(Int.self, forKey: .repsHigh) ?? 12
        restSeconds = try container.decodeIfPresent(Int.self, forKey: .restSeconds) ?? 90
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        defaultWeight = try container.decodeIfPresent(Double.self, forKey: .defaultWeight)
        warmupCount = try container.decodeIfPresent(Int.self, forKey: .warmupCount) ?? 1
        warmupPercent = try container.decodeIfPresent(Double.self, forKey: .warmupPercent) ?? 50
        note = try container.decodeIfPresent(String.self, forKey: .note)
        progression = try container.decodeIfPresent(ProgressionRule.self, forKey: .progression) ?? .none
        progressionConfig = try container.decodeIfPresent(ProgressionConfig.self, forKey: .progressionConfig)
    }

    /// 次数区间文案，如 "8-12" 或 "10"
    var repsText: String {
        repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
    }

    /// 卡片上的主文案，如 "4 组 × 8-12 次"
    var volumeText: String {
        "\(sets) 组 × \(repsText) 次"
    }

    /// 是否有用户在计划内填写的备注
    var hasNote: Bool {
        !(note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 复制一份配置，但换一个新 id，用于「复制本动作配置」
    func duplicated() -> PlanExercise {
        PlanExercise(
            exerciseID: exerciseID,
            sets: sets,
            repsLow: repsLow,
            repsHigh: repsHigh,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            defaultWeight: defaultWeight,
            warmupCount: warmupCount,
            warmupPercent: warmupPercent,
            note: note,
            progression: progression,
            progressionConfig: progressionConfig
        )
    }
}

// MARK: - 组间休息状态

/// 一次组间休息的可恢复快照。
///
/// 为什么要单独落盘而不是塞进 `WorkoutSession`：
/// - 休息状态是「当前这一刻」的临时量，历史记录里留着没意义；
/// - `WorkoutSession` 已经有一套完整的容错解码契约，不想为它再添一个可选字段；
/// - 全局同时只可能存在一次休息，单独一个 `restTimer.json` 比在会话数组里翻找更直接。
///
/// 恢复语义（页面 06 的硬要求）：
/// - 运行中：`remainingSeconds(at:)` 用 `durationSeconds - (now - startedAt)` 现算，
///   所以切后台、被最小化、甚至 App 被杀掉重启，剩余时间都不会算错；
/// - 暂停中：直接读持久化的 `remainingSeconds`，不再随时间流逝。
struct RestTimerRecord: Identifiable, Codable, Hashable {

    /// 固定 id，全局只存一条
    var id: UUID
    /// 关联的训练草稿。训练结束后这条休息状态就该被清掉。
    var sessionID: UUID
    /// 倒计时的开始时刻。暂停后再继续会把它重新设为当前时间。
    var startedAt: Date
    /// 本次休息的总时长（秒），进度环的分母
    var durationSeconds: Int
    /// 本次休息的**原始**时长（秒），只作为加减时间的上限基准。
    ///
    /// 单独存一个字段是必要的：`durationSeconds` 会被 `adjusting(by:)` 抬高，
    /// 如果拿它当上限基准，连续点「+30 秒」就会越加越多（90 → 120 → … → 无上限）。
    /// 用原始时长做基准，加时间就有一个稳定且可解释的天花板。
    var originalDurationSeconds: Int
    /// 是否处于暂停
    var isPaused: Bool
    /// 暂停时冻结的剩余秒数；运行中该值只是上一次写盘时的快照，不作为准。
    var remainingSeconds: Int
    /// 触发这次休息的动作名，显示在面板标题
    var exerciseName: String
    /// 触发这次休息的动作在计划内的条目 id，用于「设为默认休息时间」回写计划。
    /// 自由训练没有计划条目时为 nil，此时该入口置灰。
    var planEntryID: UUID?
    /// 关联的计划 id
    var planID: UUID?

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        startedAt: Date = .now,
        durationSeconds: Int,
        isPaused: Bool = false,
        remainingSeconds: Int? = nil,
        exerciseName: String,
        planEntryID: UUID? = nil,
        planID: UUID? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.originalDurationSeconds = durationSeconds
        self.isPaused = isPaused
        self.remainingSeconds = remainingSeconds ?? durationSeconds
        self.exerciseName = exerciseName
        self.planEntryID = planEntryID
        self.planID = planID
    }

    // 字段全部给了默认值兜底，升级后读到旧文件不会整条丢弃。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sessionID = try container.decode(UUID.self, forKey: .sessionID)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 90
        // 旧文件没有这个字段：退回当前的 durationSeconds，语义上等价于「没加过时间」
        originalDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .originalDurationSeconds)
            ?? durationSeconds
        isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
        remainingSeconds = try container.decodeIfPresent(Int.self, forKey: .remainingSeconds)
            ?? durationSeconds
        exerciseName = try container.decodeIfPresent(String.self, forKey: .exerciseName) ?? ""
        planEntryID = try container.decodeIfPresent(UUID.self, forKey: .planEntryID)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
    }

    /// 某一时刻的剩余秒数。运行中按墙钟现算，暂停时读冻结值。
    /// 用墙钟而不是逐秒递减，是这套状态能跨后台 / 跨重启恢复的全部原因。
    func remainingSeconds(at now: Date) -> Int {
        if isPaused { return max(0, remainingSeconds) }
        let elapsed = Int(now.timeIntervalSince(startedAt))
        return max(0, durationSeconds - max(0, elapsed))
    }

    /// 某一时刻是否已经走完
    func isFinished(at now: Date) -> Bool {
        remainingSeconds(at: now) <= 0
    }

    /// 进度环进度，0…1。0 表示刚开始（满环），1 表示走完。
    func progress(at now: Date) -> Double {
        guard durationSeconds > 0 else { return 1 }
        let remaining = Double(remainingSeconds(at: now))
        let done = (Double(durationSeconds) - remaining) / Double(durationSeconds)
        return max(0, min(1, done))
    }

    /// 暂停：把当前剩余冻结进字段
    func paused(at now: Date) -> RestTimerRecord {
        var copy = self
        copy.remainingSeconds = remainingSeconds(at: now)
        copy.isPaused = true
        return copy
    }

    /// 继续：把 startedAt 挪到现在，使剩余时间从冻结值接着走。
    /// `originalDurationSeconds` 原样带着走，上限基准不因暂停继续而改变。
    func resumed(at now: Date) -> RestTimerRecord {
        var copy = self
        copy.durationSeconds = max(copy.remainingSeconds, 1)
        copy.startedAt = now
        copy.isPaused = false
        return copy
    }

    /// 加减时间：把「剩余」设为调整后的目标值，并把起点挪到现在，使倒计时从该值接着走。
    ///
    /// 这里必须**同时**重设 `durationSeconds`：
    /// 剩余值是按 `durationSeconds - (now - startedAt)` 推导的，
    /// 只挪 `startedAt` 而不动总时长，加出来的时间会在下一次求值瞬间消失
    /// （刚 +30 又立刻变回原值）。把总时长设成目标剩余，等价于「从现在起重新倒数 N 秒」，
    /// 进度环也随之从满环重新开始，视觉上是自洽的。
    ///
    /// 上限用 `originalDurationSeconds` 而不是 `durationSeconds`，
    /// 否则连续点「+30 秒」会自己抬高自己的上限，越加越多。
    func adjusting(by delta: Int, at now: Date) -> RestTimerRecord {
        var copy = self
        let current = remainingSeconds(at: now)
        // 剩余最少 5 秒，最多不超过原始时长的两倍（且至少 120 秒），避免减到 0 或加到离谱
        let ceiling = max(originalDurationSeconds, 120) * 2
        let next = min(max(5, current + delta), ceiling)
        copy.durationSeconds = next
        copy.remainingSeconds = next
        copy.startedAt = now
        copy.isPaused = false
        return copy
    }
}

// MARK: - 训练记录

/// 一次训练会话
struct WorkoutSession: Identifiable, Codable, Hashable {

    enum Kind: String, Codable, CaseIterable {
        case strength
        case cardio

        var title: String {
            switch self {
            case .strength: return "力量"
            case .cardio: return "有氧"
            }
        }

        var symbolName: String {
            switch self {
            case .strength: return "dumbbell"
            case .cardio: return "figure.run"
            }
        }
    }

    var id: UUID
    var name: String
    var kind: Kind
    var startedAt: Date
    var endedAt: Date?
    /// 有氧训练暂停时刻（页面 31）。非 nil 表示已暂停，计时冻结在 pausedAt。
    var pausedAt: Date?
    var entries: [SetEntry]
    /// 有氧训练的里程（米）
    var distanceMeters: Double?
    /// 有氧训练的消耗（千卡），由用户填写或按时长估算
    var consumedKilocalories: Double?
    /// 有氧训练的分段记录（页面 31）。
    var segments: [WorkoutSegment]
    /// 当前配速（秒/公里，手动录入）。nil 表示未填。
    var paceSecondsPerKm: Double?
    /// 关联的计划，草稿或自由训练为 nil
    var planID: UUID?
    var note: String?

    init(
        id: UUID = UUID(),
        name: String,
        kind: Kind = .strength,
        startedAt: Date = .now,
        endedAt: Date? = nil,
        pausedAt: Date? = nil,
        entries: [SetEntry] = [],
        distanceMeters: Double? = nil,
        consumedKilocalories: Double? = nil,
        segments: [WorkoutSegment] = [],
        paceSecondsPerKm: Double? = nil,
        planID: UUID? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.entries = entries
        self.distanceMeters = distanceMeters
        self.consumedKilocalories = consumedKilocalories
        self.segments = segments
        self.paceSecondsPerKm = paceSecondsPerKm
        self.planID = planID
        self.note = note
    }

    // 旧版本 sessions.json 没有 consumedKilocalories / segments / pausedAt / pace，用容错解码保证升级后仍能读。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .strength
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        entries = try container.decodeIfPresent([SetEntry].self, forKey: .entries) ?? []
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        consumedKilocalories = try container.decodeIfPresent(Double.self, forKey: .consumedKilocalories)
        segments = try container.decodeIfPresent([WorkoutSegment].self, forKey: .segments) ?? []
        paceSecondsPerKm = try container.decodeIfPresent(Double.self, forKey: .paceSecondsPerKm)
        planID = try container.decodeIfPresent(UUID.self, forKey: .planID)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    var isFinished: Bool { endedAt != nil }

    /// 是否处于暂停（有氧训练）。暂停时计时冻结在 pausedAt。
    var isPaused: Bool { pausedAt != nil }

    /// 时长（秒）。未结束时按当前时间计算（暂停时冻结在 pausedAt），用于进行中展示。
    var durationSeconds: Int {
        Int((endedAt ?? pausedAt ?? .now).timeIntervalSince(startedAt))
    }

    /// 已完成的组
    var completedEntries: [SetEntry] {
        entries.filter { $0.isCompleted }
    }

    /// 已将完成的正式组数。未勾选的组不计入。
    var totalSets: Int { completedEntries.filter { !$0.isWarmup }.count }

    /// 已完成的全部组数（含热身），用于执行页概览
    var completedSetCount: Int { completedEntries.count }

    /// 完成过的动作数，按动作去重
    var completedExerciseCount: Int {
        Set(completedEntries.map { $0.exerciseID }).count
    }

    /// 训练容量 = Σ(重量 × 次数)，只算已完成且非热身的组
    var totalVolume: Double {
        completedEntries.reduce(0) { $0 + $1.volume }
    }

    /// 计划总组数（含未完成），用于执行页进度
    var plannedSetCount: Int { entries.count }

    /// 训练完成度，0…1。没有安排任何组时返回 0。
    var progress: Double {
        guard plannedSetCount > 0 else { return 0 }
        return Double(completedSetCount) / Double(plannedSetCount)
    }

    /// 把记录按动作分组，保持首次出现的顺序。
    /// 执行页的动作卡按这个顺序渲染，替换动作后顺序也不会跳。
    var entriesByExercise: [(exerciseID: String, entries: [SetEntry])] {
        var order: [String] = []
        var buckets: [String: [SetEntry]] = [:]
        for entry in entries {
            if buckets[entry.exerciseID] == nil {
                order.append(entry.exerciseID)
                buckets[entry.exerciseID] = []
            }
            buckets[entry.exerciseID]?.append(entry)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    /// 里程（公里）
    var distanceKilometers: Double { (distanceMeters ?? 0) / 1000 }

    /// 有氧消耗（千卡）。没填也没实测时按时长做保守估算，仅用于概览数字展示。
    var kilocalories: Double {
        if let value = consumedKilocalories, value > 0 { return value }
        guard kind == .cardio else { return 0 }
        // 每小时约 420 千卡的中等强度估算，够展示一个稳定不跳变的数字。
        return Double(durationSeconds) / 3600.0 * 420.0
    }

    /// 该动作已完成的最大重量，用于「上一训练记录摘要」与「新增一组复制上一组」。
    func lastCompletedEntry(forExercise exerciseID: String) -> SetEntry? {
        entries.last { $0.exerciseID == exerciseID && $0.isCompleted }
    }

    /// 下一次添加的组号
    func nextSetIndex(forExercise exerciseID: String) -> Int {
        (entries.filter { $0.exerciseID == exerciseID }.map { $0.index }.max() ?? 0) + 1
    }

    /// 记录摘要，用于「最近训练」列表
    var summaryText: String {
        switch kind {
        case .cardio:
            let km = distanceKilometers
            guard km > 0 else { return "有氧训练" }
            return String(format: "有氧 · %.2f 公里", km)
        case .strength:
            guard totalSets > 0 else { return "力量训练" }
            return "\(totalSets) 组 · 容量 \(Int(totalVolume.rounded())) kg"
        }
    }

    // MARK: 由计划生成

    /// 由计划生成一份待执行的训练草稿：把每个计划条目的目标值展开成若干「未完成组」。
    ///
    /// 展开后执行页一进来就是完整的计划表格，`progress` 也立刻有意义。
    /// 重量留 0（自重），让用户在第一组时填入实际重量。
    static func draft(from plan: Plan, startedAt: Date = .now) -> WorkoutSession {
        var entries: [SetEntry] = []
        for item in plan.exercises {
            let count = max(1, item.sets)
            for offset in 1...count {
                entries.append(
                    SetEntry(
                        exerciseID: item.exerciseID,
                        planEntryID: item.id,
                        index: offset,
                        weight: 0,
                        reps: item.repsLow,
                        targetRepsLow: item.repsLow,
                        targetRepsHigh: item.repsHigh,
                        isWarmup: item.isWarmup,
                        completedAt: nil
                    )
                )
            }
        }
        return WorkoutSession(
            name: plan.name,
            kind: .strength,
            startedAt: startedAt,
            entries: entries,
            planID: plan.id
        )
    }
}

/// 一组训练记录。
///
/// 训练执行页需要「未完成的组」也占据一行并显示计划目标值，所以这一条记录同时承担
/// 两种状态：`completedAt == nil` 表示还是待完成的目标，填上时间表示已勾选完成。
/// 这样组的顺序、增删、替换动作都只操作同一份数组，不需要额外的「计划组」结构。
struct SetEntry: Identifiable, Codable, Hashable {
    var id: UUID
    /// 指向动作库中的动作
    var exerciseID: String
    /// 指向计划内的配置条目。自由训练没有计划，为 nil。
    /// 替换动作时靠它把同一组的上位动作换掉而保留完成记录。
    var planEntryID: UUID?
    /// 组号，从 1 开始，用于表格左侧展示与排序
    var index: Int
    /// 重量，自重动作记 0
    var weight: Double
    var reps: Int
    /// 计划目标次数下限，用于「未完成时显示目标」与「完成时对比是否达标」
    var targetRepsLow: Int
    /// 计划目标次数上限
    var targetRepsHigh: Int
    var isWarmup: Bool
    /// nil 表示这一组尚未完成
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        exerciseID: String,
        planEntryID: UUID? = nil,
        index: Int = 1,
        weight: Double,
        reps: Int,
        targetRepsLow: Int? = nil,
        targetRepsHigh: Int? = nil,
        isWarmup: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.exerciseID = exerciseID
        self.planEntryID = planEntryID
        self.index = index
        self.weight = weight
        self.reps = reps
        self.targetRepsLow = targetRepsLow ?? reps
        self.targetRepsHigh = targetRepsHigh ?? reps
        self.isWarmup = isWarmup
        self.completedAt = completedAt
    }

    // 旧版本 sessions.json 没有这些字段，用容错解码保证升级后仍能读。
    // 尤其 `completedAt`：老数据都是已完成的，缺字段时补一个时间而不是 nil，
    // 否则历史记录会被当成「未完成组」而不计入容量统计。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        exerciseID = try container.decode(String.self, forKey: .exerciseID)
        planEntryID = try container.decodeIfPresent(UUID.self, forKey: .planEntryID)
        index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 1
        weight = try container.decodeIfPresent(Double.self, forKey: .weight) ?? 0
        reps = try container.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        targetRepsLow = try container.decodeIfPresent(Int.self, forKey: .targetRepsLow) ?? reps
        targetRepsHigh = try container.decodeIfPresent(Int.self, forKey: .targetRepsHigh) ?? reps
        isWarmup = try container.decodeIfPresent(Bool.self, forKey: .isWarmup) ?? false
        // 旧数据没有 completedAt 字段：一律视为已完成，时间回退到记录起点
        if container.contains(.completedAt) {
            completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        } else {
            completedAt = Date(timeIntervalSince1970: 0)
        }
    }

    var isCompleted: Bool { completedAt != nil }

    /// 目标次数文案，如 "8-12"
    var targetRepsText: String {
        targetRepsLow == targetRepsHigh
            ? "\(targetRepsLow)"
            : "\(targetRepsLow)-\(targetRepsHigh)"
    }

    /// 表格里显示的次数：已完成显示实际值，未完成显示目标值。
    var displayReps: Int {
        isCompleted ? reps : targetRepsLow
    }

    /// 表格里显示的重量。未完成组直接读 `weight` 字段：
    /// 计划展开成草稿时，会把该动作上一训练的最高重量预填进去，
    /// 所以这里不需要任何额外状态，未完成组也显示一个有意义的参考值。
    var displayWeight: Double { weight }

    /// 达标判断：已完成且实际次数不低于目标下限。热身组不算达标。
    var metTarget: Bool {
        guard isCompleted, !isWarmup else { return false }
        return reps >= targetRepsLow
    }

    /// 一组完成时的容量贡献。热身组不计入训练容量。
    var volume: Double {
        isWarmup ? 0 : weight * Double(reps)
    }

    /// 表格行内的可访问文案
    var accessibilityText: String {
        var parts = ["第 \(index) 组"]
        if isWarmup { parts.append("热身组") }
        parts.append(FormatterKit.weight(weight))
        parts.append("\(displayReps) 次")
        parts.append(isCompleted ? "已完成" : "未完成")
        return parts.joined(separator: "，")
    }

    /// 复制成一份新的待完成组。「新增一组」复制上一组数值时使用。
    func duplicatedTarget(at newIndex: Int) -> SetEntry {
        SetEntry(
            exerciseID: exerciseID,
            planEntryID: planEntryID,
            index: newIndex,
            weight: weight,
            reps: reps,
            targetRepsLow: targetRepsLow,
            targetRepsHigh: targetRepsHigh,
            isWarmup: isWarmup,
            completedAt: nil
        )
    }
}

// MARK: - 动作库

/// 动作难度。数据集本身没有这个字段，由器械与负重性质推导，用户可自行调整。
enum ExerciseDifficulty: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beginner: return "入门"
        case .intermediate: return "进阶"
        case .advanced: return "高级"
        }
    }

    /// 展示顺序权重
    var order: Int {
        switch self {
        case .beginner: return 0
        case .intermediate: return 1
        case .advanced: return 2
        }
    }

    /// 由器械推导默认难度。仅为合理启发，不是数据源提供的字段。
    static func infer(equipment: String) -> ExerciseDifficulty {
        switch equipment.lowercased() {
        case "body weight", "band", "resistance band", "roller", "stability ball",
             "medicine ball", "bosu ball", "wheel roller", "rope":
            return .beginner
        case "dumbbell", "cable", "kettlebell", "leverage machine", "smith machine",
             "ez barbell", "weighted", "assisted", "hammer", "stationary bike",
             "elliptical machine", "stepmill machine", "upper body ergometer",
             "skierg machine":
            return .intermediate
        default:
            // barbell / olympic barbell / sled machine / trap bar / tire 等
            return .advanced
        }
    }
}

/// 负重性质。把 28 种器械归成三类，供「自重 / 负重」这一档筛选使用。
enum LoadKind: String, Codable, CaseIterable, Identifiable {
    case bodyweight
    case weighted
    case machine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bodyweight: return "自重"
        case .weighted: return "负重"
        case .machine: return "器械"
        }
    }

    /// 由器械判定负重性质
    static func of(equipment: String) -> LoadKind {
        switch equipment.lowercased() {
        case "body weight", "band", "resistance band", "roller", "bosu ball", "wheel roller":
            return .bodyweight
        case "dumbbell", "barbell", "cable", "kettlebell", "ez barbell", "olympic barbell",
             "weighted", "trap bar", "medicine ball", "stability ball", "hammer", "tire",
             "rope":
            return .weighted
        default:
            // leverage machine / smith machine / sled machine / assisted / 各类有氧器械
            return .machine
        }
    }
}

/// 动作库条目。数据来源于 exercises-dataset，仅结构化字段落地本地；
/// 用户自建的动作以 `isCustom == true` 标记，与导入数据区分。
struct ExerciseLibraryItem: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    /// 检索别名。用于把中文口语说法（如「卧推」「引体」）映射到英文名称的动作。
    var aliases: [String]
    /// 原始英文分类，如 "chest"
    var category: String
    /// 中文分类，如 "胸"
    var categoryZh: String
    var equipment: String
    var equipmentZh: String
    /// 主目标肌群（数据集的 target 字段，英文）
    var target: String
    /// 主肌群中文名。由 target 映射得到，用于列表直接展示。
    var primaryMuscle: String
    var muscleGroup: String
    var secondaryMuscles: [String]
    /// 难度。数据集无此字段，由器械推导或用户指定。
    var difficulty: ExerciseDifficulty
    /// 中文动作说明
    var instructionsZh: String
    /// 中文分步说明
    var stepsZh: [String]
    /// 缩略图相对路径
    var image: String
    /// 动画相对路径
    var gifURL: String
    /// 媒体署名，必须随媒体一同展示
    var attribution: String
    var mediaID: String
    /// 用户自建动作标记。只有自定义动作可编辑与删除。
    var isCustom: Bool
    /// 收藏
    var isFavorite: Bool
    /// 最近一次收藏的时间。仅当 `isFavorite == true` 时有意义，
    /// 用于「收藏动作」页面的「最近收藏」排序；取消收藏时清空。
    /// 旧版本落盘的数据没有这个字段，解码时补 nil。
    var favoritedAt: Date?
    /// 隐藏。官方导入动作不可删除，但可以隐藏。
    var isHidden: Bool
    /// 默认组间休息秒数（页面 23 起自定义动作可配置）。nil 表示用全局默认。
    var defaultRestSeconds: Int?

    init(
        id: String,
        name: String,
        aliases: [String] = [],
        category: String = "",
        categoryZh: String = "",
        equipment: String = "",
        equipmentZh: String = "",
        target: String = "",
        primaryMuscle: String = "",
        muscleGroup: String = "",
        secondaryMuscles: [String] = [],
        difficulty: ExerciseDifficulty = .intermediate,
        instructionsZh: String = "",
        stepsZh: [String] = [],
        image: String = "",
        gifURL: String = "",
        attribution: String = "",
        mediaID: String = "",
        isCustom: Bool = false,
        isFavorite: Bool = false,
        favoritedAt: Date? = nil,
        isHidden: Bool = false,
        defaultRestSeconds: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.category = category
        self.categoryZh = categoryZh
        self.equipment = equipment
        self.equipmentZh = equipmentZh
        self.target = target
        self.primaryMuscle = primaryMuscle
        self.muscleGroup = muscleGroup
        self.secondaryMuscles = secondaryMuscles
        self.difficulty = difficulty
        self.instructionsZh = instructionsZh
        self.stepsZh = stepsZh
        self.image = image
        self.gifURL = gifURL
        self.attribution = attribution
        self.mediaID = mediaID
        self.isCustom = isCustom
        self.isFavorite = isFavorite
        self.favoritedAt = favoritedAt
        self.isHidden = isHidden
        self.defaultRestSeconds = defaultRestSeconds
    }

    /// 容错解码：为旧版本落盘的 JSON 补齐新增字段，避免升级后整库读不出来。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        aliases = (try? c.decode([String].self, forKey: .aliases)) ?? []
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
        gifURL = (try? c.decode(String.self, forKey: .gifURL)) ?? ""
        attribution = (try? c.decode(String.self, forKey: .attribution)) ?? ""
        mediaID = (try? c.decode(String.self, forKey: .mediaID)) ?? ""
        isCustom = (try? c.decode(Bool.self, forKey: .isCustom)) ?? false
        isFavorite = (try? c.decode(Bool.self, forKey: .isFavorite)) ?? false
        favoritedAt = try? c.decode(Date.self, forKey: .favoritedAt)
        isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
        defaultRestSeconds = try? c.decode(Int.self, forKey: .defaultRestSeconds)

        // 主肌群中文名缺失时按 target 推导，保证列表不出现空字段
        let storedPrimary = (try? c.decode(String.self, forKey: .primaryMuscle)) ?? ""
        primaryMuscle = storedPrimary.isEmpty ? MuscleName.zh(for: target) : storedPrimary

        // 难度缺失时按器械推导
        if let stored = try? c.decode(ExerciseDifficulty.self, forKey: .difficulty) {
            difficulty = stored
        } else {
            difficulty = ExerciseDifficulty.infer(equipment: equipment)
        }
    }

    /// 展示用中文名优先取别名里的中文说法，否则用原始英文名。
    var displayName: String {
        guard let chinese = aliases.first(where: { $0.containsHan }) else { return name }
        return chinese
    }

    /// 负重性质
    var loadKind: LoadKind { LoadKind.of(equipment: equipment) }

    /// 列表右上角展示的器械文案
    var equipmentText: String { equipmentZh.isEmpty ? equipment : equipmentZh }

    /// 列表展示的主肌群文案
    var primaryMuscleText: String {
        if !primaryMuscle.isEmpty { return primaryMuscle }
        return MuscleName.zh(for: target)
    }

    /// 是否有可用的本地媒体。未随包分发时不展示破图。
    var hasLocalMedia: Bool { !image.isEmpty || !gifURL.isEmpty }
}

// MARK: - 检索筛选值类型

/// 动作库的完整筛选条件。所有维度都可为空，空表示不限。
struct ExerciseFilter: Equatable {
    /// 肌群大类（快捷 Chip 行），nil 表示「全部」
    var muscleCategory: String?
    /// 高级筛选里的多选肌群，空集表示不限
    var muscleGroups: Set<String> = []
    /// 器械（中文名），空集表示不限
    var equipments: Set<String> = []
    /// 难度，nil 表示不限（单选）
    var difficulty: ExerciseDifficulty?
    /// 动作来源（全部 / 内置导入 / 自定义），单选
    var source: ExerciseSource = .all
    /// 仅看收藏
    var onlyFavorite = false
    /// 包含已隐藏的动作
    var includeHidden = false

    static let none = ExerciseFilter()

    /// 高级筛选里「非默认」的条目数，用于在入口按钮上显示角标
    var advancedCount: Int {
        var count = 0
        if !muscleGroups.isEmpty { count += 1 }
        if !equipments.isEmpty { count += 1 }
        if difficulty != nil { count += 1 }
        if source != .all { count += 1 }
        if onlyFavorite { count += 1 }
        if includeHidden { count += 1 }
        return count
    }

    var isAdvancedActive: Bool { advancedCount > 0 }

    /// 当前是否任何一个筛选条件生效
    var isAnyActive: Bool { isAdvancedActive || muscleCategory != nil }

    /// 清空全部条件（肌群快捷 Chip 行的 `muscleCategory` 由上层单独维护）
    mutating func resetAdvanced() {
        muscleGroups = []
        equipments = []
        difficulty = nil
        source = .all
        onlyFavorite = false
        includeHidden = false
    }
}

/// 动作来源筛选（页面 25）。
enum ExerciseSource: String, CaseIterable, Identifiable {
    case all
    case builtin
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .builtin: return "内置导入"
        case .custom: return "自定义动作"
        }
    }
}

/// 「最近使用」条目。只存 id，展示时再去动作库取，避免数据不同步。
struct RecentExerciseRef: Identifiable, Codable, Hashable {
    var id: String
    var usedAt: Date

    init(id: String, usedAt: Date = .now) {
        self.id = id
        self.usedAt = usedAt
    }
}

/// 动作库页面的排序方式（页面 26）。
enum ExerciseSortOrder: String, CaseIterable, Identifiable {
    /// 默认推荐：按动作库内置顺序（检索时按相关度打分）
    case defaultOrder
    /// 名称 A–Z
    case name
    /// 最近使用：最近加入训练或计划的动作优先
    case recentlyUsed
    /// 最近收藏：最近被收藏的动作优先
    case recentlyFavorited
    /// 难度：入门到高级
    case difficulty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .defaultOrder: return "默认推荐"
        case .name: return "名称 A-Z"
        case .recentlyUsed: return "最近使用"
        case .recentlyFavorited: return "最近收藏"
        case .difficulty: return "难度"
        }
    }

    /// 依赖「最近使用 / 最近收藏」数据，无数据时回退默认顺序并在顶部提示。
    var mayFallBackToDefault: Bool {
        self == .recentlyUsed || self == .recentlyFavorited
    }
}


// MARK: - 身体数据

/// 身体测量记录。
///
/// 所有数值字段都可选（`Double?`）：一条记录可以只填体重、只填腰围、
/// 或只填备注——这是规格「所有数值字段为可选」的直接映射。
/// 内部统一用 kg 与 cm 存储，单位切换只影响展示（见页面 12 的 `BodyData.swift`）。
struct BodyMeasurement: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var weightKg: Double?
    var bodyFatPercent: Double?
    var chestCm: Double?
    var waistCm: Double?
    var hipCm: Double?
    var thighCm: Double?
    var armCm: Double?
    var note: String?

    init(
        id: UUID = UUID(),
        date: Date = .now,
        weightKg: Double? = nil,
        bodyFatPercent: Double? = nil,
        chestCm: Double? = nil,
        waistCm: Double? = nil,
        hipCm: Double? = nil,
        thighCm: Double? = nil,
        armCm: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.chestCm = chestCm
        self.waistCm = waistCm
        self.hipCm = hipCm
        self.thighCm = thighCm
        self.armCm = armCm
        self.note = note
    }

    // 页面 12 之前落盘的 measurements.json 没有 hipCm（臀围）字段。
    // 逐字段 decodeIfPresent，旧文件缺失时补 nil，而不是整条丢弃。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyFatPercent = try container.decodeIfPresent(Double.self, forKey: .bodyFatPercent)
        chestCm = try container.decodeIfPresent(Double.self, forKey: .chestCm)
        waistCm = try container.decodeIfPresent(Double.self, forKey: .waistCm)
        hipCm = try container.decodeIfPresent(Double.self, forKey: .hipCm)
        thighCm = try container.decodeIfPresent(Double.self, forKey: .thighCm)
        armCm = try container.decodeIfPresent(Double.self, forKey: .armCm)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    /// 是否至少有一个有效测量值。
    /// 规格「至少填写一个有效测量值才能保存」的判断依据——备注不算测量值。
    var hasAnyValue: Bool {
        weightKg != nil || bodyFatPercent != nil || chestCm != nil || waistCm != nil
            || hipCm != nil || thighCm != nil || armCm != nil
    }
}

// MARK: - 个人资料

/// 训练目标。页面 17 起作为个人资料的一项，用单选 Chip 选择。
enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case muscleGain
    case fatLoss
    case strength
    case endurance
    case stayHealthy
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .muscleGain: return "增肌"
        case .fatLoss: return "减脂"
        case .strength: return "力量"
        case .endurance: return "体能"
        case .stayHealthy: return "保持健康"
        case .custom: return "自定义"
        }
    }
}

/// 本地个人资料。昵称 + 训练开始日期 + 训练目标 + 个人说明 + 本地头像，
/// 不涉及账号、头像上传或任何云端字段。
///
/// 单独存 `profile.json`（单个对象，不是数组）：它是「这一台设备上的一个用户」，
/// 与训练 / 身体数据 / 动作库这些集合数据天然分开。
struct UserProfile: Identifiable, Codable, Hashable {
    var id: UUID
    /// 昵称。nil 表示尚未设置，界面显示「设置昵称」。
    var nickname: String?
    /// 训练开始日期。首次创建时写入，页面 17 起可在个人资料页编辑，用于「已使用 N 天」。
    var startedAt: Date
    /// 训练目标。nil 表示尚未设置。
    var trainingGoal: TrainingGoal?
    /// 「自定义」训练目标的文字。仅当 `trainingGoal == .custom` 时有意义。
    var customGoal: String?
    /// 个人说明。仅用于本机展示，最多 200 字。
    var bio: String?
    /// 本地头像文件名（保存在 App 本地目录）。nil 表示用默认首字母头像。
    var avatarFileName: String?

    init(
        id: UUID = UUID(),
        nickname: String? = nil,
        startedAt: Date = .now,
        trainingGoal: TrainingGoal? = nil,
        customGoal: String? = nil,
        bio: String? = nil,
        avatarFileName: String? = nil
    ) {
        self.id = id
        self.nickname = nickname
        self.startedAt = startedAt
        self.trainingGoal = trainingGoal
        self.customGoal = customGoal
        self.bio = bio
        self.avatarFileName = avatarFileName
    }

    // 旧版本 profile.json 缺字段时不整体失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
        trainingGoal = try? container.decode(TrainingGoal.self, forKey: .trainingGoal)
        customGoal = try container.decodeIfPresent(String.self, forKey: .customGoal)
        bio = try container.decodeIfPresent(String.self, forKey: .bio)
        avatarFileName = try container.decodeIfPresent(String.self, forKey: .avatarFileName)
    }

    /// 修剪后的昵称。nil 或全空白时返回 nil（等同未设置）。
    var trimmedNickname: String? {
        guard let raw = nickname else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - 休息日

/// 用户主动标记的休息日。
///
/// 为什么不复用 `WorkoutSession.Kind` 加一个 `rest` 分支：训练记录会被
/// 「最近训练」「总容量」「总里程」「已完成训练数」等多处聚合计入，
/// 混入休息日会让每个聚合点都要额外过滤，漏掉一处就是错的。
/// 独立模型也让 `restDays.json` 与 `sessions.json` 各自演化。
///
/// `date` 只存「当天 00:00」这个本地时区的时间点，表示哪一天，
/// 不表示一天里的某个时刻。
struct RestDay: Identifiable, Codable, Hashable {
    var id: UUID
    var date: Date
    var note: String?
    /// 创建时间（页面 34「创建时间」展示）。旧数据缺字段时回落。
    var createdAt: Date?

    init(id: UUID = UUID(), date: Date, note: String? = nil, createdAt: Date? = nil) {
        self.id = id
        self.date = date
        self.note = note
        self.createdAt = createdAt
    }

    /// 容错解码：旧版本文件缺字段时不整体失败
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

// MARK: - 有氧分段

/// 有氧训练的一段记录（页面 31）。只记录用户手动录入的数据，不来自 GPS 或网络。
struct WorkoutSegment: Identifiable, Codable, Hashable {
    var id: UUID
    /// 分段时长（秒）
    var durationSeconds: Int
    /// 分段距离（米）
    var distanceMeters: Double?
    /// 分段配速（秒/公里），可手动填写，nil 表示未填
    var paceSecondsPerKm: Double?
    /// 分段备注
    var note: String?

    init(
        id: UUID = UUID(),
        durationSeconds: Int = 0,
        distanceMeters: Double? = nil,
        paceSecondsPerKm: Double? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.paceSecondsPerKm = paceSecondsPerKm
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds) ?? 0
        distanceMeters = try container.decodeIfPresent(Double.self, forKey: .distanceMeters)
        paceSecondsPerKm = try container.decodeIfPresent(Double.self, forKey: .paceSecondsPerKm)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    /// 配速展示，如「5′30″/公里」；未填时返回 nil。
    var paceText: String? {
        guard let seconds = paceSecondsPerKm, seconds > 0 else { return nil }
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(minutes)′\(String(format: "%02d", secs))″/公里"
    }
}

// MARK: - 有氧模板

/// 本地保存的有氧训练模板（页面 32「保存为模板」）。
struct CardioTemplate: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var sport: String
    var goalKind: String
    var goalValue: Double?
    var note: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        sport: String,
        goalKind: String,
        goalValue: Double? = nil,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.sport = sport
        self.goalKind = goalKind
        self.goalValue = goalValue
        self.note = note
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        sport = try container.decodeIfPresent(String.self, forKey: .sport) ?? "run"
        goalKind = try container.decodeIfPresent(String.self, forKey: .goalKind) ?? "free"
        goalValue = try container.decodeIfPresent(Double.self, forKey: .goalValue)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
    }
}

// MARK: - 首页状态

/// 首页「今日训练」的展示状态
enum TodayTrainingState: Equatable {
    /// 数据加载中
    case loading
    /// 没有安排
    case empty
    /// 有安排但尚未开始
    case scheduled(planID: UUID, name: String, exerciseCount: Int, estimatedMinutes: Int)
    /// 有进行中的训练，可继续
    case inProgress(
        sessionID: UUID,
        name: String,
        completedSets: Int,
        totalSets: Int,
        elapsedSeconds: Int
    )

    /// 主按钮文案
    var primaryButtonTitle: String {
        switch self {
        case .loading: return "载入中"
        case .empty: return "开始一次训练"
        case .scheduled: return "开始训练"
        case .inProgress: return "继续训练"
        }
    }

    /// 进度，0…1
    var progress: Double {
        switch self {
        case .inProgress(_, _, let done, let total, _):
            guard total > 0 else { return 0 }
            return min(1, Double(done) / Double(total))
        default:
            return 0
        }
    }
}
