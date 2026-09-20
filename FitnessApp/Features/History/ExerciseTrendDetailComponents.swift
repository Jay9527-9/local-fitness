//
//  ExerciseTrendDetailComponents.swift
//  页面 11「动作历史趋势」的图表与卡片组件。
//
//  与页面 10 同一套手绘策略：**不引入 Swift Charts**。
//  这里额外多一条理由——本页的两张图都要「点击数据点看详情」，
//  手绘时每个点是一个 `Button`，命中区域就是它自己的 frame，
//  不需要像 Charts 那样在 `.chartOverlay` 里反算几何。
//
//  所有图形本身都 `.accessibilityHidden(true)`：
//  VoiceOver 读的是外层拼好的整句摘要，逐个形状朗读只会得到一串碎片。
//

import SwiftUI

// MARK: - 摘要指标格

/// 摘要卡里的一个字段。
///
/// 一行两个字段，用 `LazyVGrid`：动态字体调大时一行两个还能读，
/// 一行三个在最大档位下必然互相挤压。
struct TrendMetricCell: View {

    let title: String
    /// 已经格式化好的展示值，包含「—」
    let value: String
    /// 单位后缀，如「kg」。nil 表示这一格没有单位（日期）。
    var unit: String?
    /// 是否用强调色。本页只有「最高单组重量」用强调色。
    var isAccent: Bool = false
    /// 补充说明，如「按 8 次组估算」。
    var note: String?

