//
//  AppSettingsView.swift
//  页面 22：应用设置。
//
//  显示 / 单位 / 提醒 / 关于 四组。每项修改后立即写入本地 UserDefaults
//  （ProfileSettings，即本 App 的「AppPreferences」），返回后相关界面即时刷新。
//  不含评分、反馈社区、账号或分享入口。
//

import SwiftUI

struct AppSettingsView: View {

    let onBack: () -> Void
    /// 进入「单位设置」（页面 42）。
    let onOpenUnits: () -> Void
    /// 进入「声音与触感」（页面 43）。
    let onOpenSoundAndHaptics: () -> Void
    /// 进入「减少动态效果」（页面 44）。
    let onOpenReduceMotion: () -> Void
    /// 进入「权限管理」（页面 51）。
    let onOpenPermissions: () -> Void

    // UserDefaults 不参与 SwiftUI 依赖追踪，保留 @State 镜像即时反映。
    @State private var appearanceMode = ProfileSettings.appearanceMode
    @State private var listTextSize = ProfileSettings.listTextSize
    @State private var restNotificationOn = RestNotification.isEnabled
    @State private var restNotificationDenied = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                displayGroup
                unitGroup
                reminderGroup
                privacyGroup
                aboutGroup
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
    }

    // MARK: 显示

    private var displayGroup: some View {
        group(title: "显示") {
            pickerRow("外观模式", selection: $appearanceMode) { mode in
                ProfileSettings.appearanceMode = mode
            }

            Divider().overlay(DS.Palette.stroke)

            Button {
                Haptics.light()
                onOpenReduceMotion()
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    Text("减少动态效果")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(ProfileSettings.motionPreference.title)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("减少动态效果，当前 \(ProfileSettings.motionPreference.title)")

            Divider().overlay(DS.Palette.stroke)

            pickerRow("列表文字大小", selection: $listTextSize) { size in
                ProfileSettings.listTextSize = size
            }
        }
    }

    // MARK: 单位

    private var unitGroup: some View {
        group(title: "单位") {
            Button {
                Haptics.light()
                onOpenUnits()
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    Text("重量 / 长度 / 有氧距离")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(ProfileSettings.weightUnit.shortTitle) · \(ProfileSettings.lengthUnit.shortTitle) · \(ProfileSettings.cardioDistanceUnit.shortTitle)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("单位设置，重量单位 \(ProfileSettings.weightUnit.shortTitle)，长度单位 \(ProfileSettings.lengthUnit.shortTitle)，有氧距离单位 \(ProfileSettings.cardioDistanceUnit.shortTitle)")
        }
    }

    // MARK: 提醒

    private var reminderGroup: some View {
        group(title: "提醒") {
            Button {
                Haptics.light()
                onOpenSoundAndHaptics()
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    Text("声音与触感")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(ProfileSettings.soundEnabled && ProfileSettings.hapticsEnabled
                         ? "提示音与触感已开启" : "部分已关闭")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("声音与触感")

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "本地休息结束通知",
                subtitle: "App 不在前台时发本地通知",
                isOn: Binding(
                    get: { restNotificationOn },
                    set: { wantsOn in
                        if wantsOn {
                            RestNotification.enable { granted in
                                restNotificationDenied = !granted
                                restNotificationOn = granted
                            }
                        } else {
                            RestNotification.disable()
                            restNotificationOn = false
                            restNotificationDenied = false
                        }
                    }
                )
            ) { _ in }
        }
    }

    // MARK: 隐私（页面 51）

    private var privacyGroup: some View {
        group(title: "隐私") {
            Button {
                Haptics.light()
                onOpenPermissions()
            } label: {
                HStack(spacing: DS.Spacing.item) {
                    Text("权限管理")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text("通知与相册")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("权限管理，本地通知与相册访问")
        }
    }

    // MARK: 关于

    private var aboutGroup: some View {
        group(title: "关于") {
            infoRow("App 版本", "v\(AppResources.appVersion)")
            Divider().overlay(DS.Palette.stroke)
            infoRow("数据结构版本", "v\(AppResources.databaseVersion)")
            Divider().overlay(DS.Palette.stroke)
            infoRow("动作库版本", "v\(AppResources.exerciseLibraryVersion)")

            Divider().overlay(DS.Palette.stroke)

            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("开源许可与媒体署名")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                Text(AppResources.exerciseDataSourceNote)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppResources.exerciseMediaAttribution)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 12)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: 复用组件

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

    /// 一个「标题 + 菜单选择」行，用原生 .menu 选择器。
    private func pickerRow<Option: CaseIterable & Identifiable & Hashable>(
        _ title: String,
        selection: Binding<Option>,
        onChange: @escaping (Option) -> Void
    ) -> some View where Option.AllCases: RandomAccessCollection {
        HStack(spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: 0)
            Picker(title, selection: Binding(
                get: { selection.wrappedValue },
                set: { newValue in
                    selection.wrappedValue = newValue
                    onChange(newValue)
                }
            )) {
                ForEach(Array(Option.allCases)) { option in
                    Text(displayTitle(option)).tag(option)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.Palette.accent)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private func displayTitle<Option>(_ option: Option) -> String {
        // 各选项枚举都提供 title，这里用协议约束不到的反射式兜底：
        // 实际上 Option 限定为 AppearanceMode / ListTextSize / BodyWeightUnit / BodyLengthUnit。
        if let a = option as? AppearanceMode { return a.title }
        if let l = option as? ListTextSize { return l.title }
        if let w = option as? BodyWeightUnit { return w.shortTitle }
        if let len = option as? BodyLengthUnit { return len.shortTitle }
        return "\(option)"
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: 0)
            Text(value)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(value)")
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

            Text("应用设置")
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

#Preview("应用设置") {
    AppSettingsView(
        onBack: {},
        onOpenUnits: {},
        onOpenSoundAndHaptics: {},
        onOpenReduceMotion: {},
        onOpenPermissions: {}
    )
    .preferredColorScheme(.dark)
}
