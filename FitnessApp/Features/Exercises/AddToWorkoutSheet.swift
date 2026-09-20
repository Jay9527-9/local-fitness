//
//  AddToWorkoutSheet.swift
//  底部弹出的「添加到训练」目标选择，以及选中计划后的处方设置面板。
//
//  三个目标：
//    1. 添加到正在进行的训练（仅存在未完成训练时显示）
//    2. 添加到已有计划（展开本地计划列表）
//    3. 新建力量训练并添加
//
//  全部只读本地数据（WorkoutSession / Plan），不涉及账号或网络。
//

import SwiftUI

// MARK: - 目标选择

/// 加入训练的第一步：选一个目标。
/// 选完「已有计划」后由调用方接着弹出处方设置面板。
struct AddToWorkoutSheet: View {

    let item: ExerciseLibraryItem
    /// 「添加到正在进行的训练」的副标题，nil 表示没有进行中的训练，该项不显示
    let activeSessionSubtitle: String?
    let plans: [Plan]

    let onAddToActiveSession: () -> Void
    let onPickPlan: (Plan) -> Void
    let onCreatePlan: () -> Void
    /// 可选：进入独立的「选择计划」页（页面 28）。为 nil 时用内联计划列表。
    var onBrowsePlans: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// 「添加到已有计划」展开的状态
    @State private var isPlanListExpanded = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    header
                    targetList

                    if isPlanListExpanded {
                        planList
                    }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
            }
            .background(DS.Palette.bg)
            .navigationTitle("添加到训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityLabel("取消添加")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(item.displayName)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(item.primaryMuscleText) · \(item.equipmentText) · \(item.difficulty.title)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 目标列表

    private var targetList: some View {
        VStack(spacing: DS.Spacing.tight) {
            // 1. 进行中的训练。没有就不显示这一项。
            if let subtitle = activeSessionSubtitle {
                targetRow(
                    icon: "figure.strengthtraining.traditional",
                    title: "添加到正在进行的训练",
                    subtitle: subtitle,
                    isHighlighted: true
                ) {
                    onAddToActiveSession()
                    dismiss()
                }
            }

            // 2. 已有计划
            targetRow(
                icon: "list.bullet.rectangle",
                title: "添加到已有计划",
                subtitle: plans.isEmpty
                    ? "还没有训练计划"
                    : "共 \(plans.count) 个计划",
                isHighlighted: false,
                isExpanded: isPlanListExpanded,
                isEnabled: !plans.isEmpty
            ) {
                if let onBrowsePlans {
                    dismiss()
                    onBrowsePlans()
                } else {
                    withAnimation(DS.Motion.standard) {
                        isPlanListExpanded.toggle()
                    }
                }
            }

            // 3. 新建力量训练并添加
            targetRow(
                icon: "plus.circle",
                title: "新建力量训练并添加",
                subtitle: "建一个新的计划，把这个动作放进去",
                isHighlighted: false
            ) {
                onCreatePlan()
                dismiss()
            }
        }
    }

    private func targetRow(
        icon: String,
        title: String,
        subtitle: String,
        isHighlighted: Bool,
        isExpanded: Bool = false,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isHighlighted ? DS.Palette.onAccent : DS.Palette.accent)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(isHighlighted ? DS.Palette.accent : DS.Palette.surfaceElevated)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.callout)
                        .foregroundStyle(
                            isEnabled ? DS.Palette.textPrimary : DS.Palette.textTertiary
                        )
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isHighlighted ? DS.Palette.accent.opacity(0.12) : DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        isHighlighted ? DS.Palette.accent.opacity(0.45) : DS.Palette.stroke,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel("\(title)，\(subtitle)")
    }

    // MARK: 计划列表

    private var planList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text("选择计划")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(plans) { plan in
                Button {
                    onPickPlan(plan)
                } label: {
                    HStack(alignment: .center, spacing: DS.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.name)
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)

                            Text("\(plan.exerciseCount) 个动作 · \(plan.estimatedMinutes) 分钟 · \(plan.frequencyText)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: DS.Spacing.tight)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(DS.Spacing.item)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Palette.surfaceElevated)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("选择计划 \(plan.name)，\(plan.exerciseCount) 个动作")
            }
        }
        .transition(.opacity.combined(with: .offset(y: -8)))
    }
}

// MARK: - 参数面板（页面 27）

