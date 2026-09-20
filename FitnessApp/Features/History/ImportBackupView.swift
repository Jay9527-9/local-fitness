//
//  ImportBackupView.swift
//  页面 20：导入本地备份。
//
//  从「本地数据管理 → 导入本地备份」进入。只从用户通过系统文件选择器主动选取的
//  本地文件导入，不访问网络或云端账号。
//
//  流程：首屏说明 + 「选择备份文件」→ 预检（六步，只读）→ 备份摘要 +
//  导入方式 / 冲突处理 → 「开始导入」六阶段进度（先建保护备份）→
//  成功页（新增 / 更新 / 跳过 / 冲突解决）→ 返回数据管理 / 查看训练历史。
//  预检失败或写入失败均不落盘；中途失败回滚到保护备份。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 导入进度步骤

/// 导入的六阶段进度。rawValue 即顺序。
enum ImportProgressStep: Int, CaseIterable, Identifiable {
    case protect
    case sessions
    case plans
    case exercises
    case verify
    case done

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .protect: return "创建保护备份"
        case .sessions: return "导入训练"
        case .plans: return "导入计划"
        case .exercises: return "导入动作与设置"
        case .verify: return "验证结果"
        case .done: return "完成"
        }
    }
}

// MARK: - ViewModel

@MainActor
final class ImportBackupViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case prechecking
        case summary(ImportBackupSummary)
        case importing
        case success(ImportCounts)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var precheckStep: ImportPrecheck.Step = .format
    @Published private(set) var importStep: ImportProgressStep = .protect

    /// 导入策略（页面 21 冲突处理确认后回填）。默认合并保留本机。
    @Published var importStrategy: ImportStrategy = .mergeKeepLocal

    let repository: FitnessRepository
    /// 预检通过后暂存的备份。
    private(set) var backup: ExportBackup?
    /// 保护备份文件，导入失败时用于回滚。
    private var protectionURL: URL?

    // 本机数据（导入开始时读一次）
    private var localSessions: [WorkoutSession] = []
    private var localPlans: [Plan] = []
    private var localExercises: [ExerciseLibraryItem] = []
    private var localMeasurements: [BodyMeasurement] = []
    private var localProfile: UserProfile?

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    var summary: ImportBackupSummary? {
        if case .summary(let s) = phase { return s }
        return nil
    }

    var counts: ImportCounts? {
        if case .success(let c) = phase { return c }
        return nil
    }

    // MARK: 预检（只读）

    func inspect(data: Data) async {
        phase = .prechecking
        precheckStep = .format
        backup = nil

        do {
            // 1. 文件格式：能读到内容且是 JSON
            precheckStep = .format
            guard !data.isEmpty else { throw ExportBackupError.emptyFile }
            guard (try? JSONSerialization.jsonObject(with: data)) != nil else {
                throw ExportBackupError.notJSON
            }
            try await pause()

            // 2. 结构版本：格式标识 + schemaVersion
            precheckStep = .schema
            let backup = try ExportBackupCoder.decode(data)
            try await pause()

            // 3. 校验摘要
            precheckStep = .checksum
            try ImportPrecheck.checkChecksum(backup)
            try await pause()

            // 4. 数据字段
            precheckStep = .fields
            try ImportPrecheck.checkFields(backup)
            try await pause()

            // 5. 数据数量
            precheckStep = .counts
            try ImportPrecheck.checkCounts(backup)
            try await pause()

            // 6. 文件完整性
            precheckStep = .integrity
            try ImportPrecheck.checkIntegrity(backup)
            try await pause()

            self.backup = backup
            phase = .summary(backup.importSummary)
        } catch {
            phase = .failed(readableMessage(for: error))
        }
    }

    // MARK: 导入

    func importBackup() async {
        guard let backup = backup else { return }
        let mode = importStrategy.mode
        let policy = importStrategy.policy
        phase = .importing
        importStep = .protect

        do {
            // 1. 创建保护备份：当前数据全量快照（含草稿与整个动作库）
            importStep = .protect
            try await loadLocalData()
            let protection = makeProtectionSnapshot()
            protectionURL = try writeProtection(protection)
            try await pause()

            // 2. 导入训练
            importStep = .sessions
            let sessionMerge = ImportMerge.mergeSessions(
                existing: localSessions, incoming: backup.sessions,
                mode: mode, policy: policy
            )
            try repository.replaceAllSessions(sessionMerge.sessions)
            try await pause()

            // 3. 导入计划
            importStep = .plans
            let planMerge = ImportMerge.mergePlans(
                existing: localPlans, incoming: backup.plans,
                mode: mode, policy: policy
            )
            try repository.replaceAllPlans(planMerge.plans)
            try await pause()

            // 4. 导入动作与设置：动作库 + 身体数据 + 偏好 + 资料
            //    规格只列六步，未单列身体数据，故随「动作与设置」一并写入。
            importStep = .exercises
            let exerciseMerge = ImportMerge.mergeExercises(
                existing: localExercises, incoming: backup.exercises,
                mode: mode, policy: policy
            )
            try repository.replaceAllExercises(exerciseMerge.library)
            let measurementMerge = ImportMerge.mergeMeasurements(
                existing: localMeasurements, incoming: backup.measurements,
                mode: mode, policy: policy
            )
            try repository.replaceAllMeasurements(measurementMerge.measurements)
            if let prefs = backup.trainingPreferences { prefs.apply() }
            if let profile = backup.profile { try repository.save(profile: profile) }
            try await pause()

            // 5. 验证结果：重读四类集合确认写入成功
            importStep = .verify
            _ = try repository.fetchRecentSessions(limit: 1)
            _ = try repository.fetchPlans()
            _ = try repository.fetchExercises(includeHidden: true)
            _ = try repository.fetchBodyMeasurements(limit: 1)
            try await pause()

            // 6. 完成
            importStep = .done
            let counts = sessionMerge.counts + planMerge.counts
                + exerciseMerge.counts + measurementMerge.counts
            phase = .success(counts)
            cleanupProtection()
            Haptics.success()
        } catch {
            await rollback()
            cleanupProtection()
            importStep = .protect
            phase = .failed(readableMessage(for: error))
        }
    }

    // MARK: 重置

    func reset() {
        backup = nil
        protectionURL = nil
        precheckStep = .format
        importStep = .protect
        phase = .idle
    }

    /// 直接进入失败态（文件读取 / 选择器失败时用，不经预检六步）。
    func fail(_ message: String) {
        backup = nil
        protectionURL = nil
        phase = .failed(message)
    }

    // MARK: 私有

    private func loadLocalData() async throws {
        localSessions = try repository.fetchRecentSessions(limit: 2000)
        localPlans = try repository.fetchPlans()
        localExercises = try repository.fetchExercises(includeHidden: true)
        localMeasurements = try repository.fetchBodyMeasurements(limit: 2000)
        localProfile = try repository.fetchProfile()
    }

    /// 保护备份：**直接构造**，不走 `makeBackup`（那个会过滤草稿与动作库）。
    private func makeProtectionSnapshot() -> ExportBackup {
        ExportBackup(
            schemaVersion: ExportBackup.schemaVersion,
            format: ExportBackup.formatIdentifier,
            createdAt: .now,
            appVersion: AppResources.appVersion,
            appName: AppResources.appName,
            dataSegments: ExportBackupSegment.allCases.map(\.rawValue),
            includeProfile: true,
            includeDrafts: true,
            sessions: localSessions,
            plans: localPlans,
            exercises: localExercises,
            measurements: localMeasurements,
            trainingPreferences: TrainingPreferencesSnapshot.capture(),
            profile: localProfile,
            checksum: ""
        )
    }

    private func writeProtection(_ protection: ExportBackup) throws -> URL {
        let data = try ExportBackupCoder.encode(protection)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("导入保护备份-\(Date().timeIntervalSince1970).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 中途失败：把保护备份写回，恢复到导入前状态。
    private func rollback() async {
        guard let url = protectionURL,
              let data = try? Data(contentsOf: url),
              let protection = try? ExportBackupCoder.decode(data) else {
            return
        }
        try? repository.replaceAllSessions(protection.sessions)
        try? repository.replaceAllPlans(protection.plans)
        try? repository.replaceAllExercises(protection.exercises)
        try? repository.replaceAllMeasurements(protection.measurements)
        if let prefs = protection.trainingPreferences { prefs.apply() }
        if let profile = protection.profile { try? repository.save(profile: profile) }
    }

    private func cleanupProtection() {
        if let url = protectionURL {
            try? FileManager.default.removeItem(at: url)
            protectionURL = nil
        }
    }

    private func pause() async throws {
        try await Task.sleep(nanoseconds: 130_000_000)
    }

    private func readableMessage(for error: Error) -> String {
        if let e = error as? ExportBackupError {
            return e.errorDescription ?? "备份文件无法识别。"
        }
        if let e = error as? ImportBackupError {
            return e.errorDescription ?? "备份无法导入。"
        }
        return "导入失败：\(error.localizedDescription)"
    }
}

// MARK: - 页面

struct ImportBackupView: View {

    @ObservedObject var viewModel: ImportBackupViewModel
    let onDone: () -> Void
    let onViewHistory: () -> Void

    @State private var showFileImporter = false
    @State private var showConflictSheet = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                content
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
        .sheet(isPresented: $showConflictSheet) {
            if let backup = viewModel.backup {
                ImportConflictView(
                    backup: backup,
                    repository: viewModel.repository,
                    initialStrategy: viewModel.importStrategy,
                    onConfirm: { strategy in
                        viewModel.importStrategy = strategy
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            introCard

        case .prechecking:
            precheckCard

        case .summary(let summary):
            summaryCard(summary)

        case .importing:
            importingCard

        case .success(let counts):
            successCard(counts)

        case .failed(let message):
            failureCard(message)
        }
    }

    // MARK: 首屏

    private var introCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.body)
                        .foregroundStyle(DS.Palette.accent)
                    Text("导入本地备份")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                Text("支持本 App 导出的版本化 JSON 备份。只从你主动选取的本地文件导入，不会访问网络或云端账号。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 18, alignment: .center)
                    Text("不支持未知来源或损坏的文件。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 预检

    private var precheckCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.item) {
                    ProgressView().tint(DS.Palette.accent)
                    Text("正在校验备份")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                Text("预检只读取文件，不会改动现有数据。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ImportPrecheck.Step.allCases) { step in
                        stepRow(step)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在校验备份，当前步骤：\(viewModel.precheckStep.title)")
    }

    private func stepRow(_ step: ImportPrecheck.Step) -> some View {
        let idx = ImportPrecheck.Step.allCases.firstIndex(of: step) ?? 0
        let currentIdx = ImportPrecheck.Step.allCases.firstIndex(of: viewModel.precheckStep) ?? 0
        return HStack(spacing: DS.Spacing.item) {
            if idx < currentIdx {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
            } else if idx == currentIdx {
                ProgressView().controlSize(.small).tint(DS.Palette.accent)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.checkboxIdle)
            }
            Text(step.title)
                .font(idx == currentIdx ? DS.Typography.body.weight(.semibold) : DS.Typography.body)
                .foregroundStyle(idx <= currentIdx ? DS.Palette.textPrimary : DS.Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
    }

    // MARK: 摘要

    private func summaryCard(_ summary: ImportBackupSummary) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    HStack(spacing: DS.Spacing.tight) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(DS.Palette.accent)
                        Text("备份摘要")
                            .font(DS.Typography.cardTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }

                    summaryRow("创建日期", FormatterKit.fullDate(summary.createdAt))
                    summaryRow("App 数据版本", "v\(summary.appVersion)")
                    summaryRow("训练记录", "\(summary.sessionCount) 条")
                    summaryRow("计划", "\(summary.planCount) 个")
                    summaryRow("自定义动作", "\(summary.customExerciseCount) 个")
                    summaryRow("身体数据", "\(summary.measurementCount) 条")
                    summaryRow("包含个人资料", summary.includeProfile ? "是" : "否")
                    summaryRow("包含未完成草稿", summary.includeDrafts ? "是" : "否")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(backupSummaryLabel(summary))

            importModeCard
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
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

    private func backupSummaryLabel(_ s: ImportBackupSummary) -> String {
        "备份摘要。创建日期 \(FormatterKit.fullDate(s.createdAt))，App 数据版本 v\(s.appVersion)，训练记录 \(s.sessionCount) 条，计划 \(s.planCount) 个，自定义动作 \(s.customExerciseCount) 个，身体数据 \(s.measurementCount) 条，包含个人资料 \(s.includeProfile ? "是" : "否")，包含未完成草稿 \(s.includeDrafts ? "是" : "否")。"
    }

    private var importModeCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Button {
                    Haptics.light()
                    showConflictSheet = true
                } label: {
                    HStack(spacing: DS.Spacing.item) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("导入方式")
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.Palette.textPrimary)
                            Text(viewModel.importStrategy.title)
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Palette.accent)
                        }
                        Spacer(minLength: DS.Spacing.tight)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("导入方式，当前\(viewModel.importStrategy.title)")
                .accessibilityHint("点按进入冲突处理")

                Divider().overlay(DS.Palette.stroke)

                HStack(alignment: .top, spacing: DS.Spacing.tight) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 18, alignment: .center)
                    Text("导入前将自动创建当前本地数据临时备份。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: 导入中

    private var importingCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.item) {
                    ProgressView().tint(DS.Palette.accent)
                    Text("正在导入")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ImportProgressStep.allCases) { step in
                        importStepRow(step)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在导入，当前步骤：\(viewModel.importStep.title)")
    }

    private func importStepRow(_ step: ImportProgressStep) -> some View {
        HStack(spacing: DS.Spacing.item) {
            if step.rawValue < viewModel.importStep.rawValue {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Palette.accent)
            } else if step.rawValue == viewModel.importStep.rawValue {
                ProgressView().controlSize(.small).tint(DS.Palette.accent)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(DS.Palette.checkboxIdle)
            }
            Text(step.title)
                .font(step.rawValue == viewModel.importStep.rawValue
                      ? DS.Typography.body.weight(.semibold)
                      : DS.Typography.body)
                .foregroundStyle(step.rawValue <= viewModel.importStep.rawValue
                                ? DS.Palette.textPrimary : DS.Palette.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: 成功

    private func successCard(_ counts: ImportCounts) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    HStack(spacing: DS.Spacing.tight) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(DS.Palette.accent)
                        Text("导入完成")
                            .font(DS.Typography.cardTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                    }

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: DS.Spacing.item
                    ) {
                        metricCell("新增", "\(counts.added)")
                        metricCell("更新", "\(counts.updated)")
                        metricCell("跳过", "\(counts.skipped)")
                        metricCell("冲突解决", "\(counts.conflictsResolved)")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("导入完成。新增 \(counts.added)，更新 \(counts.updated)，跳过 \(counts.skipped)，冲突解决 \(counts.conflictsResolved)。")
        }
    }

    private func metricCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 失败

    private func failureCard(_ message: String) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text("无法导入")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                Text(message)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("当前数据未被删除或覆盖。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
            }
        }
    }

    // MARK: 底部

    @ViewBuilder
    private var bottomBar: some View {
        switch viewModel.phase {
        case .idle:
            PrimaryButton(title: "选择备份文件", icon: "folder") {
                Haptics.light()
                showFileImporter = true
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .summary:
            PrimaryButton(title: "开始导入", icon: "tray.and.arrow.down") {
                Haptics.light()
                Task { await viewModel.importBackup() }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .success:
            VStack(spacing: DS.Spacing.item) {
                PrimaryButton(title: "查看训练历史", icon: "clock.arrow.circlepath") {
                    Haptics.light()
                    onViewHistory()
                }
                SecondaryButton(title: "返回数据管理", icon: "chevron.left") {
                    Haptics.light()
                    onDone()
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .failed:
            PrimaryButton(title: "重新选择文件", icon: "folder") {
                Haptics.light()
                viewModel.reset()
                showFileImporter = true
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
            .background(DS.Palette.bg)

        case .prechecking, .importing:
            EmptyView()
        }
    }

    // MARK: 动作

    private func handleFilePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                viewModel.fail("无法读取所选文件，请确认它仍在本地。")
                return
            }
            Task { await viewModel.inspect(data: data) }

        case .failure(let error):
            let nsError = error as NSError
            if nsError.code == NSUserCancelledError { return }
            viewModel.fail("选择文件失败：\(error.localizedDescription)")
        }
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onDone()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DS.Palette.textPrimary)
                    .frame(width: DS.Size.minTapTarget, height: DS.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")

            Text("导入本地备份")
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

// MARK: - 导入冲突处理（页面 21）

@MainActor
final class ImportConflictViewModel: ObservableObject {

    @Published var strategy: ImportStrategy
    @Published private(set) var impact: ImportImpact = ImportImpact()
    @Published private(set) var isLoading = true

    private let backup: ExportBackup
    private let repository: FitnessRepository

    init(backup: ExportBackup, repository: FitnessRepository, initialStrategy: ImportStrategy) {
        self.backup = backup
        self.repository = repository
        self.strategy = initialStrategy
    }

    func load() async {
        do {
            let sessions = try repository.fetchRecentSessions(limit: 2000)
            let plans = try repository.fetchPlans()
            let exercises = try repository.fetchExercises(includeHidden: true)
            let measurements = try repository.fetchBodyMeasurements(limit: 2000)
            impact = ImportConflictAnalysis.impact(
                sessions: sessions, plans: plans, exercises: exercises,
                measurements: measurements, backup: backup
            )
        } catch {
            impact = ImportImpact()
        }
        isLoading = false
    }

    /// 某策略下的预计影响文案。
    func impactText(for strategy: ImportStrategy) -> String {
        impact.summaryText(mode: strategy.mode, policy: strategy.policy)
    }
}

struct ImportConflictView: View {

    @ObservedObject var viewModel: ImportConflictViewModel
    let onConfirm: (ImportStrategy) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replaceConfirmText = ""

    private var isReplace: Bool { viewModel.strategy == .replaceAll }
    private var canConfirm: Bool { !isReplace || replaceConfirmText == "覆盖" }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    introCard
                    ForEach(ImportStrategy.allCases) { strategyCard($0) }
                    if isReplace { replaceWarning }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
            }
            .background(DS.Palette.bg)
            .navigationTitle("导入方式")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(
                    title: "确认导入方式",
                    icon: "checkmark",
                    isEnabled: canConfirm
                ) {
                    Haptics.success()
                    onConfirm(viewModel.strategy)
                    dismiss()
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.vertical, DS.Spacing.item)
                .background(DS.Palette.bg)
            }
            .task { await viewModel.load() }
        }
        .presentationDetents([.large])
    }

    // MARK: 说明卡

    private var introCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("冲突定义")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("本机与备份中存在相同 ID 的条目即为冲突，例如同一训练记录、同一自然日的身体数据、同名的计划等。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 策略卡

    private func strategyCard(_ strategy: ImportStrategy) -> some View {
        let selected = viewModel.strategy == strategy
        return Button {
            Haptics.light()
            viewModel.strategy = strategy
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: DS.Spacing.item) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(strategy.title)
                            .font(DS.Typography.body.weight(.semibold))
                            .foregroundStyle(strategy.isDestructive ? DS.Palette.danger : DS.Palette.textPrimary)
                        Text(strategy.subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DS.Spacing.tight)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.checkboxIdle)
                }

                if !viewModel.isLoading {
                    Text(viewModel.impactText(for: strategy))
                        .font(DS.Typography.caption2)
                        .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DS.Spacing.card)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        selected
                            ? (strategy.isDestructive ? DS.Palette.danger.opacity(0.6) : DS.Palette.accent.opacity(0.6))
                            : DS.Palette.stroke,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(strategy.title)。\(strategy.subtitle)。\(viewModel.impactText(for: strategy))")
        .accessibilityHint(strategy.isDestructive ? "危险操作，将覆盖本机全部数据" : "")
    }

    // MARK: 覆盖风险提示

    private var replaceWarning: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text("此操作将删除当前所有本地个人数据，且不可撤销。")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                TextField("输入「覆盖」以确认", text: $replaceConfirmText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .tint(DS.Palette.accent)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .accessibilityLabel("输入覆盖以确认")
            }
        }
    }
}

// MARK: - 预览

#Preview("导入备份 · 首屏") {
    ImportBackupView(
        viewModel: ImportBackupViewModel(repository: PreviewFitnessRepository.makeStrengthHistory()),
        onDone: {},
        onViewHistory: {}
    )
    .preferredColorScheme(.dark)
}
