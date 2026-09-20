//
//  ProfileData.swift
//  页面 13「我的」的值语义层。
//
//  **这个文件不 import SwiftUI**，全是纯值类型、常量与纯函数，
//  可被 Python 照搬推演（见 `Tools/probe_page13_semantics.py`）。
//
//  覆盖：个人资料的「已使用 N 天」计算、设置项的 UserDefaults 键与默认值、
//  默认休息时间预设、以及数据摘要的「— / 0」分界文案。
//

import Foundation

// MARK: - 设置项

/// 全部本地设置项。**只用 UserDefaults，不落 JSON**——这些是「偏好」不是「数据」。
///
/// 单位两把键与页面 12 共用（`preference.bodyWeightUnit` / `preference.bodyLengthUnit`），
/// 所以「我的」页里改单位，身体数据页的展示会跟着变——单位是全 App 的一处真相。
enum ProfileSettings {

    // MARK: 键

    static let weightUnitKey = "preference.bodyWeightUnit"
    static let lengthUnitKey = "preference.bodyLengthUnit"
    static let defaultRestKey = "preference.defaultRestSeconds"
    static let soundKey = "preference.soundEnabled"
    static let hapticsKey = "preference.hapticsEnabled"
    static let darkKey = "preference.darkAppearance"
    static let reduceMotionKey = "preference.reduceMotion"
    static let autoStartRestKey = "preference.autoStartRest"
    static let prefillWeightsKey = "preference.prefillWeights"
    static let appearanceModeKey = "preference.appearanceMode"
    static let listTextSizeKey = "preference.listTextSize"
    static let exerciseSortKey = "preference.exerciseSort"
    static let cardioDistanceUnitKey = "preference.cardioDistanceUnit"
    static let motionPreferenceKey = "preference.motionPreference"
    static let hasCompletedOnboardingKey = "preference.hasCompletedOnboarding"

    // MARK: 页面 43 声音与触感（细分键）

    static let soundRestEndKey = "preference.sound.restEnd"
    static let soundLastTenKey = "preference.sound.lastTen"
    static let soundSetCompleteKey = "preference.sound.setComplete"
    static let hapticSetCompleteKey = "preference.haptic.setComplete"
    static let hapticRestEndKey = "preference.haptic.restEnd"
    static let hapticWorkoutCompleteKey = "preference.haptic.workoutComplete"

    // MARK: 默认值

    /// 默认休息时间（秒）。与 `PlanExercise.restSeconds` 的默认值一致。
    static let defaultRestSeconds = 90
    /// 默认休息时间的预设档位。与 `RestDefaultPickerSheet` 同一组。
    static let restPresets = [30, 45, 60, 90, 120, 180]

    // MARK: 读

