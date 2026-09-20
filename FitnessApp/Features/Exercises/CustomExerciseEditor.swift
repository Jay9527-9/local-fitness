//
//  CustomExerciseEditor.swift
//  页面 23/24：新建 / 编辑自定义动作。
//
//  新建（editing == nil）与编辑（editing != nil）共用一份表单。
//  自定义动作没有第三方媒体，缩略图走 MuscleGlyph 代码绘制占位图，
//  因此不引入任何外部素材。保存时校验必填字段与重名；编辑时提供删除（含计划引用处理）。
//

import SwiftUI

struct CustomExerciseEditor: View {

    let repository: FitnessRepository
    /// 传入 nil 表示新建
    let editing: ExerciseLibraryItem?
    /// 保存回调。参数是整理好的动作对象（父级负责落盘与跳详情）。
    let onSaved: (ExerciseLibraryItem) -> Void
    /// 删除回调（仅编辑模式）。
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    // MARK: 表单字段

    @State private var name: String
    @State private var aliasText: String
    @State private var muscleCategory: String
    @State private var secondaryText: String
    @State private var equipmentZh: String
    @State private var equipment: String
    @State private var difficulty: ExerciseDifficulty
    @State private var steps: [String]
    @State private var defaultRestSeconds: Int
    @State private var note: String

    @State private var showNameError = false
    @State private var showDuplicateDialog = false
    @State private var showDiscardConfirm = false
    @State private var showDeleteConfirm = false
    @State private var showPlanConflictDialog = false
    @State private var showRestPicker = false
    /// 是否有未保存改动
    @State private var hasUnsavedChanges = false
    /// 非自定义动作误入时的只读标记
    @State private var isReadonly: Bool

    private static let muscleOptions = MuscleIconGroup.allCases
        .filter { $0 != .other }
        .map(\.title)

    private static let equipmentOptions = [
        ("自重", "body weight"), ("哑铃", "dumbbell"), ("杠铃", "barbell"),
        ("曲杠", "ez barbell"), ("绳索", "cable"), ("固定器械", "leverage machine"),
        ("史密斯", "smith machine"), ("壶铃", "kettlebell"), ("弹力带", "band"),
        ("负重", "weighted"), ("药球", "medicine ball"), ("瑜伽球", "stability ball"),
    ]

    init(
        repository: FitnessRepository,
        editing: ExerciseLibraryItem?,
        onSaved: @escaping (ExerciseLibraryItem) -> Void,
        onDeleted: @escaping () -> Void
    ) {
        self.repository = repository
        self.editing = editing
        self.onSaved = onSaved
        self.onDeleted = onDeleted

        _name = State(initialValue: editing?.name ?? "")
        _aliasText = State(initialValue: (editing?.aliases ?? []).joined(separator: "、"))
        _muscleCategory = State(
            initialValue: editing.map { MuscleIconGroup.of(muscle: $0.primaryMuscleText).title } ?? "胸")
        _secondaryText = State(
            initialValue: MuscleName.zhGroups(editing?.secondaryMuscles ?? []).joined(separator: "、"))
        _equipmentZh = State(initialValue: editing?.equipmentText ?? "自重")
        _equipment = State(initialValue: editing?.equipment ?? "body weight")
        _difficulty = State(initialValue: editing?.difficulty ?? .intermediate)
        _steps = State(initialValue: editing?.stepsZh ?? [])
        _defaultRestSeconds = State(initialValue: editing?.defaultRestSeconds ?? ProfileSettings.defaultRest)
        _note = State(initialValue: editing?.instructionsZh ?? "")
        _isReadonly = State(initialValue: editing.map { !$0.isCustom } ?? false)
    }

    private var isEditing: Bool { editing != nil }

