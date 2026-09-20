//
//  BodyData.swift
//  页面 12「身体数据」的值语义层。
//
//  **这个文件不 import SwiftUI**，全部是纯值类型与静态函数。
//  理由与 `HistoryCalendar.swift` / `ExerciseTrendDetail.swift` 一致：
//  本机没有 Swift 编译器，纯值层可以逐字照搬成 Python 做断言推演
//  （见 `Tools/probe_page12_semantics.py`）。
//
//  核心契约（贯穿全页）：
//  1. **内部统一存 kg 与 cm**，kg/lb、cm/in 只做展示换算，绝不回写原始值。
//  2. **「未记录」不等于「0」**：字段缺失显示「未记录」/「—」，
//     而不是 0——0 公斤体重是医学上不成立的读数。
//  3. **同日唯一键**：一个自然日只保留一条记录，趋势才不会有歧义。
//

import Foundation

// MARK: - 指标

/// 身体数据页的七个指标，与规格的 Chip 顺序一致。
///
/// 体重用重量单位、体脂率用百分比、其余五项围度用长度单位，
/// 三类量的换算口径不同，这里集中到一个枚举里，避免各处重复判断。
enum BodyMetric: String, CaseIterable, Identifiable, Equatable {
    case weight
    case bodyFat
    case chest
    case waist
    case hip
    case thigh
    case arm

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "体重"
        case .bodyFat: return "体脂率"
        case .chest: return "胸围"
        case .waist: return "腰围"
        case .hip: return "臀围"
        case .thigh: return "大腿围"
        case .arm: return "上臂围"
        }
    }

    var isWeight: Bool { self == .weight }
    var isPercent: Bool { self == .bodyFat }
    var isLength: Bool { !isWeight && !isPercent }

    /// 单位后缀：体重随重量单位、体脂率固定 %、围度随长度单位。
    func unitShort(weightUnit: BodyWeightUnit, lengthUnit: BodyLengthUnit) -> String {
        if isWeight { return weightUnit.shortTitle }
        if isPercent { return "%" }
        return lengthUnit.shortTitle
    }

    /// 从一条记录里取该指标的**原始值**（kg / cm / %）。
    /// 字段为 nil 时返回 nil——这是「未记录」与「0」分界的唯一依据。
    func rawValue(of measurement: BodyMeasurement) -> Double? {
        switch self {
        case .weight: return measurement.weightKg
        case .bodyFat: return measurement.bodyFatPercent
        case .chest: return measurement.chestCm
        case .waist: return measurement.waistCm
        case .hip: return measurement.hipCm
        case .thigh: return measurement.thighCm
        case .arm: return measurement.armCm
        }
    }

    /// 换算成展示值的纯函数。只读不改，绝不回写。
    func displayValue(
        of measurement: BodyMeasurement,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> Double? {
        guard let raw = rawValue(of: measurement) else { return nil }
        return displayValue(fromRaw: raw, weightUnit: weightUnit, lengthUnit: lengthUnit)
    }

    func displayValue(
        fromRaw raw: Double,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> Double {
        if isWeight { return weightUnit.displayValue(fromKilograms: raw) }
        if isPercent { return raw }
        return lengthUnit.displayValue(fromCentimeters: raw)
    }

    /// 展示文案，如「74.2 kg」「16.4 %」「80.5 cm」。无值返回「未记录」。
    func displayText(
        of measurement: BodyMeasurement,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        guard let value = displayValue(of: measurement, weightUnit: weightUnit, lengthUnit: lengthUnit) else {
            return "未记录"
        }
        return "\(BodyNumberFormat.decimal(value)) \(unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }
}

// MARK: - 单位

/// 重量单位。**只影响展示，绝不回写原始记录。**
///
/// 与页面 11 的 `TrendWeightUnit` 同一条契约：连一个 `mutating` 方法都没有，
/// 全部是纯函数，杜绝「把换算结果当真写回」的路径。
enum BodyWeightUnit: String, CaseIterable, Identifiable, Equatable {
    case kilograms
    case pounds

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .kilograms: return "kg"
        case .pounds: return "lb"
        }
    }

    var title: String {
        switch self {
        case .kilograms: return "公斤"
        case .pounds: return "磅"
        }
    }

    /// 1 kg = 2.20462262185 lb
    static let poundsPerKilogram: Double = 2.204_622_621_85

    /// 把「以 kg 记录的原始值」换算成本单位的展示值。kg 原样返回，不舍入——
    /// 舍入在格式化时做，图表若连算两次会把误差累积进去。
    func displayValue(fromKilograms value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .pounds: return value * Self.poundsPerKilogram
        }
    }
}

