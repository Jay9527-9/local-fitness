//
//  Components.swift
//  可复用基础组件：主按钮、快捷入口、卡片容器、进度条、骨架屏、空状态。
//

import SwiftUI

// MARK: - 主按钮

/// 荧光绿主按钮，用于页面唯一的主操作
struct PrimaryButton: View {
    let title: String
    var icon: String?
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(DS.Palette.onAccent)
            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button)
                    .fill(DS.Palette.accent)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
    }
}

// MARK: - 次级按钮

/// 描边次级按钮，用于并列的次要操作
struct SecondaryButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(DS.Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: DS.Size.quickActionHeight)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.button)
                    .fill(DS.Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.button)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - 卡片容器

/// 统一卡片外观
struct CardContainer<Content: View>: View {
    var padding: CGFloat = DS.Spacing.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
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
}

// MARK: - 区块标题

/// 区块标题行，可带尾部操作
struct SectionHeader: View {
    let title: String
    var trailingText: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            if let trailingText {
                if let trailingAction {
                    Button(trailingText, action: trailingAction)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Palette.accent)
                        .buttonStyle(PressableButtonStyle())
                } else {
                    Text(trailingText)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }
}

// MARK: - 进度条

/// 荧光绿进度条
struct ProgressBar: View {
    /// 0…1
    let value: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(DS.Palette.accent)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("训练进度")
        .accessibilityValue("\(Int(max(0, min(1, value)) * 100))%")
    }
}

// MARK: - 元信息标签

/// 小号元信息，如「12 个动作」
struct MetaLabel: View {
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(text)
                .font(DS.Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(DS.Palette.textSecondary)
    }
}

// MARK: - 空状态

/// 空状态预设（页面 48）。由代码绘制图标 + 标题 + 说明 + 可选主按钮构成。
/// 按钮回调由使用页面传入，本组件不直接读写数据。
enum EmptyStatePreset: Equatable {
    case noPlans
    case noHistory
    case noFavorites
    case noSearchResults
    case noBodyData
    case noActiveSession
    case noBackupSelected

    var icon: String {
        switch self {
        case .noPlans: return "square.stack.3d.up"
        case .noHistory: return "calendar"
        case .noFavorites: return "star"
        case .noSearchResults: return "magnifyingglass"
        case .noBodyData: return "scalemass"
        case .noActiveSession: return "play.circle"
        case .noBackupSelected: return "doc"
        }
    }

    var title: String {
        switch self {
        case .noPlans: return "还没有训练计划"
        case .noHistory: return "还没有训练记录"
        case .noFavorites: return "还没有收藏动作"
        case .noSearchResults: return "没有找到匹配动作"
        case .noBodyData: return "还没有身体数据"
        case .noActiveSession: return "没有进行中的训练"
        case .noBackupSelected: return "尚未选择备份文件"
        }
    }

    var message: String {
        switch self {
        case .noPlans: return "新建一个计划开始规律训练。"
        case .noHistory: return "完成一次训练后，这里会按日期记录。"
        case .noFavorites: return "在动作详情点星标即可收藏。"
        case .noSearchResults: return "换个关键词，或清除当前筛选。"
        case .noBodyData: return "记录体重与围度，追踪变化趋势。"
        case .noActiveSession: return "新建力量或有氧训练即可开始。"
        case .noBackupSelected: return "从系统文件选择器选取本 App 的备份文件。"
        }
    }

    var actionTitle: String {
        switch self {
        case .noPlans: return "新建第一个计划"
        case .noHistory: return "开始一次训练"
        case .noFavorites: return "浏览动作库"
        case .noSearchResults: return "清除筛选"
        case .noBodyData: return "记录身体数据"
        case .noActiveSession: return "新建力量训练"
        case .noBackupSelected: return "选择文件"
        }
    }
}

/// 空状态提示，明确给出下一步操作。页面 48 起支持代码绘制图标 + 标题 + 说明 + 主按钮。
struct EmptyStateView: View {
    let message: String
    var icon: String? = nil
    var title: String? = nil
    var actionTitle: String?
    var action: (() -> Void)?

    /// 预设构造。主按钮回调由使用页面传入，未传则不显示按钮（保持垂直居中）。
    init(preset: EmptyStatePreset, action: (() -> Void)? = nil) {
        self.message = preset.message
        self.icon = preset.icon
        self.title = preset.title
        self.actionTitle = preset.actionTitle
        self.action = action
    }

    /// 兼容原有调用形态：只给说明文字，可选标题 / 图标 / 主按钮。
    init(
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.message = message
        self.icon = nil
        self.title = nil
        self.actionTitle = actionTitle
        self.action = action
    }

    /// 减少动态效果时跳过淡入动画。
    @State private var appeared = false

    var body: some View {
        VStack(spacing: DS.Spacing.tight) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
            }

            if let title {
                Text(title)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text(message)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Palette.onAccent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(DS.Palette.accent)
                    )
                    .buttonStyle(PressableButtonStyle())
                    .padding(.top, DS.Spacing.tight)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.card)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                .foregroundStyle(DS.Palette.stroke)
        )
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(MotionConfig.fade) { appeared = true }
        }
    }
}

// MARK: - 骨架屏

/// 骨架屏占位块，带扫光动画
struct SkeletonBlock: View {
    var height: CGFloat
    var cornerRadius: CGFloat = DS.Radius.card
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DS.Palette.surface)
            .frame(height: height)
            .overlay(
                GeometryReader { proxy in
                    LinearGradient(
                        colors: [.clear, DS.Palette.shimmer, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: proxy.size.width * 0.45)
                    .offset(x: phase * proxy.size.width * 1.5)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
            .accessibilityHidden(true)
    }
}

/// 首页骨架屏
struct TrainingHomeSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            SkeletonBlock(height: 176)
            HStack(spacing: DS.Spacing.item) {
                SkeletonBlock(height: DS.Size.quickActionHeight)
                SkeletonBlock(height: DS.Size.quickActionHeight)
            }
            SkeletonBlock(height: 20, cornerRadius: 6)
                .frame(width: 90)
            SkeletonBlock(height: 132)
            SkeletonBlock(height: 20, cornerRadius: 6)
                .frame(width: 90)
            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(height: 76)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入训练数据")
    }
}
