//
//  WorkoutBackup.swift
//  本地备份的导出 / 导入 / 校验。
//
//  与 `PlanBackupWriter` 的分工：那个只导出**一个计划**，供用户单独保存训练安排；
//  这里导出的是**全部训练记录**，用于换机或重装前留一份底。
//  两者格式上都是 JSON、都带 format 与 version，但内容边界不同，故意不复用。
//
//  这一整个文件同样没有 SwiftUI 类型，能被 Python 侧照搬做推演。
//

import Foundation

// MARK: - 备份格式

/// 本地数据备份文件的结构。
///
/// 字段刻意**只有训练记录**：规格要求「清除全部训练记录」不得影响动作库与 App 设置，
/// 备份也遵循同一边界 —— 只备份可以被清除的那部分，导出与清除范围严格对齐。
/// 这样用户导入一份备份，得到的就是「训练记录恢复到导出时的样子」，
/// 不会意外把自己的动作库收藏或单位偏好改掉。
struct WorkoutBackup: Codable, Equatable {

    /// 固定为 `fitness-workouts-backup`，导入时校验用
    var format: String
    /// 格式版本。将来结构变化时靠它决定怎么读旧文件。
    var version: Int
    var exportedAt: Date
    /// 导出时的记录条数，便于导入前做一次粗略核对
    var sessionCount: Int
    var sessions: [WorkoutSession]

    /// 当前版本
    static let currentVersion = 1
    /// 格式标识
    static let formatIdentifier = "fitness-workouts-backup"
}

// MARK: - 导入结果

/// 导入结果。区分「空文件」与「格式不对」——提示语完全不同，
/// 前者可能是用户选错了文件，后者说明文件损坏。
enum WorkoutBackupError: LocalizedError, Equatable {
    case emptyFile
    case notJSON
    case wrongFormat(found: String)
    case unsupportedVersion(found: Int)
    case noSessions

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "这个文件是空的，没有可导入的内容。"
        case .notJSON:
            return "这个文件不是有效的 JSON，可能不是本 App 导出的备份。"
        case .wrongFormat(let found):
            return found.isEmpty
                ? "这个文件缺少格式标识，可能不是训练记录备份。"
                : "这个文件的格式是「\(found)」，不是训练记录备份。"
        case .unsupportedVersion(let found):
            return "备份版本 \(found) 高于当前 App 支持的版本，请先升级 App。"
        case .noSessions:
            return "备份里没有任何训练记录。"
        }
    }
}

/// 导入时对重复记录的处理方式。
enum WorkoutBackupMergePolicy: String, Equatable, CaseIterable, Identifiable {
    /// 追加不覆盖：同 id 记录以本机现有为准（默认）
    case keepExisting
    /// 用备份覆盖同 id 记录
    case overwriteExisting
    /// 清空本机记录后完全按备份恢复
    case replaceAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepExisting: return "合并，保留本机现有记录"
        case .overwriteExisting: return "合并，同一条以备份为准"
        case .replaceAll: return "清空本机记录后完全恢复"
        }
    }

    var subtitle: String {
        switch self {
        case .keepExisting: return "同一条训练以本机的版本为准，只补齐本机没有的"
        case .overwriteExisting: return "备份里的同一条训练会覆盖本机的版本"
        case .replaceAll: return "本机现有训练记录会全部被删除，只保留备份内容"
        }
    }

    var isDestructive: Bool { self == .replaceAll }
}

/// 合并计算的纯函数结果。
struct WorkoutBackupMergePlan: Equatable {
    /// 合并后应当落盘的完整记录集合
    let sessions: [WorkoutSession]
    /// 新增了几条
    let addedCount: Int
    /// 覆盖了几条
    let replacedCount: Int
    /// 因为策略跳过（本机已有且不覆盖）几条
    let skippedCount: Int

    var totalCount: Int { sessions.count }

    /// 给用户的 toast 文案
    var summaryText: String {
        var parts: [String] = []
        if addedCount > 0 { parts.append("新增 \(addedCount) 条") }
        if replacedCount > 0 { parts.append("覆盖 \(replacedCount) 条") }
        if skippedCount > 0 { parts.append("跳过 \(skippedCount) 条") }
        return parts.isEmpty ? "没有需要变更的记录" : parts.joined(separator: "，")
    }
}

// MARK: - 编解码

enum WorkoutBackupCoder {

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // prettyPrinted 让用户能用文本编辑器直接读改这份备份，
        // 与 PlanBackupWriter 保持一致。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// 构造备份对象。
    ///
    /// 只保留**已完成**的训练：进行中的草稿属于当前操作状态，
    /// 导出它没有意义，导入时还会在首页冒出一张「继续训练」卡。
    static func makeBackup(
        sessions: [WorkoutSession],
        exportedAt: Date = .now
    ) -> WorkoutBackup {
        let finished = sessions
            .filter { $0.isFinished }
            .sorted { $0.startedAt < $1.startedAt }

        return WorkoutBackup(
            format: WorkoutBackup.formatIdentifier,
            version: WorkoutBackup.currentVersion,
            exportedAt: exportedAt,
            sessionCount: finished.count,
            sessions: finished
        )
    }

    /// 编码成可写入文件的数据
    static func encode(_ backup: WorkoutBackup) throws -> Data {
        try encoder().encode(backup)
    }

