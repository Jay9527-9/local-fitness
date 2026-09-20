//
//  BodyDataComponents.swift
//  页面 12「身体数据」的图表与卡片组件。
//
//  与页面 10 / 11 同一套手绘策略：**不引入 Swift Charts**。
//  这里的折线图要「点击数据点看详情」，手绘时每个点是一个 `Button`，
//  命中区域就是它自己的 frame，不需要 `.chartOverlay` 反算几何。
//
//  所有图形本身都 `.accessibilityHidden(true)`：
//  VoiceOver 读的是外层拼好的整句摘要。
//

import SwiftUI

// MARK: - 指标 Chip 行

/// 七个指标的横向滚动 Chip 行。
///
/// 七个 Chip 在一行里放不下，必须横向滚动；用 `ScrollView(.horizontal)`
/// 而不是换行，保证用户能一屏扫到「该切到哪个指标」。
struct BodyMetricChipRow: View {

    let selected: BodyMetric
    let onSelect: (BodyMetric) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.tight) {
                ForEach(BodyMetric.allCases) { metric in
                    chip(metric)
                }
            }
            .padding(.horizontal, DS.Spacing.page)
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ metric: BodyMetric) -> some View {
        let isSelected = metric == selected
        return Button {
            Haptics.light()
            onSelect(metric)
        } label: {
            Text(metric.title)
                .font(DS.Typography.caption)
                .foregroundStyle(isSelected ? DS.Palette.onAccent : DS.Palette.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: DS.Size.bodyChipHeight)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? DS.Palette.accent : DS.Palette.surfaceElevated)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isSelected ? DS.Palette.accent : DS.Palette.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(metric.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - 单位切换

/// kg / lb 与 cm / in 两个切换器，合并成一行。
struct BodyUnitRow: View {

    @Binding var weightUnit: BodyWeightUnit
    @Binding var lengthUnit: BodyLengthUnit

    var body: some View {
        HStack(spacing: DS.Spacing.item) {
            HStack(spacing: DS.Spacing.tight) {
                Text("重量").font(DS.Typography.caption).foregroundStyle(DS.Palette.textTertiary)
                weightToggle
            }

            Divider().frame(height: 20).overlay(DS.Palette.stroke)

            HStack(spacing: DS.Spacing.tight) {
                Text("围度").font(DS.Typography.caption).foregroundStyle(DS.Palette.textTertiary)
                lengthToggle
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var weightToggle: some View {
        HStack(spacing: 0) {
            ForEach(BodyWeightUnit.allCases) { unit in
                Button {
                    Haptics.light()
                    weightUnit = unit
                } label: {
                    unitChip(unit.shortTitle, isSelected: unit == weightUnit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unit.title)
                .accessibilityAddTraits(unit == weightUnit ? [.isSelected] : [])
            }
        }
    }

    private var lengthToggle: some View {
        HStack(spacing: 0) {
            ForEach(BodyLengthUnit.allCases) { unit in
                Button {
                    Haptics.light()
                    lengthUnit = unit
                } label: {
                    unitChip(unit.shortTitle, isSelected: unit == lengthUnit)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(unit.title)
                .accessibilityAddTraits(unit == lengthUnit ? [.isSelected] : [])
            }
        }
    }

    private func unitChip(_ title: String, isSelected: Bool) -> some View {
        Text(title)
            .font(DS.Typography.caption2)
            .foregroundStyle(isSelected ? DS.Palette.accent : DS.Palette.textTertiary)
            .frame(width: 34, height: 26)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .fill(isSelected ? DS.Palette.trendUnitSelected : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                    .stroke(
                        isSelected ? DS.Palette.accent.opacity(0.5) : DS.Palette.stroke,
                        lineWidth: 1
                    )
            )
    }
}

// MARK: - 摘要卡

/// 顶部摘要卡：最近一次记录的体重 / 体脂率 / 日期 + 变化值 + 单位切换。
struct BodySummaryCard: View {

    let overview: BodyDataOverview
    @Binding var weightUnit: BodyWeightUnit
    @Binding var lengthUnit: BodyLengthUnit

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: DS.Spacing.item) {
                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                    Text("最近一次")
                        .font(DS.Typography.cardTitle)
                        .foregroundStyle(DS.Palette.textPrimary)

                    if !overview.isEmpty {
                        Text(overview.dateText)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Palette.textTertiary)
                    }

                    Spacer(minLength: 0)
                }

                if overview.isEmpty {
                    Text("还没有身体数据记录")
                        .font(DS.Typography.callout)
                        .foregroundStyle(DS.Palette.textTertiary)
                } else {
                    // 两列：体重 + 体脂率
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: DS.Spacing.item),
                            GridItem(.flexible(), spacing: DS.Spacing.item)
                        ],
                        spacing: DS.Spacing.item
                    ) {
                        metricCell(title: "体重", value: overview.weightText(unit: weightUnit), isAccent: true)
                        metricCell(title: "体脂率", value: overview.bodyFatText())
                    }

                    // 变化值。没有上一条可比较时整行不显示。
                    if overview.weightChangeText(unit: weightUnit) != nil
                        || overview.bodyFatChangeText() != nil {
                        VStack(alignment: .leading, spacing: 2) {
                            if let text = overview.weightChangeText(unit: weightUnit) {
                                changeLine(text)
                            }
                            if let text = overview.bodyFatChangeText() {
                                changeLine(text)
                            }
                        }
                    }
                }

                Divider().overlay(DS.Palette.stroke)
                BodyUnitRow(weightUnit: $weightUnit, lengthUnit: $lengthUnit)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(overview.accessibilityText)
    }

    private func metricCell(title: String, value: String, isAccent: Bool = false) -> some View {
        let isPlaceholder = value == "未记录"
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(value)
                .font(.system(size: DS.Size.bodyMetricFont, weight: .bold))
                .foregroundStyle(
                    isPlaceholder
                        ? DS.Palette.textTertiary
                        : (isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func changeLine(_ text: String) -> some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textSecondary)
    }
}

// MARK: - 趋势折线图

/// 单个数据点（圆点 + 贯穿全高的点击列）。
private struct BodyDot: View {

    let point: BodyMetricPoint
    let yRatio: CGFloat
    let plotHeight: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    private var diameter: CGFloat {
        isSelected ? DS.Size.bodySelectedDotDiameter : DS.Size.bodyDotDiameter
    }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                // 贯穿整列的透明点击区：圆点只有 7pt，手指点不中
                Rectangle().fill(Color.clear)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Circle()
                    .fill(isSelected ? DS.Palette.bodyChartSelected : DS.Palette.bodyChartDot)
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle().stroke(DS.Palette.bg, lineWidth: isSelected ? 2 : 0)
                    )
                    .offset(y: -(yRatio * plotHeight + DS.Size.bodyChartVerticalPadding))
            }
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}