    static var weightUnit: BodyWeightUnit {
        get {
            let raw = UserDefaults.standard.string(forKey: weightUnitKey) ?? ""
            return BodyWeightUnit(rawValue: raw) ?? .kilograms
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: weightUnitKey) }
    }

    static var lengthUnit: BodyLengthUnit {
        get {
            let raw = UserDefaults.standard.string(forKey: lengthUnitKey) ?? ""
            return BodyLengthUnit(rawValue: raw) ?? .centimeters
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lengthUnitKey) }
    }

    static var defaultRest: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: defaultRestKey)
            return stored > 0 ? stored : defaultRestSeconds
        }
        set { UserDefaults.standard.set(newValue, forKey: defaultRestKey) }
    }

    static var soundEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: soundKey) }
    }

    static var hapticsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: hapticsKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    static var darkAppearance: Bool {
        get {
            UserDefaults.standard.object(forKey: darkKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: darkKey) }
    }

    static var reduceMotion: Bool {
        get {
            UserDefaults.standard.object(forKey: reduceMotionKey) as? Bool ?? false
        }
        set { UserDefaults.standard.set(newValue, forKey: reduceMotionKey) }
    }

    static var autoStartRest: Bool {
        get {
            UserDefaults.standard.object(forKey: autoStartRestKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: autoStartRestKey) }
    }

    static var prefillWeights: Bool {
        get {
            UserDefaults.standard.object(forKey: prefillWeightsKey) as? Bool ?? true
        }
        set { UserDefaults.standard.set(newValue, forKey: prefillWeightsKey) }
    }

    // MARK: 页面 22 应用设置（新增键）

    static var appearanceMode: AppearanceMode {
        get {
            let raw = UserDefaults.standard.string(forKey: appearanceModeKey) ?? ""
            return AppearanceMode(rawValue: raw) ?? .dark
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: appearanceModeKey) }
    }

    static var listTextSize: ListTextSize {
        get {
            let raw = UserDefaults.standard.string(forKey: listTextSizeKey) ?? ""
            return ListTextSize(rawValue: raw) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: listTextSizeKey) }
    }

    /// 动作库排序方式（页面 26）。只影响动作库与收藏动作列表的显示顺序，不落数据。
    static var exerciseSort: ExerciseSortOrder {
        get {
            let raw = UserDefaults.standard.string(forKey: exerciseSortKey) ?? ""
            return ExerciseSortOrder(rawValue: raw) ?? .defaultOrder
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: exerciseSortKey) }
    }

    /// 有氧距离单位（页面 42）。内部始终以「米」保存，这里只控制展示格式。
    static var cardioDistanceUnit: DistanceUnit {
        get {
            let raw = UserDefaults.standard.string(forKey: cardioDistanceUnitKey) ?? ""
            return DistanceUnit(rawValue: raw) ?? .kilometers
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: cardioDistanceUnitKey) }
    }

    /// 减少动态效果模式（页面 44）。默认「跟随系统」。
    static var motionPreference: MotionPreference {
        get {
            let raw = UserDefaults.standard.string(forKey: motionPreferenceKey) ?? ""
            return MotionPreference(rawValue: raw) ?? .followSystem
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: motionPreferenceKey) }
    }

    /// 是否已完成首次启动引导（页面 47）。默认 false，清除全部本地数据后重置。
    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedOnboardingKey) }
    }

    // MARK: 页面 43 声音与触感细分开关

    /// 组间休息结束提示音。
    static var soundRestEnd: Bool {
        get { UserDefaults.standard.object(forKey: soundRestEndKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundRestEndKey) }
    }

    /// 倒计时最后 10 秒提示音。
    static var soundLastTen: Bool {
        get { UserDefaults.standard.object(forKey: soundLastTenKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundLastTenKey) }
    }

    /// 动作完成提示音。
    static var soundSetComplete: Bool {
        get { UserDefaults.standard.object(forKey: soundSetCompleteKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: soundSetCompleteKey) }
    }

    /// 完成一组触感反馈。
    static var hapticSetComplete: Bool {
        get { UserDefaults.standard.object(forKey: hapticSetCompleteKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticSetCompleteKey) }
    }

    /// 休息结束触感反馈。
    static var hapticRestEnd: Bool {
        get { UserDefaults.standard.object(forKey: hapticRestEndKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticRestEndKey) }
    }

    /// 训练完成触感反馈。
    static var hapticWorkoutComplete: Bool {
        get { UserDefaults.standard.object(forKey: hapticWorkoutCompleteKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticWorkoutCompleteKey) }
    }

    // MARK: 页面 14 训练偏好（新增键）

    // 「自动复制上次记录」沿用页面 13 已经落地的 `prefillWeights` 键：
    // 两者是同一个概念——「建议最近一次有效重量 / 次数」——只是页面 13 叫
    // 「重量预填建议」，页面 14 的规格把措辞收敛为「自动复制上次记录」。
    // 同一概念不落两把键，否则改一处另一处就会各说各话。
    static let showVolumeKey = "preference.showVolume"
    static let lastTenSecondsReminderKey = "preference.lastTenSecondsReminder"
    static let countdownStyleKey = "preference.countdownStyle"
    static let autoAdvanceExerciseKey = "preference.autoAdvanceExercise"
    static let copyPreviousSetKey = "preference.copyPreviousSet"
    static let showWarmupSetsKey = "preference.showWarmupSets"
    static let keepTimerOnMinimizeKey = "preference.keepTimerOnMinimize"

    /// 显示训练容量：训练执行页概览是否显示「总训练容量」。关闭后历史统计仍在后台计算。
    static var showVolume: Bool {
        get { UserDefaults.standard.object(forKey: showVolumeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showVolumeKey) }
    }

    /// 倒计时最后 10 秒提醒：最后 10 秒是否转荧光绿强调。
    static var lastTenSecondsReminder: Bool {
        get { UserDefaults.standard.object(forKey: lastTenSecondsReminderKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: lastTenSecondsReminderKey) }
    }

    /// 倒计时数字样式：普通 / 大号。
    static var countdownStyle: CountdownNumberStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: countdownStyleKey) ?? ""
            return CountdownNumberStyle(rawValue: raw) ?? .normal
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: countdownStyleKey) }
    }

    /// 完成当前动作后自动定位下一动作。
    static var autoAdvanceExercise: Bool {
        get { UserDefaults.standard.object(forKey: autoAdvanceExerciseKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: autoAdvanceExerciseKey) }
    }

    /// 新增组时复制上一组数值。
    static var copyPreviousSet: Bool {
        get { UserDefaults.standard.object(forKey: copyPreviousSetKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: copyPreviousSetKey) }
    }

    /// 默认显示热身组。
    static var showWarmupSets: Bool {
        get { UserDefaults.standard.object(forKey: showWarmupSetsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: showWarmupSetsKey) }
    }

    /// 最小化训练后保留计时器。关闭后仍保存草稿，但不显示悬浮 / 后台计时 UI。
    static var keepTimerOnMinimize: Bool {
        get { UserDefaults.standard.object(forKey: keepTimerOnMinimizeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: keepTimerOnMinimizeKey) }
    }

    // MARK: 恢复默认训练偏好

    /// 恢复默认训练偏好。**只重置训练偏好这一组**，不碰：
    /// - 单位（重量 / 长度）、深色外观、减少动态效果（应用设置那组）；
    /// - 训练计划、历史记录、动作库、身体数据（都在仓储，不在 UserDefaults）。
    static func restoreTrainingDefaults() {
        defaultRest = defaultRestSeconds
        prefillWeights = true
        autoStartRest = true
        showVolume = true
        lastTenSecondsReminder = true
        countdownStyle = .normal
        autoAdvanceExercise = false
        copyPreviousSet = true
        showWarmupSets = true
        keepTimerOnMinimize = true
    }

    // MARK: 全部设置项键（页面 18「清除全部本地数据」用）

    /// 所有设置项的键，用于「清除全部本地数据」时一次性移除。
    /// 移除键后各 getter 会自然回落到默认值。
    static let allKeys: [String] = [
        weightUnitKey, lengthUnitKey, defaultRestKey, soundKey, hapticsKey,
        darkKey, reduceMotionKey, autoStartRestKey, prefillWeightsKey,
        appearanceModeKey, listTextSizeKey, exerciseSortKey, cardioDistanceUnitKey,
        motionPreferenceKey, hasCompletedOnboardingKey,
        soundRestEndKey, soundLastTenKey, soundSetCompleteKey,
        hapticSetCompleteKey, hapticRestEndKey, hapticWorkoutCompleteKey,
        showVolumeKey, lastTenSecondsReminderKey, countdownStyleKey,
        autoAdvanceExerciseKey, copyPreviousSetKey, showWarmupSetsKey,
        keepTimerOnMinimizeKey,
    ]

    /// 重置全部设置项到默认值（单位 / 外观 / 减少动态 / 训练偏好 / 声音触感）。
    /// 只清 UserDefaults，不碰仓储里的训练、计划、动作库或身体数据。
    static func resetAll() {
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 会被「恢复默认」重置的选项清单（标题 + 默认值文案）。
    /// 供页面在二次确认前展示「将被重置的内容」。
    static var trainingPreferenceDefaults: [TrainingPreferenceResetItem] {
        [
            TrainingPreferenceResetItem(title: "默认组间休息时间", value: FormatterKit.rest(seconds: defaultRestSeconds)),
            TrainingPreferenceResetItem(title: "完成一组后自动开始休息", value: "开启"),
            TrainingPreferenceResetItem(title: "自动复制上次记录", value: "开启"),
            TrainingPreferenceResetItem(title: "显示训练容量", value: "开启"),
            TrainingPreferenceResetItem(title: "倒计时提示音", value: "开启"),
            TrainingPreferenceResetItem(title: "触感反馈", value: "开启"),
            TrainingPreferenceResetItem(title: "倒计时最后 10 秒提醒", value: "开启"),
            TrainingPreferenceResetItem(title: "倒计时数字样式", value: "普通"),
            TrainingPreferenceResetItem(title: "完成当前动作后自动定位下一动作", value: "关闭"),
            TrainingPreferenceResetItem(title: "新增组时复制上一组数值", value: "开启"),
            TrainingPreferenceResetItem(title: "默认显示热身组", value: "开启"),
            TrainingPreferenceResetItem(title: "最小化训练后保留计时器", value: "开启"),
        ]
    }
}

