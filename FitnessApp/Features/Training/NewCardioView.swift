//
//  NewCardioView.swift
//  页面 30：新建有氧训练设置。
//
//  手动录入：运动类型、目标类型与目标值、备注、可选「保存为个人模板」。
//  默认不使用 GPS、健康平台、蓝牙或网络；点「开始」校验后创建
//  `WorkoutSession(kind: .cardio)` 草稿并进入有氧训练执行页。
//

import SwiftUI

@MainActor
final class NewCardioViewModel: ObservableObject {

    @Published var setup = CardioSetup()

    private let repository: FitnessRepository

    init(repository: FitnessRepository) {
        self.repository = repository
    }

    /// 校验并创建有氧训练草稿。失败返回 nil。
    @discardableResult
    func createDraft() -> WorkoutSession? {
        guard CardioSetupValidation.validationError(setup) == nil else { return nil }
        let name = CardioSetupValidation.normalizedName(setup.name)
        let note = CardioSetupValidation.composedNote(setup)
        let draft = WorkoutSession(name: name, kind: .cardio, note: note)
        do {
            try repository.save(session: draft)
            return draft
        } catch {
            return nil
        }
    }
}

struct NewCardioView: View {

    @StateObject private var viewModel: NewCardioViewModel
    let onCancel: () -> Void
    let onStart: (UUID) -> Void

    @State private var goalValueText: String = ""

    init(
        repository: FitnessRepository,
        onCancel: @escaping () -> Void,
        onStart: @escaping (UUID) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: NewCardioViewModel(repository: repository))
        self.onCancel = onCancel
        self.onStart = onStart
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                nameField
                sportSection
                goalSection
                noteSection
                templateToggle
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .navigationBarHidden(true)
    }

    // MARK: 顶部栏

    private var navigationBar: some View {
        HStack(spacing: DS.Spacing.item) {
            Button {
                Haptics.light()
                onCancel()
            } label: {
                Text("取消")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取消新建有氧训练")

            Spacer(minLength: DS.Spacing.item)

            Text("新建有氧训练")
                .font(DS.Typography.cardTitle)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: DS.Spacing.item)

            Button {
                Haptics.light()
                start()
            } label: {
                Text("开始")
                    .font(DS.Typography.callout.weight(.semibold))
                    .foregroundStyle(DS.Palette.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("开始有氧训练")
        }
        .padding(.horizontal, DS.Spacing.page)
        .frame(height: DS.Size.sessionBarHeight)
        .background(
            DS.Palette.bg.overlay(alignment: .bottom) {
                Rectangle().fill(DS.Palette.stroke).frame(height: 1)
            }
        )
    }

    // MARK: 名称

    private var nameField: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            fieldLabel("训练名称")
            TextField("例如：晨跑 5 公里", text: $viewModel.setup.name)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .stroke(DS.Palette.stroke, lineWidth: 1)
                )
                .accessibilityLabel("训练名称")
        }
    }

    // MARK: 运动类型

    private var sportSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            fieldLabel("运动类型")

            FlowChips(
                items: CardioSport.allCases.map(\.title),
                isSelected: { title in
                    CardioSport.allCases.first { $0.title == title } == viewModel.setup.sport
                }
            ) { title in
                if let sport = CardioSport.allCases.first(where: { $0.title == title }) {
                    viewModel.setup.sport = sport
                }
            }
        }
    }

    // MARK: 目标

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            fieldLabel("目标类型")

            Picker("目标类型", selection: $viewModel.setup.goalKind) {
                ForEach(CardioGoalKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("目标类型")

            if viewModel.setup.goalKind.requiresGoalValue {
                HStack(spacing: DS.Spacing.tight) {
                    TextField("目标数值", text: $goalValueText)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .keyboardType(.decimalPad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(DS.Palette.fieldFill)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(DS.Palette.stroke, lineWidth: 1)
                        )
                        .accessibilityLabel("目标数值")

                    Text(viewModel.setup.goalKind.unitText)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
            }
        }
    }

    // MARK: 备注

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            fieldLabel("备注（可选）")

            TextEditor(text: Binding(
                get: { viewModel.setup.note ?? "" },
                set: { viewModel.setup.note = $0 }
            ))
            .font(DS.Typography.body)
            .foregroundStyle(DS.Palette.textPrimary)
            .frame(minHeight: 72)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(DS.Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(DS.Palette.stroke, lineWidth: 1)
            )
            .accessibilityLabel("备注")
        }
    }

    // MARK: 保存为模板

    private var templateToggle: some View {
        HStack(alignment: .center, spacing: DS.Spacing.item) {
            VStack(alignment: .leading, spacing: 2) {
                Text("保存为个人模板")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)
                Text("完成训练后询问是否保存本次参数为模板")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Spacing.tight)
            Toggle("", isOn: $viewModel.setup.saveAsTemplate)
                .labelsHidden()
                .tint(DS.Palette.accent)
                .accessibilityLabel("保存为个人模板")
        }
        .padding(DS.Spacing.item)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Palette.stroke, lineWidth: 1)
        )
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(DS.Palette.stroke)
            PrimaryButton(title: "开始", icon: "figure.run") {
                Haptics.light()
                start()
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.vertical, DS.Spacing.item)
        }
        .background(DS.Palette.bg)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Palette.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }

    /// 校验并开始：把目标值写回 setup 后创建草稿，再交给上层推进执行页。
    private func start() {
        viewModel.setup.goalValue = Double(goalValueText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let draft = viewModel.createDraft() else {
            return
        }
        onStart(draft.id)
    }
}

// MARK: - 预览

#Preview("新建有氧训练") {
    NewCardioView(
        repository: PreviewFitnessRepository(),
        onCancel: {},
        onStart: { _ in }
    )
    .preferredColorScheme(.dark)
}