/// 身体数据趋势折线图。
///
/// 纵轴按当前指标的值域**自动设置范围**，并上下各留 12pt 内边距，避免曲线贴边。
/// 上界取 `maxValue * 1.1`、下界取 `minValue * 0.9`，让折线始终处于可读区间；
/// 单条记录 / 全相等时上下界收敛，此时给一个最小跨度避免除零。
struct BodyTrendChart: View {

    let points: [BodyMetricPoint]
    @Binding var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.tight) {
            GeometryReader { proxy in
                let width = max(0, proxy.size.width)
                let plotHeight = max(0, DS.Size.bodyChartHeight - DS.Size.bodyChartVerticalPadding * 2)

                ZStack(alignment: .bottomLeading) {
                    gridLines(width: width, plotHeight: plotHeight)

                    if points.count > 1 {
                        BodyLineShape(points: points, yMin: yMin, yMax: yMax)
                            .stroke(DS.Palette.bodyChartLine, lineWidth: 2)
                            .frame(width: width, height: DS.Size.bodyChartHeight)
                            .accessibilityHidden(true)
                    }

                    dotsRow(width: width, plotHeight: plotHeight)
                }
                .frame(width: width, height: DS.Size.bodyChartHeight)
            }
            .frame(height: DS.Size.bodyChartHeight)

            axisRow
        }
    }

    // MARK: 子组件

    private func gridLines(width: CGFloat, plotHeight: CGFloat) -> some View {
        Path { path in
            for step in 0...2 {
                let y = DS.Size.bodyChartVerticalPadding + plotHeight * CGFloat(step) / 2.0
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
                BodyDot(
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
        .frame(width: width, height: DS.Size.bodyChartHeight)
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

    // MARK: 计算

    /// 值域下界。留 10% 下边距；全相等时给一个最小跨度。
    private var yMin: Double {
        let minValue = points.map { $0.rawValue }.min() ?? 0
        let span = yMax - minValue
        return span < 0.001 ? minValue - 1 : minValue - span * 0.1
    }

    /// 值域上界。留 10% 上边距。
    private var yMax: Double {
        let maxValue = points.map { $0.rawValue }.max() ?? 1
        return maxValue > 0 ? maxValue * 1.1 : 1
    }

    private func yRatio(for point: BodyMetricPoint) -> CGFloat {
        let span = yMax - yMin
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (point.rawValue - yMin) / span)))
    }
}

