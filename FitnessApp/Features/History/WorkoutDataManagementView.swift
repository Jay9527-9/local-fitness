//
//  WorkoutDataManagementView.swift
//  页面 18：本地数据管理。
//
//  从「我的 → 本地数据管理」进入。所有数据操作只针对本机 Application Support 目录，
//  不使用云端或账号同步。
//
//  结构：概览卡（6 项指标）→ 备份与恢复 → 数据维护 → 删除数据。
//  破坏性操作先写临时恢复快照、再原子落盘；二次确认里「清除全部本地数据」
//  要求输入「清除」才能确认。
//
//  与页面 10 的边界说明：这个页面从「只管理训练记录」扩展为「管理全部本地数据」，
//  但「删除全部训练记录」仍复用 `clearWorkoutRecords()`，范围不变（不动动作库与设置）。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 数据管理 ViewModel

@MainActor
final class WorkoutDataManagementViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var loadState: LoadState = .loading

    // 各数据集合的内存副本
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var restDays: [RestDay] = []
    @Published private(set) var plans: [Plan] = []
    @Published private(set) var measurements: [BodyMeasurement] = []
    @Published private(set) var customExerciseCount = 0
    @Published private(set) var storageSizeBytes: Int64 = 0

    /// 操作结果提示（成功 / 失败共用一条，样式靠 `toastIsError` 区分）
    @Published var toast: String?
    @Published var toastIsError = false

    /// 导入过程中选中的合并策略（训练记录部分）。默认「保留本机」。
    @Published var mergePolicy: WorkoutBackupMergePolicy = .keepExisting

    private let repository: FitnessRepository

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    // MARK: 派生

    var finishedCount: Int { sessions.filter { $0.isFinished }.count }
    var draftCount: Int { sessions.filter { !$0.isFinished }.count }
    var restDayCount: Int { restDays.count }
    var planCount: Int { plans.count }
    var measurementCount: Int { measurements.count }
    var exerciseLibraryVersion: String { AppResources.exerciseLibraryVersion }
    var storageSizeText: String { StorageSize.format(storageSizeBytes) }

    /// 页面 10 沿用：仅训练记录是否为空（旧导出按钮的启用条件）
    var isEmpty: Bool { finishedCount == 0 && restDayCount == 0 }
    /// 本机是否有任何数据（页面 18 概览与删除按钮用）
    var hasAnyData: Bool {
        finishedCount > 0 || planCount > 0 || measurementCount > 0 || customExerciseCount > 0
    }

    /// 页面 10 沿用：导出 / 清除的汇总文案
    var summaryText: String {
        var parts = ["已完成训练 \(finishedCount) 次"]
        if draftCount > 0 { parts.append("进行中 \(draftCount) 次") }
        parts.append("休息日标记 \(restDayCount) 天")
        return parts.joined(separator: "，")
    }

    var exportNote: String? {
        draftCount > 0
            ? "进行中的训练不导出：它属于当前操作状态。"
            : nil
    }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            try await fetchAll()
            loadState = .loaded
        } catch {
            loadState = .failed("暂时无法读取本地数据，请稍后重试。")
        }
    }

    /// 写入后刷新。不清空旧副本再重读，避免清除成功后列表闪一下旧数据。
    func reload() async {
        do {
            try await fetchAll()
            loadState = .loaded
        } catch {
            loadState = .failed("暂时无法读取本地数据，请稍后重试。")
        }
    }

    private func fetchAll() async throws {
        sessions = try repository.fetchRecentSessions(limit: 500)
        restDays = try repository.fetchRestDays()
        plans = try repository.fetchPlans()
        measurements = try repository.fetchBodyMeasurements(limit: 500)
        let all = try repository.fetchExercises(includeHidden: true)
        customExerciseCount = all.filter(\.isCustom).count
        storageSizeBytes = try repository.localDataSizeBytes()
    }

    // MARK: 导出（页面 10 沿用：仅训练记录）

    func exportBackup() -> URL? {
        do {
            let backup = WorkoutBackupCoder.makeBackup(sessions: sessions)
            let data = try WorkoutBackupCoder.encode(backup)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(WorkoutBackupCoder.fileName())
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                showToast("文件写入失败，请检查存储空间。", isError: true)
                return nil
            }
            showToast("已导出 \(backup.sessionCount) 次训练记录")
            Haptics.success()
            return url
        } catch {
            showToast("导出失败：\(error.localizedDescription)", isError: true)
            return nil
        }
    }

    // MARK: 导入（页面 10 沿用：仅训练记录）

    func importBackup(from url: URL) -> Int? {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            showToast("无法读取所选文件，请确认它仍在本地。", isError: true)
            return nil
        }

        let backup: WorkoutBackup
        do {
            backup = try WorkoutBackupCoder.decode(data)
        } catch let error as WorkoutBackupError {
            showToast(error.errorDescription ?? "备份文件无法识别。", isError: true)
            return nil
        } catch {
            showToast("备份解析失败：\(error.localizedDescription)", isError: true)
            return nil
        }

        let plan = WorkoutBackupMerger.merge(
            existing: sessions,
            incoming: backup.sessions,
            policy: mergePolicy
        )
        do {
            try repository.replaceAllSessions(plan.sessions)
        } catch {
            showToast("写入训练记录失败：\(error.localizedDescription)", isError: true)
            return nil
        }
        showToast(plan.summaryText)
        Haptics.success()
        return plan.addedCount + plan.replacedCount
    }

    // MARK: 数据维护

    /// 重建统计缓存。本 App 统计为即时计算（无持久化缓存），
    /// 这里重新读一遍训练记录，保证下次进入统计页拿到最新数据。
    func rebuildStats() {
        do {
            let fresh = try repository.fetchRecentSessions(limit: 500)
            sessions = fresh
            let count = fresh.filter { $0.isFinished }.count
            showToast("已重建统计缓存：重新读取 \(count) 次训练记录。")
            Haptics.success()
        } catch {
            showToast("重建失败：\(error.localizedDescription)", isError: true)
        }
    }

    /// 重新导入动作库种子。保留自定义动作与收藏 / 隐藏状态。
    func reseedLibrary() {
        do {
            let added = try repository.reseedExerciseLibrary()
            showToast(added > 0 ? "已重新导入动作库种子，新增 \(added) 个动作。" : "动作库种子已是最新，无需新增。")
            Haptics.success()
        } catch {
            showToast("重新导入失败：\(error.localizedDescription)", isError: true)
        }
        Task { await reload() }
    }

    /// 清理未使用的本地媒体缓存（孤儿头像文件）。
    func clearMediaCache() {
        do {
            let removed = try repository.clearUnusedMediaCache()
            showToast(removed > 0 ? "已清理 \(removed) 个未使用的本地媒体文件。" : "没有需要清理的本地媒体缓存。")
            Haptics.success()
        } catch {
            showToast("清理失败：\(error.localizedDescription)", isError: true)
        }
    }

    // MARK: 删除数据

    /// 破坏性操作前的临时恢复快照。写入临时目录，失败时供用户手动找回。
    private var recoverySnapshotURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("本地数据恢复快照.json")
    }

    @discardableResult
    private func writeRecoverySnapshot() throws -> URL {
        let profile = try? repository.fetchProfile()
        // 快照要含进行中的草稿，直接构造而不是走 makeBackup（makeBackup 会过滤草稿）。
        let backup = LocalDataBackup(
            format: LocalDataBackup.formatIdentifier,
            version: LocalDataBackup.currentVersion,
            exportedAt: .now,
            sessions: sessions,
            plans: plans,
            measurements: measurements,
            profile: profile
        )
        let data = try LocalDataBackupCoder.encode(backup)
        try data.write(to: recoverySnapshotURL, options: .atomic)
        return recoverySnapshotURL
    }

    /// 删除全部训练记录。范围与页面 10 一致：不动动作库、计划、身体数据与设置。
    /// 注意：页面 45 起，这条操作迁移到独立确认页 `ClearWorkoutRecordsView`，
    /// 由 `ClearDataViewModel.execute()` 直接调 `repository.clearWorkoutRecords()`。
    func clearAllRecords() {
        do {
            _ = try writeRecoverySnapshot()
            let count = finishedCount
            try repository.clearWorkoutRecords()
            showToast("已删除全部训练记录（\(count) 次）。恢复快照：\(recoverySnapshotURL.lastPathComponent)")
            Haptics.warning()
        } catch {
            showToast("删除失败，原数据已保留。", isError: true)
        }
        Task { await reload() }
    }

    /// 删除全部个人计划。历史训练记录不受影响。
    func deleteAllPlans() {
        do {
            _ = try writeRecoverySnapshot()
            let count = planCount
            try repository.deleteAllPlans()
            showToast("已删除全部个人计划（\(count) 个）。恢复快照：\(recoverySnapshotURL.lastPathComponent)")
            Haptics.warning()
        } catch {
            showToast("删除失败，原数据已保留。", isError: true)
        }
        Task { await reload() }
    }

    /// 删除全部身体数据。
    func deleteAllMeasurements() {
        do {
            _ = try writeRecoverySnapshot()
            let count = measurementCount
            try repository.deleteAllMeasurements()
            showToast("已删除全部身体数据（\(count) 条）。恢复快照：\(recoverySnapshotURL.lastPathComponent)")
            Haptics.warning()
        } catch {
            showToast("删除失败，原数据已保留。", isError: true)
        }
        Task { await reload() }
    }

    /// 清除全部本地数据（含偏好）。内置动作种子会在下次进入动作库时自动重新导入。
    func clearAllData() {
        do {
            _ = try writeRecoverySnapshot()
            try repository.deleteAllData()
            ProfileSettings.resetAll()
            showToast("已清除全部本地数据。恢复快照：\(recoverySnapshotURL.lastPathComponent)")
            Haptics.warning()
        } catch {
            showToast("清除失败，原数据已保留。", isError: true)
        }
        Task { await reload() }
    }

    // MARK: 提示

    private func showToast(_ text: String, isError: Bool = false) {
        toast = text
        toastIsError = isError
    }

    func clearToast() {
        toast = nil
        toastIsError = false
    }
}

