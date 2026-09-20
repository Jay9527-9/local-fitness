//
//  ReduceMotionView.swift
//  页面 44：减少动态效果设置。
//
//  三种模式（跟随系统 / 始终减少 / 正常动画），保存到 AppPreferences.motionPreference，
//  通过 `MotionConfig` 统一注入全 App。
//

import SwiftUI

struct ReduceMotionView: View {

    let onBack: () -> Void

    @State private var preference = ProfileSettings.motionPreference

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                modeGroup
                affectedGroup
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
    }

    // MARK: 模式

    private var modeGroup: some View {
        group(title: "减少 App 动画") {
            ForEach(MotionPreference.allCases) { mode in
                modeRow(mode)
                if mode != MotionPreference.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }

    private func modeRow(_ mode: MotionPreference) -> some View {
        Button {
            Haptics.light()
            preference = mode
            ProfileSettings.motionPreference = mode
        } label: {
            HStack(spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(mode.detail)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: preference == mode ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(preference == mode ? DS.Palette.accent : DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(preference == mode ? [.isSelected] : [])
        .accessibilityLabel("\(mode.title)。\(mode.detail)")
        .accessibilityValue(preference == mode ? "当前模式" : "")
    }

    // MARK: 受影响内容

    private var affectedGroup: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("受影响内容")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    bullet("页面切换淡入")
                    bullet("底部抽屉上滑")
                    bullet("按钮按压缩放")
                    bullet("图表数值递增")
                    bullet("倒计时最后 3 秒缩放")
                    bullet("骨架屏 shimmer")
                }
            }

            Text("「始终减少」时页面立即切换或仅用短淡入、按钮不缩放、统计数字直接显示最终值、骨架屏使用静态占位、倒计时不做放大动画。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Spacing.card)
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Circle()
                .fill(DS.Palette.accent)
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

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

            Text("减少动态效果")
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

#Preview("减少动态效果") {
    ReduceMotionView(onBack: {})
        .preferredColorScheme(.dark)
}
