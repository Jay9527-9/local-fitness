//
//  ExportBackup.swift
//  页面 19：导出本地备份的纯值层。
//
//  与其它备份格式的分工（都刻意不复用，边界不同）：
//  - WorkoutBackup        只导出训练记录（页面 10 的清除边界）；
//  - PlanBackup           只导出训练计划（页面 15 的多计划批量）；
//  - LocalDataBackup      本地数据管理页的导入 / 恢复快照格式（页面 18）；
//  - ExportBackup（本文件）「本地数据管理 → 导出本地备份」的完整导出格式，
//    范围最广：训练记录、个人计划、自定义动作与收藏、身体数据、训练偏好、个人资料。
//
//  规格要求含 schemaVersion / createdAt / appVersion 与所选数据段，供版本化导入识别。
//  动作库种子与媒体默认不导出（文件体积考虑），由页面上的说明文案交代。
//
//  这个文件同样没有 SwiftUI 类型，能被 Python 侧照搬做推演。
//

import Foundation

// MARK: - 导出数据段

/// 导出备份可包含的数据段。页面上每项一个开关，带数量说明。
enum ExportBackupSegment: String, CaseIterable, Identifiable {
    case sessions
    case plans
    case exercises
    case measurements
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "训练记录"
        case .plans: return "个人计划"
        case .exercises: return "自定义动作与收藏"
        case .measurements: return "身体数据"
        case .preferences: return "训练偏好与个人资料"
        }
    }
}

// MARK: - 训练偏好快照

/// 训练偏好的快照。这些值存 UserDefaults，不落 JSON，
/// 导出时单独抓一份快照塞进备份，导入时再写回。
///
/// 覆盖「训练偏好」页（页面 14）的 12 项：组间休息、自动复制、自动休息、
/// 显示容量、最后 10 秒提醒、倒计时样式、自动定位、复制上一组、显示热身组、
/// 最小化保留计时器、声音、触感。
/// 单位（重量 / 长度）与深色外观、减少动态效果属「应用设置」，不在此列。
struct TrainingPreferencesSnapshot: Codable, Equatable {
    var defaultRestSeconds: Int
    var prefillWeights: Bool
    var autoStartRest: Bool
    var showVolume: Bool
    var lastTenSecondsReminder: Bool
    var countdownStyle: String
    var autoAdvanceExercise: Bool
    var copyPreviousSet: Bool
    var showWarmupSets: Bool
    var keepTimerOnMinimize: Bool
    var soundEnabled: Bool
    var hapticsEnabled: Bool

    /// 抓取当前 UserDefaults 里的训练偏好。
    static func capture() -> TrainingPreferencesSnapshot {
        TrainingPreferencesSnapshot(
            defaultRestSeconds: ProfileSettings.defaultRest,
            prefillWeights: ProfileSettings.prefillWeights,
            autoStartRest: ProfileSettings.autoStartRest,
            showVolume: ProfileSettings.showVolume,
            lastTenSecondsReminder: ProfileSettings.lastTenSecondsReminder,
            countdownStyle: ProfileSettings.countdownStyle.rawValue,
            autoAdvanceExercise: ProfileSettings.autoAdvanceExercise,
            copyPreviousSet: ProfileSettings.copyPreviousSet,
            showWarmupSets: ProfileSettings.showWarmupSets,
            keepTimerOnMinimize: ProfileSettings.keepTimerOnMinimize,
            soundEnabled: ProfileSettings.soundEnabled,
            hapticsEnabled: ProfileSettings.hapticsEnabled
        )
    }

    /// 把快照写回 UserDefaults（导入备份时恢复训练偏好）。
    func apply() {
        ProfileSettings.defaultRest = defaultRestSeconds
        ProfileSettings.prefillWeights = prefillWeights
        ProfileSettings.autoStartRest = autoStartRest
        ProfileSettings.showVolume = showVolume
        ProfileSettings.lastTenSecondsReminder = lastTenSecondsReminder
        ProfileSettings.countdownStyle = CountdownNumberStyle(rawValue: countdownStyle) ?? .normal
        ProfileSettings.autoAdvanceExercise = autoAdvanceExercise
        ProfileSettings.copyPreviousSet = copyPreviousSet
        ProfileSettings.showWarmupSets = showWarmupSets
        ProfileSettings.keepTimerOnMinimize = keepTimerOnMinimize
        ProfileSettings.soundEnabled = soundEnabled
        ProfileSettings.hapticsEnabled = hapticsEnabled
    }

