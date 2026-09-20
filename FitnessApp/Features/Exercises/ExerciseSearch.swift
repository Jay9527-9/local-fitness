//
//  ExerciseSearch.swift
//  动作库的本地检索内核：别名匹配、加权评分、筛选、排序。
//
//  纯函数，不持有状态、不触网络。输入 1324 条动作的数组，输出排序后的结果。
//  放在独立文件里，便于单测与在预览中替换实现。
//

import Foundation

// MARK: - 检索

enum ExerciseSearch {

    /// 名称完全匹配的权重最高，别名 / 肌群 / 器械依次递减。
    private enum Weight {
        static let nameExact = 1000
        static let namePrefix = 600
        static let nameContains = 400
        static let aliasExact = 500
        static let aliasContains = 300
        static let primaryMuscle = 200
        static let secondaryMuscle = 120
        static let equipment = 150
        static let favorite = 60
        static let custom = 40
    }

    /// 先按筛选条件裁剪，再按关键词评分排序。
    /// - Parameters:
    ///   - items: 全量动作（含或不含隐藏条目都可，本函数会自行按 filter 判断）
    ///   - keyword: 用户输入，空串表示只做筛选不做检索
    ///   - filter: 筛选条件
    ///   - sort: 排序方式。`.defaultOrder` 在关键词为空时保持内置顺序、有关键词时按相关度。
    ///   - recentRank: 动作 id → 最近使用次序（0 最新），用于 `.recentlyUsed` 排序
    static func apply(
        to items: [ExerciseLibraryItem],
        keyword: String,
        filter: ExerciseFilter,
        sort: ExerciseSortOrder = .defaultOrder,
        recentRank: [String: Int] = [:]
    ) -> [ExerciseLibraryItem] {

        let filtered = items.filter { matches($0, filter: filter) }

        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return sorted(filtered, by: sort, recentRank: recentRank)
        }

        let needle = trimmed.lowercased()

        // 评分与筛选并行完成，命中 0 分的直接丢弃
        let scored: [(item: ExerciseLibraryItem, score: Int)] = filtered.compactMap { item in
            let score = self.score(item, needle: needle)
            return score > 0 ? (item, score) : nil
        }

        let matched = scored.map(\.item)

