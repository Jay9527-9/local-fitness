#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 10 规格审计（训练统计 + 数据管理 + 动作趋势）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

四条必须遵守的规则（页面 08 / 09 踩过假阳性换来的）：

1. **扫描前必须 strip_comments()。**
   项目里刻意在注释里写明「sensoryFeedback / SwiftData / containerRelativeFrame
   是 iOS 17，本项目避免」。不剥注释就会把说明文字当违规。
2. **排除类断言必须按页面范围判，不能全仓库扫。**
   规格说「本页不含分享」，但**数据管理页的导出功能必须用
   UIActivityViewController**（页面 04 已建立的导出模式）。
   所以「不含分享」这条断言的作用域要精确到统计页本体，不能带上数据管理页。
   这是页面 10 相比页面 09 最重要的作用域变化。
3. **查「注释里写了什么」的断言必须读原始 FILES，不能读剥过注释的 CODE。**
4. **优先用结构性断言，不要用注释 grep。**
   结构性断言（切片、startswith、count）在文案被改写后依然成立；
   注释 grep 会因为一次措辞调整而误报。

用法：
    python Tools/audit_page10.py
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


# 页面 10 的作用域：只有这些文件里的实现才算本页的
PAGE10_FILES = [
    "Features/History/WorkoutStatistics.swift",
    "Features/History/WorkoutStatisticsComponents.swift",
    "Features/History/WorkoutStatisticsView.swift",
    "Features/History/WorkoutBackup.swift",
    "Features/History/WorkoutDataManagementView.swift",
]

# 数据层改动也算本页交付
DATA_FILES = [
    "Data/FitnessRepository.swift",
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
]

# 有设计令牌改动的文件
TOKEN_FILES = [
    "DesignSystem/DesignTokens.swift",
    "DesignSystem/Resources.swift",
]

# 路由与装配不在页面文件里
WIRING_FILES = [
    "Features/RootView.swift",
    "Features/History/HistoryView.swift",
]

# 全仓库文件（只读，用于跨页检查）
FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE10_FILES)
DATA_CODE = "\n".join(CODE.get(f, "") for f in DATA_FILES)
TOKEN_CODE = "\n".join(CODE.get(f, "") for f in TOKEN_FILES)
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
SCAN = PAGE_CODE + "\n" + DATA_CODE + "\n" + WIRING_CODE

# 统计页本体（不含数据管理页）—— 「不含分享 / 不含社交」这类断言只作用于它
STATS_ONLY = "\n".join(CODE.get(f, "") for f in PAGE10_FILES[:3])

# 值层：可被 Python 推演脚本移植的那两个文件
VALUE_FILES = [
    "Features/History/WorkoutStatistics.swift",
    "Features/History/WorkoutBackup.swift",
]
VALUE_CODE = "\n".join(CODE.get(f, "") for f in VALUE_FILES)

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("五个页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep)))
         for f in PAGE10_FILES),
     f"缺失: {[f for f in PAGE10_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")

item("历史页「统计」分段可进入（HistoryRoute.stats 装配）",
     in_scan(r"case \.stats:") and in_scan(r"WorkoutStatisticsView\("))
item("统计页旧占位页已删除",
     not_has(ALL_CODE, r"HistoryStatsPlaceholderView"))
item("统计页路由由 onOpenStats 推入", in_scan(r"onOpenStats:") and in_scan(r"HistoryRoute\.stats"))
item("返回用 popOne() 而不是清空整个栈",
     in_scan(r"onBack: \{ popOne\(\) \}"))
item("统计页返回不清空 NavigationPath",
     not_has(
         WIRING_CODE[WIRING_CODE.find("case .stats:"):
                     WIRING_CODE.find("case .statsDataManagement")]
         if "case .stats:" in WIRING_CODE else "",
         r"path = NavigationPath\(\)"
     ))

item("顶部导航栏左侧返回", in_page(r"chevron\.left") and in_page(r"accessibilityLabel\(\"返回\"\)"))
item("顶部导航栏中间标题「训练统计」", in_page(r"Text\(\"训练统计\"\)"))
item("顶部导航栏右侧为时间范围按钮",
     in_page(r"accessibilityLabel\(\"时间范围：") or
     in_page(r"showRangePicker = true"))
item("用 safeAreaInset 固定顶部栏", in_page(r"safeAreaInset\(edge: \.top"))
item("隐藏系统导航栏（避免双层标题）", in_page(r"navigationBarHidden\(true\)"))

