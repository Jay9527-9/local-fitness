//
//  HistorySessionDetailComponents.swift
//  页面 09 的子视图：导航栏、摘要卡、动作记录卡、单组行、笔记卡、输入抽屉、toast。
//
//  拆成独立文件的原因与页面 08 一致：HistorySessionDetailView 自己已经要承担
//  「加载 → 展示 → 四类写操作 → 二次确认」的编排，再把十几段布局塞进同一个
//  类型里会让 preflight 的括号平衡检查更难定位问题，也让本机（无编译器）
//  的人工复核成本成倍上升。
//

import SwiftUI

// MARK: - 导航栏

/// 历史训练详情顶部栏：左侧返回、中间标题、右侧更多。
///
/// 用 `safeAreaInset(edge: .top)` 固定，而不是系统导航栏：
/// 项目里所有页面都手工实现顶部栏（见 WorkoutSessionView.topBar），
/// 混用会导致返回手势与 `navigationBarHidden` 的状态互相打架。
struct HistoryDetailTopBar: View {

    let title: String
    let onBack: () -> Void
    let onMore: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            Button {
                Haptics.light()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("返回")

            Text(title)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            Button {
                Haptics.light()
                onMore()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("更多操作")
            .accessibilityHint("编辑标题、备注，复制为新训练或删除")
        }
        .padding(.horizontal, DS.Spacing.tight)
        .frame(height: DS.Size.sessionBarHeight)
        .background(DS.Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Palette.stroke)
                .frame(height: 1)
        }
    }
}

// MARK: - 摘要卡

/// 顶部摘要卡：训练名、日期与开始时间、类型、时长，外加统计格。
struct HistoryDetailSummaryCard: View {

