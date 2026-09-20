//
//  ImportBackup.swift
//  页面 20：导入本地备份的纯值层。
//
//  只处理 `ExportBackup`（页面 19 导出的版本化 JSON）的预检与合并计算。
//  预检顺序：文件格式 → schemaVersion → 校验摘要 → 数据字段 → 数据数量 → 损坏。
//  预检期间不写任何本机数据；合并计算是纯函数，可被 Python 照搬推演。
//
//  与页面 10 的 WorkoutBackupMerger 分工：那个只合并训练记录（sessions-only）；
//  这里合并训练记录 / 计划 / 自定义动作 / 身体数据四类集合，并给出
//  「新增 / 更新 / 跳过 / 冲突解决」四类计数。偏好与个人资料是单对象设置，
//  不在计数之列（有则覆盖）。
//

import Foundation

// MARK: - 导入方式

/// 导入方式。默认「合并到本地数据」。
enum ImportMode: String, CaseIterable, Identifiable {
    /// 合并：本机独有保留，冲突按 ConflictPolicy 处理。
    case merge
    /// 覆盖：冲突一律以备份为准（等价于 merge + keepBackup）。
    case replace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merge: return "合并到本地数据"
        case .replace: return "覆盖本地数据"
        }
    }

    var subtitle: String {
        switch self {
        case .merge: return "保留本机独有的数据，只补齐备份里没有的"
        case .replace: return "冲突条目一律以备份为准"
        }
    }
}

// MARK: - 冲突处理

/// 合并模式下，同一条目本机与备份都存在时以谁为准。
enum ConflictPolicy: String, CaseIterable, Identifiable {
    /// 以本机为准（跳过备份里的同名条目）。默认，破坏性最小。
    case keepLocal
    /// 以备份为准（覆盖本机同名条目）。
    case keepBackup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepLocal: return "以本机为准"
        case .keepBackup: return "以备份为准"
        }
    }

    var subtitle: String {
        switch self {
        case .keepLocal: return "同一条目保留本机版本，只补新的"
        case .keepBackup: return "同一条目用备份版本覆盖本机"
        }
    }
}

// MARK: - 计数

/// 一次集合合并的计数。`conflictsResolved == updated + skipped`：
/// 每一个冲突都会被消解为「更新」（备份胜）或「跳过」（本机胜）。
struct ImportCounts: Equatable {
    var added: Int = 0
    var updated: Int = 0
    var skipped: Int = 0

    var conflictsResolved: Int { updated + skipped }

    /// 累加另一个集合的计数。
    static func + (lhs: ImportCounts, rhs: ImportCounts) -> ImportCounts {
        ImportCounts(
            added: lhs.added + rhs.added,
            updated: lhs.updated + rhs.updated,
            skipped: lhs.skipped + rhs.skipped
        )
    }

    /// 成功页的摘要文案。
    var summaryText: String {
        var parts: [String] = []
        if added > 0 { parts.append("新增 \(added)") }
        if updated > 0 { parts.append("更新 \(updated)") }
        if skipped > 0 { parts.append("跳过 \(skipped)") }
        if conflictsResolved > 0 { parts.append("冲突解决 \(conflictsResolved)") }
        return parts.isEmpty ? "没有需要变更的数据" : parts.joined(separator: "，")
    }
}

// MARK: - 错误

enum ImportBackupError: LocalizedError, Equatable {
    case checksumMismatch
    case missingSegments
    case noContent

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "校验摘要不匹配，文件可能已损坏。"
        case .missingSegments:
            return "备份缺少数据段标识，无法确认其内容。"
        case .noContent:
            return "备份里没有任何可导入的数据。"
        }
    }
}

// MARK: - 备份摘要

/// 预检通过后展示的备份摘要。
struct ImportBackupSummary: Equatable {
    let createdAt: Date
    let appVersion: String
    let sessionCount: Int
    let planCount: Int
    let customExerciseCount: Int
    let measurementCount: Int
    let includeProfile: Bool
    let includeDrafts: Bool
}

extension ExportBackup {
    /// 预检页摘要。
    var importSummary: ImportBackupSummary {
        ImportBackupSummary(
            createdAt: createdAt,
            appVersion: appVersion,
            sessionCount: sessions.count,
            planCount: plans.count,
            customExerciseCount: exercises.filter(\.isCustom).count,
            measurementCount: measurements.count,
            includeProfile: includeProfile,
            includeDrafts: includeDrafts
        )
    }
}

// MARK: - 预检

/// 预检。decode 已负责「格式 / schemaVersion」两关，这里补后四关。
enum ImportPrecheck {

    enum Step: String, CaseIterable, Identifiable {
        case format
        case schema
        case checksum
        case fields
        case counts
        case integrity

        var id: String { rawValue }

        var title: String {
            switch self {
            case .format: return "文件格式"
            case .schema: return "结构版本"
            case .checksum: return "校验摘要"
            case .fields: return "数据字段"
            case .counts: return "数据数量"
            case .integrity: return "文件完整性"
            }
        }
    }

    /// 校验一个已解码的备份。抛 `ExportBackupError` / `ImportBackupError`。
    /// **只读**：不改任何本机数据。按六步顺序可拆开调用。
    static func validate(_ backup: ExportBackup) throws {
        try checkChecksum(backup)
        try checkFields(backup)
        try checkCounts(backup)
        try checkIntegrity(backup)
    }

    /// 校验摘要一致。
    static func checkChecksum(_ backup: ExportBackup) throws {
        guard ExportBackupChecksum.isValid(backup) else {
            throw ImportBackupError.checksumMismatch
        }
    }

