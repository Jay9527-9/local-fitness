//
//  ExerciseSortMenu.swift
//  动作库的排序底部菜单（页面 26）。
//
//  单选：默认推荐 / 名称 A-Z / 最近使用 / 最近收藏 / 难度。
//  当前选项右侧显示荧光绿勾选；选中后立即更新列表（180ms 淡入）。
//  排序偏好持久化到本地 AppPreferences（ProfileSettings.exerciseSort）。
//  只影响显示顺序，不修改动作数据、计划顺序或历史训练记录。
//

import SwiftUI

// MARK: - 排序菜单内容

struct ExerciseSortMenu: View {

    /// 当前排序
    let current: ExerciseSortOrder
    /// 是否有「最近使用」数据；无数据时该项仍可选，但列表回退默认顺序并提示
    let hasRecentUsage: Bool
    /// 是否有「最近收藏」数据
    let hasRecentFavorites: Bool
    /// 选中后回调（由上层写入 AppPreferences 并刷新列表）
    let onSelect: (ExerciseSortOrder) -> Void
    /// 「取消」关闭菜单
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                ForEach(Array(ExerciseSortOrder.allCases.enumerated()), id: \.element.id) { index, order in
                    row(order)
                    if index < ExerciseSortOrder.allCases.count - 1 {
                        Divider().overlay(DS.Palette.stroke)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.page)

            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            Text("排序方式")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("取消")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消排序选择")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
    }

    private func row(_ order: ExerciseSortOrder) -> some View {
        let selected = current == order
        let needsFallback = order.mayFallBackToDefault && !hasData(for: order)

        return Button {
            Haptics.light()
            onSelect(order)
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Text(order.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)

                if needsFallback {
                    Text("暂无数据")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(DS.Palette.fieldFill)
                        )
                }

                Spacer(minLength: DS.Spacing.tight)

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(needsFallback ? "\(order.title)，暂无数据" : order.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func hasData(for order: ExerciseSortOrder) -> Bool {
        switch order {
        case .recentlyUsed: return hasRecentUsage
        case .recentlyFavorited: return hasRecentFavorites
        default: return true
        }
    }
}

// MARK: - 预览

#Preview("排序菜单") {
    ZStack {
        DS.Palette.bg.ignoresSafeArea()
    }
    .bottomDrawer(isPresented: .constant(true), height: 420, title: nil) {
        ExerciseSortMenu(
            current: .defaultOrder,
            hasRecentUsage: true,
            hasRecentFavorites: false,
            onSelect: { _ in },
            onCancel: {}
        )
    }
    .preferredColorScheme(.dark)
}