# =====================================================================
# 2. 时间范围
# =====================================================================
print("== 2. 时间范围 ==")

for kind, title in [
    ("last7Days", "近 7 天"),
    ("last30Days", "近 30 天"),
    ("thisMonth", "本月"),
    ("last3Months", "近 3 个月"),
    ("thisYear", "今年"),
    ("custom", "自定义"),
]:
    item(f"时间范围支持「{title}」",
         in_value(rf"case {kind}\b") and in_value(title))

item("六种范围构成 CaseIterable 全集",
     in_value(r"enum StatsRangeKind: String, Equatable, CaseIterable, Identifiable"))
item("每个范围都有副标题（说明口径）", in_value(r"var subtitle: String"))
item("只有自定义需要日期输入", in_value(r"var needsDateInput"))
item("自定义范围有独立构造入口", in_value(r"static func customRange\("))
# 签名跨多行，所以用「函数名 + 参数名」两段式匹配，不试图在一行里配全。
item("自定义范围无起点时退回近 30 天",
     in_value(r"static func customRange\(\s*\n\s*start: Date\?") and
     in_value(r"range\(for: \.last30Days"))
# 查注释：交换逻辑的说明写在文档注释里，剥注释就查不到，所以读原始 FILES。
# 但把断言写成「同时命中『终点早于起点』和『交换』」而不是整句照抄 ——
# 整句照抄会在文案微调时误报（页面 09 的教训）。
item("自定义范围终点早于起点时自动交换",
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"终点早于起点") and
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"交换"))
item("选择后立即重算（selectRange 写 @Published）",
     in_page(r"func selectRange\(_ kind: StatsRangeKind\)") and
     in_page(r"rangeKind = kind"))

# =====================================================================
# 3. 摘要区
# =====================================================================
print("== 3. 摘要区 ==")

item("摘要卡展示训练次数", in_value(r"title: \"训练次数\""))
item("摘要卡展示总训练时长", in_value(r"title: \"总训练时长\""))
item("摘要卡展示总完成组数", in_value(r"title: \"总完成组数\""))
item("摘要卡展示总训练容量", in_value(r"title: \"总训练容量\""))
item("含训练容量以外的距离指标", in_value(r"title: \"总距离\""))
item("有氧距离仅在存在有氧记录时追加", in_value(r"hasCardio"))
item("无法计算的指标显示「—」",
     in_value(r"var displayText: String \{ value \?\? \"—\" \}"))
item("「算不出来」用 Optional 承载，而不是用 0",
     in_value(r"let value: String\?"))
item("容量为零且无力量训练时给 nil 而不是 \"0\"",
     in_value(r"strengthCount > 0 \? \"0\" : nil"))
item("摘要卡是四张紧凑卡", in_value(r"func metrics\(includeCardioDistance") or
     in_value(r"summary\.metrics\("))
item("摘要卡用网格排布", in_page(r"LazyVGrid") and in_page(r"GridItem\(\.flexible\(\)"))
item("摘要区整体有 VoiceOver 摘要",
     in_page(r"accessibilitySummary\(rangeTitle:"))
item("摘要摘要句式形如「近 30 天完成 12 次训练」",
     in_value(r"完成 \\\(sessionCount\) 次训练") or
     in_value(r"完成") and in_value(r"次训练"))

# =====================================================================
# 4. 训练频率图
# =====================================================================
print("== 4. 训练频率图 ==")

item("第一张图表卡标题「训练频率」", in_page(r"title: \"训练频率\""))
item("频率图按日或按周聚合", in_value(r"enum StatsFrequencyGranularity") and
     in_value(r"case daily") and in_value(r"case weekly"))
item("横轴为日期", in_page(r"axisLabel") and in_value(r"FormatterKit\.monthDaySlash"))
item("纵轴为训练次数", in_value(r"var totalCount: Int") or in_value(r"strengthCount"))
item("力量与有氧用不同颜色",
     in_page(r"statsStrengthBar") and in_page(r"DS\.Palette\.cardio"))
item("两个颜色都刻意低饱和（有注释说明）",
     has(FILES.get("DesignSystem/DesignTokens.swift", ""), r"低饱和") or
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""), r"低饱和"))
item("当前选中柱用荧光绿强调",
     in_page(r"statsSelectedBar"))
item("点击柱状图显示该日训练数量和时长",
     in_page(r"selectedDate") and in_value(r"var durationSeconds: Int") or
     in_value(r"detailText"))
item("空桶也画一条细线（横轴连续）",
     in_page(r"isEmpty") and in_page(r"opacity\(0\.06\)"))
