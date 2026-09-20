//
//  ReplaceExerciseView.swift
//  页面 39：计划动作替换。
//
//  推荐替换仅基于本地分类字段（同主肌群 / 相近器械），不调用网络或 AI。
//  确认抽屉对比新旧动作 + 参数迁移策略；替换保留排序位置，不删原动作、不改其它计划。
//

import SwiftUI

// MARK: - 参数迁移策略

enum ReplaceParamStrategy: String, CaseIterable, Identifiable {
    case keepAll
    case keepSetsReps
    case useDefault

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepAll: return "保留现有组数、次数和休息时间"
        case .keepSetsReps: return "仅保留组数与次数"
        case .useDefault: return "使用新动作的默认参数"
        }
    }
}

// MARK: - 推荐纯函数

enum ReplaceRecommendation {

    /// 从动作库推荐替换：同主肌群优先，其次相近器械。返回不超过 5 个。
    static func recommend(
        for current: ExerciseLibraryItem,
        in items: [ExerciseLibraryItem]
    ) -> [ExerciseLibraryItem] {
        let currentGroup = MuscleIconGroup.of(muscle: current.primaryMuscleText)
        let currentEquipment = current.equipmentText

        return items
            .filter { $0.id != current.id && !$0.isHidden }
            .map { item -> (ExerciseLibraryItem, Int) in
                var score = 0
                let group = MuscleIconGroup.of(muscle: item.primaryMuscleText)
                if group == currentGroup { score += 3 }
                if item.equipmentText == currentEquipment { score += 2 }
                if item.primaryMuscleText == current.primaryMuscleText { score += 1 }
                return (item, score)
            }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
            }
            .prefix(5)
            .map(\.0)
    }
}

// MARK: - 页面

struct ReplaceExerciseView: View {

    let current: ExerciseLibraryItem
    let repository: FitnessRepository
    /// 同计划中已存在的动作 id 集合（用于重复检测）
    let existingIDsInPlan: Set<String>

    let onConfirm: (ExerciseLibraryItem, ReplaceParamStrategy) -> Void
    let onCancel: () -> Void

    @State private var allItems: [ExerciseLibraryItem] = []
    @State private var showAll = false
    @State private var confirmTarget: ExerciseLibraryItem?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                currentHeader
                recommendSection
                allButton
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task {
            allItems = (try? repository.fetchExercises(includeHidden: false)) ?? []
        }
        .sheet(isPresented: $showAll) {
            allExercisesSheet
        }
        .sheet(item: $confirmTarget) { target in
            confirmSheet(target)
        }
    }

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("取消")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消替换")

            Spacer(minLength: DS.Spacing.item)

            Text("替换动作")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Text("取消")
                .font(DS.Typography.callout)
                .foregroundStyle(Color.clear)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    private var currentHeader: some View {
        HStack(spacing: DS.Spacing.item) {
            ExerciseThumbnail(item: current, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(current.displayName)
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("\(current.primaryMuscleText) · \(current.equipmentText)")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var recommendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("推荐替换")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            let recommendations = ReplaceRecommendation.recommend(for: current, in: allItems)
            if recommendations.isEmpty {
                Text("暂无同肌群或相近器械的推荐动作。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            } else {
                ForEach(recommendations) { item in
                    candidateRow(item)
                }
            }
        }
    }

    private var allButton: some View {
        Button {
            Haptics.light()
            showAll = true
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15))
                    .foregroundStyle(DS.Palette.accent)
                Text("全部动作")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Spacing.tight)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Spacing.item)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("浏览全部动作")
    }

    private func candidateRow(_ item: ExerciseLibraryItem) -> some View {
        Button {
            Haptics.light()
            if existingIDsInPlan.contains(item.id) {
                confirmTarget = item
            } else {
                onConfirm(item, .keepAll)
            }
        } label: {
            HStack(spacing: DS.Spacing.item) {
                ExerciseThumbnail(item: item, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("\(item.primaryMuscleText) · \(item.equipmentText)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer(minLength: DS.Spacing.tight)
                if existingIDsInPlan.contains(item.id) {
                    Text("已在计划中")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.accent)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Spacing.item)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surfaceElevated)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("替换为 \(item.displayName)")
    }

    // MARK: 全部动作

    private var allExercisesSheet: some View {
        NavigationStack {
            ExerciseLibraryView(
                viewModel: ExerciseLibraryViewModel(repository: repository),
                onOpenExercise: { item in
                    showAll = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        confirmTarget = item
                    }
                },
                onNewCustomExercise: {},
                onEditCustomExercise: { _ in },
                onAddToWorkout: { _ in },
                pickerTitle: "选择替换动作"
            )
            .navigationBarHidden(true)
        }
    }

    // MARK: 确认抽屉

    private func confirmSheet(_ target: ExerciseLibraryItem) -> some View {
        NavigationStack {
            VStack(spacing: DS.Spacing.section) {
                VStack(spacing: DS.Spacing.tight) {
                    comparisonRow("原动作", current.displayName)
                    comparisonRow("新动作", target.displayName)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    Text("参数迁移策略")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                    ForEach(ReplaceParamStrategy.allCases) { strategy in
                        Button {
                            Haptics.light()
                            onConfirm(target, strategy)
                        } label: {
                            HStack(spacing: DS.Spacing.item) {
                                Text(strategy.title)
                                    .font(DS.Typography.body)
                                    .foregroundStyle(DS.Palette.textPrimary)
                                Spacer(minLength: DS.Spacing.tight)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textTertiary)
                            }
                            .padding(DS.Spacing.item)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                                    .fill(DS.Palette.surface)
                            )
                        }
                        .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .background(DS.Palette.bg)
            .navigationTitle("确认替换")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { confirmTarget = nil }
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func comparisonRow(_ label: String, _ name: String) -> some View {
        HStack {
            Text(label)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer()
            Text(name)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
        }
    }
}

// MARK: - 预览

#Preview("替换动作") {
    ReplaceExerciseView(
        current: ExerciseLibraryItem(
            id: "0025", name: "Barbell Bench Press",
            categoryZh: "胸", equipment: "barbell", equipmentZh: "杠铃",
            target: "pectorals", primaryMuscle: "胸大肌", difficulty: .advanced
        ),
        repository: PreviewFitnessRepository(),
        existingIDsInPlan: [],
        onConfirm: { _, _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
