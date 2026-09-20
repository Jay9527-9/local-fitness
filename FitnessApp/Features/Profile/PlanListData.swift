//
//  PlanListData.swift
//  页面 15「我的计划」的值语义层。
//
//  **这个文件不 import SwiftUI**，全是纯值类型、常量与纯函数，
//  可被 Python 照搬推演（见 `Tools/probe_page15_semantics.py`）。
//
//  覆盖：排序（最近使用 / 最近创建 / 计划名称 / 训练天数）、
//  计划列表的搜索筛选、复制计划的命名（「原名称（副本）」防叠加）、
//  以及多计划本地备份的导出 / 导入 / 校验。
//

import Foundation

// MARK: - 排序

/// 「我的计划」列表的排序方式。
enum PlanSortOrder: String, CaseIterable, Identifiable, Equatable {
    case recentlyUsed
    case recentlyCreated
    case name
    case trainingDays

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUsed: return "最近使用"
        case .recentlyCreated: return "最近创建"
        case .name: return "计划名称"
        case .trainingDays: return "训练天数"
        }
    }
}

/// 排序与筛选的纯函数。不依赖任何视图状态。
enum PlanListSorting {

    /// 按指定方式排序。**稳定排序**：同键值按 `id` 兜底，避免每次刷新顺序跳变。
    static func sort(_ plans: [Plan], by order: PlanSortOrder) -> [Plan] {
        switch order {
        case .recentlyUsed:
            // 最近使用 = lastUsedAt 降序；从未用过的（nil）排最后。
            return plans.sorted { lhs, rhs in
                switch (lhs.lastUsedAt, rhs.lastUsedAt) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.id.uuidString < rhs.id.uuidString
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil):
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            }
        case .recentlyCreated:
            return plans.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .name:
            return plans.sorted { lhs, rhs in
                let comparison = lhs.name.localizedStandardCompare(rhs.name)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        case .trainingDays:
            // 训练天数 = 每周安排的天数降序；天数相同按 id 兜底。
            return plans.sorted { lhs, rhs in
                let l = lhs.trainingDays.count
                let r = rhs.trainingDays.count
                if l != r { return l > r }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
    }

    /// 按名称实时筛选。空查询返回全部。
    static func filter(_ plans: [Plan], query: String) -> [Plan] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return plans }
        return plans.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }
}

// MARK: - 复制命名

/// 复制计划的命名。规格要求「原名称（副本）」。
enum PlanCopyName {

    /// 生成副本名。已经以「（副本）」结尾时不再叠加，避免「推拉腿（副本）（副本）」。
    static func makeCopyName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "计划" : trimmed
        if base.hasSuffix("（副本）") { return base }
        return "\(base)（副本）"
    }
}

// MARK: - 计划备份（多计划）

/// 计划备份文件的结构。与 `WorkoutBackup`（训练记录备份）和页面 04 的
/// `PlanBackupWriter`（单计划导出）都不同：这里导出**多个计划**，供
/// 「我的计划」多选模式批量导出，以及「＋」菜单导入。
///
/// 字段只保留能重建计划所需的信息：名称、训练日、动作配置。
/// 不含训练历史、动作库收藏状态或任何账号数据。
struct PlanBackup: Codable, Equatable {
    /// 固定为 `fitness-plans-backup`，导入时校验用
    var format: String
    /// 格式版本
    var version: Int
    var exportedAt: Date
    /// 备份的计划数量
    var planCount: Int
    var plans: [PlanBackupPayload]

    static let currentVersion = 1
    static let formatIdentifier = "fitness-plans-backup"
}

/// 单个计划在备份文件里的载荷。
struct PlanBackupPayload: Codable, Equatable {
    var name: String
    var trainingDays: [Int]
    var exercises: [PlanBackupExercise]
}

/// 计划里一个动作在备份文件里的载荷。
///
/// 刻意不含 `PlanExercise.id`：导入时每个条目都生成新 id，
/// 避免与源计划共享引用（与仓储 `duplicate(planID:)` 同一契约）。
struct PlanBackupExercise: Codable, Equatable {
    var exerciseID: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var restSeconds: Int
    var isWarmup: Bool
    var note: String?
    var progression: String
}