    /// 项数，供页面「数量说明」展示。
    static let itemCount = 12
    var count: Int { Self.itemCount }

    /// 用于校验摘要的规范文本：把全部字段拼成一行，任何一项被改动都会改变摘要。
    var canonicalText: String {
        "rest=\(defaultRestSeconds);prefill=\(prefillWeights);autostart=\(autoStartRest)"
            + ";volume=\(showVolume);last10=\(lastTenSecondsReminder);style=\(countdownStyle)"
            + ";advance=\(autoAdvanceExercise);copy=\(copyPreviousSet);warmup=\(showWarmupSets)"
            + ";minimize=\(keepTimerOnMinimize);sound=\(soundEnabled);haptics=\(hapticsEnabled)"
    }
}

// MARK: - 备份结构

/// 完整导出备份的结构。
struct ExportBackup: Codable, Equatable, Identifiable {
    /// 结构版本。将来结构变化时靠它决定怎么读旧文件。
    var schemaVersion: Int
    /// 固定为 `fitness-export-backup`，导入时校验用。
    var format: String
    var createdAt: Date
    var appVersion: String
    var appName: String
    /// 所选数据段的 rawValue，升序，供导入侧识别备份里有哪些数据。
    var dataSegments: [String]
    /// 是否包含个人资料（昵称 / 头像 / 说明）。
    var includeProfile: Bool
    /// 是否包含未完成的训练草稿。
    var includeDrafts: Bool
    var sessions: [WorkoutSession]
    var plans: [Plan]
    /// 自定义动作与收藏（并集，按 id 去重）。
    var exercises: [ExerciseLibraryItem]
    var measurements: [BodyMeasurement]
    var trainingPreferences: TrainingPreferencesSnapshot?
    var profile: UserProfile?
    /// 校验摘要：对语义内容取 FNV-1a 哈希。
    var checksum: String

    /// 供 `.sheet(item:)` / 结果展示使用的稳定标识。计算属性不参与编解码。
    var id: Date { createdAt }

    static let schemaVersion = 1
    static let formatIdentifier = "fitness-export-backup"
}

// MARK: - 编解码

enum ExportBackupCoder {

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 按所选数据段构造备份。
    ///
    /// - 训练记录只导出已完成的；进行中的草稿只有 `includeDrafts == true` 才并入；
    /// - 个人资料是「训练偏好与个人资料」段下的子开关：只有该段被勾选且
    ///   `includeProfile == true` 才导出（默认关闭，隐私优先）；
    /// - 训练偏好只有该段被勾选才导出；
    /// - 自定义动作与收藏取 `isCustom || isFavorite` 并集，按 id 去重后按 id 升序。
    static func makeBackup(
        sessions: [WorkoutSession],
        plans: [Plan],
        exercises: [ExerciseLibraryItem],
        measurements: [BodyMeasurement],
        preferences: TrainingPreferencesSnapshot?,
        profile: UserProfile?,
        segments: Set<ExportBackupSegment>,
        includeProfile: Bool,
        includeDrafts: Bool,
        appVersion: String,
        createdAt: Date = .now
    ) -> ExportBackup {
        let finished = sessions
            .filter(\.isFinished)
            .sorted { $0.startedAt < $1.startedAt }
        let drafts = sessions
            .filter { !$0.isFinished }
            .sorted { $0.startedAt < $1.startedAt }

        let includedSessions: [WorkoutSession]
        if segments.contains(.sessions) {
            includedSessions = includeDrafts ? finished + drafts : finished
        } else {
            includedSessions = []
        }

        let includedExercises: [ExerciseLibraryItem]
        if segments.contains(.exercises) {
            includedExercises = dedupeExercises(
                exercises.filter { $0.isCustom || $0.isFavorite }
            )
        } else {
            includedExercises = []
        }

        let exportPreferences = segments.contains(.preferences) ? preferences : nil
        let exportProfile = (segments.contains(.preferences) && includeProfile) ? profile : nil

        var backup = ExportBackup(
            schemaVersion: ExportBackup.schemaVersion,
            format: ExportBackup.formatIdentifier,
            createdAt: createdAt,
            appVersion: appVersion,
            appName: AppResources.appName,
            dataSegments: segments.map(\.rawValue).sorted(),
            includeProfile: includeProfile,
            includeDrafts: includeDrafts,
            sessions: includedSessions,
            plans: segments.contains(.plans) ? plans : [],
            exercises: includedExercises,
            measurements: segments.contains(.measurements) ? measurements : [],
            trainingPreferences: exportPreferences,
            profile: exportProfile,
            checksum: ""
        )
        backup.checksum = ExportBackupChecksum.digest(of: backup)
        return backup
    }