    private var isPlaceholder: Bool { value == "—" }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: DS.Size.trendMetricFont, weight: .bold))
                    .foregroundStyle(
                        isPlaceholder
                            ? DS.Palette.textTertiary
                            : (isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let unit, !isPlaceholder {
                    Text(unit)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

            if let note {
                Text(note)
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(minHeight: DS.Size.trendMetricRowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard !isPlaceholder else { return "\(title)，无数据" }
        var text = "\(title) \(value)"
        if let unit { text += " \(unit)" }
        if let note { text += "，\(note)" }
        return text
    }
}

// MARK: - 单位切换器

/// kg / lb 切换。
///
/// 两个等宽胶囊，选中态用强调色描边 + 淡绿底。
/// 刻意不做成 `Picker(.segmented)`：系统分段控件在深色底上的选中态
/// 是它自己的蓝色调，跟本页的荧光绿不是一个色系。
struct TrendUnitToggle: View {

    @Binding var unit: TrendWeightUnit

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TrendWeightUnit.allCases) { option in
                Button {
                    Haptics.light()
                    unit = option
                } label: {
                    Text(option.shortTitle)
                        .font(DS.Typography.caption2)
                        .foregroundStyle(
                            unit == option ? DS.Palette.accent : DS.Palette.textTertiary
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: DS.Size.trendUnitToggleHeight)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .fill(unit == option ? DS.Palette.trendUnitSelected : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                                .stroke(
                                    unit == option ? DS.Palette.accent.opacity(0.5) : DS.Palette.stroke,
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(unit == option ? [.isSelected] : [])
            }
        }
        .frame(width: 116)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 最高重量折线图

/// 单个数据点（一个圆点 + 它的点击区）。
///
/// 点击区比圆点大得多：圆点直径只有 7pt，手指点不中。
/// 这里给每个点一个贯穿全高的不可见列，点这一列任意位置都算点中它。
private struct TrendWeightDot: View {

    let point: TrendWeightPoint
    let yRatio: CGFloat
    /// 绘图区实际高度（已扣掉上下内边距），由父视图从 GeometryReader 传进来。
    /// 不在这里自己算：图表总高与内边距的约定只在父视图里出现一次，
    /// 两边各算一次迟早会漂移，表现为圆点和折线端点对不上。
    let plotHeight: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    private var diameter: CGFloat {
        isSelected ? DS.Size.trendSelectedDotDiameter : DS.Size.trendDotDiameter
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // 贯穿整列的透明点击区：圆点只有 7pt，手指点不中
                Rectangle()
                    .fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Circle()
                    .fill(
                        point.hasWeight
                            ? (isSelected ? DS.Palette.trendSelected : DS.Palette.trendDot)
                            : DS.Palette.textTertiary
                    )
                    .frame(width: diameter, height: diameter)
                    // 选中时描一圈底色环，让它在细线上也能被看到
                    .overlay(
                        Circle()
                            .stroke(DS.Palette.bg, lineWidth: isSelected ? 2 : 0)
                    )
                    .offset(y: -(yRatio * plotHeight + DS.Size.trendChartVerticalPadding))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

/// 「最高重量趋势」折线图。
///
/// 折线用**二次贝塞尔**连接，与页面 10 的容量折线同一选择：
/// 三次样条会在相邻点之间过冲，把「中间某次没练到」画成一个凸起，
/// 视觉上像那次练得特别好。
///
/// 只有一个点时不画线，只画点——两点才能定义一条线，
/// 强行画会得到除零。
struct TrendWeightChart: View {

    let points: [TrendWeightPoint]
    @Binding var selectedID: UUID?

    /// 本图不接单位：折线是相对高度的形状，图上没有一个需要换算的数字——
    /// 选中详情与降级列表才带单位，它们各自从外层拿。
    /// 传进来一个用不到的参数是给下一个读代码的人留一个悬念。

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            GeometryReader { proxy in
                let width = max(0, proxy.size.width)
                let plotHeight = max(
                    0,
                    DS.Size.trendWeightChartHeight - DS.Size.trendChartVerticalPadding * 2
                )

                ZStack(alignment: .bottomLeading) {
                    gridLines(width: width, plotHeight: plotHeight)

                    if points.count > 1 {
                        TrendWeightLineShape(points: points, maxWeight: maxWeight)
                            .stroke(DS.Palette.trendWeightLine, lineWidth: 2)
                            .frame(width: width, height: DS.Size.trendWeightChartHeight)
                            .accessibilityHidden(true)
                    }

                    dotsRow(width: width, plotHeight: plotHeight)
                }
                .frame(width: width, height: DS.Size.trendWeightChartHeight)
            }
            .frame(height: DS.Size.trendWeightChartHeight)

            axisRow
        }
    }

    // MARK: 子组件

    /// 三条水平网格线。用 `Path` 画而不是叠三个 `Rectangle`：
    /// 后者在 `.drawingGroup` 之外会有细微的接缝。
    private func gridLines(width: CGFloat, plotHeight: CGFloat) -> some View {
        Path { path in
            for step in 0...2 {
                let y = DS.Size.trendChartVerticalPadding + plotHeight * CGFloat(step) / 2.0
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: width, y: y))
            }
        }
        .stroke(DS.Palette.statsGrid, lineWidth: 1)
        .accessibilityHidden(true)
    }

    private func dotsRow(width: CGFloat, plotHeight: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(points) { point in
                TrendWeightDot(
                    point: point,
                    yRatio: yRatio(for: point),
                    plotHeight: plotHeight,
                    isSelected: selectedID == point.id
                ) {
                    Haptics.light()
                    selectedID = (selectedID == point.id) ? nil : point.id
                }
                .frame(width: max(8, width / CGFloat(max(1, points.count))))
                .contentShape(Rectangle())
            }
        }
        .frame(width: width, height: DS.Size.trendWeightChartHeight)
    }

    /// 横轴日期标签。点多的时候隔一个显示一个，避免糊成一团。
    private var axisRow: some View {
        let step = points.count > 6 ? 2 : 1
        return HStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Text(index % step == 0 || index == points.count - 1 ? point.axisLabel : "")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: 计算

    /// 纵轴上界。全为自重（weight == 0）时给 1，避免除零。
    private var maxWeight: Double {
        let maxValue = points.map { $0.topWeight }.max() ?? 0
        return maxValue > 0 ? maxValue : 1
    }

    private func yRatio(for point: TrendWeightPoint) -> CGFloat {
        let maxValue = maxWeight
        guard maxValue > 0 else { return 0 }
        return CGFloat(min(1, max(0, point.topWeight / maxValue)))
    }
}

/// 连接各数据点的折线。
///
/// 二次贝塞尔：以相邻两点的中点为控制点，得到一条单调、不过冲的曲线。
private struct TrendWeightLineShape: Shape {

    let points: [TrendWeightPoint]
    let maxWeight: Double

    func path(in rect: CGRect) -> Path {
        guard points.count > 1, maxWeight > 0 else { return Path() }

        let inset = DS.Size.trendChartVerticalPadding
        let plotHeight = max(0, rect.height - inset * 2)

        func y(for value: Double) -> CGFloat {
            let ratio = CGFloat(min(1, max(0, value / maxWeight)))
            return rect.height - inset - ratio * plotHeight
        }

        /// 第 index 个点的横坐标。**与 `dotsRow` 的列宽算法必须一致**：
        /// 点画在每列正中，折线端点也接在列中心，两者才会严格重合。
        /// 写成 rect.width / count 而不是 /(count-1)，是因为圆点用的是
        /// 「均分整宽」的列布局，不是「首点贴左、末点贴右」的轴布局。
        func x(at index: Int) -> CGFloat {
            let columnWidth = rect.width / CGFloat(points.count)
            return columnWidth * CGFloat(index) + columnWidth / 2
        }

        var path = Path()
        path.move(to: CGPoint(x: x(at: 0), y: y(for: points[0].topWeight)))

        for index in 1..<points.count {
            let previous = CGPoint(x: x(at: index - 1), y: y(for: points[index - 1].topWeight))
            let current = CGPoint(x: x(at: index), y: y(for: points[index].topWeight))
            // 控制点取两点中点：得到一条单调、不过冲的曲线。
            // 不用三次样条——它会在峰值处冲出数据点，
            // 把「这次没练到」画成一个凸起。
            let control = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: current, control: control)
        }

        return path
    }
}

// MARK: - 单次训练容量柱状图

/// 一根容量柱。
///
/// 与折线图的圆点不同：柱宽 20pt 已经够看，规格也没要求柱子可点
/// （「点数据点看详情」只写在折线图那一条上），所以这里就是一个形状，
/// 不套 `Button`——套了就要给它编一个空 action，比不套更难解释。
private struct TrendVolumeBar: View {

    let point: TrendVolumePoint
    let maxVolume: Double

    private var ratio: CGFloat {
        guard maxVolume > 0, point.volume > 0 else { return 0 }
        return CGFloat(point.volume / maxVolume)
    }

    private var plotHeight: CGFloat {
        DS.Size.trendVolumeChartHeight - DS.Size.trendChartVerticalPadding
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(DS.Palette.trendVolumeBar)
                .frame(
                    width: DS.Size.trendBarMaxWidth,
                    height: max(DS.Size.trendBarMinWidth, ratio * plotHeight)
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

/// 「单次训练容量趋势」柱状图。
struct TrendVolumeChart: View {

    let points: [TrendVolumePoint]
    let unit: TrendWeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            // 峰值读数。柱子只表达相对高度，没有它的话单位切换在这张图上
            // 是看不出变化的——切换之后图长得一模一样，用户会以为没生效。
            peakRow

            GeometryReader { proxy in
                let width = max(0, proxy.size.width)

                ZStack(alignment: .bottomLeading) {
                    Path { path in
                        for step in 0...2 {
                            let y = DS.Size.trendChartVerticalPadding
                                + (DS.Size.trendVolumeChartHeight - DS.Size.trendChartVerticalPadding * 2)
                                * CGFloat(step) / 2.0
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: width, y: y))
                        }
                    }
                    .stroke(DS.Palette.statsGrid, lineWidth: 1)
                    .accessibilityHidden(true)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(points) { point in
                            TrendVolumeBar(point: point, maxVolume: maxVolume)
                                .frame(width: max(6, width / CGFloat(max(1, points.count))))
                        }
                    }
                    .frame(width: width, height: DS.Size.trendVolumeChartHeight)
                }
            }
            .frame(height: DS.Size.trendVolumeChartHeight)

            axisRow
        }
    }

    private var maxVolume: Double {
        let maxValue = points.map { $0.volume }.max() ?? 0
        return maxValue > 0 ? maxValue : 1
    }

    private var peakRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
            Text("峰值")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            Spacer(minLength: 0)

            // 空数据时 `maxVolume` 会兜底成 1，这里必须挡掉，
            // 否则会显示一个凭空出现的「1 kg」。
            Text(points.isEmpty ? "—" : unit.volumeText(fromKilograms: maxVolume))
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
                .lineLimit(1)
        }
        .accessibilityHidden(true)
    }

    private var axisRow: some View {
        let step = points.count > 6 ? 2 : 1
        return HStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                Text(index % step == 0 || index == points.count - 1 ? point.axisLabel : "")
                    .font(DS.Typography.caption2)
                    .foregroundStyle(DS.Palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 最近记录行

/// 「最近记录」列表的一行。
///
/// 可点击整行进入历史训练详情，所以整行是一个 `Button` 而不是
/// 在右侧挂一个 chevron —— 后者在这儿的命中区太小。
struct TrendRecentRecordRow: View {

    let record: ExerciseRecentRecord
    let unit: TrendWeightUnit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: DS.Spacing.item) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(FormatterKit.monthDaySlash(record.date))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)

                    Text(record.sessionName)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(record.bestSetText(unit: unit))
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .lineLimit(1)

                    Text("\(record.setCount) 组 · \(record.volumeText(unit: unit))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 8)
            .frame(minHeight: DS.Size.trendRecordRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.accessibilityLabel)
        .accessibilityHint("查看这次训练的完整记录")
    }
}