/// 连接各数据点的折线（二次贝塞尔，不过冲）。
private struct BodyLineShape: Shape {

    let points: [BodyMetricPoint]
    let yMin: Double
    let yMax: Double

    func path(in rect: CGRect) -> Path {
        guard points.count > 1 else { return Path() }

        let inset = DS.Size.bodyChartVerticalPadding
        let plotHeight = max(0, rect.height - inset * 2)
        let span = yMax - yMin

        func y(for value: Double) -> CGFloat {
            guard span > 0 else { return rect.height / 2 }
            let ratio = CGFloat(min(1, max(0, (value - yMin) / span)))
            return rect.height - inset - ratio * plotHeight
        }

        func x(at index: Int) -> CGFloat {
            let columnWidth = rect.width / CGFloat(points.count)
            return columnWidth * CGFloat(index) + columnWidth / 2
        }

        var path = Path()
        path.move(to: CGPoint(x: x(at: 0), y: y(for: points[0].rawValue)))

        for index in 1..<points.count {
            let previous = CGPoint(x: x(at: index - 1), y: y(for: points[index - 1].rawValue))
            let current = CGPoint(x: x(at: index), y: y(for: points[index].rawValue))
            let control = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            path.addQuadCurve(to: current, control: control)
        }

        return path
    }
}

// MARK: - 指标统计行

/// 图表下的「最新值 / 变化值 / 最低值 / 最高值」四格。
struct BodyStatGrid: View {

    let metric: BodyMetric
    let stats: BodyMetricStats
    let weightUnit: BodyWeightUnit
    let lengthUnit: BodyLengthUnit

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: DS.Spacing.item),
                GridItem(.flexible(), spacing: DS.Spacing.item)
            ],
            spacing: DS.Spacing.item
        ) {
            statCell(title: "最新值", value: stats.latestText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit), isAccent: true)
            statCell(title: "变化值", value: stats.changeText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit) ?? "—")
            statCell(title: "最低值", value: stats.minText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))
            statCell(title: "最高值", value: stats.maxText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))
        }
    }

    private func statCell(title: String, value: String, isAccent: Bool = false) -> some View {
        let isPlaceholder = value == "—"
        return VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Text(value)
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(
                    isPlaceholder ? DS.Palette.textTertiary : (isAccent ? DS.Palette.accent : DS.Palette.textPrimary)
                )
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - 选中点详情

/// 点击折线图上的点后浮出的一行说明：日期 + 数值。
struct BodySelectedDetail: View {

    let point: BodyMetricPoint
    let metric: BodyMetric
    let weightUnit: BodyWeightUnit
    let lengthUnit: BodyLengthUnit

    var body: some View {
        HStack(spacing: DS.Spacing.tight) {
            Text(FormatterKit.monthDaySlash(point.date))
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            Text(point.displayText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))
                .font(DS.Typography.callout.weight(.semibold))
                .foregroundStyle(DS.Palette.accent)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Spacing.item)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                .fill(DS.Palette.accent.opacity(0.10))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(FormatterKit.monthDaySlash(point.date))，\(point.displayText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))"
        )
    }
}

// MARK: - 记录卡片

/// 记录页的一张测量卡片。整行可点进入编辑。
struct BodyRecordCard: View {