    static func encode(_ backup: ExportBackup) throws -> Data {
        try encoder().encode(backup)
    }

    /// 解码并校验。顺序：空文件 → JSON → 格式标识 → 结构版本。
    static func decode(_ data: Data) throws -> ExportBackup {
        guard !data.isEmpty else { throw ExportBackupError.emptyFile }

        let backup: ExportBackup
        do {
            backup = try decoder().decode(ExportBackup.self, from: data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw ExportBackupError.notJSON
            }
            throw ExportBackupError.wrongFormat(found: peekFormat(in: data) ?? "")
        }

        guard backup.format == ExportBackup.formatIdentifier else {
            throw ExportBackupError.wrongFormat(found: backup.format)
        }
        guard backup.schemaVersion <= ExportBackup.schemaVersion else {
            throw ExportBackupError.unsupportedSchema(found: backup.schemaVersion)
        }
        return backup
    }

    private static func peekFormat(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["format"] as? String
    }

    /// 按 id 去重并升序排列，保留先出现的那条。
    static func dedupeExercises(_ items: [ExerciseLibraryItem]) -> [ExerciseLibraryItem] {
        var seen = Set<String>()
        var result: [ExerciseLibraryItem] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result.sorted { $0.id < $1.id }
    }

    /// 备份文件名，如「本地数据备份-2026-09-19.json」
    static func fileName(for date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "本地数据备份-\(f.string(from: date)).json"
    }
}

// MARK: - 校验摘要

/// 校验摘要：FNV-1a 64 位哈希，纯 Swift 实现，无框架依赖，可被 Python 照搬。
enum ExportBackupChecksum {

    /// FNV-1a 64 位哈希。
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    /// 转成 16 位小写十六进制。
    static func hex(_ value: UInt64) -> String {
        let chars = Array("0123456789abcdef")
        var v = value
        var result = ""
        for _ in 0..<16 {
            result.append(chars[Int(v & 0xF)])
            v >>= 4
        }
        return String(result.reversed())
    }

    /// 对备份的语义内容取校验摘要。
    static func digest(of backup: ExportBackup) -> String {
        hex(fnv1a64(canonicalText(of: backup)))
    }

    /// 校验值是否与内容一致。
    static func isValid(_ backup: ExportBackup) -> Bool {
        digest(of: backup) == backup.checksum
    }

    /// 生成规范文本：包含格式、版本、段、开关与各类数据的 id 集合，
    /// 任何内容被改动都会改变摘要。刻意不含 `checksum` 字段本身。
    static func canonicalText(of backup: ExportBackup) -> String {
        var lines: [String] = []
        lines.append("format=\(backup.format)")
        lines.append("schema=\(backup.schemaVersion)")
        lines.append("app=\(backup.appVersion)")
        lines.append("segments=\(backup.dataSegments.joined(separator: ","))")
        lines.append("profile=\(backup.includeProfile)")
        lines.append("drafts=\(backup.includeDrafts)")
        lines.append("sessions=\(backup.sessions.map(\.id.uuidString).sorted().joined(separator: ","))")
        lines.append("plans=\(backup.plans.map(\.id.uuidString).sorted().joined(separator: ","))")
        lines.append("exercises=\(backup.exercises.map(\.id).sorted().joined(separator: ","))")
        lines.append("measurements=\(backup.measurements.map(\.id.uuidString).sorted().joined(separator: ","))")
        if let prefs = backup.trainingPreferences {
            lines.append("prefs=\(prefs.canonicalText)")
        }
        if let profile = backup.profile {
            lines.append("profileData=\(profileCanonicalText(profile))")
        }
        return lines.joined(separator: "\n")
    }

