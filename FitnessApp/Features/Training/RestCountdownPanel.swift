//
//  RestCountdownPanel.swift
//  页面 06：组间休息倒计时面板。
//
//  自下而上的结构：
//  ┌ 顶部：动作名 + 「组间休息」 / 右侧关闭按钮
//  ├ 中央：超大等宽剩余时间（01:30），最后 10 秒转荧光绿，最后 3 秒轻微缩放
//  ├ 圆环进度：底环低对比灰，进度环荧光绿，从完整圆环平滑减少至 0
//  ├ 第一行：−15 秒 / +15 秒 / +30 秒
//  ├ 第二行：暂停（或继续）主控 + 跳过休息
//  └ 底部：设为默认休息时间
//
//  几个刻意的取舍：
//  - **不用 BottomDrawer**：通用抽屉的把手 + 标题行无法承载「关闭按钮」和
//    「超大倒计时」这套排版，硬套会把通用组件改脏。这里复用它已经确定的
//    视觉常量（24pt 圆角、DS.Scrim、DS.Motion.drawer），但不复用它的结构。
//  - **数字不随每秒重绘整页**：面板自己持有一个 1s Timer 只驱动 `now`，
//    父页面不会被每秒唤醒。
//  - **关闭 ≠ 跳过**：关闭只把 isPresented 置 false，倒计时继续；
//    跳过才会停表并清盘。
//

import SwiftUI

struct RestCountdownPanel: View {

    /// 休息状态快照。每次 `now` 变化都会重新求值剩余时间。
    let timer: WorkoutSessionViewModel.RestTimer