    let measurement: BodyMeasurement
    let weightUnit: BodyWeightUnit
    let lengthUnit: BodyLengthUnit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(FormatterKit.fullDate(measurement.date))
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textPrimary)

                HStack(spacing: DS.Spacing.item) {
                    if let kg = measurement.weightKg {
                        metricTag("体重 \(BodyNumberFormat.decimal(weightUnit.displayValue(fromKilograms: kg))) \(weightUnit.shortTitle)", accent: true)
                    }
                    if let fat = measurement.bodyFatPercent {
                        metricTag("体脂 \(BodyNumberFormat.decimal(fat)) %")
                    }
                }

                // 已填写的围度，横向排成一行；没填的不显示。
                let lengths = circumferenceTags
                if !lengths.isEmpty {
                    HStack(spacing: DS.Spacing.tight) {
                        ForEach(lengths, id: \.self) { tag in
                            metricTag(tag)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Spacing.card)
            .frame(minHeight: DS.Size.bodyRecordRowHeight)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BodyDataBuilder.recordAccessibility(measurement, weightUnit: weightUnit, lengthUnit: lengthUnit))
        .accessibilityHint("点击编辑这条记录")
    }

    private var circumferenceTags: [String] {
        var tags: [String] = []
        if let v = measurement.chestCm {
            tags.append("胸围 \(BodyNumberFormat.decimal(lengthUnit.displayValue(fromCentimeters: v))) \(lengthUnit.shortTitle)")
        }
        if let v = measurement.waistCm {
            tags.append("腰围 \(BodyNumberFormat.decimal(lengthUnit.displayValue(fromCentimeters: v))) \(lengthUnit.shortTitle)")
        }
        if let v = measurement.hipCm {
            tags.append("臀围 \(BodyNumberFormat.decimal(lengthUnit.displayValue(fromCentimeters: v))) \(lengthUnit.shortTitle)")
        }
        if let v = measurement.thighCm {
            tags.append("大腿 \(BodyNumberFormat.decimal(lengthUnit.displayValue(fromCentimeters: v))) \(lengthUnit.shortTitle)")
        }
        if let v = measurement.armCm {
            tags.append("上臂 \(BodyNumberFormat.decimal(lengthUnit.displayValue(fromCentimeters: v))) \(lengthUnit.shortTitle)")
        }
        return tags
    }

    private func metricTag(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(DS.Typography.caption)
            .foregroundStyle(accent ? DS.Palette.accent : DS.Palette.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(accent ? DS.Palette.accent.opacity(0.12) : DS.Palette.surfaceElevated)
            )
    }
}

// MARK: - 录入面板内容

/// 新增 / 编辑面板的字段。
///
/// 面板自身持有文本状态：数值输入用 `String` 缓冲再解析，
/// 直接绑 `Double` 会在输入「80.」时跳字（项目既有约定）。
/// 所有数值字段可选；越界或非法输入在保存时统一拦截。
struct BodyEditorContent: View {

    /// 正在编辑的记录。nil 表示新增。
    let editing: BodyMeasurement?
    let onSave: (BodyMeasurement) -> Void

    @State private var date: Date = .now
    @State private var weightText: String = ""
    @State private var bodyFatText: String = ""
    @State private var chestText: String = ""
    @State private var waistText: String = ""
    @State private var hipText: String = ""
    @State private var thighText: String = ""
    @State private var armText: String = ""
    @State private var noteText: String = ""
    /// 越界 / 非法输入的提示。非空时在保存按钮上方显示。
    @State private var errorText: String?

    /// 编辑态：保留原 id，覆盖时用同一个 id（否则同日覆盖会产生新 id）。
    private var editingID: UUID?

    init(editing: BodyMeasurement?, onSave: @escaping (BodyMeasurement) -> Void) {
        self.editing = editing
        self.onSave = onSave
        self.editingID = editing?.id
        _date = State(initialValue: editing?.date ?? .now)
        _weightText = State(initialValue: editing?.weightKg.map { BodyNumberFormat.decimal($0) } ?? "")
        _bodyFatText = State(initialValue: editing?.bodyFatPercent.map { BodyNumberFormat.decimal($0) } ?? "")
        _chestText = State(initialValue: editing?.chestCm.map { BodyNumberFormat.decimal($0) } ?? "")
        _waistText = State(initialValue: editing?.waistCm.map { BodyNumberFormat.decimal($0) } ?? "")
        _hipText = State(initialValue: editing?.hipCm.map { BodyNumberFormat.decimal($0) } ?? "")
        _thighText = State(initialValue: editing?.thighCm.map { BodyNumberFormat.decimal($0) } ?? "")
        _armText = State(initialValue: editing?.armCm.map { BodyNumberFormat.decimal($0) } ?? "")
        _noteText = State(initialValue: editing?.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.item) {
            DatePicker("日期", selection: $date, displayedComponents: .date)
                .font(DS.Typography.callout)
                .tint(DS.Palette.accent)
                .foregroundStyle(DS.Palette.textPrimary)
                .accessibilityLabel("记录日期")

            fieldRow(label: "体重 (kg)", text: $weightText, placeholder: "如 74.2")
            fieldRow(label: "体脂率 (%)", text: $bodyFatText, placeholder: "如 16.4")
            fieldRow(label: "胸围 (cm)", text: $chestText, placeholder: "如 100")
            fieldRow(label: "腰围 (cm)", text: $waistText, placeholder: "如 80")
            fieldRow(label: "臀围 (cm)", text: $hipText, placeholder: "如 90")
            fieldRow(label: "大腿围 (cm)", text: $thighText, placeholder: "如 55")
            fieldRow(label: "上臂围 (cm)", text: $armText, placeholder: "如 35")

            noteField

            if let errorText {
                Text(errorText)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            PrimaryButton(title: "保存") {
                submit()
            }
        }
    }

    // MARK: 字段

    private func fieldRow(label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: DS.Spacing.item) {
            Text(label)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)
                .frame(width: 108, alignment: .leading)

            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("备注")
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textSecondary)