/// 计划备份导入时的错误。
enum PlanBackupError: LocalizedError, Equatable {
    case emptyFile
    case notJSON
    case wrongFormat(found: String)
    case unsupportedVersion(found: Int)
    case noPlans

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "这个文件是空的，没有可导入的内容。"
        case .notJSON:
            return "这个文件不是有效的 JSON，可能不是本 App 导出的计划备份。"
        case .wrongFormat(let found):
            return found.isEmpty
                ? "这个文件缺少格式标识，可能不是计划备份。"
                : "这个文件的格式是「\(found)」，不是计划备份。"
        case .unsupportedVersion(let found):
            return "计划备份版本 \(found) 高于当前 App 支持的版本，请先升级 App。"
        case .noPlans:
            return "备份里没有任何计划。"
        }
    }
}

// MARK: - 编解码

enum PlanBackupCodec {

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

    /// 把一批计划编码成备份对象。
    static func makeBackup(plans: [Plan], exportedAt: Date = .now) -> PlanBackup {
        PlanBackup(
            format: PlanBackup.formatIdentifier,
            version: PlanBackup.currentVersion,
            exportedAt: exportedAt,
            planCount: plans.count,
            plans: plans.map { PlanBackupPayload(plan: $0) }
        )
    }

    /// 编码成可写入文件的数据。
    static func encode(_ backup: PlanBackup) throws -> Data {
        try encoder().encode(backup)
    }

    /// 解码并校验。校验顺序与 `WorkoutBackupCoder` 同款：
    /// 先空文件 → 再 JSON → 再格式标识 → 最后版本。
    static func decode(_ data: Data) throws -> [Plan] {
        guard !data.isEmpty else { throw PlanBackupError.emptyFile }

        let backup: PlanBackup
        do {
            backup = try decoder().decode(PlanBackup.self, from: data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data)) == nil {
                throw PlanBackupError.notJSON
            }
            let found = peekFormat(in: data) ?? ""
            throw PlanBackupError.wrongFormat(found: found)
        }

        guard backup.format == PlanBackup.formatIdentifier else {
            throw PlanBackupError.wrongFormat(found: backup.format)
        }
        guard backup.version <= PlanBackup.currentVersion else {
            throw PlanBackupError.unsupportedVersion(found: backup.version)
        }
        guard !backup.plans.isEmpty else {
            throw PlanBackupError.noPlans
        }
        return backup.plans.map { $0.toPlan() }
    }

    /// 从任意 JSON 里尽力读出 format 字段，仅用于生成更准确的错误提示。
    private static func peekFormat(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["format"] as? String
    }

    /// 写一个多计划备份文件到临时目录，返回文件 URL 供分享面板使用。
    static func write(plans: [Plan], exportedAt: Date = .now) throws -> URL {
        let backup = makeBackup(plans: plans, exportedAt: exportedAt)
        let data = try encode(backup)

        let fileName = "训练计划备份-\(dateStamp(exportedAt)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw PlanBackupError.notJSON
        }
        return url
    }

    /// 文件名里的日期戳，如「2026-09-19」。
    private static func dateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - 载荷 ↔ 计划转换

extension PlanBackupPayload {

    /// 从计划构造载荷。
    init(plan: Plan) {
        self.init(
            name: plan.name,
            trainingDays: plan.trainingDays,
            exercises: plan.exercises.map { PlanBackupExercise(entry: $0) }
        )
    }

    /// 还原成全新计划：新 id、新动作条目 id，时间戳记为现在，`lastUsedAt` 清空。
    /// 导入的计划是一份「新」计划，不继承源计划的训练历史。
    func toPlan() -> Plan {
        Plan(
            id: UUID(),
            name: name,
            trainingDays: trainingDays,
            exercises: exercises.map { $0.toPlanExercise() },
            createdAt: .now,
            updatedAt: .now,
            lastUsedAt: nil
        )
    }
}

extension PlanBackupExercise {

    init(entry: PlanExercise) {
        self.init(
            exerciseID: entry.exerciseID,
            sets: entry.sets,
            repsLow: entry.repsLow,
            repsHigh: entry.repsHigh,
            restSeconds: entry.restSeconds,
            isWarmup: entry.isWarmup,
            note: entry.note,
            progression: entry.progression.rawValue
        )
    }

    /// 还原成一个新的动作条目。id 重新生成。
    func toPlanExercise() -> PlanExercise {
        PlanExercise(
            id: UUID(),
            exerciseID: exerciseID,
            sets: sets,
            repsLow: repsLow,
            repsHigh: repsHigh,
            restSeconds: restSeconds,
            isWarmup: isWarmup,
            note: note,
            progression: ProgressionRule(rawValue: progression) ?? .none
        )
    }
}