    // MARK: 页面

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.section) {
                    if isReadonly {
                        readonlyBanner
                    } else {
                        basicCard
                        muscleCard
                        equipmentCard
                        stepsCard
                        restCard
                        noteCard
                        if isEditing { deleteSection }
                    }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.top, DS.Spacing.item)
                .padding(.bottom, DS.Spacing.section)
            }
            .background(DS.Palette.bg)
            .navigationTitle(isEditing ? "编辑动作" : "新建动作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { requestDismiss() }
                        .foregroundStyle(DS.Palette.textSecondary)
                        .accessibilityLabel("取消并返回")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .disabled(!isReadonly && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("保存动作")
                }
            }
            .alert("名称不能为空", isPresented: $showNameError) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("请给这个动作起一个名字，方便之后检索。")
            }
            .alert("已存在同名动作", isPresented: $showDuplicateDialog) {
                Button("取消", role: .cancel) {}
                Button("保存为副本") { saveItem(forceDuplicate: true) }
            } message: {
                Text("库中已有同名动作。可取消，或继续保存为自定义副本。")
            }
            .alert("放弃修改？", isPresented: $showDiscardConfirm) {
                Button("放弃", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            } message: {
                Text("当前有未保存的修改，确定要放弃吗？")
            }
            .alert("删除自定义动作", isPresented: $showDeleteConfirm) {
                Button("删除", role: .destructive) { confirmDelete() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后不可恢复，但不会影响已完成训练中保存的动作快照。")
            }
            .alert("该动作仍被计划引用", isPresented: $showPlanConflictDialog) {
                Button("仅从动作库隐藏", role: .cancel) { hideAndDismiss() }
                Button("同时从未来计划移除", role: .destructive) { deleteAndRemoveFromPlans() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除前请选择：仅隐藏，或同时从引用它的未来计划中移除。历史训练记录不受影响。")
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: name) { _ in hasUnsavedChanges = true }
        .onChange(of: aliasText) { _ in hasUnsavedChanges = true }
        .onChange(of: steps) { _ in hasUnsavedChanges = true }
        .onChange(of: note) { _ in hasUnsavedChanges = true }
    }

    // MARK: 只读提示

    private var readonlyBanner: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                Text("内置动作不可编辑")
                    .font(DS.Typography.cardTitle)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("内置导入的动作不支持编辑，可返回详情页改为收藏或隐藏。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SecondaryButton(title: "返回详情") { dismiss() }
            }
        }
    }

    // MARK: 基本信息

    private var basicCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                fieldLabel("名称", required: true)
                TextField("例如：单臂哑铃划船", text: $name)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Palette.fieldFill))
                    .accessibilityLabel("动作名称")
                    .onChange(of: name) { newValue in
                        if newValue.count > CustomExerciseValidation.nameMaxLength {
                            name = String(newValue.prefix(CustomExerciseValidation.nameMaxLength))
                        }
                    }
                Text("\(name.count)/\(CustomExerciseValidation.nameMaxLength)")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                fieldLabel("别名")
                TextField("用「、」分隔，便于中文检索", text: $aliasText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Palette.fieldFill))
                    .accessibilityLabel("动作别名")

                // 实时预览占位图
                HStack(spacing: DS.Spacing.item) {
                    MuscleGlyph(group: MuscleIconGroup.of(muscle: muscleCategory), size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(name.isEmpty ? "动作名称" : name)
                            .font(DS.Typography.body)
                            .foregroundStyle(name.isEmpty ? DS.Palette.textTertiary : DS.Palette.textPrimary)
                            .lineLimit(2)
                        Text("列表中的占位图预览")
                            .font(DS.Typography.caption2)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("占位图预览")
            }
        }
    }

    // MARK: 肌群

    private var muscleCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                fieldLabel("主肌群", required: true)
                // 单选 Chip：主肌群决定图标分组，也是 categoryZh / primaryMuscle。
                FlowChips(
                    items: Self.muscleOptions,
                    isSelected: { $0 == muscleCategory },
                    onTap: { muscleCategory = $0 }
                )

                fieldLabel("协同肌群")
                TextField("用「、」分隔", text: $secondaryText)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Palette.fieldFill))
                    .accessibilityLabel("协同肌群")
            }
        }
    }

    // MARK: 器械与难度

    private var equipmentCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                fieldLabel("器械")
                Picker("器械", selection: $equipmentZh) {
                    ForEach(Self.equipmentOptions, id: \.0) { option in
                        Text(option.0).tag(option.0)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.Palette.accent)
                .onChange(of: equipmentZh) { newValue in
                    if let match = Self.equipmentOptions.first(where: { $0.0 == newValue }) {
                        equipment = match.1
                    }
                }
                .accessibilityLabel("器械")

                fieldLabel("难度")
                Picker("难度", selection: $difficulty) {
                    ForEach(ExerciseDifficulty.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .tint(DS.Palette.accent)
                .accessibilityLabel("难度")

                HStack {
                    Text("负重性质")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textSecondary)
                    Spacer()
                    Text(LoadKind.of(equipment: equipment).title)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("负重性质由器械推导")
            }
        }
    }

    // MARK: 分步说明

    private var stepsCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack {
                    fieldLabel("动作说明（分步骤）")
                    Spacer()
                    Button {
                        steps.append("")
                        hasUnsavedChanges = true
                    } label: {
                        Label("添加步骤", systemImage: "plus.circle.fill")
                            .font(DS.Typography.footnote)
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加步骤")
                }

                if steps.isEmpty {
                    Text("还没有步骤，点「添加步骤」开始。")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(steps.indices, id: \.self) { index in
                        stepRow(index)
                    }
                }
            }
        }
    }

    private func stepRow(_ index: Int) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.tight) {
            Text("\(index + 1)")
                .font(DS.Typography.caption2)
                .foregroundStyle(DS.Palette.accent)
                .frame(width: 20, height: 36, alignment: .center)

            TextField("步骤 \(index + 1)", text: $steps[index])
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Palette.fieldFill))
                .accessibilityLabel("第 \(index + 1) 步")

            VStack(spacing: 2) {
                reorderButton(icon: "chevron.up", enabled: index > 0) {
                    steps.swapAt(index, index - 1)
                }
                reorderButton(icon: "chevron.down", enabled: index < steps.count - 1) {
                    steps.swapAt(index, index + 1)
                }
            }

            Button {
                steps.remove(at: index)
                hasUnsavedChanges = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Palette.danger)
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除第 \(index + 1) 步")
        }
        .accessibilityElement(children: .contain)
    }

    private func reorderButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            hasUnsavedChanges = true
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? DS.Palette.textSecondary : DS.Palette.textTertiary.opacity(0.4))
                .frame(width: 32, height: 17)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "chevron.up" ? "上移一步" : "下移一步")
    }

    // MARK: 默认休息

    private var restCard: some View {
        CardContainer {
            HStack(spacing: DS.Spacing.item) {
                fieldLabel("默认组间休息时间")
                Spacer()
                Button {
                    showRestPicker = true
                } label: {
                    Text(FormatterKit.rest(seconds: defaultRestSeconds))
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.accent)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("默认组间休息时间，当前 \(FormatterKit.rest(seconds: defaultRestSeconds))")
            }
        }
        .sheet(isPresented: $showRestPicker) {
            RestPickerSheet(initialSeconds: defaultRestSeconds) { seconds in
                defaultRestSeconds = seconds
                hasUnsavedChanges = true
                showRestPicker = false
            }
        }
    }

    // MARK: 备注

    private var noteCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                fieldLabel("备注")
                TextEditor(text: $note)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 88)
                    .accessibilityLabel("备注")
            }
        }
    }

    // MARK: 删除

    private var deleteSection: some View {
        Button {
            Haptics.warning()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: DS.Spacing.item) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Palette.danger)
                    .frame(width: 24)
                Text("删除自定义动作")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Palette.danger)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: DS.Radius.card).fill(DS.Palette.danger.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Palette.danger.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("删除自定义动作")
        .accessibilityHint("删除后不可恢复，但不影响历史训练记录")
    }

    // MARK: 辅助

    private func fieldLabel(_ text: String, required: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(text)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            if required {
                Text("*")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.danger)
            }
        }
    }

    private func requestDismiss() {
        if hasUnsavedChanges && !isReadonly {
            showDiscardConfirm = true
        } else {
            dismiss()
        }
    }

    // MARK: 保存

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showNameError = true
            return
        }

        // 重名检测：编辑时排除自身
        let all = (try? repository.fetchExercises(includeHidden: true)) ?? []
        if CustomExerciseValidation.hasDuplicateName(name, in: all, excludingID: editing?.id) {
            showDuplicateDialog = true
            return
        }
        saveItem(forceDuplicate: false)
    }

    private func saveItem(forceDuplicate: Bool) {
        let normalizedName = CustomExerciseValidation.normalizedName(name) ?? ""
        let aliases = aliasText
            .components(separatedBy: CharacterSet(charactersIn: "、,，/"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let secondary = secondaryText
            .components(separatedBy: CharacterSet(charactersIn: "、,，/"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let normalizedSteps = CustomExerciseValidation.normalizedSteps(steps)

        let item = ExerciseLibraryItem(
            id: editing?.id ?? "custom-\(UUID().uuidString)",
            name: normalizedName,
            aliases: aliases,
            category: editing?.category ?? "",
            categoryZh: muscleCategory,
            equipment: equipment,
            equipmentZh: equipmentZh,
            target: muscleCategoryToTarget(muscleCategory),
            primaryMuscle: muscleCategory,
            muscleGroup: editing?.muscleGroup ?? "",
            secondaryMuscles: secondary,
            difficulty: difficulty,
            instructionsZh: note.trimmingCharacters(in: .whitespacesAndNewlines),
            stepsZh: normalizedSteps,
            image: "",
            gifURL: "",
            attribution: "",
            mediaID: "",
            isCustom: true,
            isFavorite: editing?.isFavorite ?? false,
            favoritedAt: editing?.favoritedAt,
            isHidden: editing?.isHidden ?? false,
            defaultRestSeconds: defaultRestSeconds
        )

        onSaved(item)
        dismiss()
    }

    /// 肌群分组 → 数据源 target 英文标识。
    private func muscleCategoryToTarget(_ category: String) -> String {
        switch category {
        case "胸": return "pectorals"
        case "背": return "lats"
        case "肩": return "delts"
        case "手臂": return "biceps"
        case "核心": return "abs"
        case "腿": return "quads"
        case "臀": return "glutes"
        case "小腿": return "calves"
        case "有氧": return "cardiovascular system"
        case "颈": return "levator scapulae"
        default: return ""
        }
    }

    // MARK: 删除

    private func confirmDelete() {
        guard let editing else { return }
        let plans = (try? repository.fetchPlans()) ?? []
        let referencing = CustomExerciseDelete.plansReferencing(editing.id, in: plans)
        if referencing.isEmpty {
            performDelete()
        } else {
            showPlanConflictDialog = true
        }
    }

    private func performDelete() {
        guard let editing else { return }
        try? repository.deleteExercise(id: editing.id)
        onDeleted()
        dismiss()
    }

    private func hideAndDismiss() {
        guard let editing else { return }
        try? repository.toggleHidden(exerciseID: editing.id)
        onDeleted()
        dismiss()
    }

    private func deleteAndRemoveFromPlans() {
        guard let editing else { return }
        let plans = (try? repository.fetchPlans()) ?? []
        let updated = CustomExerciseDelete.removingReferences(toExercise: editing.id, from: plans)
        try? repository.replaceAllPlans(updated)
        try? repository.deleteExercise(id: editing.id)
        onDeleted()
        dismiss()
    }
}

// MARK: - 默认休息选择器

private struct RestPickerSheet: View {

    let initialSeconds: Int
    let onSelect: (Int) -> Void

    @State private var seconds: Int
    @State private var customText: String = ""
    @State private var isCustomActive = false

    init(initialSeconds: Int, onSelect: @escaping (Int) -> Void) {
        self.initialSeconds = initialSeconds
        self.onSelect = onSelect
        let matched = ProfileSettings.restPresets.contains(initialSeconds)
        _seconds = State(initialValue: initialSeconds)
        _customText = State(initialValue: matched ? "" : "\(initialSeconds)")
        _isCustomActive = State(initialValue: !matched)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.item) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.tight), count: 3), spacing: DS.Spacing.tight) {
                        ForEach(ProfileSettings.restPresets, id: \.self) { value in
                            presetCell(value)
                        }
                    }
                    customField
                }
                .padding(DS.Spacing.card)
            }
            .background(DS.Palette.bg)
            .navigationTitle("默认组间休息时间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onSelect(initialSeconds) }
                        .foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PrimaryButton(title: "确定") {
                    if isCustomActive {
                        let parsed = Int(customText) ?? 0
                        onSelect(max(5, parsed))
                    } else {
                        onSelect(seconds)
                    }
                }
                .padding(.horizontal, DS.Spacing.page)
                .padding(.vertical, DS.Spacing.item)
                .background(DS.Palette.bg)
            }
        }
        .presentationDetents([.medium])
    }

    private func presetCell(_ value: Int) -> some View {
        let selected = !isCustomActive && seconds == value
        return Button {
            seconds = value
            isCustomActive = false
            customText = ""
        } label: {
            Text(FormatterKit.rest(seconds: value))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(selected ? DS.Palette.accent : DS.Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.chip).stroke(selected ? Color.clear : DS.Palette.stroke, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("\(value) 秒")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var customField: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text("自定义")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
            TextField("秒", text: $customText)
                .keyboardType(.numberPad)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .multilineTextAlignment(.trailing)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: DS.Radius.chip).fill(DS.Palette.fieldFill))
                .onTapGesture { isCustomActive = true }
        }
    }
}

// MARK: - 预览

#Preview("新建自定义动作") {
    CustomExerciseEditor(
        repository: PreviewFitnessRepository(),
        editing: nil,
        onSaved: { _ in },
        onDeleted: {}
    )
    .preferredColorScheme(.dark)
}