/// 加入训练 / 计划前填写动作参数：组数、次数、重量、休息、热身组、备注。
/// 顶部显示动作名称与主肌群；有最近训练记录时展示「上次记录」摘要与「使用上次参数」。
/// 底部主按钮文案随目标（训练 / 计划）变化；取消或关闭不写入任何数据。
struct ExercisePrescriptionSheet: View {

    let exerciseName: String
    let muscleText: String
    /// 底部主按钮文案，例如「添加到训练」或「添加到计划」
    let targetTitle: String
    /// 绑定到 ViewModel 的 draft
    @Binding var prescription: ExercisePrescription
    /// 「上次记录」摘要，nil 表示没有最近记录
    let lastRecordSummary: String?
    let onApplyLastRecord: () -> Void

    let onCancel: () -> Void
    let onSave: () -> Void

    /// 次数是否使用区间。关掉后上限跟随下限。
    @State private var usesRepRange: Bool
    /// 默认重量输入框（按当前单位展示）
    @State private var weightText: String
    /// 训练备注输入
    @State private var noteText: String
    /// 自定义休息是否展开
    @State private var useCustomRest: Bool

    @Environment(\.dismiss) private var dismiss

    init(
        exerciseName: String,
        muscleText: String = "",
        targetTitle: String = "添加到计划",
        prescription: Binding<ExercisePrescription>,
        lastRecordSummary: String? = nil,
        onApplyLastRecord: @escaping () -> Void = {},
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.muscleText = muscleText
        self.targetTitle = targetTitle
        self._prescription = prescription
        self.lastRecordSummary = lastRecordSummary
        self.onApplyLastRecord = onApplyLastRecord
        self.onCancel = onCancel
        self.onSave = onSave
        let draft = prescription.wrappedValue
        self._usesRepRange = State(initialValue: draft.usesRepRange)
        self._noteText = State(initialValue: draft.note ?? "")
        self._useCustomRest = State(initialValue: !Self.restPresets.contains(draft.restSeconds))
        if let weight = draft.weight, weight > 0 {
            let unit = ProfileSettings.weightUnit
            self._weightText = State(initialValue: Self.weightInputText(weight, unit: unit))
        } else {
            self._weightText = State(initialValue: "")
        }
    }