    let onTogglePause: () -> Void
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void
    let onClose: () -> Void
    /// 保存默认休息时间
    let onSetDefaultRest: (Int) -> Void
    /// 当前计划里该动作的默认休息秒数，nil 表示无计划条目（入口置灰）
    let currentDefaultRest: Int?
    let canSetDefault: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            scrim
            panel
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("组间休息")
        .accessibilityValue(accessibilityValue)
    }

    // MARK: - 遮罩

    private var scrim: some View {
        DS.Scrim.color
            .ignoresSafeArea()
            // 点遮罩不关闭：误触会打断训练节奏，关闭入口只保留右上角按钮
            .onTapGesture {}
            .accessibilityHidden(true)
    }

    // MARK: - 面板主体

    private var panel: some View {
        VStack(spacing: DS.Spacing.item) {
            header
            countdown
            adjustRow
            controlRow
            defaultRestEntry
        }
        .padding(.top, DS.Spacing.item)
        .padding(.bottom, DS.Spacing.section)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: DS.Size.restPanelRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: DS.Size.restPanelRadius,
                style: .continuous
            )
            .fill(DS.Palette.surfaceElevated)
            .ignoresSafeArea(edges: .bottom)
            .shadow(color: .black.opacity(0.4), radius: 18, y: -6)
        )
    }

    // MARK: - 顶部标题行

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 3) {
                Text(timer.exerciseName)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(timer.statusText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(timer.isPaused ? DS.Palette.accent : DS.Palette.textTertiary)
                    .lineLimit(1)
            }
            .accessibilityHidden(true)

            Spacer(minLength: DS.Spacing.tight)

            closeButton
        }
        .padding(.horizontal, DS.Spacing.card)
    }

    /// 关闭按钮：只收起面板，不停止倒计时
    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .background(Circle().fill(DS.Palette.fieldFill))
                .contentShape(Circle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("关闭休息面板")
        .accessibilityHint("倒计时会继续，回到训练页仍可看到剩余时间")
    }

    // MARK: - 超大倒计时 + 进度环

    private var countdown: some View {
        ZStack {
            ringTrack
            ringProgress

            VStack(spacing: 2) {
                Text(FormatterKit.stopwatch(seconds: timer.remainingSeconds))
                    .font(.system(
                        size: countdownFontSize,
                        weight: .bold,
                        design: .monospaced
                    ))
                    .foregroundStyle(timer.isFinalCountdown && ProfileSettings.lastTenSecondsReminder
                        ? DS.Palette.accent : DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    // 最后 3 秒轻微缩放提示。用 repeatForever 呼吸，
                    // 归零或暂停后 scale 回到 1，不会卡在放大状态。
                    .scaleEffect(timer.isFinalPulse ? 1.06 : 1.0)
                    .animation(
                        timer.isFinalPulse ? DS.Motion.restPulseRepeat : DS.Motion.restPulse,
                        value: timer.isFinalPulse
                    )

                if timer.isPaused {
                    Text("已暂停")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.accent)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: DS.Size.restRing, height: DS.Size.restRing)
        .padding(.vertical, DS.Spacing.tight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("剩余时间")
        .accessibilityValue(timer.isPaused
            ? "已暂停，剩余 \(timer.remainingSeconds) 秒"
            : "剩余 \(spokenTime)")
    }

    /// 倒计时数字字号。页面 14 训练偏好「倒计时数字样式 = 大号」时用更大的字号。
    private var countdownFontSize: CGFloat {
        switch ProfileSettings.countdownStyle {
        case .normal: return DS.Size.restCountdownFont
        case .large: return DS.Size.restCountdownFontLarge
        }
    }

    /// 低对比灰底环
    private var ringTrack: some View {
        Circle()
            .stroke(Color.white.opacity(0.10), lineWidth: DS.Size.restRingStroke)
    }

    /// 荧光绿进度环：从完整圆环平滑减少到 0。
    ///
    /// `trim(from: 0, to: 1 - progress)` 让弧长随剩余时间递减——
    /// 也就是「圆环随倒计时被吃掉」。暂停时不再对 progress 加动画，
    /// 环自然停住。
    private var ringProgress: some View {
        Circle()
            .trim(from: 0, to: 1 - timer.progress)
            .stroke(
                DS.Palette.accent,
                style: StrokeStyle(lineWidth: DS.Size.restRingStroke, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(
                timer.isPaused ? nil : .linear(duration: 0.9),
                value: timer.progress
            )
    }

    // MARK: - 第一行：时间调整

    private var adjustRow: some View {
        HStack(spacing: DS.Spacing.item) {
            adjustButton(title: "−15 秒", delta: -15, label: "减少 15 秒")
            adjustButton(title: "+15 秒", delta: 15, label: "增加 15 秒")
            adjustButton(title: "+30 秒", delta: 30, label: "增加 30 秒")
        }
        .padding(.horizontal, DS.Spacing.card)
    }

    private func adjustButton(title: String, delta: Int, label: String) -> some View {
        Button {
            onAdjust(delta)
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Palette.accent)
                .frame(maxWidth: .infinity, minHeight: DS.Size.restAdjustButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        // 0.97 缩放的按下反馈
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }

    // MARK: - 第二行：主控制 + 跳过

    private var controlRow: some View {
        HStack(spacing: DS.Spacing.item) {
            Button(action: onTogglePause) {
                HStack(spacing: 6) {
                    Image(systemName: timer.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text(timer.isPaused ? "继续" : "暂停")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(DS.Palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: DS.Size.restAdjustButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                        .fill(DS.Palette.accent)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(timer.isPaused ? "继续倒计时" : "暂停倒计时")

            Button(action: onSkip) {
                Text("跳过休息")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(minWidth: 96, minHeight: DS.Size.restAdjustButtonHeight)
                    .padding(.horizontal, DS.Spacing.item)
                    .background(
                        Capsule().fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("跳过休息")
            .accessibilityHint("停止计时并关闭面板，回到下一组")
        }
        .padding(.horizontal, DS.Spacing.card)
    }

    // MARK: - 设为默认休息时间

    @State private var showDefaultPicker = false

    private var defaultRestEntry: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.stroke)

            Button {
                guard canSetDefault else { return }
                showDefaultPicker = true
                Haptics.light()
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canSetDefault ? DS.Palette.accent : DS.Palette.textTertiary)
                        .frame(width: 20)

                    Text("设为默认休息时间")
                        .font(DS.Typography.callout)
                        .foregroundStyle(canSetDefault ? DS.Palette.textPrimary : DS.Palette.textTertiary)

                    Spacer(minLength: DS.Spacing.tight)

                    Text(currentDefaultText)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSetDefault)
            .accessibilityLabel("设为默认休息时间")
            .accessibilityValue(currentDefaultText)
            .accessibilityHint(canSetDefault
                ? "打开数值选择器，修改当前计划里这个动作的默认休息时间"
                : "自由训练没有计划，无法设置默认休息时间")
        }
        .sheet(isPresented: $showDefaultPicker) {
            RestDefaultPickerSheet(
                exerciseName: timer.exerciseName,
                initialSeconds: currentDefaultRest ?? timer.remainingSeconds,
                onSave: { seconds in
                    showDefaultPicker = false
                    onSetDefaultRest(seconds)
                },
                onCancel: { showDefaultPicker = false }
            )
        }
    }

    private var currentDefaultText: String {
        guard canSetDefault, let value = currentDefaultRest else { return "自由训练不可设" }
        return FormatterKit.rest(seconds: value)
    }

    // MARK: - 无障碍

    private var spokenTime: String {
        let seconds = timer.remainingSeconds
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes > 0 && rest > 0 { return "\(minutes) 分 \(rest) 秒" }
        if minutes > 0 { return "\(minutes) 分" }
        return "\(rest) 秒"
    }

    private var accessibilityValue: String {
        var parts: [String] = [timer.statusText, spokenTime]
        if timer.isFinalCountdown { parts.append("即将开始下一组") }
        return parts.joined(separator: "，")
    }
}

// MARK: - 默认休息时间选择器

/// 小型数值选择器：30 / 45 / 60 / 90 / 120 / 180 秒，或自定义秒数。
///
/// 保存后只更新当前计划动作的 `restSeconds`，不回写动作库本体。
struct RestDefaultPickerSheet: View {

    let exerciseName: String
    let initialSeconds: Int
    let onSave: (Int) -> Void
    let onCancel: () -> Void

    /// 预设档位
    private static let presets = [30, 45, 60, 90, 120, 180]

    @State private var seconds: Int
    @State private var customText: String = ""
    /// 自定义输入是否被选中。选中时以 customText 为准。
    @State private var isCustomActive = false

    init(
        exerciseName: String,
        initialSeconds: Int,
        onSave: @escaping (Int) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.initialSeconds = initialSeconds
        self.onSave = onSave
        self.onCancel = onCancel
        // 落在预设档上就选中它，否则进自定义
        let matched = RestDefaultPickerSheet.presets.contains(initialSeconds)
        _seconds = State(initialValue: matched ? initialSeconds : initialSeconds)
        _customText = State(initialValue: matched ? "" : "\(initialSeconds)")
        _isCustomActive = State(initialValue: !matched)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            title

            presetGrid

            customField

            footer
        }
        .padding(DS.Spacing.card)
        .background(DS.Palette.surfaceElevated)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("设置默认休息时间")
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("默认休息时间")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)

            Text("只改「\(exerciseName)」在当前计划里的配置，不动动作库本体")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.tight), count: 3),
            spacing: DS.Spacing.tight
        ) {
            ForEach(Self.presets, id: \.self) { value in
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

    @FocusState private var customFocused: Bool

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

            Text("秒")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

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

    /// 最终写入的秒数。经 `RestRange` 夹在 15…600 之间，避免 0 秒或离谱输入。
    private var resolvedSeconds: Int {
        guard isCustomActive else { return RestRange.clamp(seconds) }
        return RestRange.parse(customText, fallback: seconds)
    }
}

// MARK: - 预览

private struct RestCountdownPreviewHost: View {

    @State private var now = Date()
    @State private var isPaused = false

    let duration: Int
    let elapsed: Int

    private var record: RestTimerRecord {
        RestTimerRecord(
            sessionID: UUID(),
            startedAt: now.addingTimeInterval(-Double(elapsed)),
            durationSeconds: duration,
            isPaused: isPaused,
            remainingSeconds: isPaused ? duration - elapsed : nil,
            exerciseName: "杠铃卧推",
            planEntryID: UUID(),
            planID: UUID()
        )
    }

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()
            RestCountdownPanel(
                timer: WorkoutSessionViewModel.RestTimer(
                    record: record,
                    isPresented: true,
                    now: now
                ),
                onTogglePause: { isPaused.toggle() },
                onAdjust: { _ in },
                onSkip: {},
                onClose: {},
                onSetDefaultRest: { _ in },
                currentDefaultRest: 90,
                canSetDefault: true
            )
        }
    }
}

#Preview("组间休息 · 进行中") {
    RestCountdownPreviewHost(duration: 90, elapsed: 30)
        .preferredColorScheme(.dark)
}

#Preview("组间休息 · 最后 10 秒") {
    RestCountdownPreviewHost(duration: 90, elapsed: 84)
        .preferredColorScheme(.dark)
}

#Preview("默认休息时间选择器") {
    RestDefaultPickerSheet(
        exerciseName: "杠铃卧推",
        initialSeconds: 90,
        onSave: { _ in },
        onCancel: {}
    )
    .padding(DS.Spacing.page)
    .background(DS.Palette.bg)
    .preferredColorScheme(.dark)
}
