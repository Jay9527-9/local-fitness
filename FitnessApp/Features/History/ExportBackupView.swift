//
//  ExportBackupView.swift
//  页面 19：导出本地备份。
//
//  从「本地数据管理 → 导出本地备份」进入。仅生成本地文件，不上传、不连网盘、不连账号。
//
//  结构：说明卡（用途 / 数据摘要 / 预计大小）→ 五段开关 → 种子 / 媒体说明 →
//  个人资料独立开关 → 底部「生成备份」。生成走四步进度（整理数据 / 校验结构 /
//  写入文件 / 完成），完成后展示名称 / 大小 / 创建时间 / 校验摘要，
//  提供「保存到文件」与「使用系统分享」。进行中的训练草稿导出前提示「包含 / 跳过」。
//
//  与页面 18 的 LocalDataBackup 分工：那个是导入 / 恢复快照格式，
//  这个是范围更广的完整导出格式（含训练偏好、自定义动作与收藏、appVersion 等）。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 进度步骤

/// 生成备份的四步进度。rawValue 即顺序。
enum ExportProgressStep: Int, CaseIterable, Identifiable {
    case gather
    case validate
    case write
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .gather: return "整理数据"
        case .validate: return "校验结构"
        case .write: return "写入文件"
        case .done: return "完成"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ExportBackupViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    enum Phase: Equatable {
        case idle
        case generating
        case done(ExportResult)
        case failed(String)
    }

    /// 生成完成后的结果，展示在结果卡并供「保存到文件 / 系统分享」使用。
    struct ExportResult: Equatable, Identifiable {
        let fileName: String
        let sizeText: String
        let createdAt: Date
        let summary: String
        let checksum: String
        let url: URL

        var id: String { url.absoluteString }
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var currentStep: ExportProgressStep = .gather

    // 本机数据的内存副本
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var exercises: [ExerciseLibraryItem] = []
    @Published private(set) var measurements: [BodyMeasurement] = []
    @Published private(set) var profile: UserProfile?

    /// 选中的导出段。默认全选。
    @Published var selectedSegments: Set<ExportBackupSegment> = Set(ExportBackupSegment.allCases)
    /// 是否包含个人资料（默认关闭，隐私优先）。
    @Published var includeProfile = false
    /// 是否包含未完成的训练草稿。由导出前的提示决定，默认跳过。
    @Published var includeDrafts = false

    private let repository: FitnessRepository
    /// 写入失败时要清理的临时文件。
    private var pendingTempURL: URL?

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    // MARK: 派生

    var finishedCount: Int { sessions.filter(\.isFinished).count }
    var draftCount: Int { sessions.filter { !$0.isFinished }.count }
    var planCount: Int { plans.count }
    var measurementCount: Int { measurements.count }
    var customExerciseCount: Int { exercises.filter(\.isCustom).count }
    var favoriteExerciseCount: Int { exercises.filter(\.isFavorite).count }

    /// 自定义动作与收藏的并集数量（按 id 去重）。
    var exportExerciseCount: Int {
        var seen = Set<String>()
        var count = 0
        for item in exercises where (item.isCustom || item.isFavorite) {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                count += 1
            }
        }
        return count
    }

    var hasDrafts: Bool { draftCount > 0 }
    /// 是否至少选了一类数据。
    var canGenerate: Bool { !selectedSegments.isEmpty }

    /// 各段的「数量说明」。
    func countText(for segment: ExportBackupSegment) -> String {
        switch segment {
        case .sessions:
            var text = "\(finishedCount) 条"
            if draftCount > 0 { text += " · 进行中 \(draftCount) 条" }
            return text
        case .plans:
            return "\(planCount) 个"
        case .exercises:
            return "自定义 \(customExerciseCount) · 收藏 \(favoriteExerciseCount)"
        case .measurements:
            return "\(measurementCount) 条"
        case .preferences:
            var text = "训练偏好 \(TrainingPreferencesSnapshot.itemCount) 项"
            if profile != nil { text += " · 个人资料" }
            return text
        }
    }

    /// 当前数据摘要，供说明卡。
    var dataSummaryText: String {
        var parts: [String] = []
        if finishedCount > 0 { parts.append("训练记录 \(finishedCount) 次") }
        if planCount > 0 { parts.append("计划 \(planCount) 个") }
        if exportExerciseCount > 0 { parts.append("动作 \(exportExerciseCount) 个") }
        if measurementCount > 0 { parts.append("身体数据 \(measurementCount) 条") }
        if profile != nil { parts.append("个人资料已设置") }
        return parts.isEmpty ? "本机暂无数据" : parts.joined(separator: "，")
    }