    /// 数据段标识非空。
    static func checkFields(_ backup: ExportBackup) throws {
        guard !backup.dataSegments.isEmpty else {
            throw ImportBackupError.missingSegments
        }
    }

    /// 数据数量：声明的段与内容一致——声明了训练记录却为空视为损坏。
    static func checkCounts(_ backup: ExportBackup) throws {
        if backup.dataSegments.contains(ExportBackupSegment.sessions.rawValue)
            && backup.sessions.isEmpty {
            throw ImportBackupError.noContent
        }
    }

    /// 文件完整性：整体必须有至少一类数据。
    static func checkIntegrity(_ backup: ExportBackup) throws {
        guard backup.hasContent else {
            throw ImportBackupError.noContent
        }
    }
}

// MARK: - 合并

/// 各集合的合并计算。纯函数，不写盘。
enum ImportMerge {

    /// 通用合并：按 key 判定「本机是否有同名条目」，按 mode / policy 消解冲突。
    ///
    /// - `merge`：本机独有保留，冲突按 `policy` 处理（keepLocal 跳过 / keepBackup 覆盖）；
    /// - `replace`：破坏性覆盖——本机条目全部丢弃，只保留备份条目（去重后）。
    static func merge<T>(
        existing: [T],
        incoming: [T],
        key: (T) -> String,
        mode: ImportMode,
        policy: ConflictPolicy,
        dedupe: ([T]) -> [T]
    ) -> (items: [T], counts: ImportCounts) {
        let incomingDeduped = dedupe(incoming)

        if mode == .replace {
            // 覆盖本机全部数据：本机丢弃，仅保留备份（去重）。
            return (incomingDeduped, ImportCounts(added: incomingDeduped.count))
        }

        var result = existing
        var counts = ImportCounts()
        var existingKeys = Set(existing.map(key))

        for item in incomingDeduped {
            let k = key(item)
            if existingKeys.contains(k) {
                if policy == .keepBackup {
                    if let i = result.firstIndex(where: { key($0) == k }) {
                        result[i] = item
                        counts.updated += 1
                    }
                } else {
                    counts.skipped += 1
                }
            } else {
                result.append(item)
                counts.added += 1
            }
        }
        return (result, counts)
    }

    // MARK: 训练记录

    static func mergeSessions(
        existing: [WorkoutSession],
        incoming: [WorkoutSession],
        mode: ImportMode,
        policy: ConflictPolicy
    ) -> (sessions: [WorkoutSession], counts: ImportCounts) {
        let r = merge(
            existing: existing,
            incoming: incoming,
            key: { $0.id.uuidString },
            mode: mode,
            policy: policy,
            dedupe: { dedupeByID($0).sorted { $0.startedAt < $1.startedAt } }
        )
        return (r.items.sorted { $0.startedAt < $1.startedAt }, r.counts)
    }

    // MARK: 计划

    static func mergePlans(
        existing: [Plan],
        incoming: [Plan],
        mode: ImportMode,
        policy: ConflictPolicy
    ) -> (plans: [Plan], counts: ImportCounts) {
        let r = merge(
            existing: existing,
            incoming: incoming,
            key: { $0.id.uuidString },
            mode: mode,
            policy: policy,
            dedupe: { dedupeByID($0).sorted { $0.updatedAt > $1.updatedAt } }
        )
        return (r.items.sorted { $0.updatedAt > $1.updatedAt }, r.counts)
    }

    // MARK: 自定义动作与收藏

    /// 合并动作库：只处理自定义动作（计数），收藏标记施加到匹配的内置 / 自建条目。
    /// 内置种子动作不动。
    static func mergeExercises(
        existing: [ExerciseLibraryItem],
        incoming: [ExerciseLibraryItem],
        mode: ImportMode,
        policy: ConflictPolicy
    ) -> (library: [ExerciseLibraryItem], counts: ImportCounts) {
        let customs = incoming.filter(\.isCustom)
        let favorites = incoming.filter { $0.isFavorite && !$0.isCustom }

        let merged = merge(
            existing: existing,
            incoming: customs,
            key: { $0.id },
            mode: mode,
            policy: policy,
            dedupe: { dedupeByID($0).sorted { $0.id < $1.id } }
        )

        // 收藏标记：对备份里标记了收藏的内置动作，把本机对应条目置为收藏。
        var library = merged.items
        let favoriteIDs = Set(favorites.map(\.id))
        if !favoriteIDs.isEmpty {
            for i in library.indices where favoriteIDs.contains(library[i].id) {
                library[i].isFavorite = true
            }
        }
        return (library, merged.counts)
    }

    // MARK: 身体数据

    static func mergeMeasurements(
        existing: [BodyMeasurement],
        incoming: [BodyMeasurement],
        mode: ImportMode,
        policy: ConflictPolicy
    ) -> (measurements: [BodyMeasurement], counts: ImportCounts) {
        let r = merge(
            existing: existing,
            incoming: incoming,
            key: { $0.id.uuidString },
            mode: mode,
            policy: policy,
            dedupe: { dedupeByID($0).sorted { $0.date < $1.date } }
        )
        return (r.items.sorted { $0.date < $1.date }, r.counts)
    }

    // MARK: 去重

    private static func dedupeByID<T: Identifiable>(_ items: [T]) -> [T]
        where T.ID: Hashable {
        var seen = Set<T.ID>()
        var result: [T] = []
        for item in items where !seen.contains(item.id) {
            seen.insert(item.id)
            result.append(item)
        }
        return result
    }
}
