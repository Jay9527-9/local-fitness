//
//  ProfileView.swift
//  页面 13：我的。
//
//  纯本地个人设置中心。不含登录、账号、好友、动态、教练、订阅、
//  反馈社区或分享入口。菜单进入对应设置页 / 子页，开关即时写入本地。
//
//  单位偏好与页面 12 共用同一把 UserDefaults 键（见 `ProfileSettings`），
//  所以这里改单位，身体数据页的展示会跟着变。
//

import SwiftUI

// MARK: - ViewModel

@MainActor
final class ProfileViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    let repository: FitnessRepository

    @Published private(set) var loadState: LoadState = .loading
    /// 本地个人资料。首次读取时若为空会自动创建（开始使用日期 = 此刻）。
    @Published private(set) var profile: UserProfile?
    @Published private(set) var latestWeightKg: Double?
    @Published private(set) var finishedSessionCount = 0
    @Published private(set) var totalDurationSeconds = 0

    /// 单位偏好。只影响展示，写 UserDefaults（与页面 12 同源）。
    @Published var weightUnit: BodyWeightUnit {
        didSet { ProfileSettings.weightUnit = weightUnit }
    }
    @Published var lengthUnit: BodyLengthUnit {
        didSet { ProfileSettings.lengthUnit = lengthUnit }
    }

    private let calendar = Calendar.current

    init(repository: FitnessRepository) {
        self.repository = repository
        self.weightUnit = ProfileSettings.weightUnit
        self.lengthUnit = ProfileSettings.lengthUnit
    }

    // MARK: 派生

    var nickname: String? { profile?.trimmedNickname }
    /// 概览卡上显示的昵称。没设置时是「设置昵称」。
    var displayName: String { nickname ?? "设置昵称" }
    var startedAt: Date? { profile?.startedAt }
    var daysSinceStart: Int {
        guard let start = startedAt else { return 0 }
        return ProfileMath.daysSince(start, now: .now, calendar: calendar)
    }

    /// 当前默认休息时间（秒），供设置行展示。
    var defaultRestDisplay: Int { ProfileSettings.defaultRest }

    /// 默认休息时间的展示文案，如「1 分 30 秒」。
    var defaultRestText: String { FormatterKit.rest(seconds: ProfileSettings.defaultRest) }

    // MARK: 加载

    func load() async {
        loadState = .loading
        do {
            var current = try repository.fetchProfile()
            if current == nil {
                // 首次进入「我的」：创建一份个人资料，开始使用日期记作今天。
                current = UserProfile(startedAt: .now)
                try repository.save(profile: current!)
            }
            profile = current

            let measurements = try repository.fetchBodyMeasurements(limit: 1)
            latestWeightKg = measurements.first?.weightKg

            let sessions = try repository.fetchRecentSessions(limit: 500)
            let finished = sessions.filter { $0.isFinished }
            finishedSessionCount = finished.count
            totalDurationSeconds = finished.reduce(0) { $0 + $1.durationSeconds }

            loadState = .loaded
        } catch {
            loadState = .failed("读取个人数据失败：\(error.localizedDescription)")
        }
    }

    func reload() async {
        await load()
    }

    // MARK: 写入

    /// 保存昵称。空白归一成 nil（等同未设置）。
    func saveNickname(_ raw: String?) {
        var current = profile ?? UserProfile(startedAt: .now)
        current.nickname = raw
        try? repository.save(profile: current)
        profile = current
    }
}

// MARK: - 页面

struct ProfileView: View {

    @ObservedObject var viewModel: ProfileViewModel

    // 导航回调
    var onOpenBodyData: () -> Void = {}
    var onOpenProfileEdit: () -> Void = {}
    var onOpenPlans: () -> Void = {}
    var onOpenFavorites: () -> Void = {}
    var onOpenTrainingPreferences: () -> Void = {}
    var onOpenDataManagement: () -> Void = {}
    var onOpenAppSettings: () -> Void = {}
    var onExportBackup: () -> Void = {}
    var onImportBackup: () -> Void = {}

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                switch viewModel.loadState {
                case .loading:
                    SkeletonBlock(height: 140)
                    SkeletonBlock(height: 88)
                    SkeletonBlock(height: 220)

                case .failed(let message):
                    EmptyStateView(
                        message: message,
                        actionTitle: "重试",
                        action: { Task { await viewModel.reload() } }
                    )

                case .loaded:
                    overviewCard
                    summaryRow
                    trainingAndBodyGroup
                    dataGroup
                    appSettingsGroup
                    footerCard
                }
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .task { await viewModel.load() }
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack {
            Text("我的")
                .font(DS.Typography.largeTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.page)
        .padding(.vertical, 6)
        .background(DS.Palette.bg)
    }

    // MARK: 个人概览卡