/// 长度单位（围度）。只影响展示。
enum BodyLengthUnit: String, CaseIterable, Identifiable, Equatable {
    case centimeters
    case inches

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .centimeters: return "cm"
        case .inches: return "in"
        }
    }

    var title: String {
        switch self {
        case .centimeters: return "厘米"
        case .inches: return "英寸"
        }
    }

    /// 1 cm = 0.3937007874 in
    static let inchesPerCentimeter: Double = 0.393_700_787_4

    func displayValue(fromCentimeters value: Double) -> Double {
        switch self {
        case .centimeters: return value
        case .inches: return value * Self.inchesPerCentimeter
        }
    }
}

// MARK: - 数值格式化

/// 身体数据的数值格式化。单独抽出来便于 Python 照搬。
enum BodyNumberFormat {

    /// 保留 1 位小数，整数不带 `.0`。体重 / 围度 / 体脂率共用同一规则。
    ///
    /// 磅 / 英寸换算后 `74.2 kg` 会变成 `163.6 lb`，显示成 `164` 会让人以为精度丢了。
    static func decimal(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}

// MARK: - 趋势点

/// 趋势图上的一个点 = 某一天该指标的测量值。
///
/// 与页面 11 的「按训练聚合」不同：身体数据天然一条记录一个值，
/// 所以点直接对应一条 `BodyMeasurement`，日期就是记录日期。
struct BodyMetricPoint: Identifiable, Equatable {
    let measurementID: UUID
    let date: Date
    /// 原始值（kg / cm / %）。换算在展示层做。
    let rawValue: Double

    var id: UUID { measurementID }

    var axisLabel: String { FormatterKit.monthDaySlash(date) }

