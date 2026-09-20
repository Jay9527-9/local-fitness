//
//  CardioSessionView.swift
//  页面 31：有氧训练执行页。
//
//  顶部固定栏（最小化 / 名称 / 结束）；中央超大计时；按目标显示圆环进度；
//  统计卡（距离 / 热量 / 平均配速，手动录入，无 GPS 自动猜测）；
//  「记录数据」底部面板；暂停/继续；「添加分段」与分段列表；「结束」确认抽屉。
//  计时与草稿实时落盘，退出后可按 startedAt / pausedAt / 累计数据恢复。
//

import SwiftUI
import Combine

@MainActor
final class CardioSessionViewModel: ObservableObject {

    @Published private(set) var session: WorkoutSession?
    @Published private(set) var now = Date()

    private let repository: FitnessRepository
    private let sessionID: UUID
    private var timer: AnyCancellable?

    init(repository: FitnessRepository, sessionID: UUID) {
        self.repository = repository
        self.sessionID = sessionID
    }

    var name: String { session?.name ?? "有氧训练" }
    var elapsedSeconds: Int { session?.durationSeconds ?? 0 }
    var isPaused: Bool { session?.isPaused ?? false }
    var distanceMeters: Double { session?.distanceMeters ?? 0 }
    var kilocalories: Double { session?.consumedKilocalories ?? 0 }
    var note: String { session?.note ?? "" }
    /// 用户手动录入的配速（秒/公里）。nil 表示未填。
    /// 注意与 `averagePaceSecondsPerKm` 区分：那个是「距离 ÷ 时长」算出来的平均配速。
    var paceSecondsPerKm: Double? { session?.paceSecondsPerKm }
    var segments: [WorkoutSegment] { session?.segments ?? [] }

    var goal: (kind: CardioGoalKind, value: Double)? {
        CardioGoalParser.parse(note: session?.note)
    }

    var ringProgress: Double? {
        guard let goal else { return nil }
        return CardioRingProgress.progress(
            goalKind: goal.kind,
            goalValue: goal.value,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            kilocalories: kilocalories
        )
    }

    /// 平均配速（秒/公里），由距离与时长推导；数据不足为 nil。
    var averagePaceSecondsPerKm: Double? {
        CardioPace.pace(fromDistanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds)
    }

    func start() {
        session = try? repository.fetchSession(id: sessionID)
        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.session?.isFinished == false, self.session?.isPaused == false else { return }
                self.now = Date()
            }
    }

    func stopTimer() { timer = nil }

    // MARK: 暂停 / 继续

    func togglePause() {
        guard var session else { return }
        if session.pausedAt != nil {
            // 继续：把暂停时长从起点抹去，等价于「从现在起继续计时」。
            if let pausedAt = session.pausedAt {
                let pauseDuration = Date().timeIntervalSince(pausedAt)
                session.startedAt = session.startedAt.addingTimeInterval(pauseDuration)
            }
            session.pausedAt = nil
        } else {
            session.pausedAt = Date()
        }
        persist(session)
    }

    // MARK: 记录数据

    func recordData(distanceMeters: Double?, kilocalories: Double?, paceSecondsPerKm: Double?, note: String?) {
        guard var session else { return }
        if let distanceMeters { session.distanceMeters = distanceMeters }
        if let kilocalories { session.consumedKilocalories = kilocalories }
        if let paceSecondsPerKm { session.paceSecondsPerKm = paceSecondsPerKm }
        if let note { session.note = note }
        persist(session)
    }

    // MARK: 分段

    func addSegment(_ segment: WorkoutSegment) {
        guard var session else { return }
        session.segments.append(segment)
        persist(session)
    }

    func updateSegment(_ segment: WorkoutSegment) {
        guard var session else { return }
        if let index = session.segments.firstIndex(where: { $0.id == segment.id }) {
            session.segments[index] = segment
        }
        persist(session)
    }

    func deleteSegment(_ segment: WorkoutSegment) {
        guard var session else { return }
        session.segments.removeAll { $0.id == segment.id }
        persist(session)
    }

    // MARK: 结束

    @discardableResult
    func finish() -> WorkoutSession? {
        guard var session else { return nil }
        session.pausedAt = nil
        if let updated = try? repository.updateSessionDraft(session) {
            let finished = try? repository.finishSession(sessionID: updated.id, endedAt: Date(), note: updated.note)
            stopTimer()
            self.session = finished
            return finished
        }
        return nil
    }

    private func persist(_ session: WorkoutSession) {
        if let updated = try? repository.updateSessionDraft(session) {
            self.session = updated
        }
    }
}

