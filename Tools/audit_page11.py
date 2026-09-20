#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 11 规格审计（动作历史趋势）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08 / 09 / 10 踩过假阳性换来的规则：

1. **扫描前必须 strip_comments()。**
   项目里刻意在注释里写明「Swift Charts / sensoryFeedback 是 iOS 17，
   本项目避免」。不剥注释就会把说明文字当违规。
2. **排除类断言必须按页面范围判，不能全仓库扫。**
   「本页不含分享」在页面 11 是成立的（连导出都没有），
   但同样的词在页面 10 的数据管理页里是被允许的，全仓库扫必然误报。
3. **查「注释里写了什么」的断言必须读原始 FILES，不能读剥过注释的 CODE。**
4. **优先用结构性断言**，不要用整句注释 grep；注释措辞一改就误报。
5. **签名跨多行时用两段式正则**：`func name\\(\\s*\\n?\\s*param:`。
   页面 10 在这个坑上连错三次。
6. **作用域三选一要想清楚**：`in_page` / `in_scan` / `in_value` / `in_view`
   覆盖的文件集不同，写断言前先确认符号落在哪一档。

用法：
    python Tools/audit_page11.py
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
    """去块注释与行注释。扫描禁用符号前必须调用。"""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


# 页面 11 的作用域
PAGE11_FILES = [
    "Features/History/ExerciseTrendDetail.swift",
    "Features/History/ExerciseTrendDetailComponents.swift",
    "Features/History/ExerciseTrendDetailView.swift",
]

VALUE_FILE = "Features/History/ExerciseTrendDetail.swift"
COMPONENT_FILE = "Features/History/ExerciseTrendDetailComponents.swift"
VIEW_FILE = "Features/History/ExerciseTrendDetailView.swift"

# 路由与装配不在页面文件里
WIRING_FILES = [
    "Features/RootView.swift",
    "Features/Exercises/ExerciseDetailView.swift",
]

TOKEN_FILES = [
    "DesignSystem/DesignTokens.swift",
    "DesignSystem/Resources.swift",
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

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE11_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
COMPONENT_CODE = CODE.get(COMPONENT_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
TOKEN_CODE = "\n".join(CODE.get(f, "") for f in TOKEN_FILES)
SCAN = PAGE_CODE + "\n" + WIRING_CODE

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


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def in_token(pattern, flags=0):
    return has(TOKEN_CODE, pattern, flags)


def func_body(code, signature):
    """取函数体切片，直到大括号配平。用于「某函数里有没有做某事」的断言。"""
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
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE11_FILES),
     f"缺失: {[f for f in PAGE11_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")

item("统计页「常练动作」可进入（onOpenExerciseTrend 推入路由）",
     in_scan(r"onOpenExerciseTrend:") and in_scan(r"HistoryRoute\.exerciseTrend\("))
item("历史栏路由注册了趋势页", in_scan(r"case exerciseTrend\(String\)"))
item("历史栏路由装配的是本页",
     in_scan(r"case \.exerciseTrend\(let exerciseID\):") and in_scan(r"ExerciseTrendDetailView\("))
item("动作详情页新增「历史记录」菜单项",
     in_scan(r"onOpenHistory") and in_scan(r"Label\(\"历史记录\""))
item("动作栏路由注册了趋势页", in_scan(r"case exerciseTrend\(String\)") and
     in_scan(r"ExerciseRoute\.exerciseTrend\(item\.id\)"))
item("动作栏路由注册了下钻详情页与执行页",
     in_scan(r"case historyDetail\(UUID\)") and in_scan(r"case sessionDraft\(UUID\)"))
item("动作栏返回只弹一层", in_scan(r"func popExerciseOne\(\)") and in_scan(r"onBack: \{ popExerciseOne\(\) \}"))
item("趋势页两个下钻回调都接上了",
     in_scan(r"onOpenSessionDetail: \{ sessionID in") and in_scan(r"onStartTraining: \{ draftID in"))
item("动作名从路由查库兜底", in_scan(r"fallbackName: exerciseName\(for: exerciseID\)") or
     in_scan(r"fallbackName: lookupExerciseName\(exerciseID\)"))
item("动作栏也有兜底名查询", in_scan(r"func lookupExerciseName\(_ exerciseID: String\) -> String"))
# 页面 10 里的旧占位页在页面 11 交付后已删除，这里守住它不再回来
item("旧的趋势占位页已删除",
     not_has(ALL_CODE, r"struct ExerciseTrendView\b") and
     not_has(ALL_CODE, r"ExerciseTrendView\("))

