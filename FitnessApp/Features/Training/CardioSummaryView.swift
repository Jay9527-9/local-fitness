//
//  CardioSummaryView.swift
//  页面 32：有氧训练完成总结。
//
//  完成勾选图标 + 「有氧训练完成」+ 日期与名称；统计卡（时长/距离/热量/平均配速）；
//  分段记录；可编辑训练笔记；「保存为模板」入口；返回训练首页 / 查看历史记录。
//  完成时原子持久化（endedAt），重复触发不产生重复历史记录。
//

import SwiftUI

@MainActor
final class CardioSummaryViewModel: ObservableObject {

    @Published private(set) var session: WorkoutSession?
    @Published var noteText: String = ""
    @Published var templateName: String = ""
    @Published var didSaveTemplate = false

    private let repository: FitnessRepository
    private let sessionID: UUID

    init(repository: FitnessRepository, sessionID: UUID) {
        self.repository = repository
        self.sessionID = sessionID
    }

    var name: String { session?.name ?? "有氧训练" }
    var finishedAt: Date { session?.endedAt ?? .now }
    var elapsedSeconds: Int { session?.durationSeconds ?? 0 }
    var distanceMeters: Double { session?.distanceMeters ?? 0 }
    var kilocalories: Double { session?.consumedKilocalories ?? 0 }
    var segments: [WorkoutSegment] { session?.segments ?? [] }

    var averagePaceSecondsPerKm: Double? {
        CardioPace.pace(fromDistanceMeters: distanceMeters, elapsedSeconds: elapsedSeconds)
    }

    func load() {
        guard let session = try? repository.fetchSession(id: sessionID) else { return }
        self.session = session
        self.noteText = session.note ?? ""
    }

    /// 保存备注，立即写回本地。
    func saveNote() {
        guard var session else { return }
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = trimmed.isEmpty ? nil : trimmed
        if let updated = try? repository.updateSessionDraft(session) {
            self.session = updated
        }
    }

    /// 由本次训练生成一个本地有氧模板（需模板名）。
    @discardableResult
    func saveAsTemplate() -> Bool {
        guard var session else { return false }
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        let goal = CardioGoalParser.parse(note: session.note)
        let template = CardioTemplate(
            name: name,
            sport: goal?.kind.rawValue ?? "free",
            goalKind: goal?.kind.rawValue ?? "free",
            goalValue: goal?.value,
            note: session.note
        )
        do {
            try repository.save(cardioTemplate: template)
            didSaveTemplate = true
            return true
        } catch {
            return false
        }
    }
}

struct CardioSummaryView: View {

    @StateObject private var viewModel: CardioSummaryViewModel
    let onDone: () -> Void
    let onOpenHistory: () -> Void

    @State private var showTemplatePrompt = false

    init(
        repository: FitnessRepository,
        sessionID: UUID,
        onDone: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: CardioSummaryViewModel(repository: repository, sessionID: sessionID)
        )
        self.onDone = onDone
        self.onOpenHistory = onOpenHistory
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: DS.Spacing.section) {
                header
                statsCard
                segmentCard
                noteCard
                templateCard
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.section)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
        .task { viewModel.load() }
        .alert("保存为模板", isPresented: $showTemplatePrompt) {
            TextField("模板名称", text: $viewModel.templateName)
            Button("取消", role: .cancel) { }
            Button("保存") { _ = viewModel.saveAsTemplate() }
        } message: {
            Text("输入模板名称后保存，供下次快速创建有氧训练。")
        }
        .alert("已保存为模板", isPresented: $viewModel.didSaveTemplate) {
            Button("好", role: .cancel) { viewModel.didSaveTemplate = false }
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: DS.Spacing.item) {
            ZStack {
                Circle()
                    .fill(DS.Palette.accent)
                    .frame(width: 76, height: 76)
                Image(systemName: "checkmark")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(DS.Palette.onAccent)
            }
            .accessibilityHidden(true)

            Text("有氧训练完成")
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("\(FormatterKit.shortDate(viewModel.finishedAt)) · \(viewModel.name)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 统计卡

    private var statsCard: some View {
        CardContainer {
            VStack(spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    statCell("时长", FormatterKit.stopwatch(seconds: viewModel.elapsedSeconds))
                    statCell("距离", FormatterKit.distance(meters: viewModel.distanceMeters))
                }
                HStack(spacing: DS.Spacing.tight) {
                    statCell("热量", FormatterKit.kilocalories(viewModel.kilocalories))
                    statCell("平均配速", CardioPace.paceText(secondsPerKm: viewModel.averagePaceSecondsPerKm) ?? "—")
                }
            }
        }
    }

    private func statCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
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
        .padding(.vertical, DS.Spacing.tight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    // MARK: 分段

    private var segmentCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("分段记录")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.segments.isEmpty {
                    Text("未记录分段")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, DS.Spacing.tight)
                } else {
                    ForEach(Array(viewModel.segments.enumerated()), id: \.element.id) { index, segment in
                        HStack(spacing: DS.Spacing.tight) {
                            Text("\(index + 1)")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            Text(FormatterKit.stopwatch(seconds: segment.durationSeconds))
                                .font(DS.Typography.callout)
                                .foregroundStyle(DS.Palette.textPrimary)
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
                        if let note = segment.note, !note.isEmpty {
                            Text(note)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }

    // MARK: 笔记

    private var noteCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("训练笔记")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                TextEditor(text: $viewModel.noteText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(minHeight: 72)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .stroke(DS.Palette.stroke, lineWidth: 1)
                    )
                    .accessibilityLabel("训练笔记")

                SecondaryButton(title: "保存笔记") {
                    Haptics.light()
                    viewModel.saveNote()
                }
            }
        }
    }

    // MARK: 保存为模板

    private var templateCard: some View {
        Button {
            showTemplatePrompt = true
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.accent)
                Text("保存为模板")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: DS.Spacing.tight)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
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
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("保存为模板")
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: DS.Spacing.item) {
            Divider().overlay(DS.Palette.stroke)
            PrimaryButton(title: "返回训练首页", icon: "house") {
                onDone()
            }
            SecondaryButton(title: "查看历史记录", icon: "clock") {
                onOpenHistory()
            }
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
        .background(DS.Palette.bg)
    }
}

// MARK: - 预览

#Preview("有氧训练总结") {
    CardioSummaryView(
        repository: PreviewFitnessRepository(),
        sessionID: UUID(),
        onDone: {},
        onOpenHistory: {}
    )
    .preferredColorScheme(.dark)
}