/// 恢复默认训练偏好时会重置的一条选项。
struct TrainingPreferenceResetItem: Identifiable, Equatable {
    let title: String
    let value: String

    var id: String { title }
}

// MARK: - 倒计时数字样式

/// 倒计时数字的两种样式。只影响显示，不改动任何记录。
enum CountdownNumberStyle: String, CaseIterable, Identifiable, Equatable {
    case normal
    case large

    var id: String { rawValue }

    /// 中文标题，用于设置页单选抽屉的选项文案。
    var title: String {
        switch self {
        case .normal: return "普通"
        case .large: return "大号"
        }
    }
}

// MARK: - 外观模式（页面 22）

/// 外观模式。App 设计为深色底，故「深色」为默认；「跟随系统」仅影响系统控件外观。
enum AppearanceMode: String, CaseIterable, Identifiable {
    case dark
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "深色"
        case .system: return "跟随系统"
        }
    }
}

// MARK: - 列表文字大小（页面 22）

/// 列表文字大小。只影响动作库 / 收藏列表的条目字号，不改动数据。
enum ListTextSize: String, CaseIterable, Identifiable {
    case normal
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "系统默认"
        case .large: return "较大"
        }
    }
}

// MARK: - 有氧距离单位（页面 42）

/// 有氧距离与配速的展示单位。**内部原始数据始终以「米」保存**，
/// 这里只做展示换算，绝不回写或造成累计误差。
enum DistanceUnit: String, CaseIterable, Identifiable, Equatable {
    case kilometers
    case miles

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kilometers: return "公里"
        case .miles: return "英里"
        }
    }

    var shortTitle: String {
        switch self {
        case .kilometers: return "km"
        case .miles: return "mi"
        }
    }

    /// 1 mile = 1609.344 m
    static let metersPerMile: Double = 1609.344

    /// 把「以米记录的原始值」换算成本单位的展示值（公里 / 英里）。
    func displayValue(fromMeters value: Double) -> Double {
        switch self {
        case .kilometers: return value / 1000
        case .miles: return value / Self.metersPerMile
        }
    }
}