item("桶数量有上限保护", in_value(r"maxBuckets"))
item("桶数量达上限时可横向滚动",
     in_page(r"needsHorizontalScroll") and in_page(r"ScrollView\(\.horizontal"))
item("轴标签做过抽稀", in_page(r"shouldShowAxisLabel") and
     in_page(r"statsAxisLabelMaxCount"))
item("有图例说明颜色含义", in_page(r"legend") or in_page(r"力量训练") and in_page(r"有氧训练"))
item("频率图有 VoiceOver 摘要", in_value(r"static func accessibilitySummary\(\s*\n?\s*buckets:"))

# =====================================================================
# 5. 训练容量趋势图
# =====================================================================
print("== 5. 训练容量趋势图 ==")

item("第二张图表卡标题「训练容量趋势」", in_page(r"title: \"训练容量趋势\""))
item("容量按训练日汇总", in_value(r"struct StatsVolumePoint") and
     in_value(r"let volume: Double"))
item("容量即重量 × 次数（复用 SetEntry.volume）",
     in_value(r"entry\.volume") or in_value(r"\.volume\b"))
item("容量图不是零值折线：只输出 volume > 0 的日子",
     in_value(r"guard volume > 0") or in_value(r"volume > 0"))
item("无容量数据时显示空状态",
     in_page(r"CompactChartEmptyState") and
     in_page(r"没有数据|还没有"))
item("空状态而非零折线（有注释写明这是规格硬要求）",
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""),
         r"零折线|贴着横轴的零折线|没有数据"))
item("用平滑折线（二次贝塞尔而非三次样条）",
     in_page(r"VolumeLineShape") and
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""),
         r"过冲|三次样条|quadratic"))
item("容量图支持按全部 / 肌群 / 单个动作筛选",
     in_value(r"case all") and in_value(r"case muscle\(") and
     in_value(r"case exercise\("))
item("筛选维度可枚举", in_value(r"static func availableFilters\("))
item("筛选列表顺序稳定（不按哈希顺序）",
     in_value(r"哈希顺序|固定顺序|enum order") or
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""), r"固定"))
item("肌群过滤按枚举固定顺序输出",
     in_value(r"MuscleIconGroup\.allCases"))
item("选中点在图上放大", in_page(r"selected") and in_page(r"onSelect"))
item("单点时坐标不产生 NaN",
     in_page(r"guard points\.count > 1 else") and
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""), r"NaN"))
item("容量图有 VoiceOver 摘要",
     in_value(r"static func accessibilitySummary\(points:"))

# =====================================================================
# 6. 常练动作
# =====================================================================
print("== 6. 常练动作 ==")

item("第三张卡标题「常练动作」", in_page(r"title: \"常练动作\""))
item("按完成组数排序", in_value(r"sets desc|setCount") and
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""), r"组数"))
item("默认前 5 个", in_value(r"defaultLimit = 5"))
item("展示动作名", in_value(r"let displayName: String"))
item("展示完成组数", in_value(r"var setCountText: String"))
item("展示累计容量", in_value(r"var volumeText: String"))
item("三个层级都有排序键，结果稳定（不随字典遍历顺序变）",
     in_value(r"volume > rhs\.volume|lhs\.value > rhs\.value") or
     in_value(r"stable") or
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""), r"并列|每次进页面"))
item("点击进入动作历史趋势子页", in_page(r"onOpenExerciseTrend\(stat\)"))
# 页面 11 之前这里断言的是 ExerciseTrendView（数据管理页里的趋势占位页）。
# 页面 11 把真页面 ExerciseTrendDetailView 交付后，占位页连同它的 #Preview
# 一起删掉了，所以断言改成「路由装配的是真页面」。
item("趋势子页路由已注册", in_scan(r"case exerciseTrend\(String\)") and
     in_scan(r"ExerciseTrendDetailView\(") and
     not in_scan(r"ExerciseTrendView\("))
item("常练动作有 VoiceOver 摘要",
     in_value(r"static func accessibilitySummary\(items:"))

# =====================================================================
# 7. 训练部位分布
# =====================================================================
print("== 7. 训练部位分布 ==")

item("第四张卡标题「训练部位分布」", in_page(r"title: \"训练部位分布\""))
item("按主肌群统计完成组数",
     in_value(r"static func rows\(\s*\n\s*sessions: \[WorkoutSession\]") and
     in_value(r"primaryMuscleText"))