    /// 组间休息预设档位
    static let restPresets = [30, 45, 60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    header
                    lastRecordCard
                    setsRow
                    repsRows
                    weightRow
                    restRow
                    warmupRows
                    noteRow
                    summaryRow
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
            }
            .background(DS.Palette.bg)
            .navigationTitle("训练参数")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(DS.Palette.accent)
                    .accessibilityLabel("取消设置")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: DS.Spacing.item) {
                    PrimaryButton(title: targetTitle, icon: "checkmark") {
                        commit()
                        onSave()
                        dismiss()
                    }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.vertical, DS.Spacing.item)
                .background(DS.Palette.bg)
            }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    // MARK: 头部

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(exerciseName)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !muscleText.isEmpty {
                Text(muscleText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: 上次记录

    @ViewBuilder
    private var lastRecordCard: some View {
        if let summary = lastRecordSummary {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("上次记录")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text(summary)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }

                Spacer(minLength: DS.Spacing.tight)

                Button {
                    Haptics.light()
                    onApplyLastRecord()
                } label: {
                    Text("使用上次参数")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(DS.Palette.accent.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("使用上次参数")
                .accessibilityHint("只填入参数，不标记已完成")
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
    }

    // MARK: 组数

    private var setsRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            rowTitle("正式组数")

            StepperBlock(
                value: $prescription.sets,
                range: 1...20,
                step: 1,
                valueText: "\(prescription.sets)",
                accessibilityLabel: "正式组数"
            )
        }
    }

    // MARK: 次数

    private var repsRows: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .firstTextBaseline) {
                rowTitle("每组次数")
                Spacer(minLength: DS.Spacing.tight)
                Toggle("次数区间", isOn: $usesRepRange)
                    .labelsHidden()
                    .tint(DS.Palette.accent)
                    .onChange(of: usesRepRange) { newValue in
                        prescription.usesRepRange = newValue
                        if !newValue { prescription.repsHigh = prescription.repsLow }
                    }
                    .accessibilityLabel("使用次数区间")
            }

            if usesRepRange {
                HStack(spacing: DS.Spacing.item) {
                    StepperBlock(
                        value: $prescription.repsLow,
                        range: 1...100,
                        step: 1,
                        valueText: "\(prescription.repsLow)",
                        accessibilityLabel: "次数下限"
                    )
                    StepperBlock(
                        value: $prescription.repsHigh,
                        range: 1...100,
                        step: 1,
                        valueText: "\(prescription.repsHigh)",
                        accessibilityLabel: "次数上限"
                    )
                }
                .onChange(of: prescription.repsLow) { newValue in
                    // 上限不得低于下限
                    if prescription.repsHigh < newValue { prescription.repsHigh = newValue }
                }
            } else {
                StepperBlock(
                    value: $prescription.repsLow,
                    range: 1...100,
                    step: 1,
                    valueText: "\(prescription.repsLow)",
                    accessibilityLabel: "每组次数"
                )
                .onChange(of: prescription.repsLow) { newValue in
                    prescription.repsHigh = newValue
                }
            }
        }
    }

    // MARK: 重量

    private var weightRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            rowTitle("默认重量（可选）")

            HStack(spacing: DS.Spacing.tight) {
                TextField("自重", text: $weightText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                    .accessibilityLabel("默认重量")

                Text(ProfileSettings.weightUnit.shortTitle)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textTertiary)

                Button {
                    weightText = ""
                    prescription.weight = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除默认重量")
            }
        }
    }

    // MARK: 休息

    private var restRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            rowTitle("组间休息")

            FlowChips(
                items: Self.restPresets.map { FormatterKit.rest(seconds: $0) },
                isSelected: { label in
                    guard let seconds = Self.restPresets.first(where: { FormatterKit.rest(seconds: $0) == label }) else { return false }
                    return !useCustomRest && prescription.restSeconds == seconds
                }
            ) { label in
                if let seconds = Self.restPresets.first(where: { FormatterKit.rest(seconds: $0) == label }) {
                    useCustomRest = false
                    prescription.restSeconds = seconds
                }
            }

            HStack(spacing: DS.Spacing.tight) {
                Button {
                    useCustomRest.toggle()
                    if useCustomRest {
                        prescription.restSeconds = max(30, min(600, prescription.restSeconds))
                    }
                } label: {
                    Text("自定义")
                        .font(DS.Typography.caption)
                        .foregroundStyle(useCustomRest ? DS.Palette.onAccent : DS.Palette.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(useCustomRest ? DS.Palette.accent : DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            Capsule().stroke(useCustomRest ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("自定义休息时间")

                if useCustomRest {
                    StepperBlock(
                        value: $prescription.restSeconds,
                        range: 30...600,
                        step: 15,
                        valueText: FormatterKit.rest(seconds: prescription.restSeconds),
                        accessibilityLabel: "自定义组间休息"
                    )
                }
            }
        }
    }

    // MARK: 热身组

    private var warmupRows: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加热身组")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("热身组不计入训练容量统计")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer(minLength: DS.Spacing.tight)
                Toggle("", isOn: $prescription.isWarmup)
                    .labelsHidden()
                    .tint(DS.Palette.accent)
                    .accessibilityLabel("添加热身组")
            }

            if prescription.isWarmup {
                HStack(spacing: DS.Spacing.item) {
                    VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                        Text("热身组数量")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                        StepperBlock(
                            value: $prescription.warmupCount,
                            range: 1...5,
                            step: 1,
                            valueText: "\(prescription.warmupCount)",
                            accessibilityLabel: "热身组数量"
                        )
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                        Text("重量百分比")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                        StepperBlock(
                            value: warmupPercentBinding,
                            range: 10...100,
                            step: 10,
                            valueText: "\(Int(prescription.warmupPercent))%",
                            accessibilityLabel: "热身重量百分比"
                        )
                    }
                }
            }
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

    /// 重量百分比用 Int 步进，避免 Double 的 Stepper 语义。
    private var warmupPercentBinding: Binding<Int> {
        Binding(
            get: { Int(prescription.warmupPercent) },
            set: { prescription.warmupPercent = Double($0) }
        )
    }

    // MARK: 备注

    private var noteRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            rowTitle("训练备注（可选）")

            TextEditor(text: $noteText)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .frame(minHeight: 72)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .accessibilityLabel("训练备注")
        }
    }

    // MARK: 摘要

    private var summaryRow: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text("这组参数大约需要 \(FormatterKit.duration(seconds: prescription.estimatedSeconds))")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Text("预估按每组 40 秒动作时间加上组间休息累加，仅供参考。")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// 保存前把区间 / 重量 / 备注写回处方，保证落库的值与界面一致
    private func commit() {
        prescription.usesRepRange = usesRepRange
        if !usesRepRange { prescription.repsHigh = prescription.repsLow }
        prescription.weight = Self.parseWeight(weightText)
        let trimmedNote = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        prescription.note = trimmedNote.isEmpty ? nil : trimmedNote
    }

    // MARK: 重量换算

    private static func parseWeight(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let display = Double(trimmed), display > 0 else { return nil }
        switch ProfileSettings.weightUnit {
        case .kilograms: return display
        case .pounds: return display / BodyWeightUnit.poundsPerKilogram
        }
    }

    private static func weightInputText(_ kg: Double, unit: BodyWeightUnit) -> String {
        let display = unit.displayValue(fromKilograms: kg)
        return display == display.rounded()
            ? "\(Int(display))"
            : String(format: "%.1f", display)
    }
}