    private var overviewCard: some View {
        Button(action: onOpenProfileEdit) {
            CardContainer {
                HStack(spacing: DS.Spacing.item) {
                    // 首字母圆形头像：代码绘制，不依赖任何图片资源
                    avatar

                    VStack(alignment: .leading, spacing: 3) {
                        Text(viewModel.displayName)
                            .font(DS.Typography.sectionTitle)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1)

                        Text("已使用 \(viewModel.daysSinceStart) 天")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textSecondary)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("个人资料，\(viewModel.displayName)，已使用 \(viewModel.daysSinceStart) 天")
        .accessibilityHint("点击编辑个人资料")
    }

    /// 圆形头像：有本地照片显示照片，否则用昵称首字母 + 渐变背景。
    private var avatar: some View {
        ProfileAvatarView(
            imageData: avatarImageData,
            nickname: viewModel.nickname,
            size: 56
        )
    }

    /// 头像图片数据。个人资料里存了头像文件名时从本地目录读取。
    private var avatarImageData: Data? {
        guard let fileName = viewModel.profile?.avatarFileName else { return nil }
        return AvatarStore.data(for: fileName)
    }

    // MARK: 数据摘要

    private var summaryRow: some View {
        CardContainer {
            HStack(spacing: 0) {
                summaryCell(title: "最近体重", value: ProfileSummaryText.weightText(latestWeightKg: viewModel.latestWeightKg, unit: viewModel.weightUnit))
                divider
                summaryCell(title: "累计训练", value: ProfileSummaryText.countText(viewModel.finishedSessionCount))
                divider
                summaryCell(title: "累计时长", value: ProfileSummaryText.durationText(seconds: viewModel.totalDurationSeconds))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("最近体重 \(ProfileSummaryText.weightText(latestWeightKg: viewModel.latestWeightKg, unit: viewModel.weightUnit))，累计训练 \(ProfileSummaryText.countText(viewModel.finishedSessionCount)) 次，累计时长 \(ProfileSummaryText.durationText(seconds: viewModel.totalDurationSeconds))")
    }

    private func summaryCell(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Palette.stroke)
            .frame(width: 1, height: 32)
    }

    // MARK: 训练与身体

    private var trainingAndBodyGroup: some View {
        menuGroup(title: "训练与身体") {
            ProfileMenuRow(symbol: "figure.arms.open", title: "身体数据", subtitle: "体重、体脂率与围度", action: onOpenBodyData)
            ProfileMenuRow(symbol: "list.bullet.rectangle", title: "我的计划", subtitle: "已保存的训练计划", action: onOpenPlans)
            ProfileMenuRow(symbol: "star", title: "动作收藏", subtitle: "收藏的动作", action: onOpenFavorites)
            ProfileMenuRow(symbol: "slider.horizontal.3", title: "训练偏好", subtitle: "休息与自动开始", action: onOpenTrainingPreferences)
        }
    }

    // MARK: 数据

    private var dataGroup: some View {
        menuGroup(title: "数据") {
            ProfileMenuRow(symbol: "externaldrive", title: "本地数据管理", subtitle: "导出、导入与清除", action: onOpenDataManagement)
            ProfileMenuRow(symbol: "tray.and.arrow.down", title: "导入备份", subtitle: "从 JSON 备份恢复", action: onImportBackup)
            ProfileMenuRow(symbol: "square.and.arrow.up", title: "导出备份", subtitle: "生成 JSON 备份文件", action: onExportBackup)
        }
    }

    // MARK: 应用设置

    private var appSettingsGroup: some View {
        menuGroup(title: "应用设置") {
            ProfileMenuRow(symbol: "gearshape", title: "应用设置", subtitle: "显示、单位与提醒", action: onOpenAppSettings)
        }
    }

    // MARK: 底部版本信息

    private var footerCard: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(AppResources.appName)
                .font(DS.Typography.caption.weight(.semibold))
                .foregroundStyle(DS.Palette.textSecondary)

            Text("本地数据库 v\(AppResources.databaseVersion) · 动作库 v\(AppResources.exerciseLibraryVersion)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)

            Text("本 App 完全离线运行：不请求登录，不采集数据，不含任何社交功能。所有训练与身体数据仅保存在本机。")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            MediaAttributionLabel()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Spacing.item)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(AppResources.appName)。本地数据库版本 \(AppResources.databaseVersion)，动作库版本 \(AppResources.exerciseLibraryVersion)。")
    }

    // MARK: 菜单组

    private func menuGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer(padding: 0) {
                VStack(spacing: 0) {
                    content()
                }
            }
        }
    }
}

// MARK: - 菜单行组件

/// 一个可点击的菜单行：SF Symbol + 标题 + 摘要 + chevron。
struct ProfileMenuRow: View {

    let symbol: String
    let title: String
    var subtitle: String?
    var action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: 26, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                            .lineLimit(1)
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

/// 一个开关行。
struct ProfileToggleRow: View {

    let title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var enabled: Bool = true
    var onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                isOn = newValue
                onChange(newValue)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .tint(DS.Palette.accent)
        .disabled(!enabled)
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)\(subtitle.map { "，\($0)" } ?? "")")
        // 页面 14 起：开关的 value 必须朗读「已开启 / 已关闭」。
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

/// 一段式分段选择行（单位切换用）。
struct ProfileSegmentedRow<Option: RawRepresentable & CaseIterable & Identifiable>: View
where Option.RawValue == String {

    let title: String
    let options: [Option]
    let selected: Option
    var onSelect: (Option) -> Void

    var body: some View {
        HStack(spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                ForEach(options) { option in
                    Button {
                        Haptics.light()
                        onSelect(option)
                    } label: {
                        Text(option.rawValue)
                            .font(DS.Typography.caption2)
                            .foregroundStyle(
                                option.rawValue == selected.rawValue ? DS.Palette.onAccent : DS.Palette.textSecondary
                            )
                            .frame(width: 40, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(option.rawValue == selected.rawValue ? DS.Palette.accent : DS.Palette.surfaceElevated)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .stroke(option.rawValue == selected.rawValue ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.rawValue)
                    .accessibilityAddTraits(option.rawValue == selected.rawValue ? [.isSelected] : [])
                }
            }
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 预览

#Preview("我的") {
    ProfileView(viewModel: ProfileViewModel(repository: PreviewFitnessRepository()))
        .preferredColorScheme(.dark)
}
