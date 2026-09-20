//
//  HistorySessionDetailView.swift
//  页面 09：历史训练详情。
//
//  用途：查看一条**已完成**的本地训练记录，并做有限编辑。
//  只读部分是动作记录与全部组数据；可写部分只有标题、备注、复制成草稿、删除。
//
//  为什么组数据必须只读：
//  容量、总组数、动作数这些聚合值散落在首页「最近训练」、历史日历统计、
//  将来的训练数据汇总里。若允许在历史详情直接改某组重量或勾选状态，
//  所有聚合点都要重新推导，任何一处漏刷都会让两个页面显示不同数字。
//  规格明确禁止这件事，`HistoryEditPolicy` 把这条规则做成了可推演的显式契约。
//
//  重练的正路是「复制为新训练草稿」：把动作顺序、组数、最近实际重量次数
//  复制成一份未完成记录，再跳到训练执行页。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class HistorySessionDetailViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case missing
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var session: WorkoutSession?
    @Published private(set) var records: [HistoryExerciseRecord] = []
    @Published private(set) var summary: HistorySessionSummary?

    /// 操作结果的短提示。3 秒后自动清空。
    @Published var toast: String?

    private let repository: FitnessRepository
    let sessionID: UUID

    init(repository: FitnessRepository, sessionID: UUID) {
        self.repository = repository
        self.sessionID = sessionID
    }

    // MARK: 加载

    /// 首次加载。失败与「记录不存在」分开处理：前者可重试，后者只能返回。
    func load() async {
        loadState = .loading
        do {
            guard let loaded = try repository.fetchSession(id: sessionID) else {
                loadState = .missing
                return
            }
            apply(loaded)
            loadState = .loaded
        } catch {
            loadState = .failed("这条训练记录读取失败：\(error.localizedDescription)")
        }
    }

    /// 写入操作后重新读取。不回到 loading 态，避免整页闪骨架屏。
    func reload() async {
        guard let loaded = try? repository.fetchSession(id: sessionID) else {
            loadState = .missing
            return
        }
        // 记录已消失（比如在别处删掉了），保持 loaded 但让视图层走 missing 分支
        apply(loaded)
        loadState = .loaded
    }

    private func apply(_ loaded: WorkoutSession) {
        // 动作库用 includeHidden: true。
        //
        // 历史记录必须能显示被隐藏动作的**当前名称与肌群**；
        // 若按默认的 includeHidden: false 取，被隐藏的动作会被判成 `missing`，
        // 用户在历史页看到「该动作已不可用」，但事实上它只是被隐藏了。
        let library = (try? repository.fetchExercises(includeHidden: true)) ?? []

        session = loaded
        // 排序走 `HistoryRecordOrder.detailDefault`（动作顺序）而不是直接返回原数组：
        // 规格要求「按训练完成时的动作顺序」，把这条约定收在枚举里，
        // 视图层就不会有人顺手改成按容量排。
        records = HistoryRecordOrder.detailDefault.apply(
            to: HistorySessionDetailIndex.records(for: loaded, library: library)
        )
        summary = HistorySessionSummary.build(
            session: loaded,
            dateText: HistorySessionDetailIndex.dateText(loaded),
            startTimeText: HistorySessionDetailIndex.startTimeText(loaded)
        )
    }

    // MARK: 派生

    /// 训练类型色。与历史页日历标记点、列表行共用同一套映射。
    var kindColor: Color {
        guard let session else { return DS.Palette.accent }
        return session.kind == .cardio ? DS.Palette.cardio : DS.Palette.accent
    }

    var noteText: String? { session?.note }

    var sessionName: String { session?.name ?? "训练详情" }

    /// 「动作记录」区标题右侧的汇总文案
    var recordsTrailingText: String {
        let totals = HistorySessionDetailIndex.totals(for: records)
        return "\(totals.exerciseCount) 个动作 · \(totals.setCount) 组"
    }

    // MARK: 写操作

    /// 改标题。空白标题直接拒绝，不写库也不提示成功。
    func rename(to name: String) {
        guard var current = session else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed != current.name else {
            // 没改动就不写库，也不弹 toast——用户会以为发生了什么
            return
        }
        current.name = trimmed
        do {
            try repository.save(session: current)
            session = current
            summary = HistorySessionSummary.build(
                session: current,
                dateText: HistorySessionDetailIndex.dateText(current),
                startTimeText: HistorySessionDetailIndex.startTimeText(current)
            )
            toast = "标题已更新"
        } catch {
            toast = "保存标题失败：\(error.localizedDescription)"
        }
    }

    /// 改备注。空白即清除备注（与 `updateSessionNote` 的既定语义一致）。
    func saveNote(_ note: String?) {
        do {
            let updated = try repository.updateSessionNote(sessionID: sessionID, note: note)
            if let updated {
                session = updated
            } else {
                session?.note = note
            }
            let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            toast = (trimmed?.isEmpty ?? true) ? "备注已清除" : "备注已保存"
        } catch {
            toast = "保存备注失败：\(error.localizedDescription)"
        }
    }

    /// 复制为新训练草稿，返回新草稿 id 供调用方导航。
    ///
    /// 走 `HistorySessionDuplicator` 而不是复用页面 08 的自由训练复制：
    /// 后者的语义是「拿这条记录当模板再练一次」，会保留旧备注；
    /// 本页规格要求不复制备注，且要能报告复制了几组。
    func duplicateAsDraft() -> UUID? {
        guard let current = session else { return nil }
        let result = HistorySessionDuplicator.makeDraft(from: current)
        do {
            try repository.save(session: result.draft)
            toast = "已生成草稿：\(result.exerciseCount) 个动作 · \(result.setCount) 组"
            return result.draft.id
        } catch {
            toast = "复制失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// 删除这条记录。失败时返回 false，调用方据此决定要不要退出页面。
    func deleteSession() -> Bool {
        do {
            try repository.delete(sessionID: sessionID)
            return true
        } catch {
            toast = "删除失败：\(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - 页面

struct HistorySessionDetailView: View {

    @ObservedObject var viewModel: HistorySessionDetailViewModel
    /// 返回上一页（历史页）
    let onBack: () -> Void
    /// 复制成草稿后跳到训练执行页
    let onOpenDraft: (UUID) -> Void

    @State private var expandedExerciseIDs: Set<String> = []
    @State private var showMoreMenu = false
    @State private var editingTitle = false
    @State private var editingNote = false
    @State private var titleDraft = ""
    @State private var noteDraft = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()

            content
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        // 更多菜单
        .bottomDrawer(
            isPresented: $showMoreMenu,
            height: 372,
            title: "更多操作",
            subtitle: viewModel.sessionName
        ) {
            moreMenuContent
        }
        // 编辑标题
        .bottomDrawer(
            isPresented: $editingTitle,
            height: 250,
            title: "编辑训练标题",
            subtitle: "只修改这条本地记录的名称"
        ) {
            HistoryTextInputDrawer(
                title: "编辑训练标题",
                subtitle: "只修改这条本地记录的名称",
                placeholder: "训练名称",
                isMultiline: false,
                text: $titleDraft,
                onSave: {
                    viewModel.rename(to: titleDraft)
                    editingTitle = false
                },
                onCancel: { editingTitle = false }
            )
        }
        // 编辑备注
        .bottomDrawer(
            isPresented: $editingNote,
            height: 336,
            title: "编辑训练备注",
            subtitle: "记录这次训练的感受"
        ) {
            HistoryTextInputDrawer(
                title: "编辑训练备注",
                subtitle: "记录这次训练的感受",
                placeholder: "训练备注",
                isMultiline: true,
                text: $noteDraft,
                onSave: {
                    viewModel.saveNote(noteDraft)
                    editingNote = false
                },
                onCancel: { editingNote = false }
            )
        }
        // 删除二次确认
        .bottomDrawer(
            isPresented: $showDeleteConfirm,
            height: 364,
            title: "删除这条训练记录？",
            subtitle: "此操作不可撤销"
        ) {
            HistoryDeleteConfirmContent(
                sessionName: viewModel.sessionName,
                detailText: deleteDetailText,
                onCancel: { showDeleteConfirm = false },
                onConfirm: {
                    showDeleteConfirm = false
                    Haptics.warning()
                    if viewModel.deleteSession() {
                        // 删除成功后立刻返回。历史页会在重新出现时刷新，
                        // 日历标记与统计随之更新。
                        onBack()
                    }
                }
            )
        }
        .overlay(alignment: .bottom) { toastView }
    }

    // MARK: 顶部栏

    private var topBar: some View {
        HistoryDetailTopBar(
            title: "训练详情",
            onBack: onBack,
            onMore: { showMoreMenu = true }
        )
    }

    // MARK: 内容分发

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .loading:
            SessionSkeleton()

        case .missing:
            ScrollView {
                EmptyStateView(
                    message: "这条训练记录已经不在了，可能已被删除。",
                    actionTitle: "返回",
                    action: onBack
                )
                .padding(DS.Spacing.page)
            }

        case .failed(let message):
            ScrollView {
                EmptyStateView(message: message, actionTitle: "重试") {
                    Task { await viewModel.load() }
                }
                .padding(DS.Spacing.page)
            }

        case .loaded:
            loadedContent
        }
    }

    private var loadedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                if let summary = viewModel.summary {
                    HistoryDetailSummaryCard(
                        summary: summary,
                        kindColor: viewModel.kindColor
                    )
                }

                recordsSection

                HistoryNoteCard(note: viewModel.noteText)

                readonlyHint
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
    }

    // MARK: 动作记录

    @ViewBuilder
    private var recordsSection: some View {
        if viewModel.records.isEmpty {
            // 有氧训练没有组记录，给一句说明而不是空白区
            EmptyStateView(
                message: viewModel.session?.kind == .cardio
                    ? "这次有氧训练没有记录组数据，距离与时长见上方统计。"
                    : "这次训练没有记录任何动作。"
            )
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                SectionHeader(
                    title: "动作记录",
                    trailingText: viewModel.recordsTrailingText
                )

                ForEach(viewModel.records) { record in
                    HistoryExerciseRecordCard(
                        record: record,
                        expandedExerciseIDs: $expandedExerciseIDs
                    )
                }
            }
        }
    }

    /// 只读说明。把「为什么不能改」直接写在页面上，
    /// 比让用户疑惑「为什么没有编辑按钮」更好。
    private var readonlyHint: some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Palette.textTertiary)
                .accessibilityHidden(true)

            Text("已完成的训练记录不可直接修改组数据，以免统计数据失真。\(HistoryEditPolicy.redoHint)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.tight)
        .accessibilityElement(children: .combine)
    }

    // MARK: 更多菜单

    private var moreMenuContent: some View {
        VStack(spacing: 0) {
            DrawerActionRow(
                title: "编辑训练标题",
                subtitle: viewModel.sessionName,
                symbol: "textformat"
            ) {
                showMoreMenu = false
                titleDraft = viewModel.sessionName
                // 抽屉换抽屉：等前一个收完再弹后一个，否则遮罩会叠两层
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    editingTitle = true
                }
            }

            Divider().overlay(DS.Palette.stroke)

            DrawerActionRow(
                title: "编辑训练备注",
                subtitle: viewModel.noteText == nil ? "尚未记录笔记" : "已有笔记",
                symbol: "text.bubble"
            ) {
                showMoreMenu = false
                noteDraft = viewModel.noteText ?? ""
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    editingNote = true
                }
            }

            Divider().overlay(DS.Palette.stroke)

            DrawerActionRow(
                title: "复制为新训练草稿",
                subtitle: "保留动作与重量，不复制完成状态",
                symbol: "doc.on.doc"
            ) {
                showMoreMenu = false
                openDuplicate()
            }

            Divider().overlay(DS.Palette.stroke)

            DrawerActionRow(
                title: "删除本次记录",
                subtitle: "只删除本机这条记录，无法恢复",
                symbol: "trash",
                isDestructive: true
            ) {
                showMoreMenu = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    showDeleteConfirm = true
                }
            }
        }
    }

    private func openDuplicate() {
        guard let draftID = viewModel.duplicateAsDraft() else { return }
        Haptics.success()
        onOpenDraft(draftID)
    }

    // MARK: 删除详情

    private var deleteDetailText: String {
        guard let session = viewModel.session else { return "" }
        let sets = session.completedSetCount
        let duration = FormatterKit.duration(seconds: session.durationSeconds)
        return "\(session.kind.title)训练 · \(duration) · \(sets) 组"
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let text = viewModel.toast {
            HistoryToast(text: text) { viewModel.toast = nil }
                .task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    viewModel.toast = nil
                }
        }
    }
}

// MARK: - 预览

private struct HistorySessionDetailPreviewHost: View {
    private let repository = PreviewFitnessRepository()

    var body: some View {
        NavigationStack {
            HistorySessionDetailView(
                viewModel: HistorySessionDetailViewModel(
                    repository: repository,
                    sessionID: repository.previewFinishedSessionID
                ),
                onBack: {},
                onOpenDraft: { _ in }
            )
        }
    }
}

private struct HistorySessionDetailEmptyPreviewHost: View {
    var body: some View {
        NavigationStack {
            HistorySessionDetailView(
                viewModel: HistorySessionDetailViewModel(
                    repository: PreviewFitnessRepository.makeEmpty(),
                    sessionID: UUID()
                ),
                onBack: {},
                onOpenDraft: { _ in }
            )
        }
    }
}

#Preview("历史训练详情") {
    HistorySessionDetailPreviewHost()
        .preferredColorScheme(.dark)
}

#Preview("历史训练详情 · 记录不存在") {
    HistorySessionDetailEmptyPreviewHost()
        .preferredColorScheme(.dark)
}