    /// 预计文件大小（随所选段动态变化）。
    var estimatedSizeText: String {
        let sessionCount = selectedSegments.contains(.sessions) ? finishedCount : 0
        let planCount = selectedSegments.contains(.plans) ? planCount : 0
        let exerciseCount = selectedSegments.contains(.exercises) ? exportExerciseCount : 0
        let measurementCount = selectedSegments.contains(.measurements) ? measurementCount : 0
        let includePreferences = selectedSegments.contains(.preferences)
        let bytes = ExportBackupSize.estimate(
            sessionCount: sessionCount,
            planCount: planCount,
            exerciseCount: exerciseCount,
            measurementCount: measurementCount,
            includePreferences: includePreferences,
            includeProfile: includeProfile && includePreferences
        )
        return StorageSize.format(bytes)
    }

    var result: ExportResult? {
        if case .done(let r) = phase { return r }
        return nil
    }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            sessions = try repository.fetchRecentSessions(limit: 500)
            plans = try repository.fetchPlans()
            exercises = try repository.fetchExercises(includeHidden: true)
            measurements = try repository.fetchBodyMeasurements(limit: 500)
            profile = try repository.fetchProfile()
            loadState = .loaded
        } catch {
            loadState = .failed("暂时无法读取本地数据，请稍后重试。")
        }
    }

    // MARK: 生成

    func generate() async {
        guard !selectedSegments.isEmpty else {
            phase = .failed(ExportBackupError.emptySelection.errorDescription ?? "请至少选择一类数据。")
            return
        }

        phase = .generating
        currentStep = .gather
        let appVersion = AppResources.appVersion

        do {
            // 1. 整理数据
            currentStep = .gather
            let preferences = selectedSegments.contains(.preferences)
                ? TrainingPreferencesSnapshot.capture()
                : nil
            let profile = (selectedSegments.contains(.preferences) && includeProfile)
                ? self.profile
                : nil
            try await pause()

            // 2. 校验结构：构造备份 + 算校验摘要 + 判定非空
            currentStep = .validate
            let backup = ExportBackupCoder.makeBackup(
                sessions: sessions,
                plans: plans,
                exercises: exercises,
                measurements: measurements,
                preferences: preferences,
                profile: profile,
                segments: selectedSegments,
                includeProfile: includeProfile,
                includeDrafts: includeDrafts,
                appVersion: appVersion
            )
            guard backup.hasContent else {
                throw ExportBackupError.nothingToExport
            }
            try await pause()

            // 3. 写入文件（原子写）
            currentStep = .write
            let data: Data
            do {
                data = try ExportBackupCoder.encode(backup)
            } catch {
                throw ExportBackupError.encodeFailed
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ExportBackupCoder.fileName())
            pendingTempURL = url
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                throw ExportBackupError.writeFailed
            }
            try await pause()

            // 4. 完成
            currentStep = .done
            let result = ExportResult(
                fileName: url.lastPathComponent,
                sizeText: StorageSize.format(Int64(data.count)),
                createdAt: backup.createdAt,
                summary: backup.countSummary,
                checksum: backup.checksum,
                url: url
            )
            phase = .done(result)
            Haptics.success()
        } catch {
            cleanupPendingTempFile()
            currentStep = .gather
            phase = .failed(readableMessage(for: error))
        }
    }

    /// 回到配置态，供「重新导出」与失败后的「重试」使用。
    func reset() {
        pendingTempURL = nil
        currentStep = .gather
        phase = .idle
    }

    private func pause() async throws {
        // 本地数据量小，实际耗时近乎瞬时；每一步都稍作停留让进度可见。
        try await Task.sleep(nanoseconds: 140_000_000)
    }

    private func cleanupPendingTempFile() {
        if let url = pendingTempURL {
            try? FileManager.default.removeItem(at: url)
            pendingTempURL = nil
        }
    }

    private func readableMessage(for error: Error) -> String {
        if let exportError = error as? ExportBackupError {
            return exportError.errorDescription ?? "导出失败。"
        }
        return "导出失败：\(error.localizedDescription)"
    }
}

// MARK: - 页面

struct ExportBackupView: View {

    @ObservedObject var viewModel: ExportBackupViewModel
    let onBack: () -> Void

