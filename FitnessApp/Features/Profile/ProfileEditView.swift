//
//  ProfileEditView.swift
//  页面 17：个人资料编辑。
//
//  从「我的」顶部个人概览卡进入。资料仅存储在本机，不创建账号、不登录、不上传云端。
//
//  结构：导航栏（取消 / 个人资料 / 保存）→ 头像区 → 昵称 / 训练开始日期 / 训练目标 /
//  个人说明 → 本地资料说明。存在未保存改动时，取消会弹「放弃修改？」确认。
//

import SwiftUI
import PhotosUI
import Combine

// MARK: - 状态机

@MainActor
final class ProfileEditViewModel: ObservableObject {

    /// 头像草稿：选新照片 / 移除照片；nil 表示保持原头像不变。
    enum AvatarDraft: Equatable {
        case photo(Data)
        case removed
    }

    let repository: FitnessRepository

    /// 加载到的原始资料（保存前不改动它）。
    @Published private(set) var profile: UserProfile?
    @Published private(set) var originalAvatarFileName: String?

    // 表单草稿
    @Published var nicknameText: String = ""
    @Published var startedAt: Date = .now
    @Published var trainingGoal: TrainingGoal?
    @Published var customGoalText: String = ""
    @Published var bioText: String = ""

    // 头像草稿
    @Published var avatarDraft: AvatarDraft?

    @Published var errorMessage: String?

    private let calendar = Calendar.current

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    // MARK: 加载