            TextField("选填", text: $noteText, axis: .vertical)
                .lineLimit(1...3)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Palette.textPrimary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.chip, style: .continuous)
                        .fill(DS.Palette.fieldFill)
                )
        }
    }

    // MARK: 提交

    /// 解析并校验全部字段，通过后组装一条记录交给上层。
    private func submit() {
        errorText = nil

        let weight = parse(weightText, metric: .weight)
        let bodyFat = parse(bodyFatText, metric: .bodyFat)
        let chest = parse(chestText, metric: .chest)
        let waist = parse(waistText, metric: .waist)
        let hip = parse(hipText, metric: .hip)
        let thigh = parse(thighText, metric: .thigh)
        let arm = parse(armText, metric: .arm)

        let draft = BodyMeasurement(
            id: editingID ?? UUID(),
            date: date,
            weightKg: weight,
            bodyFatPercent: bodyFat,
            chestCm: chest,
            waistCm: waist,
            hipCm: hip,
            thighCm: thigh,
            armCm: arm,
            note: noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        guard draft.hasAnyValue else {
            errorText = "请至少填写一个测量值"
            return
        }

        onSave(draft)
    }

    /// 解析数值。空串返回 nil（字段可选）；非法或越界时设置错误提示并返回哨兵。
    private func parse(_ text: String, metric: BodyMetric) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Double(trimmed), value.isFinite else {
            if errorText == nil { errorText = "\(metric.title)输入的不是数字" }
            return nil
        }
        guard BodyMeasurementValidation.isValid(value, for: metric) else {
            if errorText == nil { errorText = BodyMeasurementValidation.rangeText(for: metric) }
            return nil
        }
        return value
    }
}

// MARK: - 动态字体降级

/// 动态字体档位判定。规格要求「动态字体较大时自动降级为列表」。
enum BodyAccessibilityScale {
    static func shouldUseList(_ category: ContentSizeCategory) -> Bool {
        category.isAccessibilityCategory
    }
}

/// 折线图在超大字体下的降级列表。与图共用同一组 `BodyMetricPoint`。
struct BodyMetricPointList: View {

    let points: [BodyMetricPoint]
    let metric: BodyMetric
    let weightUnit: BodyWeightUnit
    let lengthUnit: BodyLengthUnit

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                HStack(spacing: DS.Spacing.item) {
                    Text(point.axisLabel)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Palette.textTertiary)
                        .frame(width: 46, alignment: .leading)

                    Text(point.displayText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))
                        .font(DS.Typography.callout.weight(.semibold))
                        .foregroundStyle(DS.Palette.accent)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
                .frame(minHeight: 40)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(point.accessibilityLabel(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))

                if index < points.count - 1 {
                    Divider().overlay(DS.Palette.stroke)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 骨架

struct BodyDataSkeleton: View {
    var body: some View {
        VStack(spacing: DS.Spacing.section) {
            SkeletonBlock(height: 150)
            SkeletonBlock(height: DS.Size.bodyChartHeight + 40)
        }
    }
}

// MARK: - 覆盖确认

/// 「同一天已有记录」时的确认内容：覆盖 or 取消。
struct BodyOverwriteConfirmContent: View {

    let existingDate: Date
    let onCancel: () -> Void
    let onOverwrite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("同一天已有记录")
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                Text("\(FormatterKit.shortDate(existingDate)) 已有一条身体数据记录。覆盖后当天的旧记录会被替换，避免同一天出现多条记录。")
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消", action: onCancel)
                PrimaryButton(title: "覆盖当天记录", action: onOverwrite)
            }
        }
    }
}

// MARK: - 删除确认

/// 删除一条记录前的二次确认。
struct BodyDeleteConfirmContent: View {

    let measurement: BodyMeasurement
    let weightUnit: BodyWeightUnit
    let lengthUnit: BodyLengthUnit
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.section) {
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text("删除这条记录？")
                    .font(DS.Typography.sectionTitle)
                    .foregroundStyle(DS.Palette.textPrimary)

                Text(FormatterKit.fullDate(measurement.date))
                    .font(DS.Typography.callout)
                    .foregroundStyle(DS.Palette.textSecondary)
            }

            Text("删除后无法恢复。")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textTertiary)

            HStack(spacing: DS.Spacing.item) {
                SecondaryButton(title: "取消", action: onCancel)
                PrimaryButton(title: "删除", action: onDelete)
            }
        }
    }
}
