//
//  ExerciseFilterSheet.swift
//  动作库的高级筛选抽屉（页面 25）：肌群、器械、难度、动作来源、状态。
//
//  以底部抽屉呈现，深灰背景、顶部圆角与拖拽指示条；顶部「重置 / 筛选 / 完成」。
//  顶部实时显示当前筛选的命中数量；未选任何条件代表不过滤。
//  器械清单由数据集推导传入，不硬编码，避免与数据脱节。
//

import SwiftUI

// MARK: - 高级筛选抽屉内容

struct ExerciseFilterDrawer: View {

    @Binding var filter: ExerciseFilter

    /// 全量动作，用于实时计算命中数量
    let items: [ExerciseLibraryItem]
    /// 由 ViewModel 从动作库推导出的可用器械
    let equipments: [String]
    /// 当前隐藏的条目数，用于状态区提示
    let hiddenCount: Int
    /// 点击「完成」关闭抽屉（由上层立即刷新动作库）
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    hitCountRow
                    muscleSection
                    equipmentSection
                    difficultySection
                    sourceSection
                    statusSection
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
            }
        }
    }

    /// 肌群筛选用的大类（不含有氧 / 颈 / 其他，与规格一致）
    static let muscleGroupTitles = ["胸", "背", "肩", "手臂", "核心", "腿", "臀", "小腿"]

    // MARK: 命中数量

    private var hitCount: Int {
        items.filter { ExerciseSearch.matches($0, filter: filter) }.count
    }

    private var hitCountRow: some View {
        Text("命中 \(hitCount) 个动作")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.accent)
            .accessibilityLabel("当前筛选命中 \(hitCount) 个动作")
    }

    // MARK: 顶部栏

    private var topBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                filter.resetAdvanced()
            } label: {
                Text("重置")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重置全部筛选")

            Spacer(minLength: DS.Spacing.item)

            Text("筛选")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                onDone()
            } label: {
                Text("完成")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成筛选设置")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
    }

    // MARK: 肌群

    private var muscleSection: some View {
        section("肌群") {
            FlowChips(items: Self.muscleGroupTitles, isSelected: { filter.muscleGroups.contains($0) }) { value in
                toggle(value, in: &filter.muscleGroups)
            }
        }
    }

    // MARK: 器械

    private var equipmentSection: some View {
        section("器械") {
            FlowChips(items: equipments, isSelected: { filter.equipments.contains($0) }) { value in
                toggle(value, in: &filter.equipments)
            }
        }
    }

    // MARK: 难度（单选）

    private var difficultySection: some View {
        section("难度") {
            choiceChips(
                ExerciseDifficulty.allCases,
                isSelected: { filter.difficulty == $0 },
                title: { $0.title }
            ) { level in
                filter.difficulty = (filter.difficulty == level) ? nil : level
            }
        }
    }

    // MARK: 动作来源（单选）

    private var sourceSection: some View {
        section("动作来源") {
            choiceChips(
                ExerciseSource.allCases,
                isSelected: { filter.source == $0 },
                title: { $0.title }
            ) { source in
                filter.source = source
            }
        }
    }

    // MARK: 状态

    private var statusSection: some View {
        section("状态") {
            VStack(spacing: DS.Spacing.tight) {
                toggleRow(
                    title: "仅显示收藏",
                    subtitle: "只看已加星的动作",
                    isOn: $filter.onlyFavorite
                )

                toggleRow(
                    title: "显示已隐藏动作",
                    subtitle: hiddenCount > 0
                        ? "当前有 \(hiddenCount) 个已隐藏的动作"
                        : "还没有隐藏过动作",
                    isOn: $filter.includeHidden
                )
            }
        }
    }

    // MARK: 分组标题

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    // MARK: 单选 Chip

    private func choiceChips<T: Identifiable>(
        _ items: [T],
        isSelected: @escaping (T) -> Bool,
        title: @escaping (T) -> String,
        onTap: @escaping (T) -> Void
    ) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 88), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items) { item in
                let on = isSelected(item)
                Button {
                    Haptics.light()
                    onTap(item)
                } label: {
                    Text(title(item))
                        .font(DS.Typography.caption)
                        .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(on ? DS.Palette.accent : DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(on ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(title(item))
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: DS.Spacing.tight)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DS.Palette.accent)
                .accessibilityLabel(title)
                .accessibilityHint(subtitle)
        }
        .padding(DS.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }
}

// MARK: - 自适应流式 Chip

/// 自动换行的多选 Chip 组。用自适应网格实现，无需手写流式布局。
struct FlowChips: View {

    let items: [String]
    let isSelected: (String) -> Bool
    let onTap: (String) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 78), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                let selected = isSelected(item)

                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(DS.Typography.caption)
                        .foregroundStyle(
                            selected ? DS.Palette.onAccent : DS.Palette.textSecondary
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(
                                    selected
                                        ? DS.Palette.accent
                                        : DS.Palette.surfaceElevated
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(selected ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(item)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - 预览

#Preview("高级筛选") {
    ZStack {
        DS.Palette.bg.ignoresSafeArea()
    }
    .bottomDrawer(isPresented: .constant(true), height: 620, title: nil) {
        ExerciseFilterDrawer(
            filter: .constant(.none),
            items: [
                ExerciseLibraryItem(
                    id: "1", name: "Barbell Bench Press",
                    categoryZh: "胸", equipment: "barbell", equipmentZh: "杠铃",
                    target: "pectorals", primaryMuscle: "胸大肌", difficulty: .advanced
                ),
                ExerciseLibraryItem(
                    id: "2", name: "Pull Up",
                    categoryZh: "背", equipment: "body weight", equipmentZh: "自重",
                    target: "lats", primaryMuscle: "背阔肌", difficulty: .intermediate
                ),
            ],
            equipments: ["自重", "哑铃", "杠铃", "绳索", "固定器械", "弹力带", "壶铃"],
            hiddenCount: 3,
            onDone: {}
        )
    }
    .preferredColorScheme(.dark)
}