// MARK: - 页面

struct CardioSessionView: View {

    @StateObject private var viewModel: CardioSessionViewModel

    let onMinimize: () -> Void
    let onFinished: (WorkoutSession) -> Void

    @State private var showRecordData = false
    @State private var showSegmentSheet = false
    @State private var showFinishConfirm = false
    @State private var editingSegment: WorkoutSegment?

    init(
        repository: FitnessRepository,
        sessionID: UUID,
        onMinimize: @escaping () -> Void,
        onFinished: @escaping (WorkoutSession) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CardioSessionViewModel(repository: repository, sessionID: sessionID)
        )
        self.onMinimize = onMinimize
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.section) {
                timerBlock
                ringBlock
                statsCard
                segmentSection
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
        .task { viewModel.start() }
        .onDisappear { viewModel.stopTimer() }
        .bottomDrawer(isPresented: $showRecordData, height: 420, title: "记录数据") {
            recordDataContent
        }
        .bottomDrawer(isPresented: $showSegmentSheet, height: 460, title: "添加分段") {
            SegmentEntrySheet(
                initialDistance: nil,
                onSave: { segment in
                    viewModel.addSegment(segment)
                    showSegmentSheet = false
                }
            )
        }
        .sheet(item: $editingSegment) { segment in
            SegmentEntrySheet(
                segment: segment,
                initialDistance: segment.distanceMeters,
                onSave: { updated in
                    viewModel.updateSegment(updated)
                    editingSegment = nil
                }
            )
        }
        .bottomDrawer(isPresented: $showFinishConfirm, height: 420, title: "结束有氧训练") {
            finishConfirmContent
        }
    }

    // MARK: 顶部栏

    private var topBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onMinimize()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("最小化")

            Spacer(minLength: DS.Spacing.item)

            Text(viewModel.name)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                showFinishConfirm = true
            } label: {
                Text("结束")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("结束有氧训练")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    // MARK: 计时

    private var timerBlock: some View {
        VStack(spacing: DS.Spacing.tight) {
            if viewModel.isPaused {
                Text("已暂停")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(DS.Palette.accent.opacity(0.14)))
                    .accessibilityLabel("已暂停")
            }

            Text(FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Palette.textPrimary)
                .monospacedDigit()
                .accessibilityLabel("训练时长 \(FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds))")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.section)
    }

    // MARK: 圆环进度

    @ViewBuilder
    private var ringBlock: some View {
        if let goal = viewModel.goal {
            VStack(spacing: DS.Spacing.item) {
                ZStack {
                    Circle()
                        .stroke(DS.Palette.stroke, lineWidth: 10)
                    if let progress = viewModel.ringProgress {
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(DS.Palette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(DS.Motion.standard, value: progress)
                    }
                    VStack(spacing: 2) {
                        Text(progressLabel)
                            .font(DS.Typography.sectionTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                        Text(goalTitle(goal))
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                }
                .frame(width: 180, height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(goalTitle(goal)) 进度 \(progressLabel)")
            }
        }
    }

    private var progressLabel: String {
        guard let goal = viewModel.goal else { return "" }
        switch goal.kind {
        case .free: return FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds)
        case .duration: return FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds)
        case .distance: return FormatterKit.distance(meters: viewModel.distanceMeters)
        case .calories: return FormatterKit.kilocalories(viewModel.kilocalories)
        }
    }

    private func goalTitle(_ goal: (kind: CardioGoalKind, value: Double)) -> String {
        let formatted = goal.value == goal.value.rounded() ? "\(Int(goal.value))" : String(format: "%.1f", goal.value)
        return "目标 \(formatted)\(goal.kind.unitText)"
    }

    // MARK: 统计卡

    private var statsCard: some View {
        CardContainer {
            VStack(spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    statCell("距离", FormatterKit.distance(meters: viewModel.distanceMeters))
                    statCell("热量", FormatterKit.kilocalories(viewModel.kilocalories))
                    statCell("平均配速", CardioPace.paceText(secondsPerKm: viewModel.averagePaceSecondsPerKm) ?? "—")
                }

                Button {
                    showRecordData = true
                } label: {
                    HStack(spacing: DS.Spacing.tight) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13))
                        Text("记录数据")
                            .font(DS.Typography.callout.weight(.semibold))
                    }
                    .foregroundStyle(DS.Palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.accent.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("记录数据")
            }
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    // MARK: 分段

    private var segmentSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack {
                Text("分段记录")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button {
                    showSegmentSheet = true
                } label: {
                    Label("添加分段", systemImage: "plus")
                        .font(DS.Typography.caption.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加分段")
            }

            if viewModel.segments.isEmpty {
                Text("还没有分段记录")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, DS.Spacing.item)
            } else {
                ForEach(viewModel.segments) { segment in
                    segmentRow(segment)
                }
            }
        }
    }

    private func segmentRow(_ segment: WorkoutSegment) -> some View {
        HStack(spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatterKit.stopwatch(seconds: segment.durationSeconds))
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                if let note = segment.note, !note.isEmpty {
                    Text(note)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DS.Spacing.tight)

            if let distance = segment.distanceMeters, distance > 0 {
                Text(FormatterKit.distance(meters: distance))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            if let pace = segment.paceText {
                Text(pace)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .padding(DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        .contextMenu {
            Button {
                editingSegment = segment
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            Button(role: .destructive) {
                viewModel.deleteSegment(segment)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(segmentAccessibility(segment))
    }

    private func segmentAccessibility(_ segment: WorkoutSegment) -> String {
        var parts = [FormatterKit.stopwatch(seconds: segment.durationSeconds)]
        if let distance = segment.distanceMeters, distance > 0 {
            parts.append(FormatterKit.distance(meters: distance))
        }
        if let pace = segment.paceText { parts.append(pace) }
        if let note = segment.note, !note.isEmpty { parts.append(note) }
        return parts.joined(separator: "，")
    }

    // MARK: 底部控制

    private var bottomBar: some View {
        VStack(spacing: DS.Spacing.tight) {
            Divider().overlay(DS.Palette.stroke)

            HStack(spacing: DS.Spacing.item) {
                PrimaryButton(
                    title: viewModel.isPaused ? "继续" : "暂停",
                    icon: viewModel.isPaused ? "play.fill" : "pause.fill"
                ) {
                    Haptics.light()
                    viewModel.togglePause()
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.tight)
        }
        .background(DS.Palette.bg)
    }

    // MARK: 记录数据面板

    private var recordDataContent: some View {
        RecordDataContent(
            initialDistanceMeters: viewModel.distanceMeters,
            initialKilocalories: viewModel.kilocalories,
            initialPaceSecondsPerKm: viewModel.paceSecondsPerKm,
            initialNote: viewModel.note,
            onSave: { distance, kcal, pace, note in
                viewModel.recordData(
                    distanceMeters: distance,
                    kilocalories: kcal,
                    paceSecondsPerKm: pace,
                    note: note
                )
                showRecordData = false
            }
        )
    }

    // MARK: 结束确认

    private var finishConfirmContent: some View {
        VStack(spacing: DS.Spacing.item) {
            summaryLine("时长", FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds))
            summaryLine("距离", FormatterKit.distance(meters: viewModel.distanceMeters))
            summaryLine("热量", FormatterKit.kilocalories(viewModel.kilocalories))
            summaryLine("分段", "\(viewModel.segments.count) 段")
            if !viewModel.note.isEmpty {
                summaryLine("备注", viewModel.note)
            }

            PrimaryButton(title: "确认结束", icon: "checkmark") {
                if let finished = viewModel.finish() {
                    showFinishConfirm = false
                    onFinished(finished)
                }
            }
        }
        .padding(DS.Spacing.card)
    }

    private func summaryLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 记录数据面板内容

private struct RecordDataContent: View {

    let initialDistanceMeters: Double
    let initialKilocalories: Double
    let initialPaceSecondsPerKm: Double?
    let initialNote: String
    let onSave: (Double?, Double?, Double?, String?) -> Void

    @State private var distanceText: String
    @State private var kcalText: String
    @State private var paceText: String
    @State private var noteText: String

    init(
        initialDistanceMeters: Double,
        initialKilocalories: Double,
        initialPaceSecondsPerKm: Double?,
        initialNote: String,
        onSave: @escaping (Double?, Double?, Double?, String?) -> Void
    ) {
        self.initialDistanceMeters = initialDistanceMeters
        self.initialKilocalories = initialKilocalories
        self.initialPaceSecondsPerKm = initialPaceSecondsPerKm
        self.initialNote = initialNote
        self.onSave = onSave
        _distanceText = State(initialValue: initialDistanceMeters > 0 ? Self.num(initialDistanceMeters) : "")
        _kcalText = State(initialValue: initialKilocalories > 0 ? Self.num(initialKilocalories) : "")
        _paceText = State(initialValue: Self.paceText(initialPaceSecondsPerKm))
        _noteText = State(initialValue: initialNote)
    }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            field("累计距离（公里）", $distanceText, "km")
            field("热量（千卡）", $kcalText, "kcal")
            field("当前配速（秒/公里）", $paceText, "s/km")
            field("备注", $noteText, "")

            PrimaryButton(title: "保存") {
                // 面板填的是公里，模型存的是米。空串与「0」都要落成 nil，
                // 否则取消填写后旧值会被 0 覆盖。
                let km = Double(distanceText.trimmingCharacters(in: .whitespaces))
                onSave(
                    km.flatMap { $0 > 0 ? $0 * 1000 : nil },
                    Double(kcalText.trimmingCharacters(in: .whitespaces)),
                    Double(paceText.trimmingCharacters(in: .whitespaces)),
                    noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil : noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }
        .padding(DS.Spacing.card)
    }

    /// 秒/公里 → 输入框文本。缺值给空串，不显示 0。
    private static func paceText(_ seconds: Double?) -> String {
        guard let seconds, seconds > 0 else { return "" }
        return String(Int(seconds.rounded()))
    }

    private func field(_ title: String, _ text: Binding<String>, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            HStack(spacing: DS.Spacing.tight) {
                TextField("—", text: text)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .accessibilityLabel(title)
                if !unit.isEmpty {
                    Text(unit)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }

    private static func num(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}

// MARK: - 分段录入

private struct SegmentEntrySheet: View {

    let segment: WorkoutSegment?
    /// 新分段时由「训练累计距离」带进来的缺省值（米）。编辑时传 nil，以 `segment` 为准。
    let initialDistance: Double?
    let onSave: (WorkoutSegment) -> Void

    @State private var durationText: String
    @State private var distanceText: String
    @State private var paceText: String
    @State private var noteText: String

    init(
        segment: WorkoutSegment? = nil,
        initialDistance: Double? = nil,
        onSave: @escaping (WorkoutSegment) -> Void
    ) {
        self.segment = segment
        self.initialDistance = initialDistance
        self.onSave = onSave
        // 编辑已有分段时，以分段自身的值为准；新建时若没传就留空。
        let meters = segment?.distanceMeters ?? initialDistance
        _durationText = State(initialValue: segment.map { $0.durationSeconds > 0 ? "\($0.durationSeconds)" : "" } ?? "")
        _distanceText = State(initialValue: meters.map { $0 > 0 ? String(format: "%.2f", $0 / 1000) : "" } ?? "")
        _paceText = State(initialValue: segment?.paceSecondsPerKm.map { $0 > 0 ? "\(Int($0))" : "" } ?? "")
        _noteText = State(initialValue: segment?.note ?? "")
    }

    var body: some View {
        VStack(spacing: DS.Spacing.item) {
            TextField("时长（秒）", text: $durationText)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("分段时长")

            TextField("距离（公里）", text: $distanceText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("分段距离")

            TextField("配速（秒/公里）", text: $paceText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("分段配速")

            TextField("备注", text: $noteText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("分段备注")

            PrimaryButton(title: "保存分段") {
                let trimmed = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
                // 输入的是公里，模型存的是米。空串与「0」都落成 nil，
                // 避免把「没填」写成「0 米」而与「未记录」混淆。
                let km = Double(trimmed(distanceText))
                onSave(
                    WorkoutSegment(
                        id: segment?.id ?? UUID(),
                        durationSeconds: Int(trimmed(durationText)) ?? 0,
                        distanceMeters: km.flatMap { $0 > 0 ? $0 * 1000 : nil },
                        paceSecondsPerKm: Double(trimmed(paceText)),
                        note: trimmed(noteText).isEmpty ? nil : trimmed(noteText)
                    )
                )
            }
        }
        .padding(DS.Spacing.card)
    }
}

// MARK: - 预览

#Preview("有氧训练执行") {
    CardioSessionView(
        repository: PreviewFitnessRepository(),
        sessionID: UUID(),
        onMinimize: {},
        onFinished: { _ in }
    )
    .preferredColorScheme(.dark)
}
