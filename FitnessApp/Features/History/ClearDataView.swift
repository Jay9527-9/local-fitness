//
//  ClearDataView.swift
//  页面 45 / 46：清除训练记录 与 清除全部本地数据 的危险确认页。
//
//  独立的危险确认页（不再是内联 sheet）：风险卡、受影响数量、先导出备份、
//  输入确认短语 + 二次系统确认、保护备份 + 原子清除、失败恢复。
//

import SwiftUI

// MARK: - 值层：清除策略

/// 清除数据的两类入口，决定确认短语与清除范围。
enum ClearDataScope {
    /// 页面 45：只清训练记录与休息日。
    case records
    /// 页面 46：清除全部本地数据（含偏好），重置到首次启动引导。
    case all

    /// 必须输入的确认短语。
    var confirmPhrase: String {
        switch self {
        case .records: return "删除训练"
        case .all: return "清除全部"
        }
    }

    var title: String {
        switch self {
        case .records: return "清除训练记录"
        case .all: return "清除全部本地数据"
        }
    }

    /// 二次系统确认弹窗的标题。
    var systemConfirmTitle: String {
        switch self {
        case .records: return "确认永久删除训练记录？"
        case .all: return "确认清除全部本地数据？"
        }
    }
}

/// 清除操作的受影响数量。纯计算，可被 Python 照搬推演。
struct ClearDataCounts: Equatable {
    var finishedStrength = 0
    var finishedCardio = 0
    var drafts = 0
    var restDays = 0

    var finishedTotal: Int { finishedStrength + finishedCardio }

    /// 从训练会话与休息日推算出各数量。
    static func compute(sessions: [WorkoutSession], restDays: [RestDay]) -> ClearDataCounts {
        var counts = ClearDataCounts()
        for session in sessions {
            if session.isFinished {
                if session.kind == .cardio { counts.finishedCardio += 1 }
                else { counts.finishedStrength += 1 }
            } else {
                counts.drafts += 1
            }
        }
        counts.restDays = restDays.count
        return counts
    }
}

// MARK: - 视图模型

@MainActor
final class ClearDataViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var counts = ClearDataCounts()
    @Published private(set) var storageSizeBytes: Int64 = 0

    private let repository: FitnessRepository
    private let scope: ClearDataScope

    init(repository: FitnessRepository, scope: ClearDataScope) {
        self.repository = repository
        self.scope = scope
    }

    var storageSizeText: String { StorageSize.format(storageSizeBytes) }
    var canExecute: Bool { loadState == .loaded }

    func load() async {
        loadState = .loading
        do {
            let sessions = try repository.fetchRecentSessions(limit: 1000)
            let restDays = try repository.fetchRestDays()
            counts = ClearDataCounts.compute(sessions: sessions, restDays: restDays)
            if scope == .all {
                storageSizeBytes = try repository.localDataSizeBytes()
            }
            loadState = .loaded
        } catch {
            loadState = .failed
        }
    }

    /// 执行清除。返回是否成功（用于界面提示）。
    @discardableResult
    func execute() -> Bool {
        do {
            switch scope {
            case .records:
                let removed = counts.finishedTotal
                try repository.clearWorkoutRecords()
                return removed >= 0
            case .all:
                try repository.deleteAllData()
                ProfileSettings.resetAll()
                return true
            }
        } catch {
            return false
        }
    }
}

// MARK: - 页面 45：清除训练记录

struct ClearWorkoutRecordsView: View {

    @StateObject private var viewModel: ClearDataViewModel
    let onBack: () -> Void
    let onOpenExportBackup: () -> Void

    @State private var typedText = ""
    @State private var showSystemConfirm = false