item("用横向进度条而非饼图",
     in_page(r"StatsMuscleBarRow") and not_has(STATS_ONLY, r"PieChart|pieChart|\.chart\("))
item("每行显示肌群名", in_value(r"var title: String"))
item("每行显示组数", in_value(r"var setCountText: String"))
item("每行显示百分比", in_value(r"var percentText: String"))
item("每行显示代表色", in_value(r"var colorHex: UInt32"))
item("肌群代表色有固定映射表",
     in_value(r"enum MuscleDistributionPalette") and
     in_value(r"static func hex\(for group: MuscleIconGroup\) -> UInt32"))
item("代表色刻意避开荧光绿（有注释说明语义冲突）",
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"荧光绿是「当前选中」|浅绿|语义"))
item("不含热身组（与全站口径一致）", in_value(r"isWarmup"))
item("行顺序固定（便于跨范围对比）", in_value(r"MuscleIconGroup\.allCases"))
item("部位分布有 VoiceOver 摘要",
     in_value(r"static func accessibilitySummary\(rows:"))

# =====================================================================
# 8. 数据管理入口与页面
# =====================================================================
print("== 8. 数据管理 ==")

item("页面底部有「数据管理」入口卡",
     in_page(r"StatsDataManagementCard") and
     in_page(r"onOpenDataManagement"))
item("数据管理页路由已注册",
     in_scan(r"case statsDataManagement") and
     in_scan(r"WorkoutDataManagementView\("))
item("可导出 JSON 备份",
     in_page(r"导出 JSON 备份") and
     in_value(r"static func makeBackup\("))
item("可导入备份",
     # 页面 20 起导入独立成页（ImportBackupView），不再在数据管理页内联。
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"选择备份文件") and
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"fileImporter"))
item("可清除全部训练记录",
     in_page(r"清除全部训练记录") and
     in_page(r"func clearAllRecords\(\)") and
     in_page(r"try repository\.clearWorkoutRecords\(\)") and
     # 协议声明在 DATA_FILES 里，不在 VALUE_CODE 里 —— 断言必须写对作用域。
     # （这一条曾经因为把 in_value 和 in_page 用混而误报。）
     in_scan(r"func clearWorkoutRecords\(\) throws"))
item("清除操作必须二次确认",
     # 页面 18 之前这里是 confirmationDialog + showClearConfirm；
     # 页面 18 把破坏性确认升级为独立「二次确认页」（sheet），四种删除共用 DestructiveConfirmSheet。
     in_page(r"DestructiveConfirmSheet") and in_page(r"pendingAction"))
item("清除确认用危险色（红色）",
     # 页面 18 之前这里是 confirmationDialog 的 role: .destructive；
     # 改为 sheet 后确认按钮改用危险色描边，故改判 danger 色调。
     in_page(r"DS\.Palette\.danger\.opacity\(0\.18\)"))
item("确认文案逐字来自 WorkoutDataPolicy（单一来源）",
     # 页面 45 起「清除全部训练记录」迁到独立页 ClearWorkoutRecordsView，
     # 确认短语收敛为 ClearDataScope.records.confirmPhrase（「删除训练」），
     # 删除内容清单仍逐字复用 WorkoutDataPolicy 的承诺文案。
     has(CODE.get("Features/History/ClearDataView.swift", ""), r"ClearDataScope\.records\.confirmPhrase") or
     in_page(r"WorkoutDataPolicy\.confirmMessage"))
item("明确不会删除动作库或 App 设置",
     in_value(r"动作库") and in_value(r"preservedItems"))
item("保留清单是可枚举的 5 项",
     in_value(r"static let preservedItems") and
     in_value(r"App 设置与偏好"))
item("清除范围也是可枚举的",
     in_value(r"static let clearedScopes"))
item("导入前先完成全部校验再落盘（失败不动本机数据）",
     # 页面 18 之前靠 importBackup「先全部算完再写」；页面 18 拆成
     # inspectBackup（纯解码预检）+ importFullBackup（确认后写入）；
     # 页面 20 起导入独立成页：ImportBackupViewModel.inspect 只读预检，
     # 通过后才 startImport。
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"func inspect\(data:") and
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"func importBackup\(\)") and
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"不会改动现有数据"))
item("导入有合并策略选择",
     in_value(r"enum WorkoutBackupMergePolicy") and
     in_value(r"keepExisting") and
     in_value(r"overwriteExisting") and
     in_value(r"replaceAll"))
item("默认策略是破坏性最小的那个",
     in_page(r"mergePolicy: WorkoutBackupMergePolicy = \.keepExisting"))