    /// 解码并校验。
    ///
    /// 校验顺序有讲究：先看是不是空文件，再看是不是 JSON，再看格式标识，
    /// 最后才看版本。反过来做的话，一个被截断的 JSON 会报「版本不支持」，
    /// 把用户引到完全错误的方向。
    static func decode(_ data: Data) throws -> WorkoutBackup {
        guard !data.isEmpty else { throw WorkoutBackupError.emptyFile }

        let backup: WorkoutBackup
        do {
            backup = try decoder().decode(WorkoutBackup.self, from: data)
        } catch {
            // JSON 能解析但结构不对，与「根本不是 JSON」是两种提示。
            // 用 JSONSerialization 分辨一下，让提示更准。
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw WorkoutBackupError.notJSON
            }
            // 是合法 JSON 但缺字段：尝试只读出 format 字段用于提示
            let found = peekFormat(in: data) ?? ""
            throw WorkoutBackupError.wrongFormat(found: found)
        }

        guard backup.format == WorkoutBackup.formatIdentifier else {
            throw WorkoutBackupError.wrongFormat(found: backup.format)
        }
        guard backup.version <= WorkoutBackup.currentVersion else {
            throw WorkoutBackupError.unsupportedVersion(found: backup.version)
        }
        guard !backup.sessions.isEmpty else {
            throw WorkoutBackupError.noSessions
        }
        return backup
    }

    /// 从任意 JSON 里尽力读出 format 字段，仅用于生成更准确的错误提示。
    private static func peekFormat(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["format"] as? String
    }

    /// 备份文件名，如「训练记录备份-2026-09-19.json」
    static func fileName(for date: Date = .now) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "训练记录备份-\(f.string(from: date)).json"
    }
}

// MARK: - 合并

enum WorkoutBackupMerger {

    /// 按策略把备份合并进本机记录。
    ///
    /// 三条策略共用同一份实现，靠 `policy` 分支，避免三份几乎相同的代码各写一遍再各错一遍。
    static func merge(
        existing: [WorkoutSession],
        incoming: [WorkoutSession],
        policy: WorkoutBackupMergePolicy
    ) -> WorkoutBackupMergePlan {

        if policy == .replaceAll {
            // 完全恢复：本机的一律丢弃，按备份重建。
            // 这里要按 id 去重 —— 一份手改过的备份可能含重复 id，
            // 直接落盘会让详情页查到两条同名记录。
            let deduped = dedupe(incoming)
            return WorkoutBackupMergePlan(
                sessions: deduped.sorted { $0.startedAt < $1.startedAt },
                addedCount: deduped.count,
                replacedCount: 0,
                skippedCount: 0
            )
        }

        let existingIDs = Set(existing.map { $0.id })
        var result = existing
        var added = 0
        var replaced = 0
        var skipped = 0

        let dedupedIncoming = dedupe(incoming)

        for record in dedupedIncoming {
            if existingIDs.contains(record.id) {
                switch policy {
                case .keepExisting:
                    skipped += 1
                case .overwriteExisting:
                    if let index = result.firstIndex(where: { $0.id == record.id }) {
                        result[index] = record
                        replaced += 1
                    }
                case .replaceAll:
                    break // 上面已单独处理
                }
            } else {
                result.append(record)
                added += 1
            }
        }

        // 统一按开始时间升序落盘：仓储的 `fetchRecentSessions` 内部按倒序取，
        // 这里保证写入时的时间轴是单调的，便于人工核对备份文件。
        return WorkoutBackupMergePlan(
            sessions: result.sorted { $0.startedAt < $1.startedAt },
            addedCount: added,
            replacedCount: replaced,
            skippedCount: skipped
        )
    }

    /// 按 id 去重，保留**先出现**的那条。
    ///
    /// 保留先出现的而不是后出现的：备份是按开始时间升序生成的，
    /// 先出现的通常是最初写下的那一版；后出现的是重复追加的副本。
    static func dedupe(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        var seen = Set<UUID>()
        var result: [WorkoutSession] = []
        for session in sessions where !seen.contains(session.id) {
            seen.insert(session.id)
            result.append(session)
        }
        return result
    }
}

// MARK: - 清除范围

/// 「清除全部训练记录」到底清什么。
///
/// 这个枚举的存在本身就是一条契约：规格要求明确「不会删除动作库或 App 设置」，
/// 所以把「要清哪些集合」写成一个可枚举、可断言的对象，
/// 而不是在清空代码里隐式地只写几行 removeAll。
enum WorkoutDataScope: String, CaseIterable, Identifiable {
    /// 训练记录
    case sessions
    /// 休息日标记（同属训练时间轴上的记录，与训练记录一同清除）
    case restDays
    /// 组间休息临时状态
    case restTimer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sessions: return "训练记录"
        case .restDays: return "休息日标记"
        case .restTimer: return "进行中的休息计时"
        }
    }
}

/// 清除范围的两个集合，用于断言与提示文案。
enum WorkoutDataPolicy {

    /// 清除操作会动的数据
    static let clearedScopes: [WorkoutDataScope] = [.sessions, .restDays, .restTimer]

    /// 清除操作**不会**动的数据。这份清单是给用户的承诺，也是给测试的断言目标。
    static let preservedItems: [String] = [
        "动作库（含自建动作、收藏与隐藏状态）",
        "训练计划",
        "最近使用的动作",
        "身体数据",
        "App 设置与偏好",
    ]

    /// 二次确认里那段必须逐字出现的说明
    static let confirmMessage = "只清除本机的训练记录与休息日标记，动作库、训练计划、身体数据和 App 设置都会保留。此操作无法撤销。"

    /// 清除后的 toast
    static let clearedToast = "训练记录已清除"
}
