//
//  WorkoutSessionComponents.swift
//  训练执行页的组成部件：组表、动作卡、休息倒计时面板、完成摘要、说明抽屉、骨架屏。
//
//  拆成单独文件是为了让 WorkoutSessionView 只负责编排与抽屉路由，
//  组表这种细节多、改动频繁的部分独立出来更好维护。
//

import SwiftUI

// MARK: - 组表行

/// 组表里的一行：组号 / 重量 / 次数 / 完成状态。
///
/// 重量与次数是「可直接点击编辑的数值控件」：点一下进入行内编辑态，
/// 出现步进按钮与键盘输入；点完成圆圈或收起时提交。
struct SetRowView: View {

    let entry: SetEntry
    /// 组号，从 1 开始
    let displayIndex: Int
    /// 是否为最后一行，用于决定是否画分割线
    let isLast: Bool
    /// 当前正在编辑的单元格
    let editingCell: WorkoutSessionViewModel.SetEntryCell?
    /// 点击重量 / 次数进入编辑
    let onBeginEdit: (WorkoutSessionViewModel.SetEntryCell.Field) -> Void
    /// 提交新数值
    let onCommit: (Double, Int) -> Void
    /// 切换完成状态
    let onToggle: () -> Void
    /// 长按删除该组；不可删时传 nil
    let onRemove: (() -> Void)?