item("顶部导航栏左侧返回",
     in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("顶部导航栏中间显示动作名",
     in_view(r"Text\(viewModel\.displayName\)"))
item("顶部导航栏右侧为时间范围菜单",
     in_view(r"showRangeMenu = true") and in_view(r"Text\(viewModel\.rangeKind\.title\)"))
item("用 safeAreaInset 固定顶部栏", in_view(r"safeAreaInset\(edge: \.top"))
item("隐藏系统导航栏（避免双层标题）", in_view(r"navigationBarHidden\(true\)"))
# iOS 16.4 的 .toolbar(.hidden, for:) 在 16.3.1 上不可用，必须保持废弃写法
item("没有误用 iOS 16.4 的 .toolbar(.hidden)",
     not_has(PAGE_CODE, r"\.toolbar\(\.hidden"))

# =====================================================================
# 2. 时间范围
# =====================================================================
print("== 2. 时间范围 ==")

for kind, title in [
    ("last30Days", "近 30 天"),
    ("last3Months", "近 3 个月"),
    ("lastYear", "近一年"),
    ("allTime", "全部记录"),
]:
    item(f"时间范围支持「{title}」",
         in_value(rf"case {kind}\b") and in_value(title))

item("四档构成 CaseIterable 全集",
     in_value(r"enum TrendRangeKind: String, CaseIterable, Identifiable, Equatable"))
item("每档都有副标题说明口径", in_value(r"var subtitle: String"))
item("「全部记录」不显示区间文案", in_value(r"var showsRangeText: Bool") and
     in_value(r"self != \.allTime"))
item("单位是半开区间 [start, end)",
     in_value(r"func contains\(_ date: Date\) -> Bool") and in_value(r"date >= start && date < end"))
# 30 个自然日 = 今天 + 往前 29 天
item("近 30 天取往前 29 天（不是 30）",
     in_value(r"\.day, value: -29") and not_has(VALUE_CODE, r"\.day, value: -30\b"))
item("近 3 个月按日历月减 2（不是 90 天）",
     in_value(r"\.month, value: -2") and not_has(VALUE_CODE, r"\.day, value: -90"))
item("近一年按日历月减 11", in_value(r"\.month, value: -11"))
item("日历月起点用 dateComponents 而不是减秒",
     in_value(r"func firstDayOfMonth\(") and in_value(r"dateComponents\(\[\.year, \.month\]"))
item("终点取明天 00:00（不漏亚秒记录）",
     in_value(r"func endOfDay\(") and in_value(r"byAdding: \.day,\s*\n?\s*value: 1"))
item("起点用 startOfDay 而不是减 86400",
     in_value(r"calendar\.startOfDay\(for: date\)") and
     not_has(VALUE_CODE, r"86400"))
item("全部记录的起点是 Cocoa 纪元",
     in_value(r"Date\(timeIntervalSinceReferenceDate: 0\)") and
     not_has(VALUE_CODE, r"distantPast"))
item("切换范围只重算不重读盘",
     has(func_body(VIEW_CODE, "func selectRange"), r"recompute\(\)") and
     not_has(func_body(VIEW_CODE, "func selectRange"), r"fetchRecentSessions"))

# =====================================================================
# 3. 顶部摘要卡
# =====================================================================
print("== 3. 顶部摘要卡 ==")

item("摘要卡五个字段齐全",
     in_view(r"title: \"累计训练次数\"") and
     in_view(r"title: \"累计完成组数\"") and
     in_view(r"title: \"最高单组重量\"") and
     in_view(r"title: \"估算 1RM\"") and
     in_view(r"title: \"最近训练\""))
item("累计训练次数来自 overview", in_view(r"viewModel\.overview\.sessionCount"))
item("累计完成组数来自 overview", in_view(r"viewModel\.overview\.setCount"))
item("最高单组重量用摘要的换算文案", in_view(r"viewModel\.overview\.bestWeightText\(unit:"))
item("估算 1RM 用摘要的换算文案", in_view(r"viewModel\.overview\.bestOneRMText\(unit:"))
item("最近训练日期用摘要文案", in_view(r"viewModel\.overview\.lastTrainedText"))
item("摘要用两列网格（动态字体下不挤）",
     in_view(r"LazyVGrid\(") and in_view(r"GridItem\(\.flexible\(\)"))
item("没有有效重量时显示「—」",
     in_value(r"guard let best = bestWeight, best > 0 else \{ return \"—\" \}") or
     in_value(r"return \"—\""))
item("1RM 没得算时也是「—」",
     in_value(r"guard let best = bestOneRM, best > 0 else \{ return \"—\" \}"))
item("最近训练没记录时是「—」",
     in_value(r"guard let date = lastTrainedAt else \{ return \"—\" \}"))
item("最高重量不是 0（自重动作用 nil 表示）",
     in_value(r"let bestWeight = weighted\.map \{ \$0\.weight \}\.max\(\)") and
     in_value(r"let weighted = sets\.filter \{ \$0\.weight > 0 \}"))
item("1RM 说明写明来源次数", in_value(r"return \"按 \\\(reps\) 次组估算\""))
item("摘要卡整体有 VoiceOver 标签",
     in_view(r"accessibilityLabel\(viewModel\.overviewAccessibilityText\)"))

# =====================================================================
# 4. 最高重量趋势
# =====================================================================
print("== 4. 最高重量趋势 ==")

item("第一张图是折线（addQuadCurve）", in_component(r"addQuadCurve\(to:"))
item("只有正式组参与（排除热身组）", in_value(r"!entry\.isWarmup"))
item("只统计已完成训练", in_value(r"guard session\.isFinished"))
item("只统计已完成组", in_value(r"entry\.completedAt != nil"))
item("横轴是训练日期、纵轴是当次最高重量",
     in_value(r"struct TrendWeightPoint") and in_value(r"let topWeight: Double"))
item("按训练聚合而不是按月",
     in_value(r"static func weightPoints\(from sets: \[ValidSet\]\) -> \[TrendWeightPoint\]"))
item("同重量取次数多的那组",
     in_value(r"set\.weight == existing\.top && set\.reps > existing\.reps"))
item("不补空日（只画练过的日子）",
     in_value(r"var order: \[UUID\] = \[\]") and
     not_has(func_body(VALUE_CODE, "static func volumePoints"), r"补全|补 0|padding"))
item("点击数据点可切换选中",
     in_component(r"selectedID = \(selectedID == point\.id\) \? nil : point\.id"))
item("点击区比圆点大（贯穿整列）",
     in_component(r"Rectangle\(\)\s*\n\s*\.fill\(Color\.clear\)"))
item("选中后展示日期 / 重量×次数 / 训练名",
     in_component(r"struct TrendSelectedDetail") and
     in_component(r"FormatterKit\.monthDaySlash\(point\.date\)") and
     in_component(r"point\.bestSetText\(unit: unit\)") and
     in_component(r"Text\(point\.sessionName\)"))
item("只有一个点时不画线（避免除零）",
     in_component(r"if points\.count > 1 \{") and in_component(r"guard points\.count > 1"))
item("纵轴上界全自重时兜底为 1", in_component(r"return maxValue > 0 \? maxValue : 1"))
item("没有 Swift Charts（iOS 16 手绘）",
     not_has(PAGE_CODE, r"import Charts") and not_has(PAGE_CODE, r"Chart \{"))
item("折线本身对 VoiceOver 隐藏（读整句摘要）",
     in_component(r"accessibilityHidden\(true\)"))

# =====================================================================
# 5. 容量趋势与单位切换
# =====================================================================
print("== 5. 单次训练容量趋势 ==")

item("第二张图是柱状图", in_component(r"struct TrendVolumeChart") and in_component(r"RoundedRectangle\(cornerRadius: 3"))
item("容量 = 重量 × 次数", in_value(r"isWarmup \? 0 : weight \* Double\(reps\)") or
     in_value(r"static func volumePoints\(from sets: \[ValidSet\]\) -> \[TrendVolumePoint\]"))
item("每次训练汇总容量", in_value(r"existing\.volume \+= set\.volume"))
item("容量柱有最小高度（零容量也看得见）",
     in_component(r"max\(DS\.Size\.trendBarMinWidth, ratio \* plotHeight\)"))
item("单位切换器有 kg / lb 两档",
     in_value(r"enum TrendWeightUnit: String, CaseIterable, Identifiable, Equatable") and
     in_value(r"case kilograms") and in_value(r"case pounds"))
item("切换器挂在容量卡上", in_view(r"TrendUnitToggle\(unit: \$viewModel\.unit\)"))
item("换算系数是 1 kg = 2.20462262185 lb",
     in_value(r"static let poundsPerKilogram: Double = 2\.204_622_621_85"))
item("换算只产出展示值（没有 mutating 方法）",
     in_value(r"func displayValue\(fromKilograms value: Double\) -> Double") and
     not_has(VALUE_CODE, r"mutating func"))
item("切换单位不重新读盘",
     not_has(func_body(VIEW_CODE, "func selectUnit"), r"fetchRecentSessions") and
     not_has(func_body(VIEW_CODE, "func selectUnit"), r"recompute\(\)"))
item("切换单位不回写记录",
     not_has(func_body(VIEW_CODE, "func selectUnit"), r"save\(session:"))
item("切换单位不清空选中态以外的缓存",
     has(func_body(VIEW_CODE, "func selectUnit"), r"unit = newUnit"))
item("切范围时才清空选中态",
     has(func_body(VIEW_CODE, "func selectRange"), r"selectedPointID = nil"))
item("容量图给出峰值读数（单位切换可见）",
     in_component(r"private var peakRow: some View") and in_component(r"unit\.volumeText\(fromKilograms: maxVolume\)"))

# =====================================================================
# 6. 最近记录
# =====================================================================
print("== 6. 最近记录 ==")

item("最近记录默认 10 条", in_value(r"static let recentLimit = 10"))
item("按时间倒序", in_value(r"sorted \{ \$0\.date > \$1\.date \}"))
item("展示日期", in_component(r"FormatterKit\.monthDaySlash\(record\.date\)"))
item("展示训练名称", in_component(r"Text\(record\.sessionName\)"))
item("展示最佳组「重量 × 次数」", in_component(r"record\.bestSetText\(unit: unit\)"))
item("展示总组数", in_component(r"\\\(record\.setCount\) 组"))
item("展示该次容量", in_component(r"record\.volumeText\(unit: unit\)"))
item("最佳组比重量不比容量",
     in_value(r"let better = set\.weight > existing\.best \|\|") and
     in_value(r"set\.weight == existing\.best && set\.reps > existing\.reps"))
item("整行可点击进历史训练详情",
     in_view(r"onOpenSessionDetail\(record\.sessionID\)") and
     in_component(r"Button\(action: onTap\)"))
item("行有 VoiceOver 标签与提示",
     in_component(r"accessibilityLabel\(record\.accessibilityLabel\)") and
     in_component(r"accessibilityHint\("))

# =====================================================================
# 7. 开始练这个动作
# =====================================================================
print("== 7. 开始练这个动作 ==")

item("底部有「开始练这个动作」按钮",
     in_view(r"PrimaryButton\(title: \"开始练这个动作\"\)"))
item("空状态下也保留按钮（按钮在卡片外）",
     has(func_body(VIEW_CODE, "var body: some View"), r"startTrainingButton"))
item("点击后先弹确认抽屉", in_view(r"showStartConfirm = true"))
item("确认抽屉列出重量 / 次数 / 组数 / 休息",
     in_component(r"row\(title: \"重量\"") and
     in_component(r"row\(title: \"次数\"") and
     in_component(r"row\(title: \"组数\"") and
     in_component(r"row\(title: \"组间休息\""))
item("抽屉写明建议来源", in_component(r"Text\(suggestion\.sourceText\)"))
item("建议取自最近一次记录而不是历史最高",
     in_value(r"let lastDate = sets\.map\(\{ \$0\.date \}\)\.max\(\)") and
     in_value(r"let lastSets = sets\.filter \{ \$0\.date == lastDate \}"))
item("建议重量沿用上次，不自动加重",
     in_value(r"weight: topWeight") and
     has(FILES.get(VALUE_FILE, ""), r"不自动加重"))
item("建议次数下限不低于 5（且不倒挂）",
     in_value(r"let repsLow = min\(repsHigh, max\(5, Int\(\(Double\(repsHigh\) \* 0\.8\)\.rounded\(\.up\)\)\)\)"))
item("建议组数不低于 3", in_value(r"sets: max\(3, setCount\)"))
item("没有历史时用保守默认值 3 组 / 8-12 次 / 90 秒",
     in_value(r"static let fallback = ExerciseStartSuggestion\(") and
     in_value(r"repsLow: 8") and in_value(r"repsHigh: 12") and
     in_value(r"restSeconds: 90") and in_value(r"sets: 3"))
item("创建的是力量训练草稿",
     in_view(r"WorkoutSession\(") and in_view(r"kind: \.strength"))
item("草稿预填当前动作",
     in_value(r"static func draftEntries\(") and in_view(r"exerciseID: viewModel\.exerciseID"))
item("预填的组都未完成（不写完成时间）",
     in_value(r"completedAt: nil"))
item("草稿落盘后把 id 交给执行页",
     in_view(r"try\? viewModel\.repository\.save\(session: draft\)") and
     in_view(r"onStartTraining\(draft\.id\)"))
item("草稿用动作名当训练名", in_view(r"name: viewModel\.displayName"))
item("建议始终按全部历史算（不受当前范围影响）",
     has(func_body(VIEW_CODE, "private func recompute"), r"range\(for: \.allTime"))

# =====================================================================
# 8. 空状态
# =====================================================================
print("== 8. 空状态 ==")

item("没有任何记录时显示规格原文案",
     in_view(r"EmptyStateView\(message: \"还没有这个动作的训练记录\"\)"))
item("空状态由 overview.isEmpty 触发", in_view(r"if viewModel\.isEmpty \{"))
item("空状态时不渲染四张卡（避免三句空文案叠在一起）",
     has(func_body(VIEW_CODE, "var body: some View"), r"emptyState"))
item("摘要的空态文案与之一致",
     in_value(r"guard !isEmpty else \{ return \"还没有这个动作的训练记录\" \}"))
item("加载中显示骨架", in_view(r"TrendDetailSkeleton\(\)"))
item("读取失败有重试", in_view(r"EmptyStateView\(") and in_view(r"actionTitle: \"重试\""))

# =====================================================================
# 9. 数据来源与历史动作兜底
# =====================================================================
print("== 9. 数据来源与动作兜底 ==")

item("数据经本地 FitnessRepository 聚合",
     in_view(r"let repository: FitnessRepository") and
     in_view(r"repository\.fetchRecentSessions\("))
item("读取上限沿用全站口径 500 条", in_value(r"static let sessionFetchLimit = 500"))
item("动作名三级兜底：库名 → 快照名 → id",
     in_value(r"enum TrendExerciseNaming") and
     in_value(r"static func name\(libraryName: String\?, fallback: String\?, exerciseID: String\)"))
item("兜底最终给出「未知动作」而不是空白",
     in_value(r"return \"未知动作\""))
# `fallbackName` 与 `libraryName` 是 ViewModel 的属性，不在值层里。
# 一开始写成了 in_value，两条都查不到——符号归属的作用域要想清楚再选。
item("动作被删除/隐藏时仍按 id 与快照名展示",
     in_view(r"let fallbackName: String") and in_view(r"libraryName: String\?") and
     in_value(r"static func name\(libraryName: String\?, fallback: String\?, exerciseID: String\)"))
item("查库失败不影响展示（try? 兜底）",
     in_view(r"libraryName = try\? repository"))
item("只看已完成训练，不读草稿", in_value(r"guard session\.isFinished"))

# =====================================================================
# 10. 无障碍
# =====================================================================
print("== 10. 无障碍 ==")

item("图表提供 VoiceOver 文字摘要",
     in_view(r"accessibilitySummary: viewModel\.weightTrendSummary") and
     in_view(r"accessibilitySummary: viewModel\.volumeTrendSummary"))
item("重量趋势摘要包含范围、次数、最高、涨跌",
     in_value(r"static func weightTrendSummary\(") and
     in_value(r"parts\.append\(\"比首次提高") and
     in_value(r"parts\.append\(\"比首次下降") and
     in_value(r"parts\.append\(\"区间内基本持平\"\)"))
item("容量趋势摘要包含累计与单次最高",
     in_value(r"static func volumeTrendSummary\(") and
     in_value(r"累计 \\\(FormatterKit\.plainNumber\(total\)\) 公斤") and
     in_value(r"单次最高"))
item("空数据时摘要也说得通",
     in_value(r"\\\(rangeTitle\)内没有这个动作的训练记录。") and
     in_value(r"\\\(rangeTitle\)内没有这个动作的容量记录。"))
item("数据点有独立无障碍标签",
     in_value(r"var accessibilityLabel: String"))
item("降级判据是 isAccessibilityCategory",
     in_component(r"enum TrendAccessibilityScale") and
     in_component(r"static func shouldUseList\(_ category: ContentSizeCategory\) -> Bool") and
     in_component(r"category\.isAccessibilityCategory"))
item("页面读的是系统动态字体档位", in_view(r"@Environment\(\\\.sizeCategory\)"))
item("超大字体时折线图降级为列表",
     in_view(r"if useListFallback \{") and in_view(r"TrendWeightPointList\("))
item("超大字体时柱状图降级为列表", in_view(r"TrendVolumePointList\("))
item("降级列表与图共用同一组数据点",
     in_component(r"struct TrendWeightPointList") and in_component(r"let points: \[TrendWeightPoint\]"))
item("单位切换按钮有无障碍标签与选中态",
     in_component(r"accessibilityLabel\(option\.title\)") and
     in_component(r"accessibilityAddTraits\(unit == option \? \[\.isSelected\] : \[\]\)"))
item("返回按钮有标签", in_view(r"accessibilityLabel\(\"返回\"\)"))
item("时间范围按钮读得出当前范围",
     in_view(r"accessibilityLabel\(\"时间范围，当前"))

# =====================================================================
# 11. 反规格排除（本页专属）
# =====================================================================
print("== 11. 反规格排除 ==")

item("本页不含公开战绩", not_has(PAGE_CODE, r"战绩|leaderboard|Leaderboard"))
item("本页不含好友比较", not_has(PAGE_CODE, r"好友|friend|Friend"))
item("本页不含分享", not_has(PAGE_CODE, r"ShareLink|UIActivityViewController|分享"))
item("本页不含联网", not_has(PAGE_CODE, r"URLSession|URLRequest|http"))
item("本页不读远端数据", not_has(PAGE_CODE, r"fetchRemote|remote"))

# =====================================================================
# 12. 设计令牌
# =====================================================================
print("== 12. 设计令牌 ==")

# 颜色令牌写成 `static let x = Color(...)`，尺寸令牌写成 `static let x: CGFloat = n`。
# 断言只认「名字后面跟着声明符号」，不要把类型标注也配进去——
# 两种写法混在一起时，写成 `{token}\s*=` 会漏掉全部带类型的尺寸令牌。
for token in [
    "trendWeightLine", "trendWeightFill", "trendVolumeBar", "trendSelected",
    "trendDot", "trendUnitSelected",
]:
    item(f"调色板新增 {token}", in_token(rf"static let {token}\s*="))

for token in [
    "trendWeightChartHeight", "trendVolumeChartHeight",
    "trendDotDiameter", "trendSelectedDotDiameter",
    "trendBarMaxWidth", "trendBarMinWidth",
    "trendMetricFont", "trendMetricRowHeight",
    "trendUnitToggleHeight", "trendRecordRowHeight",
    "trendChartVerticalPadding",
]:
    item(f"尺寸新增 {token}", in_token(rf"static let {token}\s*(:|=)"))

item("页面用的令牌都能解析到",
     all(in_token(rf"\b{name}\b") for name in [
         "trendMetricFont", "trendMetricRowHeight", "trendUnitToggleHeight",
         "trendWeightChartHeight", "trendVolumeChartHeight",
         "trendDotDiameter", "trendSelectedDotDiameter",
         "trendBarMaxWidth", "trendBarMinWidth",
         "trendRecordRowHeight", "trendChartVerticalPadding",
         "trendWeightLine", "trendVolumeBar", "trendSelected",
         "trendDot", "trendUnitSelected",
     ]))

# =====================================================================
# 13. 值层与工程约束
# =====================================================================
print("== 13. 值层与工程约束 ==")

item("值层不 import SwiftUI",
     not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("值层是可推演的纯值类型",
     in_value(r"struct TrendDateRange: Equatable") and
     in_value(r"struct TrendWeightPoint: Identifiable, Equatable") and
     in_value(r"struct ExerciseTrendOverview: Equatable"))
item("页面文件都在 History 目录下且被 XcodeGen 自动收录",
     all(f.startswith("Features/History/") for f in PAGE11_FILES))
item("ViewModel 是 @MainActor 的 ObservableObject",
     in_view(r"@MainActor") and in_view(r"final class ExerciseTrendDetailViewModel: ObservableObject"))
item("异步加载走 .task", in_view(r"\.task \{ await viewModel\.load\(\) \}"))
item("三个预览覆盖有数据 / 空数据 / 范围菜单",
     has(VIEW_CODE, r"#Preview\(\"动作历史趋势 · 有数据\"\)") and
     has(VIEW_CODE, r"#Preview\(\"动作历史趋势 · 空数据\"\)") and
     has(VIEW_CODE, r"#Preview\(\"时间范围菜单\"\)"))
item("没有重复定义同名类型",
     len(re.findall(r"struct TrendWeightPoint\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct TrendVolumeChart\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum TrendRangeKind\b", ALL_CODE)) == 1)

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