// MARK: - 破坏性操作

enum DestructiveAction: Identifiable {
    case deletePlans
    case deleteMeasurements

    var id: String { title }

    var title: String {
        switch self {
        case .deletePlans: return "删除全部个人计划"
        case .deleteMeasurements: return "删除全部身体数据"
        }
    }

    var message: String {
        switch self {
        case .deletePlans:
            return "将删除本机全部个人计划。历史训练记录不受影响。"
        case .deleteMeasurements:
            return "将删除本机全部身体数据（体重、体脂率与围度记录）。"
        }
    }

    /// 是否需要输入「清除」才能确认。页面 45/46 的两种清除已迁到独立页，这里不再需要。
    var needsTypeConfirm: Bool { false }
}

// MARK: - 数据管理页

struct WorkoutDataManagementView: View {

    @ObservedObject var viewModel: WorkoutDataManagementViewModel
    let onBack: () -> Void
    /// 数据变化后通知上层（统计页要重算，历史页要重读）
    let onDataChanged: () -> Void
    /// 进入「导出本地备份」（页面 19）。由上层推入独立页面。
    let onOpenExportBackup: () -> Void
    /// 进入「导入本地备份」（页面 20）。由上层推入独立页面。
    let onOpenImportBackup: () -> Void
    /// 进入「清除训练记录」确认页（页面 45）。
    let onOpenClearRecords: () -> Void
    /// 进入「清除全部本地数据」确认页（页面 46）。
    let onOpenClearAll: () -> Void

