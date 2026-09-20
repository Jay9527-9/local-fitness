//
//  ActiveSessionPicker.swift
//  页面 29：进行中训练选择底部抽屉。
//
//  列出所有本地未结束的 `WorkoutSession`；当前打开的训练优先并打「当前训练」标签。
//  长按训练卡可「放弃此训练草稿」（二次确认，只删未完成草稿，不影响历史记录）。
//

import SwiftUI

// MARK: - 选择内容

struct ActiveSessionPicker: View {

    /// 全部未结束的训练
    let sessions: [WorkoutSession]
    /// 当前打开的训练 id（打「当前训练」标签并优先排序）
    let currentSessionID: UUID?

    let onSelect: (WorkoutSession) -> Void
    let onNewStrength: () -> Void
    let onNewCardio: () -> Void
    let onDiscard: (WorkoutSession) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            if sessions.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DS.Spacing.tight) {
                        ForEach(sortedSessions) { session in
                            sessionCard(session)
                        }
                    }
                    .padding(.horizontal, DS.Spacing.page)
                    .padding(.bottom, DS.Spacing.section)
                }
            }
        }
    }

    /// 当前训练优先，其余按开始时间倒序。
    private var sortedSessions: [WorkoutSession] {
        sessions.sorted { lhs, rhs in
            let l = lhs.id == currentSessionID ? 0 : 1
            let r = rhs.id == currentSessionID ? 0 : 1
            if l != r { return l < r }
            return lhs.startedAt > rhs.startedAt
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            Text("添加到进行中训练")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
    }

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.section) {
            EmptyStateView(message: "没有进行中的训练")

            VStack(spacing: DS.Spacing.tight) {
                PrimaryButton(title: "新建力量训练", icon: "dumbbell") {
                    onNewStrength()
                }
                SecondaryButton(title: "新建有氧训练", icon: "figure.run") {
                    onNewCardio()
                }
            }
            .padding(.horizontal, DS.Spacing.page)
        }
    }

    private func sessionCard(_ session: WorkoutSession) -> some View {
        let isCurrent = session.id == currentSessionID
        return Button {
            Haptics.light()
            onSelect(session)
        } label: {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                Image(systemName: session.kind.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isCurrent ? DS.Palette.onAccent : DS.Palette.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(isCurrent ? DS.Palette.accent : DS.Palette.surfaceElevated)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DS.Spacing.tight) {
                        Text(session.name)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)

                        if isCurrent {
                            Text("当前训练")
                                .font(DS.Typography.caption2)
                                .foregroundStyle(DS.Palette.onAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(DS.Palette.accent)
                                )
                        }
                    }

                    Text(sessionMeta(session))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isCurrent ? DS.Palette.accent.opacity(0.12) : DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(isCurrent ? DS.Palette.accent.opacity(0.45) : DS.Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                onDiscard(session)
            } label: {
                Label("放弃此训练草稿", systemImage: "trash")
            }
        }
        .accessibilityLabel(sessionAccessibility(session, isCurrent: isCurrent))
    }

    private func sessionMeta(_ session: WorkoutSession) -> String {
        let time = FormatterKit.shortDate(session.startedAt)
        let duration = FormatterKit.duration(seconds: session.durationSeconds)
        let sets = session.completedSetCount
        let type = session.kind.title
        return "\(time) · 已进行 \(duration) · \(sets) 组 · \(type)"
    }

    private func sessionAccessibility(_ session: WorkoutSession, isCurrent: Bool) -> String {
        var parts = [session.name]
        if isCurrent { parts.append("当前训练") }
        parts.append(sessionMeta(session))
        parts.append("长按可放弃此训练草稿")
        return parts.joined(separator: "，")
    }
}

// MARK: - 预览

#Preview("进行中训练选择") {
    ZStack {
        DS.Palette.bg.ignoresSafeArea()
    }
    .bottomDrawer(isPresented: .constant(true), height: 460, title: nil) {
        ActiveSessionPicker(
            sessions: [
                WorkoutSession(name: "推拉腿 · 三日", kind: .strength, startedAt: .now.addingTimeInterval(-1800)),
                WorkoutSession(name: "晨跑", kind: .cardio, startedAt: .now.addingTimeInterval(-900)),
            ],
            currentSessionID: nil,
            onSelect: { _ in },
            onNewStrength: {},
            onNewCardio: {},
            onDiscard: { _ in }
        )
    }
    .preferredColorScheme(.dark)
}