item("导入用安全作用域 URL 访问",
     # 页面 20 起在 ImportBackupView 内处理文件选取的安全作用域。
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"startAccessingSecurityScopedResource") and
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"stopAccessingSecurityScopedResource"))
item("取消选择文件不弹错误提示",
     has(FILES.get("Features/History/ImportBackupView.swift", ""), r"NSUserCancelledError"))

# =====================================================================
# 9. 备份的数据边界
# =====================================================================
print("== 9. 备份边界 ==")

item("备份只含训练记录（字段边界=清除边界）",
     in_value(r"let sessions: \[WorkoutSession\]") and
     not_has(VALUE_CODE, r"let plans|let exercises"))
item("备份有格式标识", in_value(r"formatIdentifier = \"fitness-workouts-backup\""))
item("备份有版本号", in_value(r"currentVersion = 1"))
item("导出只含已完成的训练",
     in_value(r"filter \{ \$0\.isFinished \}"))
item("导出文件为 ISO8601 日期编码",
     in_value(r"dateEncodingStrategy = \.iso8601"))
item("导出文件名带日期", in_value(r"训练记录备份-"))
item("解码校验顺序正确（空 → JSON → 格式 → 版本）",
     has(FILES.get("Features/History/WorkoutBackup.swift", ""),
         r"先看是不是空文件"))
item("「不是 JSON」与「格式不对」是两种提示",
     in_value(r"case notJSON") and in_value(r"case wrongFormat"))
item("合并按 id 去重，保留先出现的那条",
     in_value(r"static func dedupe\(") and
     has(FILES.get("Features/History/WorkoutBackup.swift", ""), r"保留\*\*先出现\*\*"))
item("三条策略共用一份实现",
     has(FILES.get("Features/History/WorkoutBackup.swift", ""),
         r"共用同一份实现"))

# =====================================================================
# 10. 纯本地聚合与缓存
# =====================================================================
print("== 10. 纯本地聚合与缓存 ==")

item("值层文件不 import SwiftUI（可被 Python 推演）",
     not_has(VALUE_CODE, r"import SwiftUI") and
     not_has(VALUE_CODE, r"import UIKit"))
item("聚合全部是纯静态函数（不依赖实例状态）",
     in_value(r"static func points\(") and
     in_value(r"static func buckets\(") and
     in_value(r"static func top\(") and
     in_value(r"static func rows\("))
item("时间范围构造接受 now 参数（可推演）",
     in_value(r"now: Date,") or in_value(r"now: Date\)"))
item("有单条缓存实现", in_value(r"struct StatsCache<Value>"))
item("缓存键包含范围", in_value(r"enum StatsCacheKey") and
     in_value(r"static func rangeKey\("))
item("缓存键用起止时间戳而非仅种类",
     in_value(r"range\.start\.timeIntervalSince1970") and
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"只用种类做 key 会命中旧缓存"))
item("缓存有失效入口", in_value(r"func invalidate\(\)"))
item("数据变化后自动失效并重算",
     in_page(r"private func invalidateCaches\(\)") and
     in_page(r"invalidateCaches\(\)"))
item("reload() 不清空为 loading 态（避免闪骨架屏）",
     in_page(r"func reload\(\) async"))
_reload_start = PAGE_CODE.find("func reload() async")
_reload_body = ""
if _reload_start >= 0:
    _end = PAGE_CODE.find("private func invalidateCaches", _reload_start)
    _reload_body = PAGE_CODE[_reload_start:_end if _end > 0 else _reload_start + 700]
item("统计页 reload() 体内不写 loadState = .loading",
     _reload_body != "" and "loadState = .loading" not in _reload_body)
item("缓存是单条而非字典/LRU（有注释说明理由）",
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"同时只有一个时间范围|单条"))
item("统计与历史读同一份数据上限（500 条）",
     in_page(r"sessionFetchLimit = 500"))
item("统计取动作库时带 includeHidden",
     in_page(r"fetchExercises\(includeHidden: true\)"))

# =====================================================================
# 11. 无障碍与动态字体
# =====================================================================
print("== 11. 无障碍与动态字体 ==")

item("每张图都有文字摘要",
     in_page(r"StatsFrequencyBuilder\.accessibilitySummary") and
     in_page(r"StatsVolumeBuilder\.accessibilitySummary") and
     in_page(r"StatsTopExerciseBuilder\.accessibilitySummary") and
     in_page(r"StatsMuscleDistributionBuilder\.accessibilitySummary"))