        switch sort {
        case .defaultOrder:
            return scored
                .sorted { lhs, rhs in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return nameAscending(lhs.item, rhs.item)
                }
                .map(\.item)
        default:
            return sorted(matched, by: sort, recentRank: recentRank)
        }
    }

    // MARK: 筛选

    static func matches(_ item: ExerciseLibraryItem, filter: ExerciseFilter) -> Bool {
        if item.isHidden && !filter.includeHidden { return false }
        switch filter.source {
        case .all: break
        case .builtin: if item.isCustom { return false }
        case .custom: if !item.isCustom { return false }
        }
        if filter.onlyFavorite && !item.isFavorite { return false }

        if let category = filter.muscleCategory {
            // 大类按「分类命中 或 主肌群命中」判断，避免 glutes 这类
            // 数据源归在「腿」下但用户按「臀」找时搜不到。
            let hitCategory = item.categoryZh == category
            let hitMuscle = MuscleIconGroup.of(muscle: item.primaryMuscleText).title == category
            guard hitCategory || hitMuscle else { return false }
        }

        if !filter.muscleGroups.isEmpty {
            let group = MuscleIconGroup.of(muscle: item.primaryMuscleText).title
            let hit = filter.muscleGroups.contains(item.categoryZh) || filter.muscleGroups.contains(group)
            guard hit else { return false }
        }

        if !filter.equipments.isEmpty {
            guard filter.equipments.contains(item.equipmentText) else { return false }
        }

        if let difficulty = filter.difficulty {
            guard item.difficulty == difficulty else { return false }
        }

        return true
    }

    // MARK: 评分

    /// 命中越靠前、字段越核心，得分越高。返回 0 表示不匹配。
    static func score(_ item: ExerciseLibraryItem, needle: String) -> Int {
        var total = 0
        let name = item.name.lowercased()

        // 名称
        if name == needle {
            total += Weight.nameExact
        } else if name.hasPrefix(needle) {
            total += Weight.namePrefix
        } else if name.contains(needle) {
            total += Weight.nameContains
        }

        // 别名：中文说法大多落在这里
        for alias in item.aliases {
            let lowered = alias.lowercased()
            if lowered == needle {
                total += Weight.aliasExact
                break
            } else if lowered.contains(needle) {
                total += Weight.aliasContains
                break
            }
        }

        // 主肌群（中文名 + 英文 target 都匹配）
        let primary = item.primaryMuscleText.lowercased()
        if primary.contains(needle) || item.target.lowercased().contains(needle) {
            total += Weight.primaryMuscle
        }

        // 次级肌群（中文名 + 英文标识）
        let secondaryHit = item.secondaryMuscles.contains { group in
            group.lowercased().contains(needle)
                || MuscleName.zhGroup(group).lowercased().contains(needle)
        }
        if secondaryHit { total += Weight.secondaryMuscle }

        // 器械（中文名 + 英文名）
        let equipment = item.equipmentText.lowercased()
        if equipment.contains(needle) || item.equipment.lowercased().contains(needle) {
            total += Weight.equipment
        }

        // 同分时让收藏与自定义动作稍微靠前
        if total > 0 {
            if item.isFavorite { total += Weight.favorite }
            if item.isCustom { total += Weight.custom }
        }

        return total
    }

    // MARK: 排序

    static func sorted(
        _ items: [ExerciseLibraryItem],
        by sort: ExerciseSortOrder,
        recentRank: [String: Int] = [:]
    ) -> [ExerciseLibraryItem] {
        switch sort {
        case .defaultOrder:
            // 默认推荐：保持动作库内置顺序，不重排。
            return items

        case .name:
            return items.sorted(by: nameAscending)

        case .difficulty:
            return items.sorted { lhs, rhs in
                if lhs.difficulty.order != rhs.difficulty.order {
                    return lhs.difficulty.order < rhs.difficulty.order
                }
                return nameAscending(lhs, rhs)
            }

        case .recentlyUsed:
            return items.sorted { lhs, rhs in
                let l = recentRank[lhs.id] ?? Int.max
                let r = recentRank[rhs.id] ?? Int.max
                if l != r { return l < r }
                return nameAscending(lhs, rhs)
            }

        case .recentlyFavorited:
            return items.sorted { lhs, rhs in
                let l = lhs.favoritedAt ?? .distantPast
                let r = rhs.favoritedAt ?? .distantPast
                if l != r { return l > r }
                return nameAscending(lhs, rhs)
            }
        }
    }

    private static func nameAscending(
        _ lhs: ExerciseLibraryItem,
        _ rhs: ExerciseLibraryItem
    ) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

// MARK: - 可用筛选项

extension ExerciseSearch {

    /// 从当前数据集推导出可用的器械清单（按出现次数降序），
    /// 而不是硬编码一份可能与数据脱节的列表。
    static func availableEquipments(in items: [ExerciseLibraryItem]) -> [String] {
        var counter: [String: Int] = [:]
        for item in items {
            let key = item.equipmentText
            guard !key.isEmpty else { continue }
            counter[key, default: 0] += 1
        }
        return counter
            .sorted { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            }
            .map(\.key)
    }

    /// 各肌群大类下的动作数，用于 Chip 上的角标
    static func muscleCounts(in items: [ExerciseLibraryItem]) -> [String: Int] {
        var counter: [String: Int] = [:]
        for item in items where !item.isHidden {
            counter[item.categoryZh, default: 0] += 1
        }
        return counter
    }

    /// 最近使用次序表：id → 0 起的名次
    static func recentRank(of items: [ExerciseLibraryItem]) -> [String: Int] {
        var rank: [String: Int] = [:]
        for (index, item) in items.enumerated() where rank[item.id] == nil {
            rank[item.id] = index
        }
        return rank
    }
}