    @State private var pendingAction: DestructiveAction?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    DataManagementSkeleton()

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.load() } }
                    )

                case .loaded:
                    summaryCard
                    backupGroup
                    maintenanceGroup
                    deleteGroup
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) { toastBar }
        .task { await viewModel.load() }
        .sheet(item: $pendingAction) { action in
            DestructiveConfirmSheet(action: action) {
                performDestructive(action)
            }
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

            Text("本地数据管理")
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

    // MARK: 概览卡

    private var summaryCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "externaldrive")
                        .font(.body)
                        .foregroundStyle(DS.Palette.accent)
                    Text("本机数据概览")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                }

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: DS.Spacing.item
                ) {
                    metricCell("训练记录", "\(viewModel.finishedCount) 次")
                    metricCell("训练计划", "\(viewModel.planCount) 个")
                    metricCell("自定义动作", "\(viewModel.customExerciseCount) 个")
                    metricCell("身体数据", "\(viewModel.measurementCount) 条")
                    metricCell("动作库版本", viewModel.exerciseLibraryVersion)
                    metricCell("存储占用", viewModel.storageSizeText)
                }

                Divider().overlay(DS.Palette.stroke)

                Text("全部数据只存在这台设备上，不上传、不同步。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本机数据概览。训练记录 \(viewModel.finishedCount) 次，训练计划 \(viewModel.planCount) 个，自定义动作 \(viewModel.customExerciseCount) 个，身体数据 \(viewModel.measurementCount) 条，动作库版本 \(viewModel.exerciseLibraryVersion)，存储占用 \(viewModel.storageSizeText)。")
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
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 备份与恢复

    private var backupGroup: some View {
        group(title: "备份与恢复") {
            DataActionRow(
                symbol: "square.and.arrow.up",
                title: "导出本地备份",
                subtitle: "选择要导出的数据范围，生成 JSON 备份文件"
            ) {
                onOpenExportBackup()
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "tray.and.arrow.down",
                title: "导入本地备份",
                subtitle: "选择备份文件，导入前先校验并预览内容"
            ) {
                onOpenImportBackup()
            }
        }
    }

    // MARK: 数据维护

    private var maintenanceGroup: some View {
        group(title: "数据维护") {
            DataActionRow(
                symbol: "arrow.clockwise",
                title: "重建统计缓存",
                subtitle: "重新读取训练记录并重算统计，不影响训练、计划与身体数据"
            ) {
                viewModel.rebuildStats()
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "square.and.arrow.down.on.square",
                title: "重新导入动作库种子",
                subtitle: "补齐缺失的内置动作，保留自定义动作与收藏、隐藏状态"
            ) {
                viewModel.reseedLibrary()
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "trash.slash",
                title: "清理未使用的本地媒体缓存",
                subtitle: "删除不再被引用的本地媒体文件（如孤儿头像）"
            ) {
                viewModel.clearMediaCache()
            }
        }
    }

    // MARK: 删除数据

    private var deleteGroup: some View {
        group(title: "删除数据") {
            DataActionRow(
                symbol: "trash",
                title: "删除全部训练记录",
                subtitle: "清空训练记录与休息日标记，动作库与设置保留",
                tint: DS.Palette.danger
            ) {
                onOpenClearRecords()
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "trash",
                title: "删除全部个人计划",
                subtitle: "删除全部训练计划，历史训练记录不受影响",
                tint: DS.Palette.danger
            ) {
                pendingAction = .deletePlans
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "trash",
                title: "删除全部身体数据",
                subtitle: "删除体重、体脂率与围度记录",
                tint: DS.Palette.danger
            ) {
                pendingAction = .deleteMeasurements
            }

            Divider().overlay(DS.Palette.stroke)

            DataActionRow(
                symbol: "exclamationmark.triangle",
                title: "清除全部本地数据",
                subtitle: "删除训练、计划、动作、收藏、身体数据、偏好、资料与本地媒体",
                tint: DS.Palette.danger
            ) {
                onOpenClearAll()
            }
        }
    }

    private func group<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    // MARK: 动作

    private func performDestructive(_ action: DestructiveAction) {
        switch action {
        case .deletePlans: viewModel.deleteAllPlans()
        case .deleteMeasurements: viewModel.deleteAllMeasurements()
        }
        onDataChanged()
    }


    // MARK: toast

    @ViewBuilder
    private var toastBar: some View {
        if let toast = viewModel.toast {
            HStack(spacing: DS.Spacing.tight) {
                Image(systemName: viewModel.toastIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(viewModel.toastIsError ? DS.Palette.danger : DS.Palette.accent)
                Text(toast)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .padding(.horizontal, DS.Spacing.page)
            .padding(.bottom, DS.Spacing.item)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .task(id: toast) {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                viewModel.clearToast()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(toast)
        }
    }
}

// MARK: - 菜单行

/// 数据管理页的菜单行：SF Symbol + 标题 + 摘要 + chevron，支持危险色。
private struct DataActionRow: View {

    let symbol: String
    let title: String
    var subtitle: String?
    var tint: Color = DS.Palette.accent
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.body)
                        .foregroundStyle(tint == DS.Palette.danger ? DS.Palette.danger : DS.Palette.textPrimary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: DS.Spacing.tight)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subtitle.map { "\(title)，\($0)" } ?? title)
    }
}