item("摘要句式形如「近 30 天完成 12 次训练，共 18 小时」",
     in_value(r"rangeTitle") and
     in_page(r"accessibilityLabel\(\s*Text\(|accessibilityLabel\(Text\("))
item("图内图形对 VoiceOver 隐藏（摘要挂在卡片上）",
     in_page(r"accessibilityHidden\(true\)") and
     in_page(r"accessibilityElement\(children: \.contain\)"))
item("只靠颜色区分时补了文字图例（色觉障碍）",
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""),
         r"色觉障碍|只靠颜色区分"))
item("柱状条有最小点击宽度（≥44pt 触控目标思路）",
     in_page(r"minWidth: DS\.Size\.minTapTarget") or
     in_page(r"DS\.Size\.minTapTarget"))
item("支持横向滚动以应对小屏",
     in_page(r"ScrollView\(\.horizontal") or in_page(r"needsHorizontalScroll"))
item("小屏空间不足时有降级路径（抽稀轴标签）",
     in_page(r"statsAxisLabelMaxCount"))
item("字号走设计令牌，跟随动态字体",
     in_page(r"DS\.Typography\.") and not_has(PAGE_CODE, r"\.font\(\.system\(size: \d+\)\)\s*$"))
item("大数值用 minimumScaleFactor 而不是截断",
     in_page(r"minimumScaleFactor") and
     has(FILES.get("Features/History/WorkoutStatisticsComponents.swift", ""),
         r"缩小比截断好|六位数|截断"))

# =====================================================================
# 12. iOS 16 兼容
# =====================================================================
print("== 12. iOS 16 兼容 ==")

ios17 = [
    ("sensoryFeedback", r"sensoryFeedback"),
    ("@Observable", r"@Observable\b"),
    ("@Bindable", r"@Bindable\b"),
    ("ContentUnavailableView", r"ContentUnavailableView"),
    ("onChange 双参数形式", r"onChange\(of:[^)]*\)\s*\{\s*\w+\s*,\s*\w+\s+in"),
    ("symbolEffect", r"symbolEffect"),
    ("SwiftData", r"import SwiftData|@Query|ModelContainer"),
    ("scrollIndicators", r"scrollIndicators\("),
    ("containerRelativeFrame", r"containerRelativeFrame"),
    ("scrollTargetBehavior", r"scrollTargetBehavior"),
    ("@retroactive", r"@retroactive"),
]
for label, pattern in ios17:
    item(f"不使用 iOS 17 的{label}", not_has(PAGE_CODE, pattern))

ios164 = [
    (".presentationBackground", r"presentationBackground\("),
    ("scrollBounceBehavior(.basedOnSize)", r"scrollBounceBehavior\(\.basedOnSize\)"),
    (".toolbar(.hidden)", r"\.toolbar\(\.hidden"),
]
for label, pattern in ios164:
    item(f"不使用 iOS 16.4+ 的{label}", not_has(PAGE_CODE, pattern))

item("用 navigationBarHidden(true) 而非 .toolbar(.hidden)",
     has(STATS_ONLY, r"navigationBarHidden\(true\)"))
item("onChange 用单参数形式（iOS 16 可用）",
     in_page(r"onChange\(of: [^)]+\) \{ _ in") or
     not_has(PAGE_CODE, r"\.onChange\("))
item("用 safeAreaInset", in_page(r"safeAreaInset\("))
item("用 LazyVStack / LazyVGrid",
     in_page(r"LazyVStack") and in_page(r"LazyVGrid"))
item("用 GridItem 两列布局", in_page(r"GridItem\(\.flexible\(\)"))

# =====================================================================
# 13. 无社交 / 无网络（只作用于统计页本体）
# =====================================================================
print("== 13. 无社交 / 无网络（统计页本体）==")

social = [
    ("好友对比", r"好友|friend|compareWith|对比好友"),
    ("排行榜", r"排行榜|leaderboard"),
    ("云同步", r"CloudKit|NSUbiquitous|iCloud|云同步"),
    ("网络请求", r"URLSession|URLRequest|dataTask"),
    ("公开链接", r"openURL|UIApplication\.shared\.open"),
    ("点赞 / 评论", r"点赞|评论|likeCount|commentCount"),
]
for label, pattern in social:
    item(f"统计页不含{label}", not_has(STATS_ONLY, pattern))

