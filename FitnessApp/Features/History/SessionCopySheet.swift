//
//  SessionCopySheet.swift
//  页面 37：复制训练记录为草稿。
//
//  复制选项（动作顺序与组数、最近重量与次数、热身组、训练备注、每组备注）。
//  所有复制的组均为未完成状态，不复制完成时间、统计结果或历史 ID。
//  若当前存在未结束训练，先提示用户选择，不静默覆盖。
//

import SwiftUI

// MARK: - 复制选项值层

struct SessionCopyOptions: Equatable {
    /// 复制动作顺序与组数：默认开启，不可关闭（页面 37 规格）。
    var copyOrderAndSets: Bool = true
    /// 复制最近实际重量与次数：默认开启。
    var copyWeightsAndReps: Bool = true
    /// 复制热身组：默认关闭。
    var copyWarmupSets: Bool = false
    /// 复制训练备注：默认关闭。
    var copyNote: Bool = false
    /// 复制每组备注：默认关闭。
    var copySetNotes: Bool = false
}

// MARK: - 复制构建（纯函数）

enum SessionCopyBuilder {

    /// 把复制选项施加到一份「未完成草稿」上，返回最终草稿。
    /// - 关闭「复制重量与次数」：重量与次数清零（保留目标区间由计划提供）。
    /// - 关闭「复制热身组」：剔除热身组。
    /// - 关闭「复制训练备注」：清空备注。
    static func apply(
        _ options: SessionCopyOptions,
        to draft: WorkoutSession
    ) -> WorkoutSession {
        var result = draft

        var entries = draft.entries
        if !options.copyWarmupSets {
            entries = entries.filter { !$0.isWarmup }
        }
        if !options.copyWeightsAndReps {
            entries = entries.map { entry in
                var copy = entry
                copy.weight = 0
                copy.reps = 0
                return copy
            }
        }
        result.entries = entries

        if !options.copyNote {
            result.note = nil
        }
        return result
    }
}

// MARK: - 确认抽屉

struct CopySessionSheet: View {

    let sourceName: String
    let finishedAt: Date
    let exerciseCount: Int
    let totalSetCount: Int
    /// 是否存在另一条未结束训练（用于冲突提示）
    let hasActiveSession: Bool

    let onCreate: (SessionCopyOptions) -> Void
    let onContinueActive: () -> Void
    let onDiscardAndCreate: (SessionCopyOptions) -> Void
    let onCancel: () -> Void

    @State private var copyWeightsAndReps = true
    @State private var copyWarmupSets = false
    @State private var copyNote = false
    @State private var copySetNotes = false

    private var options: SessionCopyOptions {
        SessionCopyOptions(
            copyOrderAndSets: true,
            copyWeightsAndReps: copyWeightsAndReps,
            copyWarmupSets: copyWarmupSets,
            copyNote: copyNote,
            copySetNotes: copySetNotes
        )
    }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            header
            sourceSummary
            optionsList
            notice
            actionButtons
        }
        .padding(.horizontal, DS.Spacing.page)
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            Spacer(minLength: DS.Spacing.item)
            Text("复制为新训练")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.item)
        }
    }

    private var sourceSummary: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(sourceName)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            Text("\(FormatterKit.shortDate(finishedAt)) · \(exerciseCount) 个动作 · \(totalSetCount) 组")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var optionsList: some View {
        VStack(spacing: 0) {
            lockedOption("复制动作顺序与组数", "默认开启，不可关闭", isOn: true)
            Divider().overlay(DS.Palette.stroke)
            toggleOption("复制最近实际重量与次数", isOn: $copyWeightsAndReps)
            Divider().overlay(DS.Palette.stroke)
            toggleOption("复制热身组", isOn: $copyWarmupSets)
            Divider().overlay(DS.Palette.stroke)
            toggleOption("复制训练备注", isOn: $copyNote)
            Divider().overlay(DS.Palette.stroke)
            toggleOption("复制每组备注", isOn: $copySetNotes)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    private func lockedOption(_ title: String, _ subtitle: String, isOn: Bool) -> some View {
        HStack(spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text(subtitle)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            Spacer(minLength: DS.Spacing.tight)
            Toggle("", isOn: .constant(isOn))
                .labelsHidden()
                .tint(DS.Palette.accent)
                .disabled(true)
                .accessibilityHidden(true)
        }
        .padding(DS.Spacing.item)
    }

    private func toggleOption(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: DS.Spacing.tight)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DS.Palette.accent)
                .accessibilityLabel(title)
        }
        .padding(DS.Spacing.item)
    }

    private var notice: some View {
        Text("所有复制的组均为未完成状态；不会复制旧训练的完成时间、统计结果或历史 ID。")
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: DS.Spacing.tight) {
            if hasActiveSession {
                PrimaryButton(title: "继续现有训练") { onContinueActive() }
                SecondaryButton(title: "放弃现有草稿后创建") {
                    onDiscardAndCreate(options)
                }
                SecondaryButton(title: "取消") { onCancel() }
            } else {
                PrimaryButton(title: "创建并开始训练") {
                    onCreate(options)
                }
                SecondaryButton(title: "取消") { onCancel() }
            }
        }
    }
}

// MARK: - 预览

#Preview("复制为草稿") {
    ZStack { DS.Palette.bg.ignoresSafeArea() }
        .bottomDrawer(isPresented: .constant(true), height: 560, title: nil) {
            CopySessionSheet(
                sourceName: "推拉腿 · 三日",
                finishedAt: .now.addingTimeInterval(-86400),
                exerciseCount: 6,
                totalSetCount: 22,
                hasActiveSession: false,
                onCreate: { _ in },
                onContinueActive: {},
                onDiscardAndCreate: { _ in },
                onCancel: {}
            )
        }
        .preferredColorScheme(.dark)
}