// MARK: - 声音与触感策略（页面 43）

/// 声音 / 触感的「是否触发」判定。纯函数，可被 Python 照搬推演。
///
/// 规则：
/// - 总提示音关闭 → 所有下属声音不触发（但子开关原配置保留）；
/// - 总触感关闭 或 设备不支持触感 → 所有下属触感不触发。
enum FeedbackPolicy {

    /// 某类声音是否应播放：总开关 + 对应子开关都开启。
    static func shouldPlaySound(master: Bool, sub: Bool) -> Bool {
        master && sub
    }

    /// 某类触感是否应触发：总开关 + 子开关开启 + 设备支持。
    static func shouldTriggerHaptic(master: Bool, sub: Bool, available: Bool) -> Bool {
        master && sub && available
    }
}

// MARK: - 减少动态效果模式（页面 44）

/// 减少 App 动画的三种模式。默认「跟随系统」。
enum MotionPreference: String, CaseIterable, Identifiable, Equatable {
    case followSystem
    case alwaysReduced
    case normal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .followSystem: return "跟随系统"
        case .alwaysReduced: return "始终减少"
        case .normal: return "正常动画"
        }
    }

    var detail: String {
        switch self {
        case .followSystem: return "动态读取系统「减少动态效果」无障碍设置"
        case .alwaysReduced: return "页面立即切换或仅短淡入，按钮不缩放，数字直接显示最终值"
        case .normal: return "保留各页面约定的 180–260ms 动效"
        }
    }

    /// 是否减少动画。`followSystem` 时以系统开关为准。纯函数，可被 Python 照搬推演。
    func isReduced(systemReduceMotion: Bool) -> Bool {
        switch self {
        case .followSystem: return systemReduceMotion
        case .alwaysReduced: return true
        case .normal: return false
        }
    }
}