// MARK: - 选中数据点的详情条

/// 点击折线图上某个点后，在图上浮出的一行说明。
///
/// 用 `@ViewBuilder` 之外的普通 struct 是因为它有明确的非空契约：
/// 没有选中点时调用方根本不渲染它，不需要在内部处理 nil。
struct TrendSelectedDetail: View {

    let point: TrendWeightPoint
    let unit: TrendWeightUnit

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
            Text(FormatterKit.monthDaySlash(point.date))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            Text(point.bestSetText(unit: unit))
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)

            Spacer(minLength: 0)

            Text(point.sessionName)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.accent.opacity(0.10))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(FormatterKit.monthDaySlash(point.date))，\(point.bestSetText(unit: unit))，\(point.sessionName)"
        )
    }
}

// MARK: - 开始训练的确认抽屉内容

/// 「开始练这个动作」的确认内容。
///
/// 列出建议的重量 / 次数 / 组数 / 休息，并**明确写出这些数字来自哪里**。
/// 用户有权知道这是照抄上次还是 App 替他编的默认值。
struct TrendStartSuggestionContent: View {

    let exerciseName: String
    let suggestion: ExerciseStartSuggestion
    let unit: TrendWeightUnit
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("开始练这个动作")
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                Text(exerciseName)
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            VStack(spacing: 0) {
                row(title: "重量", value: suggestion.weightText(unit: unit))
                Divider().overlay(DS.Palette.stroke)
                row(title: "次数", value: suggestion.repsText)
                Divider().overlay(DS.Palette.stroke)
                row(title: "组数", value: "\(suggestion.sets)")
                Divider().overlay(DS.Palette.stroke)
                row(title: "组间休息", value: FormatterKit.rest(seconds: suggestion.restSeconds))
            }
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Palette.surface)
            )

            Text(suggestion.sourceText)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消", action: onCancel)
                PrimaryButton(title: "开始训练", action: onConfirm)
            }
        }
    }

    private func row(title: String, value: String) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Text(title)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)

            Spacer(minLength: 0)

            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.textPrimary)
        }
        .padding(.horizontal, DS.Spacing.card)
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(value)")
    }
}