    func load() async {
        do {
            var current = try repository.fetchProfile()
            if current == nil {
                // 首次进入：创建一份，开始日期记作今天
                current = UserProfile(startedAt: .now)
                try repository.save(profile: current!)
            }
            profile = current
            originalAvatarFileName = current?.avatarFileName
            nicknameText = current?.nickname ?? ""
            startedAt = current?.startedAt ?? .now
            trainingGoal = current?.trainingGoal
            customGoalText = current?.customGoal ?? ""
            bioText = current?.bio ?? ""
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    // MARK: 派生

    /// 是否存在未保存改动。
    var hasUnsavedChanges: Bool {
        guard let profile else { return false }
        if ProfileValidation.normalizedNickname(nicknameText) != profile.nickname { return true }
        // 训练开始日期按自然日比较，避免 DatePicker 带来的时分秒差异误报
        if !calendar.isDate(startedAt, inSameDayAs: profile.startedAt) { return true }
        if trainingGoal != profile.trainingGoal { return true }
        if customGoalNormalized != profile.customGoal { return true }
        if ProfileValidation.normalizedBio(bioText) != profile.bio { return true }
        if avatarDraft != nil { return true }
        return false
    }

    /// 当前应展示的头像数据：新照片 → 草稿数据；移除 → nil；未变 → 原头像文件。
    var currentAvatarData: Data? {
        switch avatarDraft {
        case .photo(let data): return data
        case .removed: return nil
        case nil: return originalAvatarFileName.flatMap { AvatarStore.data(for: $0) }
        }
    }

    private var customGoalNormalized: String? {
        let trimmed = customGoalText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: 交互

    /// 选定新照片（已压缩的 JPEG 数据）。
    func pickAvatar(_ data: Data) {
        avatarDraft = .photo(data)
    }

    /// 移除照片，恢复默认首字母头像。
    func removeAvatar() {
        avatarDraft = .removed
    }

    /// 保存。返回是否成功。头像落盘失败时保留原头像并返回 false。
    func save() -> Bool {
        guard let profile else { return false }

        let newNickname = ProfileValidation.normalizedNickname(nicknameText)
        let newBio = ProfileValidation.normalizedBio(bioText)
        // 只有「自定义」目标才保留自定义文字，其它目标清掉
        let newCustom = trainingGoal == .custom ? customGoalNormalized : nil

        // 1. 头像：新照片先落盘，失败即中止并保留原头像。
        var newAvatar = originalAvatarFileName
        do {
            switch avatarDraft {
            case .photo(let data):
                newAvatar = try AvatarStore.save(data)
            case .removed:
                newAvatar = nil
            case nil:
                break
            }
        } catch {
            errorMessage = "头像保存失败，已保留原头像。"
            return false
        }

        let updated = UserProfile(
            id: profile.id,
            nickname: newNickname,
            startedAt: startedAt,
            trainingGoal: trainingGoal,
            customGoal: newCustom,
            bio: newBio,
            avatarFileName: newAvatar
        )

        do {
            try repository.save(profile: updated)
        } catch {
            // 回滚刚写的新头像文件，避免留下孤儿文件
            if case .photo = avatarDraft, let newAvatar {
                try? AvatarStore.delete(fileName: newAvatar)
            }
            errorMessage = Self.message(for: error)
            return false
        }

        // 2. 成功：删除被替换 / 移除的旧头像文件。
        if let old = originalAvatarFileName, old != newAvatar {
            try? AvatarStore.delete(fileName: old)
        }

        // 3. 同步内存副本，清掉草稿。
        self.profile = updated
        self.originalAvatarFileName = updated.avatarFileName
        self.nicknameText = updated.nickname ?? ""
        self.customGoalText = updated.customGoal ?? ""
        self.bioText = updated.bio ?? ""
        self.avatarDraft = nil
        return true
    }

    private static func message(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "操作失败：\(error.localizedDescription)"
    }
}

// MARK: - 头像视图

/// 本地头像：有照片显示照片，否则用昵称首字母 + 代码绘制渐变背景。
struct ProfileAvatarView: View {

    /// 头像图片数据。nil 表示用默认首字母头像。
    var imageData: Data?
    /// 用于默认头像首字母的昵称。空则回退「我」。
    var nickname: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                defaultAvatar
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(DS.Palette.stroke, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var defaultAvatar: some View {
        let initial = nickname?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .first.map(String.init) ?? "我"

        return ZStack {
            // 代码绘制渐变背景，不依赖任何图片资源
            LinearGradient(
                colors: [DS.Palette.accent, DS.Palette.cardio],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initial)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Palette.onAccent)
        }
    }
}

// MARK: - 页面

struct ProfileEditView: View {

    @StateObject private var viewModel: ProfileEditViewModel

    /// 取消（无改动）或「放弃修改」后返回。
    let onCancel: () -> Void
    /// 保存成功后返回。
    let onSaved: () -> Void

    @State private var photoItem: PhotosPickerItem?
    @State private var showDiscardConfirm = false

    init(
        repository: FitnessRepository,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.onCancel = onCancel
        self.onSaved = onSaved
        _viewModel = StateObject(
            wrappedValue: ProfileEditViewModel(repository: repository)
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                avatarSection
                nicknameField
                startDateField
                goalSection
                bioSection
                localNote
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .scrollDismissesKeyboard(.immediately)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
        .task { await viewModel.load() }
        .onChange(of: photoItem) { newItem in
            guard let newItem else { return }
            Task { await loadPhoto(newItem) }
        }
        .alert(
            "放弃修改？",
            isPresented: $showDiscardConfirm
        ) {
            Button("继续编辑", role: .cancel) { }
            Button("放弃修改", role: .destructive) { onCancel() }
        } message: {
            Text("有尚未保存的改动，放弃后将丢失。")
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: 导航栏

    private var navigationBar: some View {
        ZStack {
            HStack {
                Button("取消") {
                    handleCancel()
                }
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
                .accessibilityLabel("取消")

                Spacer(minLength: 0)

                Button("保存") {
                    handleSave()
                }
                .font(DS.Typography.body.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)
                .frame(height: DS.Size.minTapTarget)
                .contentShape(Rectangle())
                .accessibilityLabel("保存个人资料")
            }
            .padding(.horizontal, DS.Spacing.page)

            Text("个人资料")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    private func handleCancel() {
        if viewModel.hasUnsavedChanges {
            Haptics.warning()
            showDiscardConfirm = true
        } else {
            onCancel()
        }
    }

    private func handleSave() {
        if viewModel.save() {
            Haptics.success()
            onSaved()
        }
        // 失败时 errorMessage 已设置，由 alert 展示
    }

    // MARK: 头像

    private var avatarSection: some View {
        VStack(spacing: DS.Spacing.item) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                ProfileAvatarView(
                    imageData: viewModel.currentAvatarData,
                    nickname: viewModel.nicknameText,
                    size: 96
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("头像")
            .accessibilityHint("从系统相册选择照片")

            if viewModel.currentAvatarData != nil {
                Button("移除照片，恢复默认头像") {
                    viewModel.removeAvatar()
                }
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.accent)
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("移除照片，恢复默认头像")
            }

            Text("点击头像从相册选择照片，图片会压缩后保存在本机")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    /// 从系统相册读取并压缩照片，失败时保留原头像。
    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }

        guard let data = try? await item.loadTransferable(type: Data.self) else {
            viewModel.errorMessage = "无法读取所选照片，已保留原头像。"
            return
        }
        guard let image = UIImage(data: data) else {
            viewModel.errorMessage = "无法解析所选照片，已保留原头像。"
            return
        }
        guard let jpeg = Self.compressedJPEG(from: image) else {
            viewModel.errorMessage = "无法处理所选照片，已保留原头像。"
            return
        }
        viewModel.pickAvatar(jpeg)
    }

    /// 把照片缩到最长边不超过 512pt，再压成 JPEG，避免原图过大占满本地目录。
    private static func compressedJPEG(
        from image: UIImage,
        maxDimension: CGFloat = 512
    ) -> Data? {
        let original = image.size
        guard original.width > 0, original.height > 0 else { return nil }
        let longest = max(original.width, original.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: original.width * scale, height: original.height * scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.72)
    }

    // MARK: 昵称

    private var nicknameField: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("昵称")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)

                TextField("输入昵称", text: $viewModel.nicknameText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .tint(DS.Palette.accent)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .onChange(of: viewModel.nicknameText) { newValue in
                        if newValue.count > ProfileValidation.nicknameMaxLength {
                            viewModel.nicknameText = String(newValue.prefix(ProfileValidation.nicknameMaxLength))
                        }
                    }
                    .accessibilityLabel("昵称")

                HStack {
                    Text("留空则不显示昵称")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(viewModel.nicknameText.count)/\(ProfileValidation.nicknameMaxLength)")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .accessibilityLabel("已输入 \(viewModel.nicknameText.count) 个字符，上限 \(ProfileValidation.nicknameMaxLength)")
                }
            }
        }
    }

    // MARK: 训练开始日期

    private var startDateField: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("训练开始日期")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)

                DatePicker(
                    "训练开始日期",
                    selection: $viewModel.startedAt,
                    in: ...Date.now,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(DS.Palette.accent)
                .accessibilityLabel("训练开始日期")
            }
        }
    }

    // MARK: 训练目标

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            Text("训练目标")
                .font(DS.Typography.sectionTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            CardContainer {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    FlowChips(
                        items: TrainingGoal.allCases.map(\.title),
                        isSelected: { viewModel.trainingGoal?.title == $0 },
                        onTap: { title in
                            viewModel.trainingGoal = TrainingGoal.allCases.first { $0.title == title }
                            if viewModel.trainingGoal != .custom {
                                viewModel.customGoalText = ""
                            }
                        }
                    )

                    if viewModel.trainingGoal == .custom {
                        TextField("输入你的训练目标", text: $viewModel.customGoalText)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Palette.textPrimary)
                            .tint(DS.Palette.accent)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                    .fill(DS.Palette.fieldFill)
                            )
                            .accessibilityLabel("自定义训练目标")
                    }
                }
            }
        }
    }

    // MARK: 个人说明

    private var bioSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("个人说明")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)

                TextEditor(text: $viewModel.bioText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 100)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                            .fill(DS.Palette.fieldFill)
                    )
                    .onChange(of: viewModel.bioText) { newValue in
                        if newValue.count > ProfileValidation.bioMaxLength {
                            viewModel.bioText = String(newValue.prefix(ProfileValidation.bioMaxLength))
                        }
                    }
                    .accessibilityLabel("个人说明")

                HStack {
                    Text("仅用于本机展示")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(viewModel.bioText.count)/\(ProfileValidation.bioMaxLength)")
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .accessibilityLabel("已输入 \(viewModel.bioText.count) 个字符，上限 \(ProfileValidation.bioMaxLength)")
                }
            }
        }
    }

    // MARK: 本地资料说明

    private var localNote: some View {
        Text("这些资料仅保存在本设备，导出备份时可由你选择是否包含。")
            .font(DS.Typography.caption2)
            .foregroundStyle(DS.Palette.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Spacing.tight)
            .accessibilityLabel("本地资料说明：这些资料仅保存在本设备，导出备份时可由你选择是否包含。")
    }
}

// MARK: - 预览

#Preview("个人资料编辑") {
    ProfileEditView(
        repository: PreviewFitnessRepository(),
        onCancel: {},
        onSaved: {}
    )
    .preferredColorScheme(.dark)
}
