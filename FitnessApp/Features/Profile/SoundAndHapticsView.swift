//
//  SoundAndHapticsView.swift
//  页面 43：声音与触感设置。
//
//  三组：声音（总提示音 + 三个子开关）、触感（三个子开关）、试听。
//  总提示音关闭时子声音选项置灰但保留原配置；设备不支持触感时显示不可用并禁用。
//  通知权限只影响后台本地通知，不影响前台声音与触感。
//

import SwiftUI

struct SoundAndHapticsView: View {

    let onBack: () -> Void

    @State private var soundEnabled = ProfileSettings.soundEnabled
    @State private var hapticsEnabled = ProfileSettings.hapticsEnabled
    @State private var soundRestEnd = ProfileSettings.soundRestEnd
    @State private var soundLastTen = ProfileSettings.soundLastTen
    @State private var soundSetComplete = ProfileSettings.soundSetComplete
    @State private var hapticSetComplete = ProfileSettings.hapticSetComplete
    @State private var hapticRestEnd = ProfileSettings.hapticRestEnd
    @State private var hapticWorkoutComplete = ProfileSettings.hapticWorkoutComplete
    @State private var showMuteNotice = false

    private var hapticsAvailable: Bool { FeedbackCenter.hapticsAvailable }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                soundGroup
                hapticsGroup
                previewGroup
                notice
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) { muteNoticeBar }
    }

    // MARK: 声音

    private var soundGroup: some View {
        group(title: "声音") {
            ProfileToggleRow(
                title: "提示音",
                subtitle: "总开关，关闭后所有提示音静音",
                isOn: $soundEnabled
            ) { on in ProfileSettings.soundEnabled = on }

            Divider().overlay(DS.Palette.stroke)

            soundSubRow(
                title: "组间休息结束提示音",
                subtitle: "休息倒计时归零时播放",
                isOn: $soundRestEnd,
                enabled: soundEnabled
            ) { on in ProfileSettings.soundRestEnd = on }

            Divider().overlay(DS.Palette.stroke)

            soundSubRow(
                title: "最后 10 秒提示音",
                subtitle: "倒计时进入最后 10 秒时提示",
                isOn: $soundLastTen,
                enabled: soundEnabled
            ) { on in ProfileSettings.soundLastTen = on }

            Divider().overlay(DS.Palette.stroke)

            soundSubRow(
                title: "动作完成提示音",
                subtitle: "完成一组动作时播放",
                isOn: $soundSetComplete,
                enabled: soundEnabled
            ) { on in ProfileSettings.soundSetComplete = on }
        }
    }

    // MARK: 触感

    private var hapticsGroup: some View {
        group(title: "触感") {
            if hapticsAvailable {
                hapticSubRow(
                    title: "完成一组触感反馈",
                    subtitle: "勾选完成一组时的振动",
                    isOn: $hapticSetComplete,
                    enabled: hapticsEnabled
                ) { on in ProfileSettings.hapticSetComplete = on }

                Divider().overlay(DS.Palette.stroke)

                hapticSubRow(
                    title: "休息结束触感反馈",
                    subtitle: "休息倒计时归零时的振动",
                    isOn: $hapticRestEnd,
                    enabled: hapticsEnabled
                ) { on in ProfileSettings.hapticRestEnd = on }

                Divider().overlay(DS.Palette.stroke)

                hapticSubRow(
                    title: "训练完成触感反馈",
                    subtitle: "完成整次训练时的振动",
                    isOn: $hapticWorkoutComplete,
                    enabled: hapticsEnabled
                ) { on in ProfileSettings.hapticWorkoutComplete = on }
            } else {
                HStack(spacing: DS.Spacing.item) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.Palette.textTertiary)
                    Text("此设备不支持触感反馈。")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 14)
                .accessibilityLabel("此设备不支持触感反馈")
            }
        }
    }

    // MARK: 试听

    private var previewGroup: some View {
        group(title: "试听") {
            Button {
                FeedbackCenter.play(.restEnd)
                showMuteNotice = true
                scheduleMuteNoticeDismiss()
            } label: {
                previewRow(symbol: "speaker.wave.2", title: "试听休息结束提示音")
            }

            Divider().overlay(DS.Palette.stroke)

            Button {
                FeedbackCenter.trigger(.restEnd)
            } label: {
                previewRow(symbol: "iphone.radiowaves.left.and.right", title: "测试触感反馈")
            }
            .disabled(!hapticsAvailable)
        }
    }

    // MARK: 说明

    private var notice: some View {
        Text("通知权限只影响后台本地通知，不影响 App 前台内的声音与触感。试听使用 App 包内系统提示音，不请求网络。")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, DS.Spacing.card)
    }

    // MARK: 复用

    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            CardContainer(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    /// 声音子开关：总提示音关闭时置灰（disabled + 半透明），但保留子开关原配置。
    private func soundSubRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        enabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        ProfileToggleRow(title: title, subtitle: subtitle, isOn: isOn, enabled: enabled, onChange: onChange)
            .opacity(enabled ? 1 : 0.4)
            .accessibilityHint(enabled ? "" : "总提示音已关闭")
    }

    private func hapticSubRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        enabled: Bool,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        ProfileToggleRow(title: title, subtitle: subtitle, isOn: isOn, enabled: enabled, onChange: onChange)
            .opacity(enabled ? 1 : 0.4)
            .accessibilityHint(enabled ? "" : "触感反馈总开关已关闭")
    }

    private func previewRow(symbol: String, title: String) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 26, alignment: .center)
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func scheduleMuteNoticeDismiss() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            showMuteNotice = false
        }
    }

    @ViewBuilder
    private var muteNoticeBar: some View {
        if showMuteNotice && !ProfileSettings.soundEnabled {
            Text("提示音已关闭，试听不会出声。可在「提示音」开关打开后重试。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .padding(.horizontal, DS.Spacing.page)
                .padding(.bottom, DS.Spacing.item)
                .transition(.opacity)
                .accessibilityLabel("提示音已关闭，试听不会出声")
        }
    }

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("声音与触感")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }
}

// MARK: - 预览

#Preview("声音与触感") {
    SoundAndHapticsView(onBack: {})
        .preferredColorScheme(.dark)
}