// MARK: - 动态字体降级

/// 动态字体档位判定。
///
/// 规格要求「动态字体较大时自动降级为数据列表」。
/// 判据取 `isAccessibilityCategory` 而不是某个具体档位：
/// 系统把它设为 true 的那一刻，就是「文字已经大到图表装不下」的时刻。
enum TrendAccessibilityScale {

    /// 是否应当降级为列表。
    ///
    /// `sizeCategory` 是 `@Environment` 注入的，这里做成纯函数便于单测与复用。
    static func shouldUseList(_ category: ContentSizeCategory) -> Bool {
        category.isAccessibilityCategory
    }
}

/// 折线图在超大字体下的降级列表。
///
/// 与图共用同一组 `TrendWeightPoint`：降级只换渲染方式，不换数据，
/// 所以切换档位不会丢选中状态。
struct TrendWeightPointList: View {

    let points: [TrendWeightPoint]
    let unit: TrendWeightUnit

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: DS.Spacing.item) {
                    Text(point.axisLabel)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 46, alignment: .leading)

                    Text(point.sessionName)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: DS.Spacing.tight)

                    Text(point.bestSetText(unit: unit))
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(point.accessibilityLabel)

                if index < points.count - 1 {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 容量柱状图在超大字体下的降级列表。
struct TrendVolumePointList: View {

    let points: [TrendVolumePoint]
    let unit: TrendWeightUnit

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: DS.Spacing.item) {
                    Text(point.axisLabel)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 46, alignment: .leading)

                    Text(point.sessionName)
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textPrimary)
                        .lineLimit(1)

                    Spacer(minLength: DS.Spacing.tight)

                    Text("\(point.setCount) 组 · \(point.volumeText(unit: unit))")
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(point.accessibilityLabel)

                if index < points.count - 1 {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 骨架

struct TrendDetailSkeleton: View {
    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            SkeletonBlock(height: 150)
            SkeletonBlock(height: DS.Size.trendWeightChartHeight + 40)
            SkeletonBlock(height: DS.Size.trendVolumeChartHeight + 40)
        }
    }
}