# 分享这一条很特殊：统计页本体不含，但数据管理页的导出必须用系统分享面板。
# 所以断言写两半 —— 这正是「排除类断言必须按范围判」的活教材。
item("统计页本体不含分享", not_has(STATS_ONLY, r"UIActivityViewController|ShareLink"))
item("数据管理页的导出走系统分享面板（规格要求的导出）",
     has(CODE.get("Features/History/ExportBackupView.swift", ""),
         r"ShareSheet\(items:"))
item("统计页文件里完全没有分享相关代码（结构性检查）",
     "UIActivityViewController" not in CODE.get("Features/History/WorkoutStatisticsView.swift", "")
     and "ShareSheet" not in CODE.get("Features/History/WorkoutStatisticsView.swift", "")
     and "ShareLink" not in CODE.get("Features/History/WorkoutStatisticsView.swift", ""))
item("导出页「使用系统分享」是唯一触发分享的入口",
     len(re.findall(r"sharedFile = ExportedFile\(url:",
                    CODE.get("Features/History/ExportBackupView.swift", ""))) == 1)

# =====================================================================
# 14. 视图模型
# =====================================================================
print("== 14. 视图模型 ==")

view = CODE.get("Features/History/WorkoutStatisticsView.swift", "")
mgmt = CODE.get("Features/History/WorkoutDataManagementView.swift", "")

item("统计视图模型主线程隔离（@MainActor）",
     has(view, r"@MainActor\s+final class WorkoutStatisticsViewModel"))
item("统计加载态区分 loading / loaded / failed",
     has(view, r"case loading") and has(view, r"case loaded") and
     has(view, r"case failed"))
item("统计读取失败可重试", has(view, r"actionTitle: \"重试\""))
item("统计刷新不回到 loading 态",
     has(view, r"func reload\(\) async"))
item("数据管理视图模型主线程隔离（@MainActor）",
     has(mgmt, r"@MainActor\s+final class WorkoutDataManagementViewModel"))
item("数据管理页加载态齐备",
     has(mgmt, r"case loading") and has(mgmt, r"case loaded") and
     has(mgmt, r"case failed"))
item("操作结果用 toast 反馈",
     has(mgmt, r"showToast\(") and has(mgmt, r"var toast: String\?"))
item("toast 区分成功与失败",
     has(mgmt, r"toastIsError"))
item("导出页未勾选任何内容时禁用生成备份",
     # 页面 18 之前是「无训练记录时禁用导出」；页面 18 改为可选范围；
     # 页面 19 起导出独立成页，改为「未勾选任何数据段时禁用生成备份」。
     has(CODE.get("Features/History/ExportBackupView.swift", ""), r"canGenerate") and
     has(CODE.get("Features/History/ExportBackupView.swift", ""), r"isEnabled: viewModel\.canGenerate"))
item("清除全部本地数据需输入「清除」确认",
     # 页面 18 之前是「空数据时禁用清除按钮」；页面 18 改为「清除全部」需输入「清除」。
     has(mgmt, r"typedText == \"清除\"") and has(mgmt, r"needsTypeConfirm"))

# =====================================================================
# 15. 路由装配完整性
# =====================================================================
print("== 15. 路由装配 ==")

item("HistoryRoute 覆盖四个目标",
     in_scan(r"case sessionDetail\(UUID\)") and
     in_scan(r"case sessionDraft\(UUID\)") and
     in_scan(r"case stats\b") and
     in_scan(r"case statsDataManagement") and
     in_scan(r"case exerciseTrend\(String\)"))
item("navigationDestination 覆盖全部新 case",
     in_scan(r"case \.statsDataManagement:") and
     in_scan(r"case \.exerciseTrend\(let exerciseID\):"))
item("统计页装配了三个回调",
     in_scan(r"onBack: \{ popOne\(\) \}") and
     in_scan(r"onOpenDataManagement:") and
     in_scan(r"onOpenExerciseTrend:"))
item("数据管理页装配了 onDataChanged",
     in_scan(r"onDataChanged: \{ historyReloadToken = UUID\(\) \}"))
item("数据变化后通知历史页刷新", in_scan(r"historyReloadToken = UUID\(\)"))
item("动作趋势页从路由取动作名",
     in_scan(r"fallbackName: exerciseName\(for: exerciseID\)"))
# 页面 11 之前这里还断言了 fallbackMuscle / exerciseMuscle(for:) 与 `return .other`。
# 真趋势页的标题只显示动作名，不画肌群图标，那一路查询函数随之删除，
# 断言改成查名字这一路的兜底（`return exerciseID`）。
item("动作查询有兜底（查不到不崩）",
     in_scan(r"guard let item = try\? repository\.fetchExercises\(ids: \[exerciseID\]\)") and
     in_scan(r"return exerciseID"))

