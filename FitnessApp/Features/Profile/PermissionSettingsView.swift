//
//  PermissionSettingsView.swift
//  页面 51：权限管理。
//
//  入口：「应用设置」→「权限管理」，或首次触发相册 / 本地通知功能时的引导。
//
//  本页只展示两项本就存在的系统权限（本地通知、相册访问）的当前状态，
//  不申请新权限、不上传权限信息、不含第三方登录或隐私追踪选项。
//  拒绝权限不影响核心功能，所以本页整体是「陈述事实」的语气，不做红色警示。
//

import SwiftUI

// MARK: - 视图模型

@MainActor
final class PermissionSettingsViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var entries: [PermissionEntry] = []

    /// 从后台回到前台时要重读：用户很可能是去系统设置里改完权限再回来的，
    /// 若只在 `onAppear` 读一次，返回时数字和徽章还是旧的。
    func load() {
        PermissionCenter.read { [weak self] entries in
            guard let self else { return }
            self.entries = entries
            self.loadState = .loaded
        }
    }

    /// 汇总文案。
    var summaryText: String { PermissionCatalog.availabilitySummary(entries) }

    /// 是否存在用户自己改不了的限制状态。
    var hasRestricted: Bool { PermissionCatalog.hasRestricted(entries) }

    /// 是否有任意一项被拒绝（用于决定要不要显示「前往系统设置」的整卡引导）。
    var hasDenied: Bool { entries.contains { $0.status == .denied } }
}

// MARK: - 页面

struct PermissionSettingsView: View {

    @StateObject private var viewModel = PermissionSettingsViewModel()

    let onBack: () -> Void

    /// 从系统设置返回时重读权限状态。
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    SkeletonBlock(height: 96)
                    SkeletonBlock(height: 180)

                case .failed:
                    EmptyStateView(
                        message: "读取权限状态失败。这不影响 App 的其它功能。",
                        actionTitle: "重试",
                        action: { viewModel.load() }
                    )

                case .loaded:
                    scopeCard
                    permissionGroup
                    fallbackCard
                    privacyFooter
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .onAppear { viewModel.load() }
        .onChange(of: scenePhase) { phase in
            // 用户去系统设置改完再切回来时，徽章要跟着变。
            if phase == .active { viewModel.load() }
        }
    }

    // MARK: 顶部说明

    private var scopeCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(PermissionCatalog.scopeNote)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(PermissionCatalog.offlineNote)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if !viewModel.summaryText.isEmpty {
                    Text(viewModel.summaryText)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 权限清单

    private var permissionGroup: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("系统权限")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        permissionRow(entry)
                        if index < viewModel.entries.count - 1 {
                            Divider().overlay(DS.Palette.stroke)
                        }
                    }
                }
            }
        }
    }

    private func permissionRow(_ entry: PermissionEntry) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(statusColor(entry.status))
                    .frame(width: 26, alignment: .center)

                Text(entry.kind.title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)

                Spacer(minLength: DS.Spacing.tight)

                statusBadge(entry.status)
            }

            Text(entry.kind.purpose)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.status.detail)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // 「前往系统设置」只在已拒绝 / 受限制时出现：
            // 未授权时该由功能自己触发系统弹窗，而不是把用户推去设置里找。
            if entry.status.needsSystemSettingsLink {
                Button {
                    Haptics.light()
                    PermissionCenter.openSystemSettings()
                } label: {
                    HStack(spacing: DS.Spacing.tight) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 13, weight: .semibold))
                        Text("前往系统设置")
                            .font(DS.Typography.callout.weight(.semibold))
                    }
                    .foregroundStyle(DS.Palette.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.accent)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("前往系统设置，为「\(entry.kind.title)」修改权限")
            }
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.accessibilityLabel)
    }

    private func statusBadge(_ status: PermissionStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.title)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(DS.Palette.permissionBadgeFill)
        )
        .overlay(
            Capsule().stroke(statusColor(status).opacity(0.28), lineWidth: 1)
        )
        .accessibilityHidden(true)   // 状态已由整行的 accessibilityLabel 读出
    }

    /// 状态 → 颜色。四种状态各有可区分的颜色，见设计令牌的注释。
    private func statusColor(_ status: PermissionStatus) -> Color {
        switch status {
        case .authorized: return DS.Palette.permissionGranted
        case .notDetermined: return DS.Palette.permissionIdle
        case .denied: return DS.Palette.permissionDenied
        case .restricted: return DS.Palette.permissionRestricted
        }
    }

    // MARK: 兜底说明

    /// 拒绝权限不影响核心功能 —— 把「不影响什么」明确写出来，
    /// 否则用户会以为不给权限 App 就残废了。
    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("不开权限会怎样")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    ForEach(PermissionCatalog.order, id: \.rawValue) { kind in
                        HStack(alignment: .top, spacing: DS.Spacing.tight) {
                            Circle()
                                .fill(DS.Palette.textTertiary)
                                .frame(width: 5, height: 5)
                                .padding(.top, 6)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(DS.Typography.callout.weight(.semibold))
                                    .foregroundStyle(DS.Palette.textPrimary)
                                Text(kind.fallbackNote)
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: 隐私声明

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(PermissionCatalog.privacyNote)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.hasRestricted {
                Text("「受限制」由系统策略造成，本机无法自行修改。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.hasDenied {
                Text("在系统设置里打开权限后，回到本页会自动刷新状态。")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.card)
        .padding(.top, DS.Spacing.tight)
        .accessibilityElement(children: .combine)
    }

    // MARK: 导航栏

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

            Text("权限管理")
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

// MARK: - 预览

#Preview("权限管理") {
    PermissionSettingsView(onBack: {})
        .preferredColorScheme(.dark)
}
