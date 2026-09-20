//
//  BottomDrawer.swift
//  通用底部抽屉容器：深灰不透明面板 + 24pt 圆角 + 顶部拖拽指示条，
//  260ms ease-out 上滑，背后 35% 黑色遮罩，点击遮罩或下拉关闭。
//
//  用 ZStack 覆盖层实现而不是系统 sheet，是为了：
//  1. 完全控制圆角、遮罩浓度与进场曲线，不受系统样式影响；
//  2. 遮盖在同页面的滚动内容之上，关闭时不打断页面的滚动位置；
//  3. 避免系统 sheet 在连续弹出（配置抽屉接在计划选择之后）时的时序问题。
//

import SwiftUI

/// 抽屉里的一行操作项
struct DrawerActionRow: View {

    var title: String
    var subtitle: String?
    var symbol: String
    var isDestructive: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: {
            guard isEnabled else { return }
            Haptics.light()
            action()
        }) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.body)
                        .foregroundStyle(titleColor)
                        .multilineTextAlignment(.leading)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityText)
    }

    private var iconColor: Color {
        guard isEnabled else { return DS.Palette.textTertiary }
        return isDestructive ? DS.Palette.danger : DS.Palette.accent
    }

    private var titleColor: Color {
        guard isEnabled else { return DS.Palette.textTertiary }
        return isDestructive ? DS.Palette.danger : DS.Palette.textPrimary
    }

    private var accessibilityText: String {
        var parts = [title]
        if let subtitle, !subtitle.isEmpty { parts.append(subtitle) }
        if !isEnabled { parts.append("不可用") }
        return parts.joined(separator: "，")
    }
}

/// 通用底部抽屉。内容由调用方提供，容器只负责遮罩、圆角、动画与关闭手势。
struct BottomDrawer<Content: View>: View {

    /// 抽屉高度。用固定高度而不是 detents，行为在各机型上更可预期。
    var height: CGFloat
    /// 顶部标题区；传 nil 则只保留拖拽指示条
    var title: String? = nil
    var subtitle: String? = nil
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    /// 上下拖动过程中的位移
    @State private var dragOffset: CGFloat = 0
    /// 遮罩与面板的进场进度
    @State private var isVisible = false

    private var cornerRadius: CGFloat { DS.Radius.drawer }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Scrim.color
                .ignoresSafeArea()
                .opacity(isVisible ? 1 : 0)
                .onTapGesture { dismiss() }
                .accessibilityLabel("关闭")
                .accessibilityAddTraits(.isButton)

            panel
                .offset(y: isVisible ? max(0, dragOffset) : height)
                .animation(DS.Motion.drawer, value: isVisible)
                .animation(DS.Motion.standard, value: dragOffset)
        }
        .onAppear {
            // 首次进入要在下一帧再翻转，否则 SwiftUI 会把初始与目标状态合并、动画不生效。
            DispatchQueue.main.async { isVisible = true }
        }
        .accessibilityAddTraits(.isModal)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            handle
            if title != nil || subtitle != nil {
                header
            }
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(
            // 不透明深灰面板，避免身后内容透出影响阅读
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
            .fill(DS.Palette.surfaceElevated)
            .ignoresSafeArea(edges: .bottom)
        )
        .gesture(dragGesture)
    }

    /// 顶部拖拽指示条。做成可拖拽区域，避免整块面板都被手势吞掉。
    private var handle: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let title {
                Text(title)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
            }
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.card)
        .padding(.bottom, DS.Spacing.item)
    }

    /// 下拉关闭：跟手位移，松手超过 80pt 或快速下甩即关闭
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height > 80
                    || value.predictedEndTranslation.height > 180
                if shouldDismiss {
                    dismiss()
                } else {
                    dragOffset = 0
                }
            }
    }

    private func dismiss() {
        withAnimation(DS.Motion.drawer) {
            isVisible = false
        }
        // 等离场动画播完再通知外部销毁，避免面板突然消失
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            onDismiss()
        }
    }
}

/// 把抽屉叠加到任意页面上的统一修饰器，省去每个界面重复写 ZStack。
extension View {
    func bottomDrawer<Content: View>(
        isPresented: Binding<Bool>,
        height: CGFloat,
        title: String? = nil,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        overlay {
            if isPresented.wrappedValue {
                BottomDrawer(
                    height: height,
                    title: title,
                    subtitle: subtitle,
                    onDismiss: { isPresented.wrappedValue = false },
                    content: content
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
    }
}

// MARK: - 触感反馈

/// `sensoryFeedback` 是 iOS 17+ API，这里统一走 UIKit 生成器。
///
/// 页面 13 起增加全局开关：`ProfileSettings.hapticsEnabled` 关闭时静默返回，
/// 这样「我的 → 应用设置 → 触感」能真正关掉全 App 的触感，而不是只改个摆设。
enum Haptics {

    private static var isEnabled: Bool { ProfileSettings.hapticsEnabled }

    /// 轻量触感，用于列表行、抽屉选项等常规点击
    static func light() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    /// 中等触感，用于拖拽落位、删除确认等有重量的操作
    static func medium() {
        guard isEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    /// 成功提示，用于保存、复制等正向结果
    static func success() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// 警告提示，用于二次确认弹窗
    static func warning() {
        guard isEnabled else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)
    }
}

// MARK: - 预览

#Preview("底部抽屉") {
    ZStack {
        DS.Palette.bg.ignoresSafeArea()
        Text("页面内容")
            .foregroundStyle(DS.Palette.textSecondary)
    }
    .bottomDrawer(isPresented: .constant(true), height: 320, title: "杠铃卧推", subtitle: "胸部 · 杠铃") {
        VStack(spacing: 0) {
            DrawerActionRow(title: "添加到进行中的训练", subtitle: "推拉腿 · 三日 · 已完成 6 组", symbol: "play.circle") {}
            Divider().overlay(DS.Palette.stroke)
            DrawerActionRow(title: "添加到已有计划", symbol: "list.bullet.rectangle") {}
            Divider().overlay(DS.Palette.stroke)
            DrawerActionRow(title: "新建力量训练并添加", symbol: "plus.circle") {}
            Divider().overlay(DS.Palette.stroke)
            DrawerActionRow(title: "从计划移除", symbol: "trash", isDestructive: true) {}
        }
    }
}
