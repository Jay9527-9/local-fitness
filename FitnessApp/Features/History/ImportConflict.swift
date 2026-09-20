//
//  ImportConflict.swift
//  页面 21：导入冲突处理的纯值层。
//
//  三种导入策略 + 影响数量估算。冲突定义：本机与备份中存在相同 ID 的条目
//  （身体数据同一自然日、计划同名这些「可识别冲突」在导出/导入往返中
//   都以同一 ID 体现，故统一按 ID 判）。
//
//  无 SwiftUI 引入，可被 Python 照搬推演。
//

import Foundation

// MARK: - 导入策略

/// 三种导入策略。每种映射到一组 (mode, policy)。
enum ImportStrategy: String, CaseIterable, Identifiable {
    case mergeKeepLocal
    case mergeKeepBackup
    case replaceAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mergeKeepLocal: return "合并并保留本机数据"
        case .mergeKeepBackup: return "合并并优先备份数据"
        case .replaceAll: return "覆盖本机全部数据"
        }
    }

    var subtitle: String {
        switch self {
        case .mergeKeepLocal: return "只新增不存在的记录；冲突项保留本机版本"
        case .mergeKeepBackup: return "只新增不存在的记录；冲突项以备份版本覆盖本机"
        case .replaceAll: return "删除当前所有本地个人数据，再导入备份"
        }
    }

    /// 是否属于「覆盖」这类破坏性策略（需要二次确认）。
    var isDestructive: Bool { self == .replaceAll }

    /// 对应的导入方式。
    var mode: ImportMode {
        self == .replaceAll ? .replace : .merge
    }

    /// 对应的冲突策略。
    var policy: ConflictPolicy {
        self == .mergeKeepBackup ? .keepBackup : .keepLocal
    }
}

// MARK: - 影响数量

/// 某一集合的影响数量。
struct CategoryImpact: Equatable {
    var added: Int = 0
    var conflicts: Int = 0
}

/// 各集合的影响数量汇总。
struct ImportImpact: Equatable {
    var sessions = CategoryImpact()
    var plans = CategoryImpact()
    var measurements = CategoryImpact()
    var exercises = CategoryImpact()

    var totalAdded: Int { sessions.added + plans.added + measurements.added + exercises.added }
    var totalConflicts: Int {
        sessions.conflicts + plans.conflicts + measurements.conflicts + exercises.conflicts
    }

    /// 当前策略下的影响摘要文本。
    func summaryText(mode: ImportMode, policy: ConflictPolicy) -> String {
        switch mode {
        case .merge:
            if totalAdded == 0 && totalConflicts == 0 {
                return "备份与本机数据一致，没有需要变更的条目。"
            }
            var parts: [String] = []
            if totalAdded > 0 { parts.append("新增 \(totalAdded) 条") }
            if totalConflicts > 0 { parts.append("\(totalConflicts) 个冲突按「\(policy.title)」处理") }
            return "将" + parts.joined(separator: "，") + "。"
        case .replace:
            let total = totalAdded + totalConflicts
            return total == 0
                ? "覆盖后本机数据将被清空。"
                : "将删除本机数据，导入备份中的 \(total) 条数据。"
        }
    }
}

// MARK: - 影响分析

/// 对比本机与备份，按 ID 计算每个集合的「新增 / 冲突」数量。
enum ImportConflictAnalysis {

    static func impact(
        sessions: [WorkoutSession],
        plans: [Plan],
        exercises: [ExerciseLibraryItem],
        measurements: [BodyMeasurement],
        backup: ExportBackup
    ) -> ImportImpact {
        ImportImpact(
            sessions: categoryImpact(
                existing: sessions, incoming: backup.sessions, key: { $0.id.uuidString }),
            plans: categoryImpact(
                existing: plans, incoming: backup.plans, key: { $0.id.uuidString }),
            measurements: categoryImpact(
                existing: measurements, incoming: backup.measurements, key: { $0.id.uuidString }),
            exercises: categoryImpact(
                existing: exercises.filter(\.isCustom),
                incoming: backup.exercises.filter(\.isCustom),
                key: { $0.id })
        )
    }

    /// 计算某一集合的新增 / 冲突数。冲突 = 本机与备份同 key。
    private static func categoryImpact<T>(
        existing: [T],
        incoming: [T],
        key: (T) -> String
    ) -> CategoryImpact {
        let existingKeys = Set(existing.map(key))
        var impact = CategoryImpact()
        for item in incoming {
            if existingKeys.contains(key(item)) {
                impact.conflicts += 1
            } else {
                impact.added += 1
            }
        }
        return impact
    }
}
