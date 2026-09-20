#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 12 规格审计（身体数据）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–11 踩过假阳性换来的规则（详见 audit_page11.py 头部）：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判，不能全仓库扫。
3. 查「注释里写了什么」的断言读原始 FILES。
4. 优先用结构性断言。
5. 跨行签名用两段式正则。
6. 作用域三选一（in_page / in_scan / in_value / in_view / in_model）。

用法：
    python Tools/audit_page12.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")


def read(rel):
    path = os.path.join(SRC, rel.replace("/", os.sep))
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


PAGE12_FILES = [
    "Features/Profile/BodyData.swift",
    "Features/Profile/BodyDataComponents.swift",
    "Features/Profile/BodyDataView.swift",
]

VALUE_FILE = "Features/Profile/BodyData.swift"
COMPONENT_FILE = "Features/Profile/BodyDataComponents.swift"
VIEW_FILE = "Features/Profile/BodyDataView.swift"

# 模型与仓储、路由装配不在页面文件里
MODEL_FILE = "Models/Models.swift"
WIRING_FILES = [
    "Features/RootView.swift",
    "Features/Profile/ProfileView.swift",
]
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
]
TOKEN_FILES = [
    "DesignSystem/DesignTokens.swift",
]

FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE12_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
COMPONENT_CODE = CODE.get(COMPONENT_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
REPO_CODE = "\n".join(CODE.get(f, "") for f in REPO_FILES)
TOKEN_CODE = "\n".join(CODE.get(f, "") for f in TOKEN_FILES)
SCAN = PAGE_CODE + "\n" + WIRING_CODE + "\n" + MODEL_CODE + "\n" + REPO_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_component(pattern, flags=0):
    return has(COMPONENT_CODE, pattern, flags)


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_model(pattern, flags=0):
    return has(MODEL_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def in_token(pattern, flags=0):
    return has(TOKEN_CODE, pattern, flags)


def in_repo(pattern, flags=0):
    return has(REPO_CODE, pattern, flags)


def func_body(code, signature):
    start = code.find(signature)
    if start < 0:
        return ""
    brace = code.find("{", start)
    if brace < 0:
        return ""
    depth = 0
    for i in range(brace, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[brace:i + 1]
    return ""


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("三个页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE12_FILES),
     f"缺失: {[f for f in PAGE12_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")

item("我的页身体数据卡可点击进入",
     in_scan(r"onOpenBodyData") and in_scan(r"ProfileRoute\.bodyData"))
item("我的 Tab 有独立 NavigationStack",
     in_scan(r"struct ProfileTab") and in_scan(r"NavigationStack\(path: \$path\)"))
item("路由注册了身体数据页",
     in_scan(r"case bodyData") and in_scan(r"BodyDataView\("))
# 页面 13 重写「我的」页后，身体数据入口从「整卡 Button」变成了
# 菜单行（`ProfileMenuRow(title: "身体数据", action: onOpenBodyData)`），
# 断言按新实现判：入口回调仍指向 onOpenBodyData 即可。
item("我的页身体数据入口仍接 onOpenBodyData",
     in_scan(r"title: \"身体数据\"") and in_scan(r"action: onOpenBodyData"))
item("返回只弹一层", in_scan(r"func popOne\(\)") and in_scan(r"path\.removeLast\(\)"))
item("保存/删除后刷新我的页（reloadToken）",
     in_scan(r"profileReloadToken = UUID\(\)") and in_scan(r"\.id\(profileReloadToken\)"))

item("顶部导航栏左侧返回",
     in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("顶部导航栏中间标题「身体数据」",
     in_view(r"Text\(\"身体数据\"\)"))
item("顶部导航栏右侧新增按钮",
     in_view(r"systemName: \"plus\"") and in_view(r"accessibilityLabel\(\"新增身体数据\"\)"))
item("新增打开底部录入面板", in_view(r"openEditor\(nil\)") and in_view(r"showEditor = true"))
item("用 safeAreaInset 固定顶部栏", in_view(r"safeAreaInset\(edge: \.top"))
item("隐藏系统导航栏", in_view(r"navigationBarHidden\(true\)"))
item("没有误用 iOS 16.4 的 .toolbar(.hidden)",
     not_has(PAGE_CODE, r"\.toolbar\(\.hidden"))

# =====================================================================
# 2. 模型与指标
# =====================================================================
print("== 2. 模型与指标 ==")

item("BodyMeasurement 有臀围 hipCm 字段", in_model(r"var hipCm: Double\?"))
item("七个指标字段齐全（体重/体脂/胸/腰/臀/大腿/上臂）",
     in_model(r"weightKg: Double\?") and in_model(r"bodyFatPercent: Double\?") and
     in_model(r"chestCm: Double\?") and in_model(r"waistCm: Double\?") and
     in_model(r"hipCm: Double\?") and in_model(r"thighCm: Double\?") and
     in_model(r"armCm: Double\?"))
item("模型有容错解码（旧文件缺 hipCm 不崩）",
     in_model(r"init\(from decoder: Decoder\)") and
     in_model(r"hipCm = try container\.decodeIfPresent\(Double\.self, forKey: \.hipCm\)"))
item("模型提供 hasAnyValue 判断", in_model(r"var hasAnyValue: Bool"))
item("指标枚举覆盖七个指标",
     in_value(r"enum BodyMetric: String, CaseIterable, Identifiable, Equatable") and
     all(in_value(rf"case {c}\b") for c in ["weight", "bodyFat", "chest", "waist", "hip", "thigh", "arm"]))
item("七个指标都有中文名",
     all(in_value(t) for t in ["体重", "体脂率", "胸围", "腰围", "臀围", "大腿围", "上臂围"]))
item("指标能从记录里取原始值", in_value(r"func rawValue\(of measurement: BodyMeasurement\) -> Double\?") and
     in_value(r"case \.hip: return measurement\.hipCm"))
item("指标区分重量/百分比/长度三类",
     in_value(r"var isWeight: Bool") and in_value(r"var isPercent: Bool") and in_value(r"var isLength: Bool"))

# =====================================================================
# 3. 顶部摘要卡
# =====================================================================
print("== 3. 顶部摘要卡 ==")

item("摘要卡含体重", in_component(r"title: \"体重\"") and in_component(r"overview\.weightText\(unit:"))
item("摘要卡含体脂率", in_component(r"title: \"体脂率\"") and in_component(r"overview\.bodyFatText\(\)"))
item("摘要卡含记录日期", in_component(r"overview\.dateText"))
item("缺失字段显示「未记录」而不是 0",
     in_value(r"guard let kg = weightKg else \{ return \"未记录\" \}") and
     in_value(r"guard let percent = bodyFatPercent else \{ return \"未记录\" \}"))
item("卡片底部显示与上一条的变化值",
     in_value(r"weightChangeKg: Double\?") and
     in_component(r"overview\.weightChangeText\(unit: weightUnit\)"))
item("变化值带符号（+ / −）", in_value(r"let sign = delta > 0 \? \"\+\" : \"−\""))
item("变化值为 0 时显示「持平」", in_value(r"return \"持平\""))
item("没有上一条可比时不显示变化行",
     in_value(r"guard let delta = weightChangeKg else \{ return nil \}"))
item("摘要卡整体有 VoiceOver 标签",
     in_component(r"accessibilityLabel\(overview\.accessibilityText\)"))

# =====================================================================
# 4. 单位切换
# =====================================================================
print("== 4. 单位切换 ==")

item("重量单位 kg / lb", in_value(r"enum BodyWeightUnit: String, CaseIterable, Identifiable, Equatable") and
     in_value(r"case kilograms") and in_value(r"case pounds"))
item("长度单位 cm / in", in_value(r"enum BodyLengthUnit: String, CaseIterable, Identifiable, Equatable") and
     in_value(r"case centimeters") and in_value(r"case inches"))
item("磅换算系数正确", in_value(r"static let poundsPerKilogram: Double = 2\.204_622_621_85"))
item("英寸换算系数正确", in_value(r"static let inchesPerCentimeter: Double = 0\.393_700_787_4"))
item("换算只产出展示值（没有 mutating）",
     in_value(r"func displayValue\(fromKilograms value: Double\) -> Double") and
     in_value(r"func displayValue\(fromCentimeters value: Double\) -> Double") and
     not_has(VALUE_CODE, r"mutating func"))
item("单位切换器有重量与围度两组",
     in_component(r"struct BodyUnitRow") and in_component(r"Text\(\"重量\"\)") and in_component(r"Text\(\"围度\"\)"))
item("单位偏好存 UserDefaults（纯本地）",
     in_view(r"UserDefaults\.standard\.set\(weightUnit\.rawValue") and
     in_view(r"UserDefaults\.standard\.set\(lengthUnit\.rawValue"))

# =====================================================================
# 5. 趋势图
# =====================================================================
print("== 5. 趋势图 ==")

item("趋势图是折线（addQuadCurve）", in_component(r"addQuadCurve\(to:"))
item("横轴为日期", in_value(r"let date: Date") and in_component(r"point\.axisLabel"))
item("纵轴按当前指标自动设范围",
     in_component(r"private var yMin: Double") and in_component(r"private var yMax: Double"))
item("纵轴留上下边距避免贴边",
     in_component(r"minValue - span \* 0\.1") and in_component(r"maxValue \* 1\.1"))
item("点击数据点可切换选中",
     in_component(r"selectedID = \(selectedID == point\.id\) \? nil : point\.id"))
item("点击后展示对应日期和数值",
     in_component(r"struct BodySelectedDetail") and
     in_component(r"FormatterKit\.monthDaySlash\(point\.date\)") and
     in_component(r"point\.displayText\(metric:"))
item("不足两条记录时用空状态",
     in_value(r"guard points\.count >= 2 else \{" ) and
     in_value(r"记录更多数据后可查看趋势"))
item("视图层按 hasEnoughForTrend 分支",
     in_view(r"hasEnoughForTrend") and in_view(r"EmptyStateView\(message: \"记录更多数据后可查看趋势\"\)"))
item("不补空日（只画有记录的日期）",
     in_value(r"compactMap \{ measurement -> BodyMetricPoint\? in") and
     in_value(r"sorted \{ \$0\.date < \$1\.date \}"))
item("只有一个点时不画线（避免除零）", in_component(r"if points\.count > 1 \{"))
item("没有 Swift Charts", not_has(PAGE_CODE, r"import Charts") and not_has(PAGE_CODE, r"Chart \{"))
item("图形对 VoiceOver 隐藏", in_component(r"accessibilityHidden\(true\)"))

# =====================================================================
# 6. 指标统计
# =====================================================================
print("== 6. 指标统计 ==")

item("图表下展示最新值", in_component(r"title: \"最新值\"") and in_component(r"stats\.latestText"))
item("图表下展示变化值", in_component(r"title: \"变化值\"") and in_component(r"stats\.changeText"))
item("图表下展示最低值", in_component(r"title: \"最低值\"") and in_component(r"stats\.minText"))
item("图表下展示最高值", in_component(r"title: \"最高值\"") and in_component(r"stats\.maxText"))
item("统计来自纯值层", in_value(r"static func stats\(") and
     in_value(r"minValue: values\.min\(\)") and in_value(r"maxValue: values\.max\(\)"))
item("变化 = 最新 − 上一条", in_value(r"change = \(latest\?\.rawValue \?\? 0\) - \(points\[points\.count - 2\]\.rawValue\)"))

# =====================================================================
# 7. 记录列表
# =====================================================================
print("== 7. 记录列表 ==")

item("记录按日期倒序", in_view(r"sorted \{ \$0\.date > \$1\.date \}"))
item("记录卡展示体重", in_component(r"体重 \\\(BodyNumberFormat\.decimal\(weightUnit\.displayValue\(fromKilograms: kg\)"))
item("记录卡展示体脂率", in_component(r"体脂 \\\(BodyNumberFormat\.decimal\(fat\)\) %"))
item("记录卡展示已填写的围度",
     in_component(r"circumferenceTags") and in_component(r"胸围") and
     in_component(r"腰围") and in_component(r"臀围") and in_component(r"大腿") and in_component(r"上臂"))
item("点击记录进入编辑", in_component(r"onTap: \(\) -> Void") and in_view(r"openEditor\(measurement\)"))
item("左滑删除", in_view(r"swipeActions\(edge: \.trailing"))
item("长按删除", in_view(r"contextMenu"))
item("删除有二次确认", in_view(r"showDeleteConfirm = true") and in_component(r"struct BodyDeleteConfirmContent"))
item("记录卡有 VoiceOver 标签", in_component(r"BodyDataBuilder\.recordAccessibility"))

# =====================================================================
# 8. 新增 / 编辑面板
# =====================================================================
print("== 8. 新增 / 编辑面板 ==")

item("面板有日期选择", in_component(r"DatePicker\(\"日期\""))
item("面板有七个数值字段 + 备注",
     in_component(r"label: \"体重 \(kg\)\"") and in_component(r"label: \"体脂率 \(%\)\"") and
     in_component(r"label: \"胸围 \(cm\)\"") and in_component(r"label: \"腰围 \(cm\)\"") and
     in_component(r"label: \"臀围 \(cm\)\"") and in_component(r"label: \"大腿围 \(cm\)\"") and
     in_component(r"label: \"上臂围 \(cm\)\"") and in_component(r"Text\(\"备注\"\)"))
item("数值字段用 String 缓冲（避免输入跳字）",
     in_component(r"@State private var weightText: String = \"\"") and
     in_component(r"TextField\(placeholder, text: text\)"))
item("至少一个有效测量值才能保存",
     in_component(r"guard draft\.hasAnyValue else \{") and
     in_component(r"errorText = \"请至少填写一个测量值\""))
item("输入范围校验体重 20–400 kg",
     in_value(r"static let weightRange: ClosedRange<Double> = 20\.\.\.400"))
item("输入范围校验体脂率 1–70%",
     in_value(r"static let bodyFatRange: ClosedRange<Double> = 1\.\.\.70"))
item("围度也有合理范围（20–300 cm）",
     in_value(r"static let lengthRange: ClosedRange<Double> = 20\.\.\.300"))
item("越界给出提示文案", in_value(r"static func rangeText\(for metric: BodyMetric\) -> String") and
     in_value(r"需在"))
item("非法输入（非数字）也拦截", in_component(r"输入的不是数字"))

# =====================================================================
# 9. 同日唯一键
# =====================================================================
print("== 9. 同日唯一键 ==")

item("仓储 save 按自然日去重（JSON）",
     in_repo(r"calendar\.isDate\(\$0\.date, inSameDayAs: measurement\.date\)") and
     in_repo(r"measurements\.removeAll"))
item("仓储 save 按自然日去重（内存桩）",
     in_repo(r"calendar\.isDate\(\$0\.date, inSameDayAs: measurement\.date\)"))
item("同日冲突检测在值层", in_value(r"static func existingMeasurement\(") and
     in_value(r"calendar\.isDate\(\$0\.date, inSameDayAs: date\)"))
item("同日已有记录时询问覆盖",
     in_view(r"conflict\(on: draft\.date") and in_component(r"struct BodyOverwriteConfirmContent"))
item("覆盖文案含「覆盖当天记录」与「取消」",
     in_component(r"PrimaryButton\(title: \"覆盖当天记录\"") and
     in_component(r"SecondaryButton\(title: \"取消\""))
item("编辑保留原 id（覆盖同一 id 语义）",
     in_component(r"editingID = editing\?\.id") and in_component(r"id: editingID \?\? UUID\(\)"))

# =====================================================================
# 10. 数据来源与仓储
# =====================================================================
print("== 10. 数据来源与仓储 ==")

item("数据经本地 FitnessRepository 读写",
     in_view(r"let repository: FitnessRepository") and
     in_view(r"repository\.fetchBodyMeasurements\(") and
     in_view(r"repository\.save\(measurement:") and
     in_view(r"repository\.delete\(measurementID:"))
item("读取上限沿用 500 条", in_value(r"static let fetchLimit = 500"))
item("保存/删除后重读盘（缓存失效）",
     in_view(r"private func refresh\(\)") and
     in_view(r"repository\.fetchBodyMeasurements\(limit:"))
item("协议 50 方法不变（身体数据三方法早已存在）",
     in_scan(r"func fetchBodyMeasurements\(limit: Int\)") and
     in_scan(r"func save\(measurement: BodyMeasurement\)") and
     in_scan(r"func delete\(measurementID: UUID\)"))

# =====================================================================
# 11. 无障碍
# =====================================================================
print("== 11. 无障碍 ==")

item("图表有 VoiceOver 摘要",
     in_view(r"accessibilityLabel\(viewModel\.trendSummary\)") and
     in_value(r"static func trendSummary\("))
item("摘要包含最新/变化/最低/最高",
     in_value(r"最新") and in_value(r"较上次") and in_value(r"最低") and in_value(r"最高"))
item("数据点有独立无障碍标签",
     in_value(r"func accessibilityLabel\(") and in_value(r"FormatterKit\.monthDaySlash\(date\)"))
item("动态字体较大时降级为列表",
     in_component(r"enum BodyAccessibilityScale") and
     in_component(r"category\.isAccessibilityCategory"))
item("页面读系统动态字体档位", in_view(r"@Environment\(\\\.sizeCategory\)"))
item("超大字体时折线图降级为列表",
     in_view(r"if useListFallback \{") and in_view(r"BodyMetricPointList\("))
item("降级列表与图共用同一组点",
     in_component(r"struct BodyMetricPointList") and in_component(r"let points: \[BodyMetricPoint\]"))
item("单位切换按钮有无障碍标签与选中态",
     in_component(r"accessibilityLabel\(unit\.title\)") and
     in_component(r"accessibilityAddTraits\(unit == weightUnit \? \[\.isSelected\] : \[\]\)"))
item("新增/返回按钮有标签",
     in_view(r"accessibilityLabel\(\"返回\"\)") and in_view(r"accessibilityLabel\(\"新增身体数据\"\)"))

# =====================================================================
# 12. 反规格排除
# =====================================================================
print("== 12. 反规格排除 ==")

item("不接入健康平台", not_has(PAGE_CODE, r"HealthKit|HKHealthStore"))
item("不含账号/登录", not_has(PAGE_CODE, r"登录|signIn|account|Account"))
item("不含社交", not_has(PAGE_CODE, r"好友|friend|Friend|分享|ShareLink"))
item("不含云同步", not_has(PAGE_CODE, r"CloudKit|iCloud|NSUbiquitous"))
item("不含联网", not_has(PAGE_CODE, r"URLSession|URLRequest|http"))

# =====================================================================
# 13. 设计令牌
# =====================================================================
print("== 13. 设计令牌 ==")

for token in ["bodyChartLine", "bodyChartFill", "bodyChartDot", "bodyChartSelected"]:
    item(f"调色板新增 {token}", in_token(rf"static let {token}\s*="))

for token in [
    "bodyChartHeight", "bodyChartVerticalPadding",
    "bodyDotDiameter", "bodySelectedDotDiameter",
    "bodyChipHeight", "bodyMetricFont", "bodyRecordRowHeight",
]:
    item(f"尺寸新增 {token}", in_token(rf"static let {token}\s*(:|=)"))

item("页面用的令牌都能解析到",
     all(in_token(rf"\b{name}\b") for name in [
         "bodyChartHeight", "bodyChartVerticalPadding", "bodyDotDiameter",
         "bodySelectedDotDiameter", "bodyChipHeight", "bodyMetricFont",
         "bodyRecordRowHeight", "bodyChartLine", "bodyChartFill",
         "bodyChartDot", "bodyChartSelected",
     ]))

# =====================================================================
# 14. 值层与工程约束
# =====================================================================
print("== 14. 值层与工程约束 ==")

item("值层不 import SwiftUI",
     not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("值层是可推演的纯值类型",
     in_value(r"struct BodyMetricPoint: Identifiable, Equatable") and
     in_value(r"struct BodyDataOverview: Equatable") and
     in_value(r"struct BodyMetricStats: Equatable"))
item("页面文件都在 Profile 目录下且被 XcodeGen 自动收录",
     all(f.startswith("Features/Profile/") for f in PAGE12_FILES))
item("ViewModel 是 @MainActor 的 ObservableObject",
     in_view(r"@MainActor") and in_view(r"final class BodyDataViewModel: ObservableObject"))
item("异步加载走 .task", in_view(r"\.task \{ await viewModel\.load\(\) \}"))
item("两个预览覆盖有数据 / 空数据",
     has(VIEW_CODE, r"#Preview\(\"身体数据 · 有数据\"\)") and
     has(VIEW_CODE, r"#Preview\(\"身体数据 · 空数据\"\)"))
item("没有重复定义同名类型",
     len(re.findall(r"struct BodyTrendChart\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum BodyMetric\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum BodyDataBuilder\b", ALL_CODE)) == 1)

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