    let summary: HistorySessionSummary
    /// 训练类型色。力量用荧光绿，有氧用蓝绿，与历史页的标记点同一套映射。
    let kindColor: Color

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {

                Text(summary.name)
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Spacing.tight) {
                    kindBadge

                    Text("\(summary.dateText) · \(summary.startTimeText)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: DS.Spacing.tight) {
                    MetaLabel(text: summary.durationText, icon: "clock")
                    if !summary.isFinished {
                        MetaLabel(text: "进行中", icon: "exclamationmark.circle")
                    }
                }

                Divider().overlay(DS.Palette.stroke)

                metricGrid
            }
        }
        // 整张卡合并成一句完整语句朗读，避免 VoiceOver 逐个念出孤立的数字格
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }

    private var kindBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: summary.kind.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(summary.kind.title)
                .font(DS.Typography.caption2)
        }
        .foregroundStyle(kindColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(kindColor.opacity(0.14))
        )
        .accessibilityHidden(true)
    }

    /// 统计格。两列布局，格数不是偶数时最后一格不拉伸以保持对齐。
    private var metricGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: DS.Spacing.item),
            GridItem(.flexible(), spacing: DS.Spacing.item)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Spacing.item) {
            ForEach(summary.metrics) { metric in
                metricCell(metric)
            }
        }
        .accessibilityHidden(true)
    }

    private func metricCell(_ metric: HistorySessionSummary.Metric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(metricText(metric))
                    .font(.system(size: DS.Size.detailMetricFont, weight: .bold))
                    .foregroundStyle(metric.isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unit = metric.unit {
                    Text(unit)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 历史详情**不做递增动画**。
    ///
    /// 页面 07 的总结页是「刚刚完成」，从 0 递增到目标值有成就感；
    /// 而这里打开的是一条早已结束的记录，数字再跑一遍既没有叙事意义，
    /// 又会让「快速核对历史数据」这件事变慢。所以统一直接显示终值。
    private func metricText(_ metric: HistorySessionSummary.Metric) -> String {
        if let literal = metric.literalText { return literal }
        return FormatterKit.plainNumber(metric.value)
    }
}

// MARK: - 动作记录卡

/// 一个动作在历史详情里的卡片：动作名、肌群标签、组数与容量，可展开看每一组。
struct HistoryExerciseRecordCard: View {

    let record: HistoryExerciseRecord
    @Binding var expandedExerciseIDs: Set<String>

    private var isExpanded: Bool { expandedExerciseIDs.contains(record.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {

            Button {
                toggle()
            } label: {
                header
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(record.accessibilityLabel)
            .accessibilityValue(isExpanded ? "已展开" : "已收起")
            .accessibilityHint(isExpanded ? "轻点两下收起每组记录" : "轻点两下展开每组记录")
            .accessibilityAddTraits(.isButton)

            // 降级提示：动作被隐藏或删除时，明确说明数据仍在
            if let notice = record.availability.noticeText, isExpanded {
                Label(notice, systemImage: "info.circle")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
            }

            if isExpanded {
                VStack(spacing: DS.Spacing.tight) {
                    ForEach(record.entries) { entry in
                        HistorySetRow(entry: entry)
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
                Text(record.displayName)
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: DS.Spacing.item) {
                    if !record.primaryMuscle.isEmpty {
                        MetaLabel(text: record.primaryMuscle, icon: "figure.strengthtraining.traditional")
                    }
                    MetaLabel(text: record.setCountText, icon: "checkmark.circle")
                }

                HStack(spacing: DS.Spacing.item) {
                    MetaLabel(text: record.volumeText, icon: "scalemass")
                    if !record.hasAnyCompleted {
                        MetaLabel(text: "无完成记录", icon: "minus.circle")
                    }
                }
            }

            Spacer(minLength: 0)

            // 已删除 / 已隐藏的动作在这里给一个持续可见的小标记，
            // 而不是只在展开时才提示——否则收起状态下用户会觉得名字很奇怪
            if record.availability != .available {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
                    .accessibilityHidden(true)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
                .rotationEffect(.degrees(isExpanded ? 0 : -90))
                .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func toggle() {
        withAnimation(DS.Motion.disclosure) {
            if isExpanded {
                expandedExerciseIDs.remove(record.id)
            } else {
                expandedExerciseIDs.insert(record.id)
            }
        }
        Haptics.light()
    }
}

// MARK: - 单组行

/// 历史详情里的一组：组号、热身标记、重量×次数、完成时间、达标状态。
///
/// 与页面 07 的 `ExerciseBreakdownRow.setRow` 分开实现，因为本页规格额外要求
/// 展示「完成时间」这一列，且历史数据存在 1970 兜底值的脏数据需要过滤，
/// 直接复用会把那段兜底逻辑耦合进总结页。
struct HistorySetRow: View {

    let entry: SetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: DS.Spacing.item) {
                Text("第 \(entry.index) 组")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(width: 52, alignment: .leading)

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

                Text(HistorySetDisplay.loadText(for: entry))
                    .font(DS.Typography.footnote)
                    .foregroundStyle(entry.isCompleted ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: DS.Spacing.tight)

                if let state = HistorySetDisplay.targetStateText(for: entry) {
                    Text(state)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .accessibilityHidden(true)
                }

                if entry.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Palette.accent)
                        .accessibilityHidden(true)
                }
            }

            // 完成时间独立一行，避免与右侧的状态标记争夺横向空间
            if let time = HistorySetDisplay.completionTimeText(for: entry) {
                Text("完成于 \(time)")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .padding(.leading, 52 + DS.Spacing.item)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: DS.Size.detailSetRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HistorySetDisplay.accessibilityLabel(for: entry))
    }
}

// MARK: - 训练笔记卡

/// 底部训练笔记。空笔记显示「未记录训练笔记」，与规格一致。
///
/// 与页面 07 的 `SessionNoteCard` 的差别：那版自带就地编辑，
/// 本页规格要求编辑入口在右上角「更多」菜单里，笔记区只做展示。
/// 因此这里是一个纯只读卡片，避免同一页出现两个编辑入口。
struct HistoryNoteCard: View {

    let note: String?

    private var trimmedNote: String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(title: "训练笔记")

            if let text = trimmedNote {
                Text(text)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            } else {
                Text("未记录训练笔记")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 标题 / 备注输入抽屉

/// 通用单字段输入抽屉。编辑标题与编辑备注共用一套布局，
/// 只是行数与键盘类型不同。
struct HistoryTextInputDrawer: View {

    let title: String
    let subtitle: String?
    let placeholder: String
    /// 多行模式（备注）vs 单行模式（标题）
    let isMultiline: Bool
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {

            if isMultiline {
                TextEditor(text: $text)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 110)
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
                    .accessibilityLabel("训练备注输入框")
            } else {
                TextField(placeholder, text: $text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.horizontal, DS.Spacing.item)
                    .frame(minHeight: DS.Size.setValueField)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit(onSave)
                    .accessibilityLabel(placeholder)
            }

            if isMultiline {
                // 备注允许清空（清空即删除备注），标题不允许
                Text("留空将清除这条备注。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
            }

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消", action: onCancel)
                PrimaryButton(title: "保存", isEnabled: canSave, action: onSave)
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.tight)
        .onAppear {
            // 延后一帧再聚焦，避免抽屉进场动画与键盘弹出互相打断
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                isFocused = true
            }
        }
        .accessibilityHint(subtitle ?? "")
    }

    /// 标题不能是空白；备注可以清空。
    private var canSave: Bool {
        guard !isMultiline else { return true }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - 删除确认

/// 删除确认抽屉的内容区。用 `BottomDrawer` 承载，
/// 与项目里其他二次确认保持同一种交互语言（而非系统 alert）。
///
/// 规格要求文案必须明确「只删除本机这条训练记录，无法恢复」。
struct HistoryDeleteConfirmContent: View {

    let sessionName: String
    let detailText: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {

            HStack(alignment: .top, spacing: DS.Spacing.item) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Text("「\(sessionName)」")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detailText)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Palette.danger.opacity(0.10))
            )

            // 规格原文要求的不可恢复声明，措辞保留「本机」二字，
            // 与本项目「不上传、不同步」的定位一致。
            Text("只删除本机这一条训练记录，无法恢复。日历标记与统计数据会同步刷新。")
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消", action: onCancel)

                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                        Text("删除记录")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.quickActionHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .fill(DS.Palette.danger.opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .stroke(DS.Palette.danger.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("确认删除这条训练记录")
                .accessibilityHint("删除后无法恢复")
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.tight)
    }
}

// MARK: - Toast

/// 操作完成后的短暂反馈。规格要求「操作完成使用简短 toast 反馈」。
///
/// 底部对齐、3 秒自动消失、可点击立刻收起。
/// 与页面 08 的 banner 同一视觉，但这里是独立组件，因为页面 08 的那条
/// 内联在视图里且带 `viewModel.banner` 依赖，抽出来会牵动已通过门禁的代码。
struct HistoryToast: View {

    let text: String
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)
                .accessibilityHidden(true)

            Text(text)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .fill(DS.Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.button, style: .continuous)
                .stroke(DS.Palette.stroke)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        .padding(.horizontal, DS.Spacing.page)
        .padding(.bottom, DS.Spacing.item)
        .transition(.opacity)
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