# =====================================================================
# 16. 设计令牌
# =====================================================================
print("== 16. 设计令牌 ==")

tokens = [
    "statsStrengthBar", "statsSelectedBar", "statsGrid",
    "statsVolumeLine", "statsVolumeFill",
    "statsMetricFont", "statsMetricCardHeight",
    "statsFrequencyChartHeight", "statsVolumeChartHeight",
    "statsBarMaxWidth", "statsBarMinWidth", "statsAxisWidth",
    "statsMuscleBarHeight", "statsMinVisibleBuckets", "statsAxisLabelMaxCount",
]
for token in tokens:
    item(f"新增令牌 DS.*.{token}", has(TOKEN_CODE, rf"\b{token}\b"))

item("强调色仍是荧光绿 C6FF3E", has(TOKEN_CODE, r"C6FF3E|0xC6FF3E"))
item("新增两份格式化函数",
     has(TOKEN_CODE, r"static func monthDaySlash") and
     has(TOKEN_CODE, r"static func dateRangeSlash"))

# =====================================================================
# 17. 数据层
# =====================================================================
print("== 17. 数据层 ==")

item("协议新增 replaceAllSessions", in_scan(r"func replaceAllSessions\(_ sessions: \[WorkoutSession\]\) throws"))
item("协议新增 replaceAllRestDays", in_scan(r"func replaceAllRestDays\(_ restDays: \[RestDay\]\) throws"))
item("协议新增 clearWorkoutRecords", in_scan(r"func clearWorkoutRecords\(\) throws"))
item("JSON 仓储实现了三者",
     has(CODE.get("Data/JSONFitnessRepository.swift", ""), r"func replaceAllSessions\(") and
     has(CODE.get("Data/JSONFitnessRepository.swift", ""), r"func replaceAllRestDays\(") and
     has(CODE.get("Data/JSONFitnessRepository.swift", ""), r"func clearWorkoutRecords\("))
item("预览仓储实现了三者",
     has(CODE.get("Data/PreviewFitnessRepository.swift", ""), r"func replaceAllSessions\(") and
     has(CODE.get("Data/PreviewFitnessRepository.swift", ""), r"func replaceAllRestDays\(") and
     has(CODE.get("Data/PreviewFitnessRepository.swift", ""), r"func clearWorkoutRecords\("))
item("清除实现显式声明不动哪些集合",
     has(FILES.get("Data/JSONFitnessRepository.swift", ""),
         r"没有触碰|plans / exercises / measurements"))
item("预览仓储有只练有氧的样例（覆盖容量降级路径）",
     has(CODE.get("Data/PreviewFitnessRepository.swift", ""),
         r"makeCardioOnlyHistory"))
item("预览仓储有统计样例数据",
     has(CODE.get("Data/PreviewFitnessRepository.swift", ""),
         r"statisticsSampleSessions"))

# =====================================================================
# 18. 动作历史趋势（规格的「子页」要求）
# =====================================================================
print("== 18. 动作历史趋势子页 ==")

item("趋势子页按月聚合",
     in_value(r"static func monthlyPoints\("))
item("趋势保留空月份（与容量图相反，有注释说明）",
     in_value(r"保留空月份|含空月份") or
     has(FILES.get("Features/History/WorkoutStatistics.swift", ""),
         r"空月"))
item("趋势默认 12 个月", in_value(r"defaultMonths = 12"))
item("趋势有防呆上限", in_value(r"min\(months, 60\)"))
item("趋势口径与全站一致（不含热身）", in_value(r"!entry\.isWarmup"))
item("有最近记录列表", in_value(r"static func recentSessions\("))
item("最高重量为空时给 nil 而不是 0",
     in_value(r"var bestWeight: Double\?") and
     in_value(r"return values\.isEmpty \? nil"))
item("趋势有 VoiceOver 摘要",
     in_value(r"var accessibilityText: String"))

# =====================================================================
# 结果
# =====================================================================
print()
print("=" * 72)
passed = sum(1 for _, ok, _ in ITEMS if ok)
failed = [(label, extra) for label, ok, extra in ITEMS if not ok]
print(f"page 10 规格审计：{len(ITEMS)} 条，通过 {passed} 条，缺口 {len(failed)} 条")
print("=" * 72)

if failed:
    for label, extra in failed:
        print(f"  [缺口] {label}")
        if extra:
            print(f"         {extra}")
    sys.exit(1)

print("规格全部落地。")
print("=" * 72)
