//
//  OnboardingView.swift
//  页面 47：首次启动引导。
//
//  4 页全屏引导，代码绘制的抽象图形（系统矢量符号 + SwiftUI 形状），
//  深炭黑背景 + 荧光绿强调。不使用第三方插画、原应用文案、账号登录或社交邀请。
//  完成或跳过后创建默认 UserProfile + AppPreferences，标记 hasCompletedOnboarding。
//

import SwiftUI

// MARK: - 引导页定义

private enum OnboardingPage: Int, CaseIterable {
    case record = 0
    case profile = 1
    case goal = 2
    case privacy = 3

    var title: String {
        switch self {
        case .record: return "记录每一次训练"
        case .profile: return "简单设置一下"
        case .goal: return "你的训练目标"
        case .privacy: return "数据只属于你"
        }
    }

    var body: String {
        switch self {
        case .record: return "训练计划、动作与记录只保存在本机。"
        case .profile: return "填写可选资料，跳过则使用默认设置。"
        case .goal: return "选择目标以便后续推荐，可稍后在个人资料中修改。"
        case .privacy: return "你的数据默认不上传，可随时从设置导出备份。"
        }
    }

    var symbol: String {
        switch self {
        case .record: return "dumbbell"
        case .profile: return "person.crop.circle"
        case .goal: return "target"
        case .privacy: return "lock.shield"
        }
    }
}

// MARK: - 引导视图

struct OnboardingView: View {

    let repository: FitnessRepository
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var pageIndex = 0
    @State private var nickname = ""
    @State private var weightUnit = ProfileSettings.weightUnit
    @State private var lengthUnit = ProfileSettings.lengthUnit
    @State private var goal: TrainingGoal?

    var body: some View {
        ZStack {
            DS.Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                pageContent
                    .id(pageIndex)
                    .transition(.opacity)

                Spacer(minLength: 0)

                pageIndicator
                bottomControls
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: 页面内容

    @ViewBuilder
    private var pageContent: some View {
        let page = OnboardingPage(rawValue: pageIndex) ?? .record
        VStack(spacing: DS.Spacing.section) {
            Spacer(minLength: 0)

            hero(for: page)

            VStack(spacing: DS.Spacing.item) {
                Text(page.title)
                    .font(DS.Typography.largeTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .multilineTextAlignment(.center)

                Text(page.body)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if page == .profile {
                profileForm
            } else if page == .goal {
                goalPicker
            }

            Spacer(minLength: 0)
        }
    }

    private func hero(for page: OnboardingPage) -> some View {
        ZStack {
            Circle()
                .fill(DS.Palette.accent.opacity(0.12))
                .frame(width: 120, height: 120)

            Circle()
                .stroke(DS.Palette.accent.opacity(0.35), lineWidth: 1.5)
                .frame(width: 140, height: 140)

            Image(systemName: page.symbol)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(DS.Palette.accent)
        }
        .accessibilityHidden(true)
    }

    // MARK: 第 2 页：可选资料

    private var profileForm: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            TextField("昵称（可选）", text: $nickname)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .accessibilityLabel("昵称，可选")

            unitRow("重量单位", options: BodyWeightUnit.self, selection: $weightUnit)
            unitRow("长度单位", options: BodyLengthUnit.self, selection: $lengthUnit)
        }
    }

    private func unitRow<Option: RawRepresentable & CaseIterable & Identifiable & Hashable>(
        _ title: String,
        options: Option.Type,
        selection: Binding<Option>
    ) -> some View where Option.AllCases: RandomAccessCollection, Option.RawValue == String {
        HStack(spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer(minLength: 0)
            ForEach(Array(options.allCases)) { option in
                Button {
                    Haptics.light()
                    selection.wrappedValue = option
                } label: {
                    Text(option.rawValue)
                        .font(DS.Typography.caption)
                        .foregroundStyle(selection.wrappedValue == option ? DS.Palette.onAccent : DS.Palette.textSecondary)
                        .frame(minWidth: 40, minHeight: 30)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(selection.wrappedValue == option ? DS.Palette.accent : DS.Palette.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(selection.wrappedValue == option ? Color.clear : DS.Palette.stroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection.wrappedValue == option ? [.isSelected] : [])
            }
        }
    }

    // MARK: 第 3 页：训练目标

    private var goalPicker: some View {
        FlowChips(
            items: Self.goalOptions.map(\.title),
            isSelected: { goal?.title == $0 },
            onTap: { title in
                Haptics.light()
                goal = Self.goalOptions.first { $0.title == title }
            }
        )
    }

    private static var goalOptions: [TrainingGoal] {
        TrainingGoal.allCases.filter { $0 != .custom }
    }

    // MARK: 页码指示器

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<OnboardingPage.allCases.count, id: \.self) { index in
                Capsule()
                    .fill(index == pageIndex ? DS.Palette.accent : DS.Palette.stroke)
                    .frame(width: index == pageIndex ? 20 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(pageIndex + 1) 页，共 \(OnboardingPage.allCases.count) 页")
    }

    // MARK: 底部控制

    private var bottomControls: some View {
        VStack(spacing: DS.Spacing.item) {
            HStack(spacing: DS.Spacing.item) {
                Button("跳过") { skip() }
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .accessibilityLabel("跳过引导")

                Spacer(minLength: 0)

                PrimaryButton(title: primaryButtonTitle, isEnabled: true) {
                    advance()
                }
                .frame(maxWidth: 200)
            }
        }
        .padding(.top, DS.Spacing.item)
    }

    private var primaryButtonTitle: String {
        switch pageIndex {
        case 0: return "开始设置"
        case 1, 2: return "下一步"
        case 3: return "进入训练"
        default: return "下一步"
        }
    }

    // MARK: 动作

    private func advance() {
        if pageIndex < OnboardingPage.allCases.count - 1 {
            Haptics.light()
            withAnimation(MotionConfig.fade ?? .easeInOut(duration: 0.001)) {
                pageIndex += 1
            }
        } else {
            finish()
        }
    }

    private func skip() {
        finish()
    }

    private func finish() {
        // 写入可选资料到 AppPreferences。
        ProfileSettings.weightUnit = weightUnit
        ProfileSettings.lengthUnit = lengthUnit

        // 创建 / 更新本地 UserProfile。不生成任何默认训练或默认计划。
        do {
            var profile = try repository.fetchProfile() ?? UserProfile()
            let trimmed = ProfileValidation.normalizedNickname(nickname)
            if let trimmed { profile.nickname = trimmed }
            if let goal { profile.trainingGoal = goal }
            try repository.save(profile: profile)
        } catch {
            // 资料写入失败不阻断进入 App：设置项已落在 UserDefaults。
        }

        onComplete()
    }
}