    func displayText(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        let value = metric.displayValue(fromRaw: rawValue, weightUnit: weightUnit, lengthUnit: lengthUnit)
        return "\(BodyNumberFormat.decimal(value)) \(metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }

    func accessibilityLabel(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        "\(FormatterKit.monthDaySlash(date))，\(displayText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }
}

// MARK: - 顶部摘要卡

/// 顶部摘要卡的内容。
///
/// 所有「算不出来」的字段都是 Optional，与统计页 `StatsMetric.value: String?`
/// 同一套语义：**算不出来显示「未记录」，算出来是 0 才显示 0**。
struct BodyDataOverview: Equatable {

    /// 最近一条记录的日期。没有任何记录时为 nil。
    let latestDate: Date?
    /// 最近一条记录的体重（kg）。那条记录没填体重时为 nil。
    let weightKg: Double?
    /// 最近一条记录的体脂率（%）。
    let bodyFatPercent: Double?
    /// 体重相对上一条有体重的记录的变化（kg）。最近一条没体重、或没有上一条时为 nil。
    let weightChangeKg: Double?
    /// 体脂率变化（%）。同上。
    let bodyFatChange: Double?

    var isEmpty: Bool { latestDate == nil }

    func weightText(unit: BodyWeightUnit) -> String {
        guard let kg = weightKg else { return "未记录" }
        return "\(BodyNumberFormat.decimal(unit.displayValue(fromKilograms: kg))) \(unit.shortTitle)"
    }

    func bodyFatText() -> String {
        guard let percent = bodyFatPercent else { return "未记录" }
        return "\(BodyNumberFormat.decimal(percent)) %"
    }

    var dateText: String {
        guard let date = latestDate else { return "—" }
        return FormatterKit.shortDate(date)
    }

    /// 体重变化文案，如「较上次 −0.6 kg」/「较上次 +0.3 kg」/「较上次持平」。
    /// 无变化数据（最近一条没体重、或没有上一条）时返回 nil，UI 不显示这一行。
    func weightChangeText(unit: BodyWeightUnit) -> String? {
        guard let delta = weightChangeKg else { return nil }
        return "较上次 \(Self.deltaText(delta, unit: unit.shortTitle))"
    }

    func bodyFatChangeText() -> String? {
        guard let delta = bodyFatChange else { return nil }
        return "较上次 \(Self.deltaText(delta, unit: "%"))"
    }

    /// 变化值的带符号文案。正值加 +，负值自带 −，零显示「持平」。
    private static func deltaText(_ delta: Double, unit: String) -> String {
        guard abs(delta) >= 0.05 else { return "持平" }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(BodyNumberFormat.decimal(abs(delta))) \(unit)"
    }

    var accessibilityText: String {
        guard !isEmpty else { return "还没有身体数据记录" }
        var parts = [weightText(unit: .kilograms), bodyFatText()]
        if let change = weightChangeKg {
            parts.append("体重较上次 \(Self.deltaText(change, unit: "公斤"))")
        }
        parts.append("记录日期 \(dateText)")
        return parts.joined(separator: "，") + "。"
    }
}

// MARK: - 指标统计

/// 选中指标的「最新值 / 变化值 / 最低值 / 最高值」。
struct BodyMetricStats: Equatable {
    /// 该指标最近一次的值（原始值）。
    let latestValue: Double?
    /// 该指标最近一次的日期。
    let latestDate: Date?
    /// 相对上一条的变化（原始值）。
    let change: Double?
    /// 全期最低（原始值）。
    let minValue: Double?
    /// 全期最高（原始值）。
    let maxValue: Double?

    func latestText(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        guard let value = latestValue else { return "—" }
        let display = metric.displayValue(fromRaw: value, weightUnit: weightUnit, lengthUnit: lengthUnit)
        return "\(BodyNumberFormat.decimal(display)) \(metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }

    func changeText(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String? {
        guard let delta = change else { return nil }
        let unit = metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit)
        guard abs(delta) >= 0.05 else { return "持平" }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(BodyNumberFormat.decimal(abs(delta))) \(unit)"
    }

    func minText(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        guard let value = minValue else { return "—" }
        let display = metric.displayValue(fromRaw: value, weightUnit: weightUnit, lengthUnit: lengthUnit)
        return "\(BodyNumberFormat.decimal(display)) \(metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }

    func maxText(
        metric: BodyMetric,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        guard let value = maxValue else { return "—" }
        let display = metric.displayValue(fromRaw: value, weightUnit: weightUnit, lengthUnit: lengthUnit)
        return "\(BodyNumberFormat.decimal(display)) \(metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit))"
    }
}

// MARK: - 输入校验

/// 录入面板的范围校验。
///
/// 规格只给了两个例子（体重 20–400、体脂率 1–70），围度也需要一个合理范围，
/// 否则用户能输入 5 cm 的胸围或 9999 cm 的腰围。取 20–300 cm，
/// 覆盖从极瘦到极壮的所有成年人。
enum BodyMeasurementValidation {

    static let weightRange: ClosedRange<Double> = 20...400
    static let bodyFatRange: ClosedRange<Double> = 1...70
    static let lengthRange: ClosedRange<Double> = 20...300

    static func validRange(for metric: BodyMetric) -> ClosedRange<Double>? {
        switch metric {
        case .weight: return weightRange
        case .bodyFat: return bodyFatRange
        default: return lengthRange
        }
    }

    static func isValid(_ value: Double, for metric: BodyMetric) -> Bool {
        guard let range = validRange(for: metric), value.isFinite else { return false }
        return range.contains(value)
    }

    /// 越界时的提示文案，如「体重需在 20–400 kg 之间」。
    static func rangeText(for metric: BodyMetric) -> String {
        guard let range = validRange(for: metric) else { return "" }
        let unit = metric == .weight ? "kg" : (metric == .bodyFat ? "%" : "cm")
        return "\(metric.title)需在 \(BodyNumberFormat.decimal(range.lowerBound))–\(BodyNumberFormat.decimal(range.upperBound)) \(unit) 之间"
    }
}

// MARK: - 聚合

/// 页面 12 的全部聚合。
enum BodyDataBuilder {

    /// 单次读取的原始记录上限，与全站一致。
    static let fetchLimit = 500

    /// 该指标的全部趋势点，按日期从旧到新。只含「有该指标」的记录——
    /// 不补空日：身体数据不是每天必测，补 0 会把「没测」画成「值降到 0」。
    static func points(
        for metric: BodyMetric,
        measurements: [BodyMeasurement]
    ) -> [BodyMetricPoint] {
        measurements
            .compactMap { measurement -> BodyMetricPoint? in
                guard let value = metric.rawValue(of: measurement) else { return nil }
                return BodyMetricPoint(
                    measurementID: measurement.id,
                    date: measurement.date,
                    rawValue: value
                )
            }
            .sorted { $0.date < $1.date }
    }

    /// 顶部摘要卡。最近一条记录取「日期最大」的那条，字段缺什么显示什么。
    ///
    /// 变化值：与「上一条有体重的记录」相比。最近一条记录自己没体重时，
    /// 变化为 nil（没有可比较的基准）。体脂率同理。
    static func overview(measurements: [BodyMeasurement]) -> BodyDataOverview {
        guard let latest = measurements.max(by: { $0.date < $1.date }) else {
            return BodyDataOverview(
                latestDate: nil, weightKg: nil, bodyFatPercent: nil,
                weightChangeKg: nil, bodyFatChange: nil
            )
        }

        let byDateDesc = measurements.sorted { $0.date > $1.date }
        // dropFirst 跳过最近那条本身，再找上一条有该字段的记录。
        let weightChange: Double?
        if let latestWeight = latest.weightKg {
            let previous = byDateDesc.dropFirst().first { $0.weightKg != nil }?.weightKg
            weightChange = previous.map { latestWeight - $0 }
        } else {
            weightChange = nil
        }

        let fatChange: Double?
        if let latestFat = latest.bodyFatPercent {
            let previous = byDateDesc.dropFirst().first { $0.bodyFatPercent != nil }?.bodyFatPercent
            fatChange = previous.map { latestFat - $0 }
        } else {
            fatChange = nil
        }

        return BodyDataOverview(
            latestDate: latest.date,
            weightKg: latest.weightKg,
            bodyFatPercent: latest.bodyFatPercent,
            weightChangeKg: weightChange,
            bodyFatChange: fatChange
        )
    }

    /// 选中指标的「最新 / 变化 / 最低 / 最高」。
    static func stats(
        for metric: BodyMetric,
        measurements: [BodyMeasurement]
    ) -> BodyMetricStats {
        let values = measurements
            .compactMap { metric.rawValue(of: $0) }
        guard !values.isEmpty else {
            return BodyMetricStats(
                latestValue: nil, latestDate: nil, change: nil, minValue: nil, maxValue: nil
            )
        }

        let points = Self.points(for: metric, measurements: measurements)
        let latest = points.last
        let change: Double?
        if points.count >= 2 {
            change = (latest?.rawValue ?? 0) - (points[points.count - 2].rawValue)
        } else {
            change = nil
        }

        return BodyMetricStats(
            latestValue: latest?.rawValue,
            latestDate: latest?.date,
            change: change,
            minValue: values.min(),
            maxValue: values.max()
        )
    }

    /// 趋势图的 VoiceOver 摘要。不足两条记录时给一句「记录更多数据后可查看趋势」。
    static func trendSummary(
        metric: BodyMetric,
        points: [BodyMetricPoint],
        stats: BodyMetricStats,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        guard points.count >= 2 else {
            return "\(metric.title)记录更多数据后可查看趋势。"
        }
        var parts = ["\(metric.title)趋势，共 \(points.count) 次记录"]
        parts.append("最新 \(stats.latestText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))")
        if let change = stats.changeText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit) {
            parts.append("较上次 \(change)")
        }
        parts.append("最低 \(stats.minText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))")
        parts.append("最高 \(stats.maxText(metric: metric, weightUnit: weightUnit, lengthUnit: lengthUnit))")
        return parts.joined(separator: "，") + "。"
    }

    /// 一条记录卡片的无障碍标签：日期 + 已填写的字段，未填的跳过。
    static func recordAccessibility(
        _ measurement: BodyMeasurement,
        weightUnit: BodyWeightUnit,
        lengthUnit: BodyLengthUnit
    ) -> String {
        var parts = [FormatterKit.shortDate(measurement.date)]
        for metric in BodyMetric.allCases {
            if let value = metric.displayValue(of: measurement, weightUnit: weightUnit, lengthUnit: lengthUnit) {
                let unit = metric.unitShort(weightUnit: weightUnit, lengthUnit: lengthUnit)
                parts.append("\(metric.title) \(BodyNumberFormat.decimal(value)) \(unit)")
            }
        }
        if let note = measurement.note, !note.isEmpty {
            parts.append("备注 \(note)")
        }
        return parts.joined(separator: "，")
    }

    /// 与给定日期同一自然日的记录（不含自身 id）。用于「覆盖当天记录」判断。
    ///
    /// 返回的是「同一天里已有的那条」，可能有也可能没有。
    static func existingMeasurement(
        on date: Date,
        excluding id: UUID?,
        measurements: [BodyMeasurement],
        calendar: Calendar
    ) -> BodyMeasurement? {
        measurements.first {
            $0.id != id && calendar.isDate($0.date, inSameDayAs: date)
        }
    }
}
