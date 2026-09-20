//
//  CustomExerciseForm.swift
//  页面 23/24：新建 / 编辑自定义动作的纯值层。
//
//  名称校验（1–50 字）、重名检测、分步说明规范化、删除时的计划引用判定。
//  无 SwiftUI 引入，可被 Python 照搬推演。
//

import Foundation

// MARK: - 校验

enum CustomExerciseValidation {

    /// 动作名称最大字符数。
    static let nameMaxLength = 50

    /// 规范化名称：去前后空白，超过上限截断；空串返回 nil（等同未填写）。
    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(nameMaxLength))
    }

    /// 是否与现有动作重名（大小写不敏感，去前后空白比较）。
    /// `excludingID` 用于编辑时排除自身。
    static func hasDuplicateName(
        _ raw: String,
        in existing: [ExerciseLibraryItem],
        excludingID: String?
    ) -> Bool {
        guard let normalized = normalizedName(raw) else { return false }
        return existing.contains { item in
            item.id != (excludingID ?? "")
                && (item.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalized) == .orderedSame)
        }
    }

    /// 规范化分步说明：去前后空白，去掉空步骤。允许空数组（表示无步骤）。
    static func normalizedSteps(_ raw: [String]) -> [String] {
        raw
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - 删除

enum CustomExerciseDelete {

    /// 引用了某动作的计划（用于「删除时被计划引用」提示）。
    static func plansReferencing(_ exerciseID: String, in plans: [Plan]) -> [Plan] {
        plans.filter { $0.exercises.contains { $0.exerciseID == exerciseID } }
    }

    /// 从各计划中移除该动作的引用（用于「同时从未来计划移除」）。
    /// 返回更新后的计划集合，纯函数不写盘。
    static func removingReferences(
        toExercise exerciseID: String,
        from plans: [Plan]
    ) -> [Plan] {
        plans.map { plan in
            var copy = plan
            copy.exercises.removeAll { $0.exerciseID == exerciseID }
            return copy
        }
    }

    /// 引用了某动作的计划名称，用于确认文案。
    static func referencingPlanNames(_ exerciseID: String, in plans: [Plan]) -> [String] {
        plansReferencing(exerciseID, in: plans).map(\.name)
    }
}
