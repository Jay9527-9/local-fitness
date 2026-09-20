//
//  PlanExerciseConfigView.swift
//  计划内的动作配置页。
//
//  关键约束：只修改该计划里的 `PlanExercise` 配置，
//  不写回动作库的 `ExerciseLibraryItem`，所以导入动作永远不会被改动。
//

import SwiftUI

struct PlanExerciseConfigView: View {

    let entry: PlanExercise
    let item: ExerciseLibraryItem?
    let planName: String

    var onSave: (PlanExercise) -> Void
    /// 从上次训练填充（只建议，需用户确认）
    var onFillFromLast: (() -> Void)? = nil
    /// 替换动作（页面 39）
    var onReplace: (() -> Void)? = nil
    /// 从计划移除
    var onRemove: (() -> Void)? = nil
    /// 递增规则（页面 40）
    var onOpenProgression: ((ProgressionConfig?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var draft: ExerciseDraft
    /// 备注输入框的焦点。`.focused(_:)` 收的是 `FocusState<Bool>.Binding`，
    /// 普通的 `@State private var x = false` 传进去是 `Binding<Bool>`，类型不匹配。
    @FocusState private var noteFocused: Bool

    init(
        entry: PlanExercise,
        item: ExerciseLibraryItem?,
        planName: String,
        onSave: @escaping (PlanExercise) -> Void,
        onFillFromLast: (() -> Void)? = nil,
        onReplace: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil,
        onOpenProgression: ((ProgressionConfig?) -> Void)? = nil
    ) {
        self.entry = entry
        self.item = item
        self.planName = planName
        self.onSave = onSave
        self.onFillFromLast = onFillFromLast
        self.onReplace = onReplace
        self.onRemove = onRemove
        self.onOpenProgression = onOpenProgression
        _draft = State(initialValue: ExerciseDraft(entry: entry))
    }

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    header
                    fillFromLastButton
                    setsSection
                    repsSection
                    weightSection
                    restSection
                    warmupSection
                    noteSection
                    progressionSection
                    replaceRemoveSection
                    scopeNotice
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.card)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("动作配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DS.Palette.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
    }

    // MARK: - 顶部摘要

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            PlanExerciseThumbnail(item: item, size: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(item?.displayName ?? "动作已从动作库移除")
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)

                Text(summaryLine)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryLine: String {
        var parts: [String] = []
        if let item {
            parts.append(item.primaryMuscleText)
            parts.append(item.equipmentText)
        }
        parts.append("在「\(planName)」内")
        return parts.joined(separator: " · ")
    }

    // MARK: - 从上次训练填充

    @ViewBuilder
    private var fillFromLastButton: some View {
        if let onFillFromLast {
            Button {
                Haptics.light()
                onFillFromLast()
            } label: {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                    Text("从上次训练填充")
                        .font(DS.Typography.callout.weight(.semibold))
                }
                .foregroundStyle(DS.Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.accent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从上次训练填充")
            .accessibilityHint("只建议最近有效重量与次数，不影响已保存的记录")
        }
    }

    // MARK: - 组数

    private var setsSection: some View {
        configCard(title: "组数") {
            VStack(spacing: DS.Spacing.item) {
                StepperBlock(
                    value: $draft.sets,
                    range: 1...20,
                    step: 1,
                    valueText: "\(draft.sets)",
                    accessibilityLabel: "组数"
                )
                Text(setSummaryText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var setSummaryText: String {
        let total = draft.sets * draft.repsHigh
        return "最多约 \(total) 次，按上限估算"
    }

    // MARK: - 次数范围

    private var repsSection: some View {
        configCard(title: "次数范围") {
            VStack(spacing: DS.Spacing.item) {
                Toggle(isOn: $draft.repsLow.fixedMode(step: 2, upper: $draft.repsHigh)) {
                    Text("固定次数")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .tint(DS.Palette.accent)
                .accessibilityLabel("固定次数，关闭则使用次数区间")

                HStack(spacing: DS.Spacing.item) {
                    StepperBlock(
                        value: $draft.repsLow,
                        range: 1...50,
                        step: 1,
                        valueText: "\(draft.repsLow)",
                        accessibilityLabel: "次数下限"
                    )

                    if draft.repsLow != draft.repsHigh {
                        StepperBlock(
                            value: $draft.repsHigh,
                            range: 1...50,
                            step: 1,
                            valueText: "\(draft.repsHigh)",
                            accessibilityLabel: "次数上限"
                        )
                    }
                }
                .onChange(of: draft.repsLow) { newValue in
                    // 下限抬高时把上限一起顶上，避免出现 12-8 这种反向区间
                    if newValue > draft.repsHigh { draft.repsHigh = newValue }
                }

                Text("当前：\(draft.repsText) 次")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 建议重量

    private var weightSection: some View {
        configCard(title: "建议重量") {
            HStack(spacing: DS.Spacing.tight) {
                TextField(
                    "自重 / 未填",
                    text: Binding(
                        get: { draft.defaultWeight.map { Self.weightText($0) } ?? "" },
                        set: { newValue in
                            draft.defaultWeight = Double(newValue.trimmingCharacters(in: .whitespaces))
                        }
                    )
                )
                .keyboardType(.decimalPad)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .accessibilityLabel("建议重量")

                Text("kg")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    private static func weightText(_ kg: Double) -> String {
        kg == kg.rounded() ? "\(Int(kg))" : String(format: "%.1f", kg)
    }

    // MARK: - 休息

    private var restSection: some View {
        configCard(title: "组间休息") {
            VStack(spacing: DS.Spacing.item) {
                StepperBlock(
                    value: $draft.restSeconds,
                    range: 15...600,
                    step: 15,
                    valueText: FormatterKit.rest(seconds: draft.restSeconds),
                    accessibilityLabel: "组间休息秒数"
                )
                Text("建议 90-180 秒：复合动作取长值，孤立动作取短值。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 热身组

    private var warmupSection: some View {
        configCard(title: "热身组") {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Toggle(isOn: $draft.isWarmup) {
                    Text("标记为热身组")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .tint(DS.Palette.accent)
                .accessibilityLabel("标记为热身组")

                if draft.isWarmup {
                    HStack(spacing: DS.Spacing.item) {
                        Text("热身组数量")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                        Spacer(minLength: DS.Spacing.tight)
                        StepperBlock(
                            value: $draft.warmupCount,
                            range: 1...5,
                            step: 1,
                            valueText: "\(draft.warmupCount)",
                            accessibilityLabel: "热身组数量"
                        )
                        .frame(width: 160)
                    }
                }

                Text("热身组不纳入计划容量与动作总数统计。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    // MARK: - 备注

    private var noteSection: some View {
        configCard(title: "备注") {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.note)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 88)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(DS.Palette.surface)
                        )
                        .focused($noteFocused)
                        .accessibilityLabel("动作备注")

                    if draft.note.isEmpty {
                        Text("例如：肩不适时改哑铃，起始重量 40kg")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }
                }

                Text("只在当前计划内生效，不会改动动作库里这个动作的说明。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    // MARK: - 递增规则

    private var progressionSection: some View {
        configCard(title: "递增规则") {
            Button {
                Haptics.light()
                onOpenProgression?(draft.progressionConfig)
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(progressionSummary)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text("只为下一次训练提供建议，不会自动改重量")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    Spacer(minLength: DS.Spacing.tight)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("递增规则，\(progressionSummary)")
        }
    }

    private var progressionSummary: String {
        guard let config = draft.progressionConfig else {
            return draft.progression == .none ? "不设置" : draft.progression.title
        }
        return config.isEnabled ? "已启用（\(config.method.title)）" : "未启用"
    }

    // MARK: - 替换 / 移除

    @ViewBuilder
    private var replaceRemoveSection: some View {
        VStack(spacing: DS.Spacing.tight) {
            if let onReplace {
                Button {
                    Haptics.light()
                    onReplace()
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Palette.accent)
                        Text("替换动作")
                            .font(DS.Typography.callout)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("替换动作")
            }

            if let onRemove {
                Button {
                    Haptics.warning()
                    onRemove()
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        Image(systemName: "trash")
                            .font(.system(size: 15))
                            .foregroundStyle(DS.Palette.danger)
                        Text("从计划移除")
                            .font(DS.Typography.callout.weight(.semibold))
                            .foregroundStyle(DS.Palette.danger)
                        Spacer(minLength: DS.Spacing.tight)
                    }
                    .padding(DS.Spacing.item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Palette.danger.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .stroke(DS.Palette.danger.opacity(0.3), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("从计划移除")
            }
        }
    }

    // MARK: - 作用范围说明

    private var scopeNotice: some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(DS.Palette.textTertiary)
            Text("这里的修改只作用于本计划内的这个条目。动作库中的原始动作说明、媒体与其它计划都不受影响。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.tight)
    }

    // MARK: - 底部保存

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.stroke)

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消") {
                    dismiss()
                }
                PrimaryButton(title: "保存配置") {
                    onSave(draft.applied(to: entry))
                    Haptics.success()
                    dismiss()
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.tight)
        }
        .background(DS.Palette.bg)
    }

    // MARK: - 卡片外壳

    private func configCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.card)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Palette.stroke, lineWidth: 1)
        )
    }
}

// MARK: - 便捷绑定

private extension Binding where Value == Int {
    /// 用 `Binding<Bool>` 驱动「固定次数」开关，避免再存一份 `usesRepRange` 布尔值，
    /// 直接以「上下限是否相等」这个单一事实来源推导，不会出现两处状态不同步。
    ///
    /// 关闭固定次数的同时把上限抬高一档，否则 getter 立刻又读到相等、
    /// 开关会弹回打开状态，用户会觉得点击无效。
    func fixedMode(step: Int, upper: Binding<Int>) -> Binding<Bool> {
        Binding<Bool>(
            get: { wrappedValue == upper.wrappedValue },
            set: { isFixed in
                if isFixed {
                    // 固定次数：把上限对齐到下限
                    upper.wrappedValue = wrappedValue
                } else {
                    // 恢复区间：给上限留出至少一档空间。
                    // 必须写 `Swift.min`：本扩展在 `Binding` 上，而 `Binding`
                    // 自身满足 `Comparable` 时会有实例方法 `min`，不加限定
                    // 会被解析成实例方法而不是全局函数。
                    upper.wrappedValue = Swift.min(50, wrappedValue + step)
                }
            }
        )
    }
}

// MARK: - 预览

#Preview("动作配置") {
    NavigationStack {
        PlanExerciseConfigView(
            entry: PlanExercise(
                exerciseID: "0025",
                sets: 4,
                repsLow: 6,
                repsHigh: 10,
                restSeconds: 120,
                isWarmup: false,
                note: "肩不适时改哑铃",
                progression: .addWeight
            ),
            item: nil,
            planName: "推拉腿 · 三日",
            onSave: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