    @State private var showDraftPrompt = false
    @State private var confirmProfile = false
    @State private var showExporter = false
    @State private var exportDocument: BackupDocument?
    @State private var sharedFile: ExportedFile?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    ExportBackupSkeleton()

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    content
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .confirmationDialog(
            "是否包含未完成训练草稿",
            isPresented: $showDraftPrompt,
            titleVisibility: .visible
        ) {
            Button("包含未完成草稿") {
                viewModel.includeDrafts = true
                Task { await viewModel.generate() }
            }
            Button("跳过未完成草稿") {
                viewModel.includeDrafts = false
                Task { await viewModel.generate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("本机有 \(viewModel.draftCount) 次进行中的训练草稿。无论是否包含，都不会改动当前训练状态。")
        }
        .alert("包含个人资料", isPresented: $confirmProfile) {
            Button("包含") { viewModel.includeProfile = true }
            Button("取消", role: .cancel) {}
        } message: {
            Text("备份将包含昵称、头像与个人说明。")
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: viewModel.result?.fileName ?? "本地数据备份.json"
        ) { result in
            handleSaveResult(result)
        }
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
        }
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .generating:
            progressCard
            configContent

        case .done(let result):
            resultCard(result)

        case .failed(let message):
            failureCard(message)

        case .idle:
            configContent
        }
    }

    private var configContent: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            introCard
            segmentCard
            noteCard
            profileCard
        }
    }

    // MARK: 说明卡

    private var introCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                        .foregroundStyle(DS.Palette.accent)
                    Text("导出本地备份")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                Text("生成一份版本化 JSON 备份，用于换机或重装前留底。文件只保存在本机，不会上传、不连网盘、不连账号。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(DS.Palette.stroke)

                infoRow(title: "当前数据", value: viewModel.dataSummaryText)
                infoRow(title: "预计大小", value: viewModel.estimatedSizeText)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("导出本地备份。当前数据 \(viewModel.dataSummaryText)，预计大小 \(viewModel.estimatedSizeText)。")
    }

    private func infoRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer(minLength: DS.Spacing.item)
            Text(value)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: 数据段开关

    private var segmentCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("导出内容")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(ExportBackupSegment.allCases.enumerated()), id: \.element.id) { index, segment in
                        segmentRow(segment)
                        if index < ExportBackupSegment.allCases.count - 1 {
                            Divider().overlay(DS.Palette.stroke)
                        }
                    }
                }
            }
        }
    }

    private func segmentRow(_ segment: ExportBackupSegment) -> some View {
        Toggle(isOn: binding(for: segment)) {
            HStack(spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(segment.title)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                Spacer(minLength: DS.Spacing.tight)
                Text(viewModel.countText(for: segment))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        }
        .toggleStyle(.switch)
        .tint(DS.Palette.accent)
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 13)
        .accessibilityValue(viewModel.selectedSegments.contains(segment) ? "已选中" : "未选中")
        .accessibilityHint("\(viewModel.countText(for: segment))")
    }

    private func binding(for segment: ExportBackupSegment) -> Binding<Bool> {
        Binding(
            get: { viewModel.selectedSegments.contains(segment) },
            set: { on in
                if on { viewModel.selectedSegments.insert(segment) }
                else { viewModel.selectedSegments.remove(segment) }
            }
        )
    }

    // MARK: 种子 / 媒体说明

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            noteRow(icon: "books.vertical", text: "内置动作库种子不随备份导出，避免文件过大。")
            noteRow(icon: "photo.on.rectangle", text: "媒体文件不导出，可在重新安装后重新导入。")
        }
    }

    private func noteRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Palette.textTertiary)
                .frame(width: 18, alignment: .center)
            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 个人资料独立开关

    private var profileCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Toggle(isOn: profileBinding) {
                    Text("是否包含个人资料")
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                }
                .toggleStyle(.switch)
                .tint(DS.Palette.accent)
                .accessibilityValue(viewModel.includeProfile ? "已选中" : "未选中")

                Text("默认关闭。开启后备份会包含昵称、头像与个人说明。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 开启个人资料时先弹提示，确认后才真正置真。
    private var profileBinding: Binding<Bool> {
        Binding(
            get: { viewModel.includeProfile },
            set: { on in
                if on {
                    confirmProfile = true
                } else {
                    viewModel.includeProfile = false
                }
            }
        )
    }

    // MARK: 进度

    private var progressCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("正在生成备份")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ExportProgressStep.allCases) { step in
                        stepRow(step)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在生成备份，当前步骤：\(viewModel.currentStep.title)")
    }

    private func stepRow(_ step: ExportProgressStep) -> some View {
        HStack(spacing: DS.Spacing.item) {
            if step.rawValue < viewModel.currentStep.rawValue {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
            } else if step.rawValue == viewModel.currentStep.rawValue {
                ProgressView()
                    .controlSize(.small)
                    .tint(DS.Palette.accent)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.checkboxIdle)
            }

            Text(step.title)
                .font(step.rawValue == viewModel.currentStep.rawValue
                      ? DS.Typography.body.weight(.semibold)
                      : DS.Typography.body)
                .foregroundStyle(
                    step.rawValue <= viewModel.currentStep.rawValue
                        ? DS.Palette.textPrimary
                        : DS.Palette.textTertiary
                )
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }

    // MARK: 结果

    private func resultCard(_ result: ExportBackupViewModel.ExportResult) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    HStack(spacing: DS.Spacing.tight) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Palette.accent)
                        Text("备份已生成")
                            .font(DS.Typography.cardTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }

                    resultRow(title: "备份名称", value: result.fileName)
                    resultRow(title: "文件大小", value: result.sizeText)
                    resultRow(title: "创建时间", value: FormatterKit.fullDate(result.createdAt))
                    resultRow(title: "包含内容", value: result.summary)

                    Divider().overlay(DS.Palette.stroke)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("校验摘要")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                        Text(result.checksum)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(DS.Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .textSelection(.enabled)
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("备份已生成。名称 \(result.fileName)，大小 \(result.sizeText)，创建时间 \(FormatterKit.fullDate(result.createdAt))，包含 \(result.summary)。")

            Button {
                Haptics.light()
                viewModel.reset()
            } label: {
                Text("调整选项，重新导出")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func resultRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
            Spacer(minLength: DS.Spacing.item)
            Text(value)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 失败

    private func failureCard(_ message: String) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text("导出失败")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                Text(message)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("原始数据未被改动，未完成的临时文件已清理。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 底部

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.phase {
        case .idle:
            PrimaryButton(
                title: "生成备份",
                icon: "square.and.arrow.up",
                isEnabled: viewModel.canGenerate
            ) {
                startGenerate()
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .done(let result):
            VStack(spacing: DS.Spacing.item) {
                PrimaryButton(title: "使用系统分享", icon: "square.and.arrow.up") {
                    Haptics.light()
                    // 分享的是用户主动选择的文件，交给系统面板，不生成公开链接或社交卡片。
                    sharedFile = ExportedFile(url: result.url)
                }
                SecondaryButton(title: "保存到文件", icon: "folder") {
                    Haptics.light()
                    prepareSaveToFiles(result)
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .failed:
            PrimaryButton(title: "重试", icon: "arrow.clockwise") {
                Haptics.light()
                viewModel.reset()
                startGenerate()
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .generating:
            EmptyView()
        }
    }

    // MARK: 动作

    private func startGenerate() {
        if viewModel.hasDrafts {
            showDraftPrompt = true
        } else {
            viewModel.includeDrafts = false
            Task { await viewModel.generate() }
        }
    }

    private func prepareSaveToFiles(_ result: ExportBackupViewModel.ExportResult) {
        guard let data = try? Data(contentsOf: result.url) else { return }
        exportDocument = BackupDocument(data: data)
        showExporter = true
    }

    private func handleSaveResult(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            Haptics.success()
        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError { return }
        }
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("导出本地备份")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }
}

// MARK: - 保存到文件的文档封装

/// `fileExporter` 需要一个 FileDocument。这里把已生成的 JSON 数据包一层。
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 骨架屏

struct ExportBackupSkeleton: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            SkeletonBlock(height: 180)
            SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 70)
            SkeletonBlock(height: 240)
            SkeletonBlock(height: 80)
            SkeletonBlock(height: 90)
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入导出备份")
    }
}

// MARK: - 预览

#Preview("导出备份 · 有数据") {
    ExportBackupView(
        viewModel: ExportBackupViewModel(
            repository: PreviewFitnessRepository.makeStrengthHistory()
        ),
        onBack: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("导出备份 · 空数据") {
    ExportBackupView(
        viewModel: ExportBackupViewModel(repository: PreviewFitnessRepository.makeEmpty()),
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
