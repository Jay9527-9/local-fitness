//
//  ProfileSubpages.swift
//  页面 13「我的」的子页：个人资料编辑、我的计划、动作收藏、训练偏好。
//
//  全部是只读 / 轻量设置页，不引入账号或社交；写操作只走本地仓储 / UserDefaults。
//

import SwiftUI

// MARK: - 个人资料编辑

// 页面 17 起，「个人资料编辑」从只改昵称的轻量页升级为完整表单
// （头像 / 昵称 / 训练开始日期 / 训练目标 / 个人说明），
// 迁到独立的 `ProfileEditView.swift`（Features/Profile）。
// 这里不再保留旧占位实现。

// MARK: - 我的计划

// 页面 15 起，「我的计划」从只读列表升级为完整的计划管理页，
// 迁到独立的 `PlanListView.swift`（搜索 / 排序 / 三点菜单 / 多选 / 导入导出）。
// 这里不再保留旧占位实现。

// MARK: - 动作收藏

// 页面 16 起，「动作收藏」从只读列表升级为完整的收藏管理页
// （搜索 / 排序 / 肌群筛选 / 取消收藏撤销 / 长按菜单），
// 迁到独立的 `FavoriteExercisesView.swift`（Features/Exercises）。
// 这里不再保留旧占位实现。

// MARK: - 训练偏好

/// 页面 14：训练偏好设置。
///
/// 三组（训练记录 / 计时器 / 训练流程）+ 底部「恢复默认训练偏好」危险操作。
/// 全部开关即时原子写入本地 `ProfileSettings`（UserDefaults），不落仓储、不碰训练数据。
struct TrainingPreferencesView: View {

    let onBack: () -> Void

    // 各开关的显示镜像。UserDefaults 不参与 SwiftUI 依赖追踪，
    // 所以保留 @State 镜像，切换后立刻反映到界面并写回。
    @State private var defaultRest = ProfileSettings.defaultRest
    @State private var autoCopyLastRecord = ProfileSettings.prefillWeights
    @State private var autoStartRest = ProfileSettings.autoStartRest
    @State private var showVolume = ProfileSettings.showVolume
    @State private var soundEnabled = ProfileSettings.soundEnabled
    @State private var hapticsEnabled = ProfileSettings.hapticsEnabled
    @State private var lastTenSecondsReminder = ProfileSettings.lastTenSecondsReminder
    @State private var countdownStyle = ProfileSettings.countdownStyle
    @State private var autoAdvanceExercise = ProfileSettings.autoAdvanceExercise
    @State private var copyPreviousSet = ProfileSettings.copyPreviousSet
    @State private var showWarmupSets = ProfileSettings.showWarmupSets
    @State private var keepTimerOnMinimize = ProfileSettings.keepTimerOnMinimize
    @State private var restNotificationOn = RestNotification.isEnabled
    @State private var restNotificationDenied = false

