//
//  FavoriteExercisesSort.swift
//  页面 16：收藏动作的排序与筛选内核（纯函数，不持有状态）。
//
//  数据只来自本地动作库的 `isFavorite` 状态；检索复用动作库的评分器，
//  排序里新增「最近收藏」维度，依据是条目上的 `favoritedAt` 时间戳。
//

import Foundation

// MARK: - 排序方式

/// 收藏动作页面的排序方式
enum FavoriteSortOrder: String, CaseIterable, Identifiable {
    case recentlyFavorited
    case name
    case primaryMuscle
    case recentlyUsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyFavorited: return "最近收藏"
        case .name: return "动作名称"
        case .primaryMuscle: return "主肌群"
        case .recentlyUsed: return "最近使用"
        }
    }
}

// MARK: - 筛选与排序内核

enum FavoriteExercisesFilter {

    /// 先按肌群与关键词裁剪，再按排序方式排序。
    /// - Parameters:
    ///   - items: 已收藏的动作（调用方保证只传入 `isFavorite == true` 的条目）
    ///   - keyword: 检索关键词，空串表示不限
    ///   - muscleCategory: 肌群大类（如「胸」「背」），nil 表示全部
    ///   - sort: 排序方式
    ///   - recentRank: 动作 id → 最近使用名次（0 最新），用于 `.recentlyUsed`
    static func apply(
        to items: [ExerciseLibraryItem],
        keyword: String,
        muscleCategory: String?,
        sort: FavoriteSortOrder,
        recentRank: [String: Int]
    ) -> [ExerciseLibraryItem] {
        var filtered = items

        if let category = muscleCategory {
            filtered = filtered.filter {
                $0.categoryZh == category
                    || MuscleIconGroup.of(muscle: $0.primaryMuscleText).title == category
            }
        }

        let needle = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !needle.isEmpty {
            // 复用动作库的评分器：名称 / 别名 / 主次肌群 / 器械 都计入
            filtered = filtered.filter { ExerciseSearch.score($0, needle: needle) > 0 }
        }

        return sorted(filtered, by: sort, recentRank: recentRank)
    }

    /// 各肌群大类下的收藏数，用于 Chip 角标。
    /// 按 `categoryZh` 计数（与动作库的 Chip 一致）；收藏列表本身含隐藏条目，
    /// 所以这里不像动作库那样再过滤 `isHidden`。
    static func muscleCounts(in items: [ExerciseLibraryItem]) -> [String: Int] {
        var counter: [String: Int] = [:]
        for item in items {
            counter[item.categoryZh, default: 0] += 1
        }
        return counter
    }

    // MARK: 排序

    static func sorted(
        _ items: [ExerciseLibraryItem],
        by order: FavoriteSortOrder,
        recentRank: [String: Int]
    ) -> [ExerciseLibraryItem] {
        switch order {
        case .name:
            return items.sorted { nameAscending($0, $1) }

        case .primaryMuscle:
            return items.sorted { lhs, rhs in
                let lm = lhs.primaryMuscleText
                let rm = rhs.primaryMuscleText
                if lm != rm {
                    return lm.localizedCaseInsensitiveCompare(rm) == .orderedAscending
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
            // 收藏时间越晚越靠前；没有时间戳的老数据（升级前已收藏）排在后面，
            // 再退回到按名称排序，保证结果稳定。
            return items.sorted { lhs, rhs in
                switch (lhs.favoritedAt, rhs.favoritedAt) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return nameAscending(lhs, rhs)
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return nameAscending(lhs, rhs)
                }
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