    /// 本地编辑缓冲。进入编辑态时从 entry 初始化，提交后清空。
    @State private var weightDraft: Double = 0
    @State private var repsDraft: Int = 0
    /// 键盘输入的原始文本。直接绑数值会因为「80.」这类中间态解析失败而跳字，
    /// 所以先攒文本，提交时再解析。
    @State private var weightText: String = ""
    @State private var repsText: String = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case weight
        case reps
    }

    private var weightEditing: Bool { editingCell?.field == .weight && editingCell?.entryID == entry.id }
    private var repsEditing: Bool { editingCell?.field == .reps && editingCell?.entryID == entry.id }
    private var isEditing: Bool { weightEditing || repsEditing }

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            indexLabel
            weightControl
            repsControl
            Spacer(minLength: 0)
            checkbox
        }
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(isEditing ? DS.Palette.surfaceElevated : Color.clear)
        )
        .animation(DS.Motion.standard, value: isEditing)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(DS.Palette.stroke)
                    .frame(height: 1)
                    .padding(.leading, DS.Size.setIndexColumn)
            }
        }
        .overlay(alignment: .leading) { warmupAccent }
        .contextMenu {
            if let onRemove {
                Button(role: .destructive, action: onRemove) {
                    Label("删除这一组", systemImage: "trash")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.accessibilityText)
    }

    /// 热身组左侧的强调条，视觉上与正式组区分
    @ViewBuilder
    private var warmupAccent: some View {
        if entry.isWarmup {
            RoundedRectangle(cornerRadius: 1)
                .fill(DS.Palette.textTertiary)
                .frame(width: 2)
                .padding(.vertical, 6)
                .accessibilityHidden(true)
        }
    }

    // MARK: 组号

    private var indexLabel: some View {
        VStack(spacing: 1) {
            Text("\(displayIndex)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(entry.isWarmup ? DS.Palette.textTertiary : DS.Palette.textPrimary)
        }
        .frame(width: DS.Size.setIndexColumn, alignment: .leading)
        .accessibilityHidden(true)
    }

    // MARK: 重量

    private var weightControl: some View {
        Group {
            if weightEditing {
                valueEditor(
                    text: $weightText,
                    keyboard: .decimalPad,
                    canDecrease: weightDraft > 0,
                    canIncrease: weightDraft < 500,
                    onDecrease: {
                        commit(weight: max(0, weightDraft - stepForWeight), reps: repsDraft)
                    },
                    onIncrease: {
                        commit(weight: min(500, weightDraft + stepForWeight), reps: repsDraft)
                    },
                    onCommitTyped: {
                        commit(weight: parsedWeight, reps: repsDraft)
                    },
                    field: .weight
                )
            } else {
                valueButton(
                    text: FormatterKit.weight(entry.displayWeight),
                    isMuted: !entry.isCompleted,
                    isCompleted: entry.isCompleted
                ) {
                    beginEdit(.weight, weight: entry.displayWeight, reps: entry.displayReps)
                }
                .accessibilityLabel("第 \(displayIndex) 组重量")
                .accessibilityValue(FormatterKit.weight(entry.displayWeight))
                .accessibilityHint("双击编辑重量")
            }
        }
        .frame(width: DS.Size.setValueField)
    }

    /// 把键盘输入的文本解析成重量。空串或非法输入回落到当前草稿值，
    /// 避免用户清空输入框时把重量意外写成 0。
    private var parsedWeight: Double {
        let trimmed = weightText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Double(trimmed) else { return weightDraft }
        return min(500, max(0, value))
    }

    /// 加减步长：有重量按 2.5 kg，自重按 5 kg 起步更顺手
    private var stepForWeight: Double {
        entry.weight >= 20 ? 2.5 : 5
    }

    // MARK: 次数

    private var repsControl: some View {
        Group {
            if repsEditing {
                valueEditor(
                    text: $repsText,
                    keyboard: .numberPad,
                    canDecrease: repsDraft > 0,
                    canIncrease: repsDraft < 100,
                    onDecrease: { commit(weight: weightDraft, reps: max(0, repsDraft - 1)) },
                    onIncrease: { commit(weight: weightDraft, reps: min(100, repsDraft + 1)) },
                    onCommitTyped: { commit(weight: weightDraft, reps: parsedReps) },
                    field: .reps
                )
            } else {
                valueButton(
                    text: "\(entry.displayReps)",
                    isMuted: !entry.isCompleted,
                    isCompleted: entry.isCompleted
                ) {
                    beginEdit(.reps, weight: entry.displayWeight, reps: entry.displayReps)
                }
                .accessibilityLabel("第 \(displayIndex) 组次数")
                .accessibilityValue("\(entry.displayReps) 次")
                .accessibilityHint("双击编辑次数")
            }
        }
        .frame(width: DS.Size.setValueField)
    }

    private var parsedReps: Int {
        let trimmed = repsText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let value = Int(trimmed) else { return repsDraft }
        return min(100, max(0, value))
    }

    /// 未进入编辑态的数值。灰描边，点击可编辑。
    private func valueButton(
        text: String,
        isMuted: Bool,
        isCompleted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    isCompleted ? DS.Palette.textPrimary : DS.Palette.textSecondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: DS.Size.minTapTarget)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(isMuted ? Color.clear : DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// 编辑态：减 / 输入框 / 加。数值可以直接用键盘输入，也可以用两侧步进微调。
    private func valueEditor(
        text: Binding<String>,
        keyboard: UIKeyboardType,
        canDecrease: Bool,
        canIncrease: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        onCommitTyped: @escaping () -> Void,
        field: Field
    ) -> some View {
        HStack(spacing: 0) {
            miniStep(symbol: "minus", isEnabled: canDecrease, action: onDecrease)

            TextField("", text: text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Palette.accent)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: DS.Size.minTapTarget)
                .focused($focusedField, equals: field)
                .submitLabel(.done)
                .onSubmit(onCommitTyped)
                // 失焦也提交，避免用户直接点别处时输入被丢掉
                .onChange(of: focusedField) { newValue in
                    if newValue != field { onCommitTyped() }
                }

            miniStep(symbol: "plus", isEnabled: canIncrease, action: onIncrease)
        }
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .stroke(DS.Palette.accent.opacity(0.55), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(field == .weight ? "重量输入" : "次数输入")
        .accessibilityValue(text.wrappedValue)
    }

    private func miniStep(symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isEnabled ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                .frame(width: 26, height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled)
        .accessibilityHidden(true)
    }

    // MARK: 完成勾选

    /// 圆形勾选按钮：灰色描边 → 荧光绿实心勾选
    private var checkbox: some View {
        Button {
            onToggle()
        } label: {
            ZStack {
                Circle()
                    .fill(entry.isCompleted ? DS.Palette.accent : Color.clear)
                    .frame(width: DS.Size.setCheckbox, height: DS.Size.setCheckbox)

                Circle()
                    .stroke(
                        entry.isCompleted ? Color.clear : DS.Palette.checkboxIdle,
                        lineWidth: 1.6
                    )
                    .frame(width: DS.Size.setCheckbox, height: DS.Size.setCheckbox)

                if entry.isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Palette.onAccent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .animation(DS.Motion.check, value: entry.isCompleted)
        .accessibilityLabel(entry.isCompleted ? "第 \(displayIndex) 组已完成" : "完成第 \(displayIndex) 组")
        .accessibilityAddTraits(entry.isCompleted ? [.isSelected] : [])
    }

    // MARK: 编辑生命周期

    private func beginEdit(
        _ field: WorkoutSessionViewModel.SetEntryCell.Field,
        weight: Double,
        reps: Int
    ) {
        weightDraft = weight
        repsDraft = reps
        weightText = weight <= 0 ? "" : trimmedNumber(weight)
        repsText = "\(reps)"
        onBeginEdit(field)
        // 焦点要在下一帧设置，否则视图还没重建，绑定的 TextField 不存在
        DispatchQueue.main.async {
            focusedField = (field == .weight) ? .weight : .reps
        }
    }

    private func commit(weight: Double, reps: Int) {
        weightDraft = weight
        repsDraft = reps
        weightText = weight <= 0 ? "" : trimmedNumber(weight)
        repsText = "\(reps)"
        onCommit(weight, reps)
    }

    /// 80.0 显示成 "80"，82.5 保留一位小数
    private func trimmedNumber(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - 顶部秒表

/// 顶部训练计时器。
///
/// 自己持有 1 秒的 Timer，只让这一小块重绘。如果把秒数放进 ViewModel 的
/// @Published 里，一次几百组的训练会在每一秒重建整屏动作卡。
/// 已训练时长始终按「当前时间 − 开始时间」计算，所以最小化、切后台、
/// 甚至 App 被终止后重开，时长都能自动对上，不需要补算。
struct SessionHeaderClock: View {

    let startedAt: Date?
    let isFinished: Bool

    @State private var now: Date = .now
    @State private var timer: Timer?

    private var elapsedSeconds: Int {
        guard let startedAt else { return 0 }
        return max(0, Int(now.timeIntervalSince(startedAt)))
    }

    private var text: String { FormatterKit.stopwatch(seconds: elapsedSeconds) }

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundStyle(DS.Palette.accent)
            .lineLimit(1)
            .accessibilityLabel("已训练 \(text)")
            .onAppear {
                now = .now
                guard !isFinished else { return }
                startTimer()
            }
            .onDisappear { stopTimer() }
            .onChange(of: isFinished) { finished in
                if finished { stopTimer() }
            }
            // 从后台回来时立刻校准一次，不等下一个 tick
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                now = .now
                if !isFinished && timer == nil { startTimer() }
            }
    }

    private func startTimer() {
        stopTimer()
        let created = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                now = .now
            }
        }
        RunLoop.main.add(created, forMode: .common)
        timer = created
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - 淡入数字

/// 数值变化时做一次 180ms 淡入的数字文本。
///
/// 不用 `.id(value) + .transition` 是因为 transition 需要祖先视图上有显式动画
/// 才会播放，在 `List` / `ScrollView` 里行为不稳定。这里改用 `.task(id:)`
/// 自己把透明度从 0 推到 1，只依赖自身状态，放在任何层级都一致。
struct FadingNumberText: View {

    let value: String
    var duration: Double = 0.18

    @State private var opacity: Double = 1

    var body: some View {
        Text(value)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .opacity(opacity)
            .task(id: value) {
                opacity = 0
                withAnimation(.easeOut(duration: duration)) {
                    opacity = 1
                }
            }
            .accessibilityLabel(value)
    }
}

// MARK: - 动作卡底部轻量按钮

/// 卡片底部的三个轻量按钮：图标 + 小字，等宽排布。
struct CardQuickAction: View {

    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(DS.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(DS.Palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: DS.Size.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - 动作卡

/// 一张动作卡：名称、目标肌群、上次记录摘要、组表、更多按钮、底部三个轻量按钮。
struct ExerciseCardView: View {

    let card: WorkoutSessionViewModel.ExerciseCard
    @ObservedObject var session: WorkoutSessionViewModel

    let onToggle: (SetEntry) -> Void
    let onEditCell: (SetEntry, WorkoutSessionViewModel.SetEntryCell.Field) -> Void
    let onCommitCell: (SetEntry, Double, Int) -> Void
    let onRemoveSet: (SetEntry) -> Void
    let canRemoveSet: Bool
    let onAddSet: () -> Void
    let onRest: () -> Void
    let onInfo: () -> Void
    let onMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(DS.Palette.stroke).padding(.top, DS.Spacing.item)
            tableHeader
            setList
            Divider().overlay(DS.Palette.stroke)
            quickActions
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
    }

    // MARK: 标题区

    private var header: some View {
        HStack(alignment: .top, spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                HStack(spacing: DS.Spacing.tight) {
                    Text(card.name)
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(2)

                    if card.isWarmup {
                        warmupBadge
                    }
                }

                HStack(spacing: DS.Spacing.tight) {
                    if !card.muscleText.isEmpty {
                        Text(card.muscleText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if !card.muscleText.isEmpty && !card.configText.isEmpty {
                        Text("·")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    if !card.configText.isEmpty {
                        Text(card.configText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
                    }
                }

                // 上一次训练同一动作的摘要
                if let lastTime = card.lastTimeSummary {
                    Text(lastTime)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.tight)

            moreButton
        }
    }

    /// 热身组标签：低对比灰色，与正式组的荧光绿形成区分
    private var warmupBadge: some View {
        Text("热身")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(DS.Palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(DS.Palette.warmupFill)
            )
            .overlay(
                Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .accessibilityLabel("热身组")
    }

    private var moreButton: some View {
        Button(action: onMore) {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: DS.Size.minTapTarget, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(card.name) 更多操作")
    }

    // MARK: 组表

    /// 组表列头。列宽与 SetRowView 对齐。
    private var tableHeader: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text("组")
                .frame(width: DS.Size.setIndexColumn, alignment: .leading)
            Text("重量")
                .frame(width: DS.Size.setValueField, alignment: .center)
            Text("次数")
                .frame(width: DS.Size.setValueField, alignment: .center)
            Spacer(minLength: 0)
            Text("完成")
                .frame(width: DS.Size.minTapTarget, alignment: .center)
        }
        .font(DS.Typography.caption2)
        .foregroundStyle(DS.Palette.textTertiary)
        .padding(.top, DS.Spacing.item)
        .padding(.bottom, 2)
        .accessibilityHidden(true)
    }

    private var setList: some View {
        // 页面 14 训练偏好「默认显示热身组」关闭时，热身组行从组表隐藏。
        // 只影响展示，热身组仍留在会话模型里，统计与历史照常计算。
        let visible = ProfileSettings.showWarmupSets
            ? card.entries
            : card.entries.filter { !$0.isWarmup }
        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { offset, entry in
                SetRowView(
                    entry: entry,
                    displayIndex: offset + 1,
                    isLast: offset == visible.count - 1,
                    editingCell: session.editingCell,
                    onBeginEdit: { field in onEditCell(entry, field) },
                    onCommit: { weight, reps in
                        onCommitCell(entry, weight, reps)
                        session.editingCell = nil
                    },
                    onToggle: { onToggle(entry) },
                    onRemove: canRemoveSet ? { onRemoveSet(entry) } : nil
                )
            }
        }
    }

    // MARK: 底部三个轻量按钮

    private var quickActions: some View {
        HStack(spacing: 0) {
            CardQuickAction(title: "新增一组", symbol: "plus") { onAddSet() }
            divider
            CardQuickAction(title: "休息计时", symbol: "timer") { onRest() }
            divider
            CardQuickAction(title: "动作说明", symbol: "info.circle") { onInfo() }
        }
        .padding(.top, DS.Spacing.tight)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Palette.stroke)
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
    }
}

// MARK: - 休息结束提示

/// 倒计时归零后压在页面顶部的提示条：「休息结束，开始下一组」。
///
/// 不复用 `ToastBanner`：toast 在底部、用于操作反馈；
/// 这条提示要出现在视线落点上方的顶部，且语义是「可以开始下一组了」。
struct RestFinishedBanner: View {

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Palette.accent)

            Text("休息结束，开始下一组")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, DS.Spacing.item)
        .background(
            Capsule().fill(DS.Palette.surfaceElevated)
        )
        .overlay(
            Capsule().stroke(DS.Palette.accent.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("休息结束，开始下一组")
    }
}

// MARK: - 完成确认抽屉

/// 完成训练前的确认。
///
/// 展示本次训练名称、总时长、完成动作数、完成组数与训练总容量；
/// 有氧训练改为展示距离与时长。三个操作中只有「完成训练」会写入记录，
/// 「取消」与「继续训练」都只是收起抽屉，不触碰训练草稿。
struct FinishSummaryContent: View {

    @ObservedObject var session: WorkoutSessionViewModel
    /// 取消：收起抽屉，不改动草稿
    let onCancel: () -> Void
    /// 继续训练：收起抽屉并回到训练页，不改动草稿
    let onResume: () -> Void
    /// 完成训练：写入 endedAt、最终备注与聚合数据
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                titleBlock

                metricGrid

                noteField
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.top, DS.Spacing.tight)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actions
        }
    }

    // MARK: - 训练名称

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.sessionName)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(session.isCardio ? "有氧训练" : "力量训练")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 聚合数据

    /// 有氧训练展示距离与时长，力量训练展示时长、完成动作数、完成组数与总容量。
    private var metricGrid: some View {
        VStack(spacing: DS.Spacing.tight) {
            if session.isCardio {
                HStack(spacing: DS.Spacing.tight) {
                    metric(title: "总时长", value: session.elapsedText)
                    metric(title: "距离", value: FormatterKit.distance(meters: session.distanceMeters ?? 0))
                }
                HStack(spacing: DS.Spacing.tight) {
                    metric(title: "消耗估算", value: FormatterKit.kilocalories(session.kilocalories))
                    // 有氧训练也记录动作条目时保留完成动作数，避免信息断层
                    metric(title: "完成动作", value: "\(session.completedExerciseCount) 个")
                }
            } else {
                HStack(spacing: DS.Spacing.tight) {
                    metric(title: "总时长", value: session.elapsedText)
                    metric(title: "完成动作", value: "\(session.completedExerciseCount) 个")
                }
                HStack(spacing: DS.Spacing.tight) {
                    metric(title: "完成组数", value: "\(session.completedSetCount) 组")
                    metric(title: "训练总容量",
                           value: "\(FormatterKit.plainNumber(session.totalVolume)) kg")
                }
            }
        }
        // 合并为完整语句，避免 VoiceOver 逐个朗读孤立数字。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(confirmationAccessibilityText)
    }

    private var confirmationAccessibilityText: String {
        var parts: [String] = [session.sessionName]
        parts.append("总时长 \(session.elapsedText)")
        if session.isCardio {
            parts.append("距离 \(FormatterKit.distance(meters: session.distanceMeters ?? 0))")
            parts.append("消耗估算 \(FormatterKit.kilocalories(session.kilocalories))")
            parts.append("完成 \(session.completedExerciseCount) 个动作")
        } else {
            parts.append("完成 \(session.completedExerciseCount) 个动作")
            parts.append("共 \(session.completedSetCount) 组")
            parts.append("训练总容量 \(FormatterKit.plainNumber(session.totalVolume)) 千克")
        }
        return parts.joined(separator: "，")
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.fieldFill)
        )
        .accessibilityHidden(true)
    }

    // MARK: - 备注

    private var noteField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text("训练备注")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            TextEditor(text: $session.finishNote)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 74)
                .padding(DS.Spacing.tight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .accessibilityLabel("训练备注")
                .accessibilityHint("仅「完成训练」会保存这段文字")
        }
    }

    // MARK: - 三个操作

    private var actions: some View {
        VStack(spacing: DS.Spacing.item) {
            PrimaryButton(title: "完成训练", icon: "checkmark") {
                onConfirm()
            }

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消") { onCancel() }
                SecondaryButton(title: "继续训练") { onResume() }
            }
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.top, DS.Spacing.item)
        .padding(.bottom, DS.Spacing.item)
        .background(DS.Palette.surfaceElevated)
    }
}

