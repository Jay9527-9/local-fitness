//
//  ProgressionRuleView.swift
//  页面 40：计划递增规则设置。
//
//  只给「下一次训练」提供建议，不自动修改已完成训练、不强制变更用户输入。
//  数值校验失败时在字段下方显示中文原因；不允许保存不完整或逻辑冲突的规则。
//

import SwiftUI

@MainActor
final class ProgressionRuleViewModel: ObservableObject {

    @Published var config: ProgressionConfig

    init(config: ProgressionConfig?) {
        self.config = config ?? ProgressionConfig()
    }

    /// 示例预览（仅用于说明，不写入训练数据）。
    func previewTexts(baseWeight: Double, baseReps: Int) -> (hit: String, miss: String) {
        let nextWeight = baseWeight + config.weightIncrementKg
        let hit = "若本次完成 \(3)×\(baseReps)，下次建议 \(Self.weightText(nextWeight))"
        let miss: String
        switch config.missedAction {
        case .keep, .retry:
            miss = "若未完成目标，下次维持 \(Self.weightText(baseWeight))"
        case .deload:
            let reduced = baseWeight * (1 - config.deloadPercent / 100)
            miss = "若未完成目标，下次建议降至 \(Self.weightText(reduced))"
        }
        return (hit, miss)
    }

    private static func weightText(_ kg: Double) -> String {
        kg == kg.rounded() ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }
}

struct ProgressionRuleView: View {

    @StateObject private var viewModel: ProgressionRuleViewModel
    let baseWeight: Double
    let onSave: (ProgressionConfig?) -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var deloadIntervalText: String
    @State private var deloadPercentText: String
    @State private var validationMessage: String?

    init(
        config: ProgressionConfig?,
        baseWeight: Double = 40,
        onSave: @escaping (ProgressionConfig?) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ProgressionRuleViewModel(config: config))
        self.baseWeight = baseWeight
        self.onSave = onSave
        let cfg = config ?? ProgressionConfig()
        _weightText = State(initialValue: Self.num(cfg.weightIncrementKg))
        _repsText = State(initialValue: "\(cfg.repsIncrement)")
        _deloadIntervalText = State(initialValue: "\(cfg.deloadInterval)")
        _deloadPercentText = State(initialValue: Self.num(cfg.deloadPercent))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                explainCard
                enableToggle
                if viewModel.config.isEnabled {
                    conditionSection
                    methodSection
                    incrementsSection
                    missedSection
                    deloadSection
                    previewSection
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
    }

    // MARK: 导航

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onSave(nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("递增规则")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                commitAndSave()
            } label: {
                Text("保存")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("保存递增规则")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    private var explainCard: some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Image(systemName: "info.circle")
                .font(.system(size: 14))
                .foregroundStyle(DS.Palette.textTertiary)
            Text("递增规则只为下一次训练提供建议，不自动修改已完成训练，也不强制变更你的输入。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.fieldFill)
        )
    }

    private var enableToggle: some View {
        HStack(spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text("启用递增建议")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("关闭后隐藏以下设置并保留原配置")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: DS.Spacing.tight)
            Toggle("", isOn: $viewModel.config.isEnabled)
                .labelsHidden()
                .tint(DS.Palette.accent)
                .accessibilityLabel("启用递增建议")
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

    private var conditionSection: some View {
        card("达标条件") {
            ForEach(ProgressionCondition.allCases) { option in
                radio(option.title, selected: viewModel.config.condition == option) {
                    viewModel.config.condition = option
                }
            }
        }
    }

    private var methodSection: some View {
        card("递增方式") {
            ForEach(ProgressionMethod.allCases) { option in
                radio(option.title, selected: viewModel.config.method == option) {
                    viewModel.config.method = option
                }
            }
        }
    }

    private var incrementsSection: some View {
        card("增幅") {
            VStack(spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.item) {
                    Text("重量增幅（kg）")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    TextField("0.5–20", text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(DS.Palette.fieldFill)
                        )
                        .accessibilityLabel("重量增幅")
                }
                HStack(spacing: DS.Spacing.item) {
                    Text("次数增幅（次）")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    TextField("1–10", text: $repsText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(DS.Palette.fieldFill)
                        )
                        .accessibilityLabel("次数增幅")
                }
                if let message = validationMessage {
                    Text(message)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var missedSection: some View {
        card("未达标处理") {
            ForEach(MissedTargetAction.allCases) { option in
                radio(option.title, selected: viewModel.config.missedAction == option) {
                    viewModel.config.missedAction = option
                }
            }
        }
    }

    private var deloadSection: some View {
        card("降载规则") {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Toggle(isOn: $viewModel.config.deloadEnabled) {
                    Text("启用降载")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .tint(DS.Palette.accent)
                .accessibilityLabel("启用降载")

                if viewModel.config.deloadEnabled {
                    HStack(spacing: DS.Spacing.item) {
                        Text("每 N 次训练")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                        Spacer()
                        TextField("间隔", text: $deloadIntervalText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(DS.Palette.fieldFill)
                            )
                            .accessibilityLabel("降载间隔")
                    }
                    HStack(spacing: DS.Spacing.item) {
                        Text("重量降低百分比")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                        Spacer()
                        TextField("0–100", text: $deloadPercentText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(DS.Palette.fieldFill)
                            )
                            .accessibilityLabel("降载百分比")
                    }
                }
            }
        }
    }

    private var previewSection: some View {
        card("示例预览") {
            let preview = viewModel.previewTexts(baseWeight: baseWeight, baseReps: 10)
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(preview.hit)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text(preview.miss)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text("预览仅用于说明，不写入训练数据。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func card(_ title: String, @ViewBuilder content: () -> some View) -> some View {
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
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    private func radio(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.textTertiary)
                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func commitAndSave() {
        viewModel.config.weightIncrementKg = Double(weightText.trimmingCharacters(in: .whitespaces)) ?? 0
        viewModel.config.repsIncrement = Int(repsText.trimmingCharacters(in: .whitespaces)) ?? 0
        viewModel.config.deloadInterval = Int(deloadIntervalText.trimmingCharacters(in: .whitespaces)) ?? 0
        viewModel.config.deloadPercent = Double(deloadPercentText.trimmingCharacters(in: .whitespaces)) ?? 0
        validationMessage = viewModel.config.validationError
        guard validationMessage == nil else { return }
        onSave(viewModel.config)
    }

    private static func num(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - 预览

#Preview("递增规则") {
    ProgressionRuleView(config: ProgressionConfig(), onSave: { _ in })
        .preferredColorScheme(.dark)
}
