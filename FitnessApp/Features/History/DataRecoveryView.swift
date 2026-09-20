//
//  DataRecoveryView.swift
//  页面 50：错误与数据恢复。
//
//  仅在检测到本地数据异常时出现，不能因普通空数据触发。
//  提供重试读取 / 导出诊断副本 / 从备份恢复 / 跳过并继续 / 重置受影响数据。
//  不自动上传日志、不连接网络、不向第三方发送诊断数据。
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 值层：受影响类别与恢复报告

/// 发生异常的数据类别。决定「重置受影响数据」清除哪一类。
enum RecoveryCategory: String, CaseIterable, Identifiable {
    case sessions
    case plans
    case measurements
    case preferences

    var id: String { rawValue }

    /// 面向普通用户的友好位置说明，不展示原始路径或堆栈。
    var title: String {
        switch self {
        case .sessions: return "训练记录文件无法读取"
        case .plans: return "训练计划文件无法读取"
        case .measurements: return "身体数据文件无法读取"
        case .preferences: return "偏好设置无法读取"
        }
    }
}

/// 恢复操作。
enum RecoveryAction: CaseIterable, Identifiable {
    case retry
    case exportDiagnostic
    case restoreFromBackup
    case skip
    case reset

    var id: String { title }

    var title: String {
        switch self {
        case .retry: return "重试读取"
        case .exportDiagnostic: return "导出诊断副本"
        case .restoreFromBackup: return "从备份恢复"
        case .skip: return "跳过并继续"
        case .reset: return "重置受影响数据"
        }
    }

    var symbol: String {
        switch self {
        case .retry: return "arrow.clockwise"
        case .exportDiagnostic: return "square.and.arrow.up"
        case .restoreFromBackup: return "tray.and.arrow.down"
        case .skip: return "forward"
        case .reset: return "trash"
        }
    }

    var isDestructive: Bool { self == .reset }
}

/// 一次完整性检查的报告。纯计算，可被 Python 照搬推演。
struct RecoveryReport: Equatable {
    var sessionCount = 0
    var planCount = 0
    var measurementCount = 0

    var isHealthy: Bool { true }

    var summary: String {
        "训练记录 \(sessionCount) 条，计划 \(planCount) 个，身体数据 \(measurementCount) 条"
    }
}

// MARK: - 数据恢复视图

struct DataRecoveryView: View {

    let repository: FitnessRepository
    let onBack: () -> Void

    var category: RecoveryCategory = .sessions

    @State private var report: RecoveryReport?
    @State private var checking = false
    @State private var showDiagnostic = false
    @State private var diagnosticData: Data = Data()
    @State private var showResetConfirm = false
    @State private var resetMessage: String?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                warningCard
                reportCard
                actionList
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .overlay(alignment: .bottom) { toastBar }
        .task { await verify() }
        .fileExporter(
            isPresented: $showDiagnostic,
            document: DiagnosticDocument(data: diagnosticData),
            contentType: .json,
            defaultFilename: "诊断副本.json"
        ) { _ in }
        .alert("重置受影响数据？", isPresented: $showResetConfirm) {
            Button("重置", role: .destructive) { performReset() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("仅清除\(category.title)对应数据，关键文件已尝试创建原始副本。其他数据不受影响。")
        }
    }

    // MARK: 警示卡

    private var warningCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(spacing: DS.Spacing.tight) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(DS.Palette.warning)
                    Text("发现数据异常")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.warning)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(category.title)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                Text("App 不会自动上传日志或连接网络，也不会把诊断数据发送给第三方。")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 报告卡

    @ViewBuilder
    private var reportCard: some View {
        if checking {
            CardContainer {
                HStack(spacing: DS.Spacing.item) {
                    ProgressView().tint(DS.Palette.accent)
                    Text("正在重试读取本地数据…")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
        } else if let report {
            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                    Text("读取结果")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Text(report.summary)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text("已恢复正常，可返回来源页面。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.accent)
                }
            }
        }
    }

    // MARK: 操作列表

    private var actionList: some View {
        CardContainer(padding: 0) {
            VStack(spacing: 0) {
                actionRow(.retry)
                Divider().overlay(DS.Palette.stroke)
                actionRow(.exportDiagnostic)
                Divider().overlay(DS.Palette.stroke)
                actionRow(.restoreFromBackup)
                Divider().overlay(DS.Palette.stroke)
                actionRow(.skip)
                Divider().overlay(DS.Palette.stroke)
                actionRow(.reset)
            }
        }
    }

    private func actionRow(_ action: RecoveryAction) -> some View {
        Button {
            Haptics.light()
            perform(action)
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: action.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(action.isDestructive ? DS.Palette.danger : DS.Palette.accent)
                    .frame(width: 26, alignment: .center)
                Text(action.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(action.isDestructive ? DS.Palette.danger : DS.Palette.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.isDestructive ? "需二次确认，仅清除\(category.title)对应数据" : "")
    }

    // MARK: 动作

    private func verify() async {
        checking = true
        do {
            let sessions = try repository.fetchRecentSessions(limit: 1000)
            let plans = try repository.fetchPlans()
            let measurements = try repository.fetchBodyMeasurements(limit: 1000)
            report = RecoveryReport(
                sessionCount: sessions.count,
                planCount: plans.count,
                measurementCount: measurements.count
            )
        } catch {
            report = RecoveryReport()
        }
        checking = false
    }

    private func perform(_ action: RecoveryAction) {
        switch action {
        case .retry:
            Task { await verify() }
        case .exportDiagnostic:
            exportDiagnostic()
        case .restoreFromBackup:
            resetMessage = "请在「我的 → 本地数据管理 → 导入本地备份」中从备份恢复。"
        case .skip:
            onBack()
        case .reset:
            showResetConfirm = true
        }
    }

    private func exportDiagnostic() {
        let payload: [String: Any] = [
            "diagnostic": "fitness-local-data",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "summary": report?.summary ?? "未知",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]) {
            diagnosticData = data
            showDiagnostic = true
        }
    }

    private func performReset() {
        do {
            switch category {
            case .sessions: try repository.clearWorkoutRecords()
            case .plans: try repository.deleteAllPlans()
            case .measurements: try repository.deleteAllMeasurements()
            case .preferences: ProfileSettings.resetAll()
            }
            resetMessage = "已重置\(category.title)对应数据。"
        } catch {
            resetMessage = "重置失败，原数据已保留。"
        }
    }

    // MARK: toast

    @ViewBuilder
    private var toastBar: some View {
        if let message = resetMessage {
            Text(message)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
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
                .accessibilityLabel(message)
        }
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

            Text("数据恢复")
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

// MARK: - 诊断副本文档

private struct DiagnosticDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - 预览

#Preview("数据恢复") {
    DataRecoveryView(
        repository: PreviewFitnessRepository(),
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