// MARK: - 数值步进控件

/// 左右加减 + 中间数值。比系统 Stepper 更适合深色卡片里的触控。
struct StepperBlock: View {

    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    /// 中间显示的文案，可能与数值不同（例如把 90 秒显示成「1 分 30 秒」）
    let valueText: String
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 0) {
            stepButton(symbol: "minus", delta: -step)

            Text(valueText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: DS.Size.minTapTarget)

            stepButton(symbol: "plus", delta: step)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: apply(step)
            case .decrement: apply(-step)
            default: break
            }
        }
    }

    private func stepButton(symbol: String, delta: Int) -> some View {
        Button {
            apply(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isEnabled(delta) ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled(delta))
        .accessibilityHidden(true)
    }

    private func isEnabled(_ delta: Int) -> Bool {
        range.contains(value + delta)
    }

    private func apply(_ delta: Int) {
        let next = value + delta
        guard range.contains(next) else { return }
        value = next
    }
}

// MARK: - 新建计划命名

/// 「新建力量训练并添加」时给计划起名。
struct NewPlanNameSheet: View {

    @State private var name: String

    let defaultName: String
    let exerciseName: String
    let onCancel: () -> Void
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    init(
        defaultName: String,
        exerciseName: String,
        onCancel: @escaping () -> Void,
        onCreate: @escaping (String) -> Void
    ) {
        self.defaultName = defaultName
        self.exerciseName = exerciseName
        self.onCancel = onCancel
        self.onCreate = onCreate
        self._name = State(initialValue: defaultName)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text("新计划名称")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)

                    TextField("", text: $name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .tint(DS.Palette.accent)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($isFocused)
                        .submitLabel(.done)
                        .onSubmit { create() }
                        .padding(DS.Spacing.item)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                                .fill(DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                                .stroke(DS.Palette.stroke, lineWidth: 1)
                        )
                        .accessibilityLabel("新计划名称")
                }

                Text("将把「\(exerciseName)」加入这个新计划。训练日之后可在计划详情里设置。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                PrimaryButton(
                    title: "创建并添加",
                    icon: "checkmark",
                    isEnabled: !trimmedName.isEmpty
                ) {
                    create()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.section)
            .background(DS.Palette.bg)
            .navigationTitle("新建训练")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onCancel()
                        dismiss()
                    }
                    .foregroundStyle(DS.Palette.accent)
                    .accessibilityLabel("取消新建")
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .onAppear { isFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName)
        dismiss()
    }
}

// MARK: - 预览

#Preview("添加到训练") {
    AddToWorkoutSheet(
        item: ExerciseLibraryItem(
            id: "0025", name: "Barbell Bench Press",
            aliases: ["卧推", "平板卧推"],
            categoryZh: "胸",
            equipment: "barbell", equipmentZh: "杠铃",
            target: "pectorals", primaryMuscle: "胸大肌",
            difficulty: .advanced
        ),
        activeSessionSubtitle: "推拉腿 · 三日 · 已进行 30 分钟",
        plans: [
            Plan(name: "推拉腿 · 三日", trainingDays: [1, 3, 5]),
            Plan(name: "上肢强化", trainingDays: [2, 4]),
        ],
        onAddToActiveSession: {},
        onPickPlan: { _ in },
        onCreatePlan: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("训练参数") {
    ExercisePrescriptionSheet(
        exerciseName: "杠铃卧推",
        muscleText: "胸大肌 · 杠铃",
        targetTitle: "添加到计划",
        prescription: .constant(.default(for: ExerciseLibraryItem(
            id: "0025", name: "Barbell Bench Press",
            equipment: "barbell", target: "pectorals", primaryMuscle: "胸大肌",
            difficulty: .advanced
        ))),
        lastRecordSummary: "上次 60 kg × 8 次",
        onApplyLastRecord: {},
        onCancel: {},
        onSave: {}
    )
    .preferredColorScheme(.dark)
}