    // 抽屉状态
    @State private var showRestPicker = false
    @State private var showCountdownStylePicker = false
    @State private var showResetConfirm = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                recordGroup
                timerGroup
                flowGroup
                resetSection
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .bottomDrawer(
            isPresented: $showRestPicker,
            height: 430,
            title: "默认休息时间",
            subtitle: "新建动作与未单独配置动作的组间休息秒数"
        ) {
            DefaultRestPickerContent(
                scope: .appDefault,
                initialSeconds: defaultRest,
                onSave: { seconds in
                    defaultRest = seconds
                    ProfileSettings.defaultRest = seconds
                    showRestPicker = false
                    Haptics.success()
                },
                onCancel: { showRestPicker = false }
            )
        }
        .bottomDrawer(
            isPresented: $showCountdownStylePicker,
            height: 320,
            title: "倒计时数字样式",
            subtitle: "组间休息倒计时的数字大小"
        ) {
            CountdownStylePickerContent(selected: countdownStyle) { style in
                countdownStyle = style
                ProfileSettings.countdownStyle = style
                showCountdownStylePicker = false
            }
        }
        .bottomDrawer(
            isPresented: $showResetConfirm,
            height: 460,
            title: "恢复默认训练偏好",
            subtitle: "以下选项将被重置"
        ) {
            ResetTrainingDefaultsContent(
                items: ProfileSettings.trainingPreferenceDefaults,
                onCancel: { showResetConfirm = false },
                onConfirm: {
                    ProfileSettings.restoreTrainingDefaults()
                    syncAllFromSettings()
                    showResetConfirm = false
                    Haptics.success()
                }
            )
        }
    }

    // MARK: 训练记录

    private var recordGroup: some View {
        group(title: "训练记录") {
            prefMenuRow(
                title: "默认组间休息时间",
                value: FormatterKit.rest(seconds: defaultRest),
                symbol: "timer"
            ) { showRestPicker = true }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "自动复制上次记录",
                subtitle: "添加已有动作时建议上次的重量与次数，不自动写入完成状态",
                isOn: $autoCopyLastRecord
            ) { on in ProfileSettings.prefillWeights = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "完成一组后自动开始休息",
                subtitle: "勾选完成一组后自动弹出休息倒计时",
                isOn: $autoStartRest
            ) { on in ProfileSettings.autoStartRest = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "显示训练容量",
                subtitle: "关闭后训练执行页不显示总容量，历史统计仍在后台计算",
                isOn: $showVolume
            ) { on in ProfileSettings.showVolume = on }
        }
    }

    // MARK: 计时器

    private var timerGroup: some View {
        group(title: "计时器") {
            ProfileToggleRow(
                title: "倒计时提示音",
                subtitle: "休息结束播放短提示音",
                isOn: $soundEnabled
            ) { on in ProfileSettings.soundEnabled = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "触感反馈",
                subtitle: "按压与休息结束的振动反馈",
                isOn: $hapticsEnabled
            ) { on in ProfileSettings.hapticsEnabled = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "倒计时最后 10 秒提醒",
                subtitle: "最后 10 秒数字转荧光绿强调",
                isOn: $lastTenSecondsReminder
            ) { on in ProfileSettings.lastTenSecondsReminder = on }

            Divider().overlay(DS.Palette.stroke)

            prefMenuRow(
                title: "倒计时数字样式",
                value: countdownStyle.title,
                symbol: "textformat.size"
            ) { showCountdownStylePicker = true }

            Divider().overlay(DS.Palette.stroke)

            // 页面 06 引入的「休息结束本地通知」开关。页面 14 规格的计时器组
            // 只列了提示音 / 触感 / 最后 10 秒 / 数字样式四项，但通知是已经
            // 接线的真实功能（`RestNotification`），删掉会把它变成永远无法关闭。
            ProfileToggleRow(
                title: "休息结束通知",
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

            if restNotificationDenied {
                Text("未获得通知权限，可在系统「设置 → 通知」里为本应用打开。倒计时本身不受影响。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.bottom, DS.Spacing.item)
            }
        }
    }

    // MARK: 训练流程

    private var flowGroup: some View {
        group(title: "训练流程") {
            ProfileToggleRow(
                title: "完成当前动作后自动定位下一动作",
                subtitle: "一组动作全部完成后自动滚动到下一个动作",
                isOn: $autoAdvanceExercise
            ) { on in ProfileSettings.autoAdvanceExercise = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "新增组时复制上一组数值",
                subtitle: "关闭后新组以计划目标次数起填，不继承上一组重量",
                isOn: $copyPreviousSet
            ) { on in ProfileSettings.copyPreviousSet = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "默认显示热身组",
                subtitle: "关闭后计划里标记的热身组默认收起",
                isOn: $showWarmupSets
            ) { on in ProfileSettings.showWarmupSets = on }

            Divider().overlay(DS.Palette.stroke)

            ProfileToggleRow(
                title: "最小化训练后保留计时器",
                subtitle: "关闭后仍保存训练草稿，但不显示后台计时",
                isOn: $keepTimerOnMinimize
            ) { on in ProfileSettings.keepTimerOnMinimize = on }
        }
    }

    // MARK: 恢复默认

    private var resetSection: some View {
        Button {
            Haptics.warning()
            showResetConfirm = true
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .frame(width: 24)
                Text("恢复默认训练偏好")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.danger)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.danger.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.danger.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("恢复默认训练偏好")
        .accessibilityHint("只重置训练偏好，不影响训练计划、历史记录、动作库或身体数据")
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

    /// 一个「标题 + 当前值 + chevron」的菜单行，点击打开底部抽屉。
    private func prefMenuRow(title: String, value: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.light()
            action()
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 26, alignment: .center)

                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer(minLength: DS.Spacing.tight)

                Text(value)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，当前 \(value)")
    }

    /// 把全部 @State 镜像同步回当前 UserDefaults 值（恢复默认后调用）。
    private func syncAllFromSettings() {
        defaultRest = ProfileSettings.defaultRest
        autoCopyLastRecord = ProfileSettings.prefillWeights
        autoStartRest = ProfileSettings.autoStartRest
        showVolume = ProfileSettings.showVolume
        soundEnabled = ProfileSettings.soundEnabled
        hapticsEnabled = ProfileSettings.hapticsEnabled
        lastTenSecondsReminder = ProfileSettings.lastTenSecondsReminder
        countdownStyle = ProfileSettings.countdownStyle
        autoAdvanceExercise = ProfileSettings.autoAdvanceExercise
        copyPreviousSet = ProfileSettings.copyPreviousSet
        showWarmupSets = ProfileSettings.showWarmupSets
        keepTimerOnMinimize = ProfileSettings.keepTimerOnMinimize
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

            Text("训练偏好")
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

// MARK: - 倒计时数字样式单选抽屉

/// 普通 / 大号 的单选底部抽屉内容。
struct CountdownStylePickerContent: View {

    let selected: CountdownNumberStyle
    let onSelect: (CountdownNumberStyle) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CountdownNumberStyle.allCases) { style in
                Button {
                    Haptics.light()
                    onSelect(style)
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(style.title)
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Palette.textPrimary)
                            Text(styleSubtitle(style))
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: style == selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundStyle(style == selected ? DS.Palette.accent : DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(style == selected ? [.isSelected] : [])
                .accessibilityLabel("\(style.title)倒计时数字")

                if style != CountdownNumberStyle.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
        .padding(.bottom, DS.Spacing.item)
    }

    private func styleSubtitle(_ style: CountdownNumberStyle) -> String {
        switch style {
        case .normal: return "紧凑显示，适合多行场景"
        case .large: return "数字更大，隔远也能看清"
        }
    }
}

// MARK: - 恢复默认确认内容

/// 恢复默认前的确认：列出将被重置的选项，二次确认后才真正写回默认值。
struct ResetTrainingDefaultsContent: View {

    let items: [TrainingPreferenceResetItem]
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack {
                        Text(item.title)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Spacer(minLength: 0)
                        Text(item.value)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .padding(.horizontal, DS.Spacing.card)
                    .padding(.vertical, 8)
                }
            }

            Text("只重置训练偏好，不影响训练计划、历史记录、动作库或身体数据。")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.card)

            Button {
                Haptics.warning()
                onConfirm()
            } label: {
                Text("恢复默认")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .fill(DS.Palette.danger.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .stroke(DS.Palette.danger.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, DS.Spacing.card)
            .accessibilityLabel("确认恢复默认训练偏好")

            SecondaryButton(title: "取消") { onCancel() }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.bottom, DS.Spacing.item)
        }
    }
}

// MARK: - 预览

#Preview("训练偏好") {
    TrainingPreferencesView(onBack: {})
        .preferredColorScheme(.dark)
}
