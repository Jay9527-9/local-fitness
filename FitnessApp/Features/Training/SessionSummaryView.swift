//
//  SessionSummaryView.swift
//  页面 07：训练总结。
//  全屏展示完成图标、统计卡片、动作完成情况与训练笔记，底部给出返回与历史入口。
//

import SwiftUI

struct SessionSummaryView: View {
    let repository: FitnessRepository
    let sessionID: UUID
    /// 返回训练首页并刷新「最近训练」
    let onDone: () -> Void
    /// 跳转历史页并定位到本次训练详情
    let onOpenHistory: () -> Void

    @State private var session: WorkoutSession?
    @State private var exerciseNames: [String: String] = [:]
    /// 已展开的动作。默认全部收起，避免长训练列表一次铺满屏。
    @State private var expandedExerciseIDs: Set<String> = []

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()

            if let session {
                content(for: session)
            } else {
                EmptyStateView(
                    message: "找不到这次训练记录。",
                    actionTitle: "返回",
                    action: onDone
                )
                .padding(DS.Spacing.page)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if session != nil { bottomBar }
        }
        .navigationBarHidden(true)
        .task { load() }
    }

    // MARK: - 主体

    private func content(for session: WorkoutSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                header(for: session)

                metrics(for: session)

                if !session.entriesByExercise.isEmpty {
                    exerciseBreakdown(for: session)
                }

                SessionNoteCard(note: session.note) { newNote in
                    saveNote(newNote)
                }

                MediaAttributionLabel()
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.section)
            .padding(.bottom, DS.Spacing.item)
        }
    }

    // MARK: - 顶部

    private func header(for session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            // 页面标题。合并成一个可朗读语句，并用 .isHeader 让 VoiceOver 能按标题跳转。
            HStack(spacing: DS.Spacing.item) {
                Text("训练完成")
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.accent)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("训练完成")
            .accessibilityAddTraits(.isHeader)

            SummaryCheckGlyph()
                .padding(.top, DS.Spacing.tight)

            Text(session.name)
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(FormatterKit.fullDate(session.startedAt)) · \(FormatterKit.duration(seconds: session.durationSeconds))")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 统计卡片

    @ViewBuilder
    private func metrics(for session: WorkoutSession) -> some View {
        let cards = metricCards(for: session)

        HStack(alignment: .top, spacing: DS.Spacing.item) {
            ForEach(cards) { card in
                metricCard(card)
            }
        }
        // 卡片整体合并为一句可朗读的完整语句，避免 VoiceOver 逐个读出孤立数字。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryAccessibilityText(for: session))
    }

    private func metricCard(_ card: SummaryMetricCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            CountUpNumberText(
                value: card.value,
                format: card.format,
                isAccent: card.isAccent,
                literalText: card.literalText
            )

            if let unit = card.unit {
                Text(unit)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.item)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
        // 数值由上方容器统一朗读，卡片自身不再暴露给 VoiceOver。
        .accessibilityHidden(true)
    }

    /// 力量训练展示时长 / 总组数 / 总容量；有氧训练额外补充距离、平均配速与消耗估算。
    private func metricCards(for session: WorkoutSession) -> [SummaryMetricCard] {
        var cards: [SummaryMetricCard] = [
            SummaryMetricCard(
                id: "duration",
                title: "训练时长",
                value: Double(session.durationSeconds),
                unit: "秒",
                format: { FormatterKit.stopwatch(seconds: Int($0.rounded())) }
            ),
            SummaryMetricCard(
                id: "sets",
                title: "总组数",
                value: Double(session.completedSetCount),
                unit: "组"
            )
        ]

        if session.kind == .cardio {
            cards.append(SummaryMetricCard(
                id: "distance",
                title: "距离",
                value: session.distanceKilometers,
                unit: "公里",
                format: { String(format: "%.2f", $0) },
                isAccent: true
            ))
            // 平均配速不是连续可累加的量，用直接显示而非递增动画的数字呈现。
            cards.append(SummaryMetricCard(
                id: "pace",
                title: "平均配速",
                value: 0,
                unit: "/ 公里",
                literalText: FormatterKit.pace(
                    seconds: session.durationSeconds,
                    meters: session.distanceMeters
                ),
                isAccent: true
            ))
            cards.append(SummaryMetricCard(
                id: "kcal",
                title: "消耗估算",
                value: session.kilocalories,
                unit: "千卡"
            ))
        } else {
            cards.append(SummaryMetricCard(
                id: "volume",
                title: "总容量",
                value: session.totalVolume,
                unit: "kg",
                isAccent: true
            ))
        }

        return cards
    }

    /// 「训练时长 45 分 12 秒，总组数 18 组，总容量 4200 千克」
    private func summaryAccessibilityText(for session: WorkoutSession) -> String {
        var parts: [String] = []
        parts.append("训练时长 \(FormatterKit.duration(seconds: session.durationSeconds))")

        if session.kind == .cardio {
            parts.append("距离 \(FormatterKit.distance(meters: session.distanceMeters))")
            let pace = FormatterKit.pace(
                seconds: session.durationSeconds,
                meters: session.distanceMeters
            )
            parts.append(pace == "—" ? "平均配速暂无数据" : "平均配速每公里 \(pace)")
            parts.append("消耗估算 \(FormatterKit.kilocalories(session.kilocalories))")
        } else {
            parts.append("完成 \(session.completedSetCount) 组")
            parts.append("总容量 \(FormatterKit.plainNumber(session.totalVolume)) 千克")
        }

        return parts.joined(separator: "，")
    }

    // MARK: - 动作完成情况

    private func exerciseBreakdown(for session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            SectionHeader(
                title: "动作完成情况",
                trailingText: "\(session.completedExerciseCount)/\(session.entriesByExercise.count) 个动作"
            )

            ForEach(session.entriesByExercise, id: \.exerciseID) { group in
                ExerciseBreakdownRow(
                    exerciseID: group.exerciseID,
                    entries: group.entries,
                    displayName: exerciseNames[group.exerciseID] ?? group.exerciseID,
                    expandedExerciseIDs: $expandedExerciseIDs
                )
            }
        }
    }

    // MARK: - 底部操作

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Palette.stroke)
                .frame(height: 1)

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "查看历史记录") { onOpenHistory() }
                PrimaryButton(title: "返回训练首页", icon: "checkmark") { onDone() }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.tight)
        }
        .background(DS.Palette.bg)
    }

    // MARK: - 数据

    private func load() {
        // 读取失败时不编造数据，交给空状态处理。
        guard let loaded = try? repository.fetchSession(id: sessionID) else { return }
        session = loaded
        buildNameIndex()
    }

    private func buildNameIndex() {
        guard let session else { return }
        // 优先用动作库名称，缺失时回退到快照里记录的 id，保证不出现空白行。
        let all = (try? repository.fetchExercises()) ?? []
        var index: [String: String] = [:]
        for item in all { index[item.id] = item.name }
        for group in session.entriesByExercise where index[group.exerciseID] == nil {
            index[group.exerciseID] = group.exerciseID
        }
        exerciseNames = index
    }

    private func saveNote(_ newNote: String?) {
        guard let current = session else { return }
        try? repository.updateSessionNote(sessionID: current.id, note: newNote)
        // 立即刷新本地副本，避免为了一个备注字段重新走一次完整读取。
        session?.note = newNote
    }
}

// MARK: - 统计卡片模型

/// 单张统计卡片。`literalText` 非空时直接显示文本，不参与递增动画
/// （平均配速这类比值不适合从 0 递增）。
struct SummaryMetricCard: Identifiable {
    let id: String
    let title: String
    let value: Double
    var unit: String?
    var literalText: String?
    var format: (Double) -> String = { FormatterKit.plainNumber($0) }
    var isAccent: Bool = false
}

// MARK: - 预览

private struct SessionSummaryPreviewHost: View {
    private let repository = PreviewFitnessRepository()
    private let sessionID = UUID()

    var body: some View {
        NavigationStack {
            SessionSummaryView(
                repository: repository,
                sessionID: sessionID,
                onDone: {},
                onOpenHistory: {}
            )
        }
    }
}

#Preview("训练总结") {
    SessionSummaryPreviewHost()
}