    init(
        repository: FitnessRepository,
        onBack: @escaping () -> Void,
        onOpenExportBackup: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClearDataViewModel(repository: repository, scope: .records))
        self.onBack = onBack
        self.onOpenExportBackup = onOpenExportBackup
    }

    private var canDelete: Bool {
        viewModel.canExecute && typedText == ClearDataScope.records.confirmPhrase
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                riskCard
                countsCard
                backupEntry
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task { await viewModel.load() }
        .alert(ClearDataScope.records.systemConfirmTitle, isPresented: $showSystemConfirm) {
            Button("永久删除", role: .destructive) { runDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后不可恢复，除非你已导出备份。")
        }
    }

    private var riskCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text("此操作将删除")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("已完成的力量训练、有氧训练、未完成训练草稿、训练笔记、组记录、统计缓存与休息日标记。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(DS.Palette.stroke)

                Text("不会删除：个人计划、动作库、自定义动作、收藏动作、身体数据、个人资料与应用设置。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var countsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("受影响数量")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.canExecute {
                    HStack(spacing: DS.Spacing.item) {
                        countCell("完成训练", "\(viewModel.counts.finishedTotal)")
                        countCell("进行中草稿", "\(viewModel.counts.drafts)")
                        countCell("有氧记录", "\(viewModel.counts.finishedCardio)")
                        countCell("休息日", "\(viewModel.counts.restDays)")
                    }
                } else {
                    Text("暂时无法读取本地数据，无法执行删除。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.danger)
                }
            }
        }
    }

    private func countCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.danger)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backupEntry: some View {
        Button {
            Haptics.light()
            onOpenExportBackup()
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(DS.Palette.accent)
                Text("先导出备份")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("先导出备份")
    }

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

            Text("清除训练记录")
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

    private var bottomBar: some View {
        VStack(spacing: DS.Spacing.item) {
            TextField("输入「删除训练」以确认", text: $typedText)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .accessibilityLabel("输入删除训练以确认")

            Button {
                showSystemConfirm = true
            } label: {
                Text("永久删除")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canDelete ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .fill(canDelete ? DS.Palette.danger.opacity(0.18) : DS.Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .stroke(canDelete ? DS.Palette.danger.opacity(0.5) : DS.Palette.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canDelete)
            .accessibilityLabel("永久删除")
            .accessibilityHint(!canDelete ? "需要先输入删除训练" : "")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
        .background(DS.Palette.bg)
    }

    private func runDelete() {
        if viewModel.execute() {
            Haptics.warning()
        }
        onBack()
    }
}

// MARK: - 页面 46：清除全部本地数据

struct ClearAllDataView: View {

    @StateObject private var viewModel: ClearDataViewModel
    let onBack: () -> Void
    let onOpenExportBackup: () -> Void
    /// 清除成功后重置 App 到首次启动引导。
    let onClearedAllData: () -> Void

    @State private var typedText = ""
    @State private var acknowledged = false
    @State private var showSystemConfirm = false

    init(
        repository: FitnessRepository,
        onBack: @escaping () -> Void,
        onOpenExportBackup: @escaping () -> Void,
        onClearedAllData: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: ClearDataViewModel(repository: repository, scope: .all))
        self.onBack = onBack
        self.onOpenExportBackup = onOpenExportBackup
        self.onClearedAllData = onClearedAllData
    }

    private var canDelete: Bool {
        viewModel.canExecute
            && acknowledged
            && typedText == ClearDataScope.all.confirmPhrase
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                riskCard
                countsCard
                backupEntry
                acknowledgeToggle
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .task { await viewModel.load() }
        .alert(ClearDataScope.all.systemConfirmTitle, isPresented: $showSystemConfirm) {
            Button("确认清除", role: .destructive) { runClearAll() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("所有个人数据将无法恢复，除非你已导出备份。")
        }
    }

    private var riskCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.danger)
                    Text("此操作将删除")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.danger)
                        .accessibilityAddTraits(.isHeader)
                }
                Text("训练记录与草稿、个人计划、自定义动作、收藏和隐藏状态、身体数据、休息日、训练偏好、个人资料、已下载本地媒体与统计缓存。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(DS.Palette.stroke)

                Text("内置动作库种子不会永久丢失，下一次启动可重新导入；但所有个人数据无法恢复，除非你先导出备份。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var countsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("本次将清除")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)

                if viewModel.canExecute {
                    HStack(spacing: DS.Spacing.item) {
                        countCell("完成训练", "\(viewModel.counts.finishedTotal)")
                        countCell("进行中草稿", "\(viewModel.counts.drafts)")
                        countCell("休息日", "\(viewModel.counts.restDays)")
                        countCell("占用空间", viewModel.storageSizeText)
                    }
                } else {
                    Text("暂时无法读取本地数据，无法执行清除。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.danger)
                }
            }
        }
    }

    private func countCell(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backupEntry: some View {
        Button {
            Haptics.light()
            onOpenExportBackup()
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(DS.Palette.accent)
                Text("先导出备份")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("先导出备份")
    }

    private var acknowledgeToggle: some View {
        Button {
            Haptics.light()
            acknowledged.toggle()
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: acknowledged ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(acknowledged ? DS.Palette.accent : DS.Palette.checkboxIdle)
                Text("我理解此操作无法撤销")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(acknowledged ? [.isSelected] : [])
        .accessibilityLabel("我理解此操作无法撤销")
    }

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

            Text("清除全部本地数据")
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

    private var bottomBar: some View {
        VStack(spacing: DS.Spacing.item) {
            TextField("输入「清除全部」以确认", text: $typedText)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .accessibilityLabel("输入清除全部以确认")

            Button {
                showSystemConfirm = true
            } label: {
                Text("永久清除")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canDelete ? DS.Palette.textPrimary : DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: DS.Size.buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .fill(canDelete ? DS.Palette.danger.opacity(0.18) : DS.Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.button)
                            .stroke(canDelete ? DS.Palette.danger.opacity(0.5) : DS.Palette.stroke, lineWidth: 1)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canDelete)
            .accessibilityLabel("永久清除")
            .accessibilityHint(!canDelete ? "需要先勾选理解并输入清除全部" : "")
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, DS.Spacing.item)
        .background(DS.Palette.bg)
    }

    private func runClearAll() {
        if viewModel.execute() {
            Haptics.warning()
            onClearedAllData()
        }
    }
}