// MARK: - 备注编辑抽屉

/// 只改训练备注的小抽屉。
struct NoteEditorContent: View {

    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            TextEditor(text: $text)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(DS.Spacing.tight)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .padding(.horizontal, DS.Spacing.card)
                .accessibilityLabel("训练备注")

            PrimaryButton(title: "保存备注") { onSave() }
                .padding(.horizontal, DS.Spacing.card)

            SecondaryButton(title: "取消") { onCancel() }
                .padding(.horizontal, DS.Spacing.card)
                .padding(.bottom, DS.Spacing.item)
        }
    }
}

// MARK: - 动作说明只读抽屉

/// 训练中查看动作说明。只读，不可编辑任何内容。
struct ExerciseInfoDrawerContent: View {

    let card: WorkoutSessionViewModel.ExerciseCard

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                if let item = card.item {
                    if !item.instructionsZh.isEmpty {
                        Text(item.instructionsZh)
                            .font(DS.Typography.callout)
                            .foregroundStyle(DS.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !item.stepsZh.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                            ForEach(Array(item.stepsZh.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .top, spacing: DS.Spacing.tight) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(DS.Palette.onAccent)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(DS.Palette.accent))
                                    Text(step)
                                        .font(DS.Typography.footnote)
                                        .foregroundStyle(DS.Palette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    infoRow(title: "目标肌群", value: item.target)
                    if !item.secondaryMuscles.isEmpty {
                        infoRow(title: "协同肌群", value: item.secondaryMuscles.joined(separator: "、"))
                    }
                    infoRow(title: "器械", value: item.equipmentZh)

                    MediaAttributionLabel()
                } else {
                    Text("这个动作在动作库中已不存在，说明无法显示。")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.bottom, DS.Spacing.item)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(DS.Typography.footnote)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 提示条

/// 短提示，1.8 秒后自动消失。
struct ToastBanner: View {

    let text: String

    var body: some View {
        Text(text)
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Palette.textPrimary)
            .padding(.horizontal, DS.Spacing.item)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(DS.Palette.surfaceElevated)
            )
            .overlay(
                Capsule().stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 3)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - 骨架屏

/// 训练执行页骨架屏
struct SessionSkeleton: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SkeletonBlock(height: 96)
            ForEach(0..<2, id: \.self) { _ in
                SkeletonBlock(height: 268)
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.top, DS.Spacing.card)
        .accessibilityElement()
        .accessibilityLabel("正在载入训练")
    }
}

// MARK: - 预览

private struct WorkoutSessionPreviewHost: View {
    let sessionID: UUID
    let repository: PreviewFitnessRepository

    var body: some View {
        NavigationStack {
            WorkoutSessionView(
                repository: repository,
                sessionID: sessionID,
                onFinished: { _ in },
                onMinimize: {},
                onEditConfig: { _ in },
                onRequestReplace: { _ in }
            )
        }
    }
}

#Preview("训练执行") {
    WorkoutSessionPreviewHost(
        sessionID: PreviewFitnessRepository().previewActiveSessionID,
        repository: PreviewFitnessRepository()
    )
}
