//
//  RestDaySheets.swift
//  页面 33（新增休息日）与页面 34（编辑休息日备注）的底部抽屉。
//
//  休息日独立存 `RestDay`，不计入训练次数/时长/容量/动作统计。
//  同日重复标记会提示编辑已有备注，不创建重复记录；删除只删该 RestDay。
//

import SwiftUI

// MARK: - 值层

enum RestDayForm {
    /// 备注上限（页面 34）。
    static let noteMaxLength = 300

    /// 自然日归一化：把日期归到当天零点，避免时区导致的跨日误判。
    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 截断备注到 300 字。
    static func normalizedNote(_ raw: String) -> String {
        String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(noteMaxLength))
    }
}

// MARK: - 页面 33：新增休息日

struct AddRestDaySheet: View {

    /// 默认日期（从历史页传入，其它入口默认当天）
    let defaultDate: Date
    /// 当天是否已有训练记录（非阻断提示）
    let hasSessionsOnDay: Bool
    /// 当天是否已有休息日记录
    let existingRestDay: RestDay?

    let onSave: (Date, String?) -> Void
    let onEditExisting: () -> Void

    @State private var date: Date
    @State private var note: String = ""

    init(
        defaultDate: Date,
        hasSessionsOnDay: Bool,
        existingRestDay: RestDay?,
        onSave: @escaping (Date, String?) -> Void,
        onEditExisting: @escaping () -> Void
    ) {
        self.defaultDate = defaultDate
        self.hasSessionsOnDay = hasSessionsOnDay
        self.existingRestDay = existingRestDay
        self.onSave = onSave
        self.onEditExisting = onEditExisting
        _date = State(initialValue: defaultDate)
        _note = State(initialValue: existingRestDay?.note ?? "")
    }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            header

            if existingRestDay != nil {
                duplicateNotice
            } else {
                form
            }
        }
        .padding(.horizontal, DS.Spacing.page)
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                onEditExisting()
            } label: {
                Text("取消")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消")

            Spacer(minLength: DS.Spacing.item)

            Text("添加休息日")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                onSave(RestDayForm.startOfDay(date), RestDayForm.normalizedNote(note).isEmpty ? nil : RestDayForm.normalizedNote(note))
            } label: {
                Text("保存")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .disabled(existingRestDay != nil)
            .opacity(existingRestDay != nil ? 0.4 : 1)
            .accessibilityLabel("保存休息日")
        }
    }

    private var form: some View {
        VStack(spacing: DS.Spacing.item) {
            if hasSessionsOnDay {
                HStack(alignment: .top, spacing: DS.Spacing.tight) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Palette.accent)
                    Text("当天已有训练记录，仍要标记为休息日吗？轻量训练或补录场景可能需要保留两种信息。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DS.Spacing.item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Palette.accent.opacity(0.08))
                )
            }

            DatePicker("日期", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)
                .font(DS.Typography.body)
                .tint(DS.Palette.accent)
                .accessibilityLabel("休息日日期")

            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("备注（可选）")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                TextEditor(text: $note)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .accessibilityLabel("休息日备注")
            }
        }
    }

    private var duplicateNotice: some View {
        VStack(spacing: DS.Spacing.item) {
            Image(systemName: "info.circle")
                .font(.system(size: 24))
                .foregroundStyle(DS.Palette.accent)
            Text("当天已标记为休息日")
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
            PrimaryButton(title: "编辑已有备注") {
                onEditExisting()
            }
            SecondaryButton(title: "取消") {
                onEditExisting()
            }
        }
        .padding(.vertical, DS.Spacing.section)
    }
}

// MARK: - 页面 34：休息日详情

struct RestDayDetailSheet: View {

    let restDay: RestDay
    /// 当天训练记录数量（用于额外列出训练入口）
    let sessionsOnDay: [WorkoutSession]

    let onSaveNote: (String?) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    let onOpenSession: (UUID) -> Void

    @State private var note: String
    @State private var showDeleteConfirm = false

    init(
        restDay: RestDay,
        sessionsOnDay: [WorkoutSession],
        onSaveNote: @escaping (String?) -> Void,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onOpenSession: @escaping (UUID) -> Void
    ) {
        self.restDay = restDay
        self.sessionsOnDay = sessionsOnDay
        self.onSaveNote = onSaveNote
        self.onDelete = onDelete
        self.onClose = onClose
        self.onOpenSession = onOpenSession
        _note = State(initialValue: restDay.note ?? "")
    }

    private var hasChanges: Bool {
        let original = restDay.note ?? ""
        let current = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return current != original
    }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            header

            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("\(FormatterKit.shortDate(restDay.date)) · 休息日")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                if let createdAt = restDay.createdAt {
                    Text("创建于 \(FormatterKit.shortDate(createdAt))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("备注")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                TextEditor(text: $note)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(minHeight: 96)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .accessibilityLabel("休息日备注")
            }

            if !sessionsOnDay.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text("当天训练（\(sessionsOnDay.count) 次）")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textSecondary)
                    ForEach(sessionsOnDay) { session in
                        Button {
                            onOpenSession(session.id)
                        } label: {
                            HStack(spacing: DS.Spacing.tight) {
                                Image(systemName: session.kind.symbolName)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.Palette.accent)
                                Text(session.name)
                                    .font(DS.Typography.callout)
                                    .foregroundStyle(DS.Palette.textPrimary)
                                    .lineLimit(1)
                                Spacer(minLength: DS.Spacing.tight)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(DS.Palette.textTertiary)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            PrimaryButton(title: "保存备注", isEnabled: hasChanges) {
                Haptics.light()
                let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                onSaveNote(trimmed.isEmpty ? nil : RestDayForm.normalizedNote(trimmed))
            }

            Button {
                showDeleteConfirm = true
            } label: {
                Text("取消休息日标记")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消休息日标记")
        }
        .padding(.horizontal, DS.Spacing.page)
        .alert("取消休息日标记", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { }
            Button("删除", role: .destructive) { onDelete() }
        } message: {
            Text("只删除该休息日标记，不影响同日的训练记录、身体数据或计划。")
        }
    }

    private var header: some View {
        HStack(spacing: DS.Spacing.item) {
            Spacer(minLength: DS.Spacing.item)
            Text("休息日")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Spacing.item)
            Button {
                onClose()
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
    }
}

// MARK: - 预览

#Preview("新增休息日") {
    ZStack { DS.Palette.bg.ignoresSafeArea() }
        .bottomDrawer(isPresented: .constant(true), height: 360, title: nil) {
            AddRestDaySheet(
                defaultDate: .now,
                hasSessionsOnDay: true,
                existingRestDay: nil,
                onSave: { _, _ in },
                onEditExisting: {}
            )
        }
        .preferredColorScheme(.dark)
}