    private static func profileCanonicalText(_ p: UserProfile) -> String {
        "\(p.id.uuidString)|\(p.nickname ?? "")|\(p.trainingGoal?.rawValue ?? "")"
            + "|\(p.customGoal ?? "")|\(p.bio ?? "")|\(p.avatarFileName ?? "")"
            + "|\(Int(p.startedAt.timeIntervalSince1970))"
    }
}

// MARK: - 错误

enum ExportBackupError: LocalizedError, Equatable {
    case emptyFile
    case notJSON
    case wrongFormat(found: String)
    case unsupportedSchema(found: Int)
    case emptySelection
    case nothingToExport
    case encodeFailed
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "这个文件是空的，没有可导出的内容。"
        case .notJSON:
            return "备份结构不是有效的 JSON。"
        case .wrongFormat(let found):
            return found.isEmpty
                ? "这个文件缺少格式标识，可能不是本 App 导出的备份。"
                : "这个文件的格式是「\(found)」，不是本 App 的导出备份。"
        case .unsupportedSchema(let found):
            return "备份结构版本 \(found) 高于当前 App 支持的版本，请先升级 App。"
        case .emptySelection:
            return "请至少选择一类要导出的数据。"
        case .nothingToExport:
            return "所选范围内没有可导出的数据。"
        case .encodeFailed:
            return "备份结构序列化失败。"
        case .writeFailed:
            return "文件写入失败，请检查存储空间。"
        }
    }
}

// MARK: - 派生

extension ExportBackup {

    /// 是否至少含一类数据。
    var hasContent: Bool {
        !sessions.isEmpty || !plans.isEmpty || !exercises.isEmpty || !measurements.isEmpty
            || trainingPreferences != nil || profile != nil
    }

    /// 各段条目数摘要，供结果卡与提示使用。
    var countSummary: String {
        var parts: [String] = []
        if !sessions.isEmpty { parts.append("训练记录 \(sessions.count) 条") }
        if !plans.isEmpty { parts.append("计划 \(plans.count) 个") }
        if !exercises.isEmpty { parts.append("动作 \(exercises.count) 个") }
        if !measurements.isEmpty { parts.append("身体数据 \(measurements.count) 条") }
        if trainingPreferences != nil { parts.append("训练偏好") }
        if profile != nil { parts.append("个人资料") }
        return parts.isEmpty ? "无内容" : parts.joined(separator: "，")
    }
}

// MARK: - 大小估算

/// 导出文件大小的粗估。纯函数，只做量级参考，不是精确值。
enum ExportBackupSize {

    /// 按条数估算导出文件的字节数。
    static func estimate(
        sessionCount: Int,
        planCount: Int,
        exerciseCount: Int,
        measurementCount: Int,
        includePreferences: Bool,
        includeProfile: Bool
    ) -> Int64 {
        var bytes: Int64 = 0
        bytes += Int64(max(0, sessionCount)) * 2600      // 训练记录含组表
        bytes += Int64(max(0, planCount)) * 900          // 计划含动作条目
        bytes += Int64(max(0, exerciseCount)) * 1200     // 动作含说明与分步
        bytes += Int64(max(0, measurementCount)) * 260   // 身体数据
        if includePreferences { bytes += 600 }           // 训练偏好
        if includeProfile { bytes += 900 }               // 个人资料
        bytes += 400                                     // 头部元数据 + 校验摘要
        return bytes
    }
}
