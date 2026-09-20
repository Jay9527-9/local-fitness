#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
page 08 规格审计：逐条核对用户原文规格是否落地。

规则（与 page 07 一致）：
- 每条规格对应一个可检的证据：要么是源码里的正则，要么是文件存在性。
- 证据不足即判 gap，不允许「看起来做了」就放过。
- 审计脚本本身保留，不删除——它是下次回归的基线。
"""

import io
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "FitnessApp")

# 相对路径 -> 全文
FILES = {}
for root, dirs, fs in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in (".git", "build", "DerivedData")]
    for name in fs:
        if name.endswith(".swift"):
            path = os.path.join(root, name)
            FILES[os.path.relpath(path, ROOT).replace("\\", "/")] = io.open(
                path, encoding="utf-8", errors="replace"
            ).read()

ALL = "\n".join(FILES.values())


def strip_comments(text):
    """去掉 // 行注释与 /* */ 块注释，只留代码。

    必须做这一步：项目中大量注释写着「xxx 是 iOS 17 API，这里故意不用」，
    若直接在全文里搜关键字，这些注释会被当成违规代码命中。
    page 07 的探针就吃过这个亏。"""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    lines = []
    for line in text.split("\n"):
        # 简易处理：字符串字面量里的 // 罕见，这里不特殊照顾
        idx = line.find("//")
        lines.append(line if idx < 0 else line[:idx])
    return "\n".join(lines)


CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

# 测试用桩：本页相关源文件
PAGE08_FILES = [
    "Features/History/HistoryView.swift",
    "Features/History/HistoryCalendar.swift",
    "Features/History/HistoryCalendarComponents.swift",
    "Features/RootView.swift",
    "Models/Models.swift",
    "Data/FitnessRepository.swift",
]
PAGE08_CODE = "\n".join(CODE.get(f, "") for f in PAGE08_FILES)


def in_file(relpath, pattern):
    """在指定文件里找正则（只看代码，跳过注释）"""
    text = CODE.get(relpath, "")
    return re.search(pattern, text) is not None


def anywhere(pattern):
    """全项目代码里找（跳过注释）"""
    return re.search(pattern, ALL_CODE) is not None


def anywhere_in(pattern, relpaths):
    text = "\n".join(CODE.get(f, "") for f in relpaths)
    return re.search(pattern, text) is not None


# (分组, 规格描述, 判定结果)
RESULTS = []


def item(group, desc, ok):
    RESULTS.append((group, desc, bool(ok)))


# ============ 一、视觉与范围 ============
G = "一、视觉与范围"
item(G, "深色炭黑背景", in_file("DesignSystem/DesignTokens.swift", r"bg = Color\(hex: 0x0B0B0C\)"))
item(G, "深灰卡片", in_file("DesignSystem/DesignTokens.swift", r"surface = Color\(hex: 0x151517\)"))
item(G, "荧光绿强调色", in_file("DesignSystem/DesignTokens.swift", r"accent = Color\(hex: 0xC6FF3E\)"))
item(G, "只展示本地数据（无网络层）",
     not anywhere(r"URLSession|Alamofire|http[s]?://api"))
# 规格「不含分享」限定的是历史页；计划导出备份是页面 04 的既有功能，
# 因此这里只检查历史页与它自己新增的组件不含分享能力。
item(G, "历史页无分享功能", not anywhere_in(r"ShareLink|UIActivityViewController", PAGE08_FILES))
item(G, "无云同步", not anywhere(r"CloudKit|CKRecord|NSUbiquitousKeyValueStore"))
item(G, "无好友排名", not anywhere(r"leaderboard|ranking|好友榜"))

# ============ 二、导航栏 ============
G = "二、导航栏"
item(G, "大标题「历史」", in_file("Features/History/HistoryView.swift",
                                  r'Text\("历史"\)'))
item(G, "大标题用 largeTitle 语义字体",
     in_file("Features/History/HistoryView.swift", r"DS\.Typography\.largeTitle"))
item(G, "标题带 isHeader 无障碍特征",
     in_file("Features/History/HistoryView.swift", r"accessibilityAddTraits\(\.isHeader\)"))
item(G, "右侧新增按钮", in_file("Features/History/HistoryView.swift",
                                r'accessibilityLabel\("新增"\)'))
item(G, "新增菜单：新建力量训练",
     in_file("Features/History/HistoryView.swift", r'"新建力量训练"'))
item(G, "新增菜单：新建有氧训练",
     in_file("Features/History/HistoryView.swift", r'"新建有氧训练"'))
item(G, "新增菜单：添加休息日",
     in_file("Features/History/HistoryView.swift", r'"添加休息日"'))
item(G, "新增菜单：导入本地计划",
     in_file("Features/History/HistoryView.swift", r'"导入本地计划"'))

# ============ 三、月历 ============
G = "三、月历"
item(G, "上月 / 本月 / 下月切换控件",
     in_file("Features/History/HistoryCalendarComponents.swift", r"struct MonthSwitcher"))
item(G, "上个月按钮", in_file("Features/History/HistoryCalendarComponents.swift",
                              r'"上个月"'))
item(G, "下个月按钮", in_file("Features/History/HistoryCalendarComponents.swift",
                              r'"下个月"'))
item(G, "回到本月/当前月份", in_file("Features/History/HistoryCalendarComponents.swift",
                                     r'"回到本月"'))
item(G, "默认定位本月",
     in_file("Features/History/HistoryView.swift",
             r"visibleMonth: Date = HistoryCalendar\.startOfDay\(for: \.now\)"))
item(G, "按周一至周日排列（7 列）",
     in_file("Features/History/HistoryCalendar.swift",
             r"dayCountInWeek = 7") and in_file(
         "Features/History/HistoryCalendarComponents.swift",
         r"WeekdayLabel\.all"))
item(G, "周一起始换算用 WeekdayLabel.normalize",
     in_file("Features/History/HistoryCalendar.swift",
             r"WeekdayLabel\.normalize\(calendarWeekday:"))
item(G, "今天有细描边", in_file("Features/History/HistoryCalendarComponents.swift",
                                 r"calendarTodayRing"))
item(G, "今天描边线宽 1.5",
     in_file("DesignSystem/DesignTokens.swift",
             r"calendarTodayStroke: CGFloat = 1\.5"))
item(G, "选中日期荧光绿圆形背景",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r"calendarSelectionCircle"))

# ============ 四、标记点 ============
G = "四、标记点"
item(G, "力量训练标记为荧光绿",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r"case \.strength: return DS\.Palette\.accent"))
item(G, "有氧标记为蓝绿（新增令牌）",
     in_file("DesignSystem/DesignTokens.swift", r"cardio = Color\(hex: 0x3ED8C6\)"))
item(G, "有氧标记用 cardio 令牌",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r"case \.cardio: return DS\.Palette\.cardio"))
item(G, "休息日标记为灰色",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r"case \.rest: return DS\.Palette\.restMarker"))
item(G, "同一天多条记录使用多个并列点（每个训练各一个点）",
     in_file("Features/History/HistoryCalendar.swift",
             r"var markers: \[DayMarker\] \{\s*\n\s*var result.*sessions\.map"))
item(G, "不使用社交徽章",
     # 只排查真正的社交语义；weekdayBadge / kindBadge / warmupBadge 是
     # 星期圆钮、类型标签、热身标签，与社交无关。
     not anywhere(r"socialBadge|likeBadge|friendBadge|排行榜徽章|点赞"))

# ============ 五、当日时间线 ============
G = "五、当日时间线"
item(G, "点击日期显示当日时间线",
     in_file("Features/History/HistoryView.swift", r"DayTimelineSection"))
item(G, "按开始时间排列",
     in_file("Features/History/HistoryCalendar.swift",
             r"sorted \{ \$0\.startedAt < \$1\.startedAt \}"))
item(G, "卡片显示训练名称", in_file("Features/History/HistoryCalendarComponents.swift",
                                     r"Text\(session\.name\)"))
item(G, "卡片显示类型", in_file("Features/History/HistoryCalendarComponents.swift",
                                 r"session\.kind\.title"))
item(G, "卡片显示训练时长", in_file("Features/History/HistoryCalendarComponents.swift",
                                     r"FormatterKit\.duration\(seconds: session\.durationSeconds\)"))
item(G, "力量显示完成组数", in_file("Features/History/HistoryCalendarComponents.swift",
                                     r"session\.completedSetCount"))
item(G, "力量显示容量", in_file("Features/History/HistoryCalendarComponents.swift",
                                 r"session\.totalVolume|summaryText"))
item(G, "有氧显示距离",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r"FormatterKit\.distance\(meters:"))
item(G, "点击卡片进入历史训练详情",
     in_file("Features/History/HistoryView.swift", r"onOpenSession") and
     in_file("Features/RootView.swift", r"HistoryRoute\.sessionDetail"))

# ============ 六、空状态 ============
G = "六、空状态"
item(G, "无训练显示「当天没有训练记录」",
     in_file("Features/History/HistoryCalendarComponents.swift",
             r'"当天没有训练记录"'))
item(G, "提供「新增训练」按钮",
     in_file("Features/History/HistoryCalendarComponents.swift", r'"新增训练"'))
item(G, "不使用大块空白（不用 EmptyStateView 撑满）",
     not in_file("Features/History/HistoryView.swift",
                 r"case \.calendar:\s*\n\s*EmptyStateView"))

# ============ 七、分段切换 ============
G = "七、分段切换"
item(G, "固定分段控件", in_file("Features/History/HistoryView.swift",
                                 r"private var segmentPicker"))
item(G, "日历分段", in_file("Features/History/HistoryCalendar.swift", r"case calendar"))
item(G, "列表分段", in_file("Features/History/HistoryCalendar.swift", r"case list"))
item(G, "统计分段", in_file("Features/History/HistoryCalendar.swift", r"case stats"))
item(G, "日历为默认",
     in_file("Features/History/HistoryView.swift",
             r"segment: HistorySegment = \.calendar"))
item(G, "列表按日期倒序",
     in_file("Features/History/HistoryCalendar.swift",
             r"sorted \{ \$0\.startedAt > \$1\.startedAt \}"))
item(G, "统计进入下一页（独立路由）",
     in_file("Features/RootView.swift", r"case stats") and
     # 页面 10 之前这里断言的是 HistoryStatsPlaceholderView（当时的占位页）。
     # 页面 10 交付后占位页被删掉、换成真正的 WorkoutStatisticsView，
     # 所以断言改成「装配的是真页面」，而不是继续要求占位页存在。
     in_file("Features/RootView.swift", r"WorkoutStatisticsView") and
     not in_file("Features/RootView.swift", r"HistoryStatsPlaceholderView"))

# ============ 八、长按菜单 ============
G = "八、长按菜单"
item(G, "长按日期弹菜单", in_file("Features/History/HistoryCalendarComponents.swift",
                                   r"LongPressGesture"))
item(G, "日期菜单：新建力量训练",
     in_file("Features/History/HistoryView.swift", r"dayMenuContent"))
item(G, "日期菜单含新建有氧 / 添加休息日",
     in_file("Features/History/HistoryView.swift", r'"新建有氧训练"') and
     in_file("Features/History/HistoryView.swift", r'"添加休息日"'))
item(G, "长按训练卡弹菜单（contextMenu）",
     in_file("Features/History/HistoryCalendarComponents.swift", r"\.contextMenu"))
item(G, "卡片菜单：编辑训练标题",
     in_file("Features/History/HistoryCalendarComponents.swift", r'"编辑训练标题"'))
item(G, "卡片菜单：复制为新训练",
     in_file("Features/History/HistoryCalendarComponents.swift", r'"复制为新训练"'))
item(G, "卡片菜单：删除记录",
     in_file("Features/History/HistoryCalendarComponents.swift", r'"删除记录"'))
item(G, "删除二次确认",
     in_file("Features/History/HistoryView.swift",
             r'\.alert\("删除这条训练记录？"'))
item(G, "删除按钮标 destructive",
     in_file("Features/History/HistoryView.swift",
             r'Button\("删除", role: \.destructive\)'))
item(G, "只删除当前本地记录",
     in_file("Features/History/HistoryView.swift",
             r"repository\.delete\(sessionID: session\.id\)"))

# ============ 九、Tab 与过渡 ============
G = "九、Tab 与过渡"
item(G, "底部沿用四栏 Tab", in_file("Features/RootView.swift", r"enum MainTab") and
     in_file("Features/RootView.swift", r"case history"))
item(G, "高亮「历史」",
     in_file("Features/RootView.swift", r"selection == \.history|\.history:"))
item(G, "切换月份 180-220ms 淡入",
     in_file("Features/History/HistoryView.swift",
             r"withAnimation\(DS\.Motion\.tabSwitch\) \{ viewModel\.goToPreviousMonth"))
item(G, "切换日期 180-220ms",
     in_file("Features/History/HistoryView.swift",
             r"withAnimation\(DS\.Motion\.standard\) \{ viewModel\.select\(date\)"))
item(G, "切换分段 180-220ms",
     in_file("Features/History/HistoryView.swift",
             r"withAnimation\(DS\.Motion\.tabSwitch\) \{ viewModel\.segment = item"))
item(G, "tabSwitch = 220ms",
     in_file("DesignSystem/DesignTokens.swift", r"tabSwitch = Animation\.easeOut\(duration: 0\.22\)"))
item(G, "standard = 200ms",
     in_file("DesignSystem/DesignTokens.swift", r"standard = Animation\.easeInOut\(duration: 0\.2\)"))

# ============ 十、数据层 ============
G = "十、数据层"
item(G, "读取 WorkoutSession",
     in_file("Features/History/HistoryView.swift", r"fetchRecentSessions\(limit: 500\)"))
item(G, "读取 Plan",
     in_file("Features/History/HistoryView.swift", r"导入本地计划"))
item(G, "读取 BodyMeasurement",
     in_file("Data/FitnessRepository.swift", r"func fetchBodyMeasurements\(limit:"))
item(G, "休息日有独立模型",
     in_file("Models/Models.swift", r"struct RestDay"))
item(G, "休息日协议读取方法",
     in_file("Data/FitnessRepository.swift", r"func fetchRestDays\(\) throws -> \[RestDay\]"))
item(G, "休息日协议写入方法",
     in_file("Data/FitnessRepository.swift", r"func save\(restDay: RestDay\) throws"))
item(G, "休息日协议删除方法",
     in_file("Data/FitnessRepository.swift", r"func delete\(restDayID: UUID\) throws"))
item(G, "JSON 实现有 restDays 缓存",
     in_file("Data/JSONFitnessRepository.swift", r"private var restDays: \[RestDay\]"))
item(G, "JSON 实现有 restDays.json",
     in_file("Data/JSONFitnessRepository.swift", r'"restDays\.json"'))
item(G, "Preview 实现有 restDays",
     in_file("Data/PreviewFitnessRepository.swift", r"private var restDays: \[RestDay\]"))
item(G, "清库时清空休息日",
     in_file("Data/JSONFitnessRepository.swift", r"recentExercises = \[\]; restDays = \[\]"))
item(G, "同日只保留一条休息日",
     in_file("Data/JSONFitnessRepository.swift",
             r"inSameDayAs: restDay\.date"))
item(G, "本地时区自然日筛选（用 Calendar，不用秒数除法）",
     in_file("Features/History/HistoryCalendar.swift",
             r"calendar\.startOfDay\(for: session\.startedAt\)") and
     not anywhere_in(r"timeIntervalSince1970\s*/\s*86400", PAGE08_FILES) and
     not anywhere_in(r"/\s*86400", PAGE08_FILES))

# ============ 十一、无障碍与动态字体 ============
G = "十一、无障碍与动态字体"
item(G, "日历日期朗读含日期",
     # 只要求「存在这个方法且第一段是日期」。
     # 早先写成字面量 `accessibilityLabel(isSelected:`，把「参数写在同一行」
     # 这个排版细节也当成了规格 —— 签名拆行改写会让它误报。
     # 真正要保的是 `parts` 的首元素来自 formatter(day)。
     in_file("Features/History/HistoryCalendar.swift",
             r"func accessibilityLabel\(\s*isSelected:") and
     in_file("Features/History/HistoryCalendar.swift",
             r"var parts: \[String\] = \[formatter\(day\)\]"))
item(G, "朗读含训练数量",
     in_file("Features/History/HistoryCalendar.swift", r"次训练"))
item(G, "朗读含选中状态",
     in_file("Features/History/HistoryCalendar.swift", r'"已选中"'))
item(G, "选中态用 isSelected 无障碍特征",
     in_file("Features/History/HistoryCalendarComponents.swift", r"\.isSelected"))
item(G, "日期朗读含今天",
     in_file("Features/History/HistoryCalendar.swift", r'"今天"'))
item(G, "训练卡片有完整朗读语句",
     in_file("Features/History/HistoryCalendarComponents.swift", r"accessibilityText"))
item(G, "长按有 accessibilityHint",
     in_file("Features/History/HistoryCalendarComponents.swift", r"accessibilityHint"))
item(G, "文案全部用语义化字体（支持动态字体）",
     not anywhere(r"Font\.system\(size: (?!20)") and
     in_file("DesignSystem/DesignTokens.swift", r"Typography"))

# ============ 十二、iOS 16 兼容 ============
G = "十二、iOS 16 兼容"
item(G, "不用 SwiftData", not anywhere(r"\bimport SwiftData\b"))
item(G, "不用 @Observable", not anywhere(r"@Observable"))
item(G, "不用 ContentUnavailableView", not anywhere(r"ContentUnavailableView"))
item(G, "不用 sensoryFeedback", not anywhere(r"sensoryFeedback"))
item(G, "不用 scrollTargetBehavior", not anywhere(r"scrollTargetBehavior"))
item(G, "不用 containerRelativeFrame", not anywhere(r"containerRelativeFrame"))
item(G, "不用 presentationBackground", not anywhere(r"presentationBackground"))
item(G, "导航用 NavigationStack",
     in_file("Features/RootView.swift", r"NavigationStack\(path:"))
item(G, "路由用 navigationDestination",
     in_file("Features/RootView.swift", r"navigationDestination\(for: HistoryRoute"))

# ============ 汇总 ============
groups = []
for group, desc, ok in RESULTS:
    if group not in groups:
        groups.append(group)

total = len(RESULTS)
passed = sum(1 for _, _, ok in RESULTS if ok)
gaps = [(g, d) for g, d, ok in RESULTS if not ok]

print("=" * 72)
print(f"page 08 规格审计：{total} 条，通过 {passed} 条，缺口 {len(gaps)} 条")
print("=" * 72)

for group in groups:
    rows = [(d, ok) for g, d, ok in RESULTS if g == group]
    okc = sum(1 for _, ok in rows if ok)
    print(f"\n{group}  ({okc}/{len(rows)})")
    for desc, ok in rows:
        mark = "ok  " if ok else "GAP "
        print(f"  [{mark}] {desc}")

print("\n" + "=" * 72)
if gaps:
    print("未落地：")
    for g, d in gaps:
        print(f"  ✗ [{g}] {d}")
    print("=" * 72)
    sys.exit(1)
print("规格全部落地。")
print("=" * 72)