// MARK: - 破坏性操作确认

private struct DestructiveConfirmSheet: View {

    let action: DestructiveAction
    let onConfirm: () -> Void

    @State private var typedText = ""
    @Environment(\.dismiss) private var dismiss

    private var canConfirm: Bool {
        action.needsTypeConfirm ? typedText == "清除" : true
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    HStack(spacing: DS.Spacing.item) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(DS.Palette.danger)
                        Text(action.title)
                            .font(DS.Typography.sectionTitle)
                            .foregroundStyle(DS.Palette.danger)
                    }

                    Text(action.message)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if action.needsTypeConfirm {
                        TextField("输入「清除」以确认", text: $typedText)
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
                            .accessibilityLabel("输入清除以确认")
                    }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
            }
            .background(DS.Palette.bg)
            .navigationTitle("危险操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: DS.Spacing.item) {
                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text(action.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(canConfirm ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.button)
                                    .fill(canConfirm ? DS.Palette.danger.opacity(0.18) : DS.Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.button)
                                    .stroke(canConfirm ? DS.Palette.danger.opacity(0.5) : DS.Palette.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!canConfirm)
                    .accessibilityLabel(action.title)
                    .accessibilityHint(action.needsTypeConfirm && !canConfirm ? "需要先输入清除" : "")

                    SecondaryButton(title: "取消") { dismiss() }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.vertical, DS.Spacing.item)
                .background(DS.Palette.bg)
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 数据管理骨架屏

struct DataManagementSkeleton: View {

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            SkeletonBlock(height: 180)
            SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 80)
            SkeletonBlock(height: 170)
            SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 80)
            SkeletonBlock(height: 150)
            SkeletonBlock(height: 20, cornerRadius: 6).frame(width: 80)
            SkeletonBlock(height: 220)
        }
        .accessibilityElement()
        .accessibilityLabel("正在载入本地数据管理")
    }
}

// MARK: - 预览

#Preview("数据管理 · 有数据") {
    WorkoutDataManagementView(
        viewModel: WorkoutDataManagementViewModel(
            repository: PreviewFitnessRepository.makeStrengthHistory()
        ),
        onBack: {},
        onDataChanged: {},
        onOpenExportBackup: {},
        onOpenImportBackup: {},
        onOpenClearRecords: {},
        onOpenClearAll: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("数据管理 · 空数据") {
    WorkoutDataManagementView(
        viewModel: WorkoutDataManagementViewModel(repository: PreviewFitnessRepository.makeEmpty()),
        onBack: {},
        onDataChanged: {},
        onOpenExportBackup: {},
        onOpenImportBackup: {},
        onOpenClearRecords: {},
        onOpenClearAll: {}
    )
    .preferredColorScheme(.dark)
}
