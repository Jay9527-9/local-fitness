//
//  ResumeSessionView.swift
//  页面 49：恢复进行中训练。
//
//  训练首页加载完成后以底部抽屉提示「检测到未完成训练」，
//  展示训练名称 / 开始时间 / 已进行时长 / 已完成组数 / 训练类型，
//  提供继续训练、稍后处理、放弃草稿三种操作。多条遗留草稿展示列表。
//

import SwiftUI

// MARK: - 值层：草稿摘要

/// 一条未结束训练草稿的展示摘要。纯计算，可被 Python 照搬推演。
struct ResumeDraft: Identifiable, Equatable {
    let id: UUID
    let name: String
    let kind: WorkoutSession.Kind
    let startedAt: Date
    let durationSeconds: Int
    let completedSetCount: Int
    let totalSetCount: Int

    init(session: WorkoutSession) {
        self.id = session.id
        self.name = session.name
        self.kind = session.kind
        self.startedAt = session.startedAt
        self.durationSeconds = session.durationSeconds
        self.completedSetCount = session.entries.filter(\.isCompleted).count
        self.totalSetCount = session.entries.count
    }

    var kindTitle: String {
        kind == .cardio ? "有氧训练" : "力量训练"
    }
}

/// 草稿摘要的纯推导。
enum ResumeDraftMath {

    /// 草稿已「暂停」的自然日数（按开始日期到今天）。
    static func ageDays(startedAt: Date, now: Date, calendar: Calendar) -> Int {
        let from = calendar.startOfDay(for: startedAt)
        let to = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: from, to: to).day ?? 0
        return max(0, days)
    }

    /// 草稿较旧时的提醒文案。0 天不提醒。
    static func ageReminder(days: Int) -> String? {
        days > 0 ? "该训练已暂停 \(days) 天" : nil
    }
}

// MARK: - 抽屉视图

/// 「检测到未完成训练」底部抽屉。草稿列表由调用方传入，抽屉不直接读写数据。
struct ResumeSessionDrawer: View {

    let drafts: [WorkoutSession]
    let onResume: (WorkoutSession) -> Void
    let onLater: () -> Void
    let onAbandon: (WorkoutSession) -> Void
    /// 草稿数据损坏 / 恢复失败时进入数据恢复页（页面 50）。
    let onOpenRecovery: () -> Void

    @State private var pendingAbandon: WorkoutSession?

    private var now: Date { Date() }
    private var calendar: Calendar { .current }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            if drafts.isEmpty {
                EmptyStateView(preset: .noActiveSession)
            } else if drafts.count == 1, let draft = drafts.first {
                singleDraftCard(draft)
            } else {
                draftList
            }
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.bottom, DS.Spacing.item)
        .confirmationDialog(
            "放弃此训练草稿？",
            isPresented: Binding(
                get: { pendingAbandon != nil },
                set: { if !$0 { pendingAbandon = nil } }
            ),
            presenting: pendingAbandon
        ) { draft in
            Button("放弃草稿", role: .destructive) { onAbandon(draft) }
            Button("取消", role: .cancel) { pendingAbandon = nil }
        } message: { draft in
            Text("只删除「\(draft.name)」这条未完成草稿，不影响任何历史训练记录。")
        }
    }

    // MARK: 单条草稿

    private func singleDraftCard(_ session: WorkoutSession) -> some View {
        let draft = ResumeDraft(session: session)
        return VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(spacing: DS.Spacing.tight) {
                Image(systemName: draft.kind == .cardio ? "figure.run" : "dumbbell")
                    .foregroundStyle(draft.kind == .cardio ? DS.Palette.cardio : DS.Palette.accent)
                Text(draft.name)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(draft.kindTitle)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            metaRow(draft)

            if let reminder = ResumeDraftMath.ageReminder(
                days: ResumeDraftMath.ageDays(startedAt: draft.startedAt, now: now, calendar: calendar)
            ) {
                Text(reminder)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.danger)
            }

            actionButtons(session)
        }
        .padding(DS.Spacing.card)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("检测到未完成训练，\(draft.name)，\(draft.kindTitle)")
    }

    private func metaRow(_ draft: ResumeDraft) -> some View {
        HStack(spacing: DS.Spacing.item) {
            metaCell("开始", FormatterKit.shortDate(draft.startedAt))
            metaCell("时长", FormatterKit.duration(seconds: draft.durationSeconds))
            metaCell("完成组数", "\(draft.completedSetCount) / \(draft.totalSetCount)")
        }
    }

    private func metaCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 多条草稿列表

    private var draftList: some View {
        VStack(spacing: DS.Spacing.tight) {
            ForEach(drafts) { session in
                let draft = ResumeDraft(session: session)
                HStack(spacing: DS.Spacing.item) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)
                        Text("\(draft.kindTitle) · \(FormatterKit.shortDate(draft.startedAt)) · \(draft.completedSetCount)/\(draft.totalSetCount) 组")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.surface)
                )
                .contentShape(Rectangle())
                .onTapGesture { onResume(session) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(draft.name)，\(draft.kindTitle)")
            }
        }
    }

    // MARK: 操作按钮

    private func actionButtons(_ session: WorkoutSession) -> some View {
        VStack(spacing: DS.Spacing.tight) {
            PrimaryButton(title: "继续训练", icon: "play.fill") {
                onResume(session)
            }

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "稍后处理") {
                    onLater()
                }
                SecondaryButton(title: "放弃草稿") {
                    pendingAbandon = session
                }
            }
        }
    }
}