// MARK: - 个人资料字段校验（页面 17）

/// 个人资料字段的规范化与长度限制。纯函数，可被 Python 照搬推演。
enum ProfileValidation {

    /// 昵称最大字符数（去除前后空格后）。
    static let nicknameMaxLength = 20
    /// 个人说明最大字符数。
    static let bioMaxLength = 200

    /// 规范化昵称：去前后空白，超过上限截断；空串返回 nil（等同未设置）。
    static func normalizedNickname(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(nicknameMaxLength))
    }

    /// 规范化个人说明：去前后空白，超过上限截断；空串返回 nil。
    static func normalizedBio(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(bioMaxLength))
    }
}

// MARK: - 个人资料计算

/// 个人资料相关的纯计算。
enum ProfileMath {

    /// 「已使用 N 天」。按自然日算：昨天开始 = 1 天，今天开始 = 0 天。
    ///
    /// 用 `calendar.startOfDay` 而不是减 86400 秒（夏令时安全）。
    /// 结果恒不小于 0——时钟回拨也不该出现负天数。
    static func daysSince(_ start: Date, now: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: start)
        let to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(0, days)
    }
}

// MARK: - 数据摘要文案

/// 个人数据摘要的「— / 0」分界。
///
/// 与统计页 `StatsMetric.value: String?` 同一套语义：
/// **没有记录显示「—」，有记录但值是 0 才显示 0**。
enum ProfileSummaryText {

    /// 最近体重文案。没体重记录时返回「—」；有体重按单位换算。
    static func weightText(
        latestWeightKg: Double?,
        unit: BodyWeightUnit
    ) -> String {
        guard let kg = latestWeightKg else { return "—" }
        let converted = unit.displayValue(fromKilograms: kg)
        return "\(BodyNumberFormat.decimal(converted)) \(unit.shortTitle)"
    }

    /// 累计训练次数。没有已完成的训练时显示「—」而不是「0」。
    static func countText(_ count: Int) -> String {
        count <= 0 ? "—" : "\(count)"
    }

    /// 累计训练时长文案。没有时长时显示「—」。
    static func durationText(seconds: Int) -> String {
        seconds <= 0 ? "—" : FormatterKit.duration(seconds: seconds)
    }
}
