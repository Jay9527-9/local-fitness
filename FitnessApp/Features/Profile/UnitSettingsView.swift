//
//  UnitSettingsView.swift
//  页面 42：单位设置。
//
//  重量单位（kg/lb）、长度单位（cm/in）、有氧距离（公里/英里）三组单选。
//  所有单位只影响展示；内部原始数据始终以 kg、cm、m 保存，切换单位
//  不改写历史值、计划数据，也不重复换算写回。
//

import SwiftUI

struct UnitSettingsView: View {

    let onBack: () -> Void

    // UserDefaults 不参与 SwiftUI 依赖追踪，保留 @State 镜像即时反映。
    @State private var weightUnit = ProfileSettings.weightUnit
    @State private var lengthUnit = ProfileSettings.lengthUnit
    @State private var distanceUnit = ProfileSettings.cardioDistanceUnit

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                weightGroup
                lengthGroup
                distanceGroup
                explanation
            }
            .padding(.horizontal, DS.Spacing.page)
            .padding(.top, DS.Spacing.item)
            .padding(.bottom, DS.Spacing.section)
        }
        .background(DS.Palette.bg)
        .safeAreaInset(edge: .top, spacing: 0) { navigationBar }
        .navigationBarHidden(true)
    }

    // MARK: 重量单位

    private var weightGroup: some View {
        group(title: "重量单位") {
            ForEach(BodyWeightUnit.allCases) { unit in
                unitRow(
                    title: unit.title,
                    detail: unit.shortTitle,
                    selected: weightUnit == unit
                ) {
                    weightUnit = unit
                    ProfileSettings.weightUnit = unit
                }
                if unit != BodyWeightUnit.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }

    // MARK: 长度单位

    private var lengthGroup: some View {
        group(title: "长度单位") {
            ForEach(BodyLengthUnit.allCases) { unit in
                unitRow(
                    title: unit.title,
                    detail: "身体围度、身高",
                    selected: lengthUnit == unit
                ) {
                    lengthUnit = unit
                    ProfileSettings.lengthUnit = unit
                }
                if unit != BodyLengthUnit.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }

    // MARK: 有氧距离

    private var distanceGroup: some View {
        group(title: "有氧距离") {
            ForEach(DistanceUnit.allCases) { unit in
                unitRow(
                    title: unit.title,
                    detail: "距离与配速显示",
                    selected: distanceUnit == unit
                ) {
                    distanceUnit = unit
                    ProfileSettings.cardioDistanceUnit = unit
                }
                if unit != DistanceUnit.allCases.last {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
    }

    // MARK: 说明

    private var explanation: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text("内部原始数据始终以 kg、cm、m 保存。切换单位只改变显示格式，不会改写历史值、计划数据，也不会因反复换算产生累计误差。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Spacing.card)
    }

    // MARK: 复用

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

    private func unitRow(
        title: String,
        detail: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Palette.textPrimary)
                    Text(detail)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.textTertiary)
            }
            .padding(.horizontal, DS.Spacing.card)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityLabel("\(title)，\(detail)")
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

            Text("单位设置")
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

#Preview("单位设置") {
    UnitSettingsView(onBack: {})
        .preferredColorScheme(.dark)
}
