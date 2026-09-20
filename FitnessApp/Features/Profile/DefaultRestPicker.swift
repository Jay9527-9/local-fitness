//
//  DefaultRestPicker.swift
//  页面 41：默认休息时间选择器。
//
//  统一「默认休息时间」底部抽屉：预设 Chip + 自定义输入（15–600 秒）+ 取消/保存。
//  两个入口共用同一组件：
//  - 训练偏好 → 保存到 `ProfileSettings.defaultRest`（即 AppPreferences.defaultRestSeconds）；
//  - 当前动作休息面板 → 保存到该动作在当前计划的 `PlanExercise.restSeconds`。
//
//  值层（`RestRange` / `DefaultRestScope`）不 import SwiftUI，可被 Python 照搬推演。
//

import SwiftUI

// MARK: - 值层：休息时间范围

/// 默认休息时间的合法范围与预设档位。
///
/// 规格：预设 30 / 45 / 60 / 90 / 120 / 180 秒，自定义输入 15–600 秒。
/// 任何入口写入前都经 `clamp` 夹取，杜绝 0 秒或离谱输入。
enum RestRange {

    /// 自定义输入下限（秒）
    static let minSeconds = 15
    /// 自定义输入上限（秒）
    static let maxSeconds = 600
    /// 预设档位。与规格一致。
    static let presets = [30, 45, 60, 90, 120, 180]

    /// 是否落在合法范围内（含边界）。
    static func isValid(_ seconds: Int) -> Bool {
        seconds >= minSeconds && seconds <= maxSeconds
    }

    /// 夹取到合法范围。越界值会落到边界，而不是原样写回。
    static func clamp(_ seconds: Int) -> Int {
        min(max(minSeconds, seconds), maxSeconds)
    }

    /// 从自定义文本解析出秒数。空 / 非法回落到预设当前值，再由 clamp 兜底。
    static func parse(_ text: String, fallback: Int) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = Int(trimmed) ?? fallback
        return clamp(parsed)
    }
}

// MARK: - 值层：适用范围

/// 默认休息时间从哪个入口进入，决定写入目标与说明文案。
enum DefaultRestScope: Equatable {
    /// 训练偏好 → 写入 AppPreferences.defaultRestSeconds。
    case appDefault
    /// 当前动作休息面板 → 写入 PlanExercise.restSeconds。
    case planExercise

    /// 底部说明：默认休息时间只影响哪些对象，绝不碰历史。
    var explanation: String {
        switch self {
        case .appDefault:
            return "默认休息时间只影响新建动作和未单独配置的动作，不会修改现有计划动作、进行中训练或历史记录。"
        case .planExercise:
            return "只改当前动作在此计划里的休息时间，不动动作库本体、其他计划或历史训练记录。"
        }
    }
}

// MARK: - 视图

/// 默认休息时间抽屉内容：预设 Chip + 自定义输入 + 取消/保存。
///
/// 关闭或取消不写任何数据；保存时由调用方按 scope 决定落点。
struct DefaultRestPickerContent: View {

    let scope: DefaultRestScope
    let initialSeconds: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    @State private var seconds: Int
    @State private var customText: String = ""
    @State private var isCustomActive = false
    @FocusState private var customFocused: Bool

    init(
        scope: DefaultRestScope,
        initialSeconds: Int,
        onSave: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.scope = scope
        self.initialSeconds = initialSeconds
        self.onSave = onSave
        self.onCancel = onCancel
        let matched = RestRange.presets.contains(initialSeconds)
        _seconds = State(initialValue: matched ? initialSeconds : RestRange.clamp(initialSeconds))
        _customText = State(initialValue: matched ? "" : "\(RestRange.clamp(initialSeconds))")
        _isCustomActive = State(initialValue: !matched)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            presetGrid

            customField

            Text(scope.explanation)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(scope.explanation)

            footer
        }
        .padding(DS.Spacing.card)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("默认休息时间，当前 \(resolvedSeconds) 秒")
    }

    // MARK: 预设

    private var presetGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.tight), count: 3),
            spacing: DS.Spacing.tight
        ) {
            ForEach(RestRange.presets, id: \.self) { value in
                presetCell(value)
            }
        }
    }

    private func presetCell(_ value: Int) -> some View {
        let selected = !isCustomActive && seconds == value
        return Button {
            seconds = value
            isCustomActive = false
            customText = ""
            customFocused = false
            Haptics.light()
        } label: {
            Text(FormatterKit.rest(seconds: value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(selected ? DS.Palette.accent : DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(selected ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(value) 秒")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: 自定义

    private var customField: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text("自定义")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)

            TextField("秒", text: $customText)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.Palette.textPrimary)
                .focused($customFocused)
                .padding(.horizontal, DS.Spacing.tight)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(isCustomActive ? DS.Palette.accent : DS.Palette.stroke, lineWidth: 1)
                )
                .onChange(of: customFocused) { focused in
                    if focused { isCustomActive = true }
                }
                .onChange(of: customText) { _ in
                    isCustomActive = true
                }
                .accessibilityLabel("自定义休息时间，\(RestRange.minSeconds) 到 \(RestRange.maxSeconds) 秒")

            Text("秒")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    // MARK: 取消 / 保存

    private var footer: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                customFocused = false
                onCancel()
            } label: {
                Text("取消")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("取消")

            Button {
                customFocused = false
                onSave(resolvedSeconds)
            } label: {
                Text("保存")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.onAccent)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                            .fill(DS.Palette.accent)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("保存默认休息时间")
        }
        .padding(.top, DS.Spacing.tight)
    }

    /// 最终写入的秒数。预设或自定义输入都经 RestRange 夹取到 15…600。
    private var resolvedSeconds: Int {
        guard isCustomActive else { return RestRange.clamp(seconds) }
        return RestRange.parse(customText, fallback: seconds)
    }
}
