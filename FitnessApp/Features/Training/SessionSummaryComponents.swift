//
//  SessionSummaryComponents.swift
//  训练总结页专用组件：代码绘制的完成勾选、递增数字、动作完成情况行、笔记卡片。
//
//  说明：勾选图形完全用 SwiftUI 路径绘制，不引入任何第三方插画或图片资源。
//

import SwiftUI

// MARK: - 代码绘制的完成勾选

/// 训练完成图标。外圈荧光绿描边，内部为勾选路径。
/// 用 Canvas 之外的纯 Shape 组合，保证 VoiceOver 与动态字体下行为稳定。
struct SummaryCheckGlyph: View {
    var size: CGFloat = DS.Size.summaryCheckRing
    var strokeWidth: CGFloat = DS.Size.summaryCheckStroke

    var body: some View {
        ZStack {
            Circle()
                .stroke(DS.Palette.accent, lineWidth: strokeWidth)
                .frame(width: size, height: size)

            CheckmarkShape()
                .stroke(
                    DS.Palette.accent,
                    style: StrokeStyle(
                        lineWidth: strokeWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(
                    width: size * 0.46,
                    height: size * 0.46
                )
        }
        // 图形是纯装饰，朗读交给外层合并后的标题语句。
        .accessibilityHidden(true)
    }
}

/// 勾选路径。按 0…1 归一化坐标绘制，随 frame 等比缩放。
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        // 起笔左下 → 折点底部中间偏左 → 收笔右上
        path.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.36, y: rect.minY + h * 0.86))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.14))
        return path
    }
}

// MARK: - 递增数字

/// 统计卡片数值。从 0 递增到目标值，动画时长 500ms。
///
/// 减少动态效果开启时直接显示最终值，不做任何中间帧。
/// 用 `.task(id:)` 驱动而非 `.animation`，因为在 ScrollView 内
/// 隐式动画对文本内容的插值并不可靠。
struct CountUpNumberText: View {
    /// 目标数值
    let value: Double
    /// 展示格式。默认取整。
    var format: (Double) -> String = { FormatterKit.plainNumber($0) }
    /// 强调色显示
    var isAccent: Bool = false
    /// 非空时直接显示该文本，跳过递增动画。
    /// 平均配速这类比值不适合从 0 递增，会读出无意义的中间值。
    var literalText: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed: Double = 0

    var body: some View {
        Text(literalText ?? format(displayed))
            .font(.system(size: DS.Size.summaryMetricFont, weight: .bold))
            .foregroundStyle(isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .task(id: value) { await runCountUp() }
    }

    @MainActor
    private func runCountUp() async {
        // 直接显示型卡片没有任何递增过程
        guard literalText == nil else { return }

        let target = max(0, value)

        guard !reduceMotion else {
            displayed = target
            return
        }

        // 从 0 起跑，让「本次训练」的增量有可见的积累感。
        displayed = 0
        let steps = 24
        let stepDuration = 0.5 / Double(steps)
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            // easeOut：前段快，尾部收敛，和视觉节奏一致
            let eased = 1 - pow(1 - progress, 3)
            displayed = target * eased
            try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
            if Task.isCancelled { return }
        }
        displayed = target
    }
}

// MARK: - 动作完成情况行

/// 「动作完成情况」中的单个动作行。支持展开 / 收起每一组的记录。
struct ExerciseBreakdownRow: View {
    let exerciseID: String
    let entries: [SetEntry]
    /// 动作名称。优先取动作库，取不到时由调用方兜底传入。
    let displayName: String
    @Binding var expandedExerciseIDs: Set<String>

    private var isExpanded: Bool { expandedExerciseIDs.contains(exerciseID) }

    private var completed: [SetEntry] { entries.filter { $0.isCompleted } }

    private var exerciseVolume: Double {
        completed.reduce(0) { $0 + $1.volume }
    }

    /// 「40 kg × 8」
    private var topSetText: String {
        guard let best = completed.max(by: { $0.volume < $1.volume }) else { return "—" }
        return "\(FormatterKit.weight(best.weight)) × \(best.reps)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Button {
                toggle()
            } label: {
                header
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityHint(isExpanded ? "轻点两下收起每组记录" : "轻点两下展开每组记录")
            .accessibilityAddTraits(.isButton)

            if isExpanded {
                VStack(spacing: DS.Spacing.tight) {
                    ForEach(entries) { entry in
                        setRow(entry)
                    }
                }
                .padding(.top, DS.Spacing.tight)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DS.Spacing.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .animation(DS.Motion.disclosure, value: isExpanded)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)

                HStack(spacing: DS.Spacing.item) {
                    MetaLabel(text: "\(completed.count)/\(entries.count) 组", icon: "checkmark.circle")
                    if exerciseVolume > 0 {
                        MetaLabel(text: "容量 \(FormatterKit.plainNumber(exerciseVolume)) kg",
                                  icon: "scalemass")
                    } else {
                        MetaLabel(text: topSetText, icon: "dumbbell")
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func setRow(_ entry: SetEntry) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Text("第 \(entry.index + 1) 组")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 54, alignment: .leading)

            if entry.isWarmup {
                Text("热身")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DS.Palette.warmupFill)
                    )
            }

            Text(entry.isCompleted ? "\(FormatterKit.weight(entry.weight)) × \(entry.reps)" : "未完成")
                .font(DS.Typography.footnote)
                .foregroundStyle(entry.isCompleted ? DS.Palette.textPrimary : DS.Palette.textTertiary)

            Spacer(minLength: 0)

            if entry.isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Palette.accent)
            }
        }
        .frame(minHeight: 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityText)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [displayName]
        parts.append("完成 \(completed.count) 组，共 \(entries.count) 组")
        if exerciseVolume > 0 {
            parts.append("该动作容量 \(FormatterKit.plainNumber(exerciseVolume)) 千克")
        }
        return parts.joined(separator: "，")
    }

    private func toggle() {
        withAnimation(DS.Motion.disclosure) {
            if isExpanded {
                expandedExerciseIDs.remove(exerciseID)
            } else {
                expandedExerciseIDs.insert(exerciseID)
            }
        }
        Haptics.light()
    }
}

// MARK: - 训练笔记

/// 「训练笔记」卡片。空备注时给出「未记录训练笔记」与编辑入口；
/// 编辑后立即回写本地 WorkoutSession。
struct SessionNoteCard: View {
    /// 当前备注。nil 或空白视为空。
    let note: String?
    /// 保存回调。传入去掉首尾空白的文本，空文本表示清空备注。
    let onSave: (String?) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var hasNote: Bool {
        !(note?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(
                title: "训练笔记",
                trailingText: hasNote && !isEditing ? "编辑" : nil,
                trailingAction: hasNote && !isEditing ? { beginEditing() } : nil
            )

            if isEditing {
                editor
            } else if hasNote, let note {
                Text(note)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                emptyState
            }
        }
        .padding(DS.Spacing.card)
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("未记录训练笔记")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textTertiary)

            Button("添加笔记", action: beginEditing)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.onAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(DS.Palette.accent))
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint("打开笔记输入框")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            TextEditor(text: $draft)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(DS.Spacing.item)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .focused($isFocused)
                .accessibilityLabel("训练笔记输入框")

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消") {
                    isFocused = false
                    isEditing = false
                }

                PrimaryButton(title: "保存") {
                    commit()
                }
            }
        }
    }

    private func beginEditing() {
        draft = note ?? ""
        isEditing = true
        Haptics.light()
        // 延后一帧再聚焦，避免键盘与视图切换动画互相打断
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isFocused = true
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
        isFocused = false
        isEditing = false
        Haptics.success()
    }
}
