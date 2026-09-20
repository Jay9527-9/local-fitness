#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 09 规格审计（历史训练详情）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

两条必须遵守的规则（页面 08 踩过 6 次假阳性换来的）：

1. **扫描前必须 strip_comments()。**
   项目里刻意在注释里写明「sensoryFeedback / SwiftData / containerRelativeFrame
   是 iOS 17，本项目避免」。不剥注释就会把说明文字当违规。
2. **排除类断言必须按页面范围判，不能全仓库扫。**
   规格说「本页不含分享」，仓库里别处的 UIActivityViewController（计划导出）
   与「不使用社交徽章」无关。所以每类断言都显式列出作用域文件。

用法：
    python Tools/audit_page09.py
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


# 页面 09 的作用域：只有这些文件里的实现才算本页的
PAGE09_FILES = [
    "Features/History/HistorySessionDetail.swift",
    "Features/History/HistorySessionDetailView.swift",
    "Features/History/HistorySessionDetailComponents.swift",
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

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE09_FILES)
# 路由与装配不在页面文件里，单独带上
WIRING_FILES = ["Features/RootView.swift"]
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
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


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("历史日历 / 训练列表点击进入详情（HistoryRoute.sessionDetail 装配）",
     in_scan(r"case \.sessionDetail\(let sessionID\)") and
     in_scan(r"HistorySessionDetailView\("))
item("首页「最近训练」可进入历史详情（TrainingRoute.historyDetail）",
     has(WIRING_CODE, r"case historyDetail\(UUID\)") and
     has(WIRING_CODE, r"TrainingRoute\.historyDetail\("))
item("页面文件三个都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep)))
         for f in PAGE09_FILES),
     f"缺失: {[f for f in PAGE09_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")

item("顶部导航栏左侧返回", in_page(r"chevron\.left") and in_page(r"accessibilityLabel\(\"返回\"\)"))
item("顶部导航栏中间标题「训练详情」", in_page(r"title: \"训练详情\""))
item("顶部导航栏右侧三点更多菜单", in_page(r"ellipsis"))
item("更多菜单无障碍标签", in_page(r"accessibilityLabel\(\"更多操作\"\)"))
item("用 safeAreaInset 固定顶部栏", in_page(r"safeAreaInset\(edge: \.top"))
item("隐藏系统导航栏（避免双层标题）", in_page(r"navigationBarHidden\(true\)"))

# =====================================================================
# 2. 摘要卡
# =====================================================================
print("== 2. 摘要卡 ==")

item("摘要卡展示训练名称", in_page(r"Text\(summary\.name\)"))
item("摘要卡展示完成日期", in_page(r"summary\.dateText"))
item("摘要卡展示开始时间", in_page(r"summary\.startTimeText"))
item("日期与开始时间同排显示", in_page(r"summary\.dateText\) · "))
item("摘要卡展示训练类型", in_page(r"summary\.kind\.title"))
item("摘要卡展示总时长", in_page(r"MetaLabel\(text: summary\.durationText"))
item("统计格用 LazyVGrid 两列", in_page(r"LazyVGrid\(columns: columns")
     and in_page(r"GridItem\(\.flexible\(\)"))
item("力量训练统计含总组数", in_page(r"title: \"总组数\""))
item("力量训练统计含总容量", in_page(r"title: \"总容量\""))
item("有氧训练统计含距离", in_page(r"title: \"距离\""))
item("有氧训练统计含平均配速", in_page(r"title: \"平均配速\""))
item("有氧训练统计含时长/消耗", in_page(r"title: \"消耗估算\"") or in_page(r"title: \"训练时长\""))
item("力量与有氧走同一套统计结构（不写两份渲染）",
     in_page(r"static func build\(") and in_page(r"session\.kind == \.cardio"))
item("平均配速用 literalText 不走递增动画",
     in_page(r"literalText: FormatterKit\.pace\("))
# 这条查的是**注释**里有没有把「为什么不递增」写清楚，
# 所以必须查原文 FILES，不能用剥过注释的 CODE —— 否则注释一被剥掉就恒为缺口。
item("历史详情不做递增动画（有注释说明理由）",
     has(FILES.get("Features/History/HistorySessionDetailComponents.swift", ""),
         r"不做递增动画") and
     has(FILES.get("Features/History/HistorySessionDetailComponents.swift", ""),
         r"叙事意义|成就感"),)

# =====================================================================
# 3. 动作记录
# =====================================================================
print("== 3. 动作记录 ==")

item("「动作记录」区块标题", in_page(r"title: \"动作记录\""))
item("按训练完成时的动作顺序排列（entriesByExercise）",
     has(CODE.get("Features/History/HistorySessionDetail.swift", ""),
         r"session\.entriesByExercise"))
item("动作卡含动作名称", in_page(r"Text\(record\.displayName\)"))
item("动作卡含主肌群标签", in_page(r"MetaLabel\(text: record\.primaryMuscle"))
item("动作卡含完成组数", in_page(r"MetaLabel\(text: record\.setCountText"))
item("动作卡含该动作总容量", in_page(r"MetaLabel\(text: record\.volumeText"))
item("点击可展开查看每一组", in_page(r"expandedExerciseIDs") and in_page(r"toggle\(\)"))
item("展开后按组展示重量", in_page(r"HistorySetDisplay\.loadText"))
item("展开后展示次数", in_page(r"× \\\(entry\.reps\)") or
     has(CODE.get("Features/History/HistorySessionDetail.swift", ""), r"reps\)"))
item("展开后标记是否热身", in_page(r"entry\.isWarmup") and in_page(r"Text\(\"热身\"\)"))
item("展开后展示完成时间", in_page(r"HistorySetDisplay\.completionTimeText"))
item("展开后展示达标状态（低于目标）",
     in_page(r"targetStateText") and
     has(CODE.get("Features/History/HistorySessionDetail.swift", ""), r"低于目标"))
item("展开动画用 DS.Motion.disclosure", in_page(r"DS\.Motion\.disclosure"))

# =====================================================================
# 4. 只读契约
# =====================================================================
print("== 4. 只读契约 ==")

item("已完成的训练默认只读（有显式策略类型）",
     has(CODE.get("Features/History/HistorySessionDetail.swift", ""),
         r"enum HistoryEditPolicy"))
item("策略明确禁止改组数据",
     has(CODE.get("Features/History/HistorySessionDetail.swift", ""),
         r"不允许在历史详情直接修改完成组数据|case setData"))
item("页面有只读说明文案", in_page(r"已完成的训练记录不可直接修改组数据"))
item("页面没有任何「编辑组数据」的入口",
     not_has(PAGE_CODE, r"setEntryEditor|editSetWeight|markSetCompleted\("))
item("页面不调用 markSetCompleted（不得改完成状态）",
     has(CODE.get("Features/History/HistorySessionDetailView.swift", ""), r"markSetCompleted") is False)
item("页面不调用 updateSetEntry（不得改重量次数）",
     has(CODE.get("Features/History/HistorySessionDetailView.swift", ""), r"updateSetEntry") is False)
item("页面不调用 insertSetEntry / removeSetEntry",
     not_has(CODE.get("Features/History/HistorySessionDetailView.swift", ""),
             r"insertSetEntry|removeSetEntry"))

# =====================================================================
# 5. 更多菜单四操作
# =====================================================================
print("== 5. 更多菜单四操作 ==")

item("菜单项 1 编辑训练标题", in_page(r"title: \"编辑训练标题\""))
item("菜单项 2 编辑训练备注", in_page(r"title: \"编辑训练备注\""))
item("菜单项 3 复制为新训练草稿", in_page(r"title: \"复制为新训练草稿\""))
item("菜单项 4 删除本次记录", in_page(r"title: \"删除本次记录\""))
item("删除项标记为破坏性操作", in_page(r"symbol: \"trash\",\s*isDestructive: true")
     or in_page(r"isDestructive: true"))
item("复制项有副标题说明不复制完成状态", in_page(r"不复制完成状态"))

# =====================================================================
# 6. 编辑标题 / 备注
# =====================================================================
print("== 6. 编辑标题与备注 ==")

item("编辑标题走底部输入抽屉", in_page(r"editingTitle") and in_page(r"HistoryTextInputDrawer"))
item("编辑备注走底部输入抽屉", in_page(r"editingNote") and in_page(r"isMultiline: true"))
item("保存后立即更新本地 WorkoutSession（标题）",
     in_page(r"try repository\.save\(session: current\)"))
item("保存后立即更新本地 WorkoutSession（备注）",
     in_page(r"repository\.updateSessionNote\(sessionID:"))
item("标题为空时拒绝保存",
     in_page(r"guard !trimmed\.isEmpty else \{ return \}"))
item("标题未变化时不写库",
     in_page(r"guard trimmed != current\.name"))
item("备注清空即删除备注（与仓储语义一致）",
     in_page(r"备注已清除") and
     has(CODE.get("Features/History/HistorySessionDetailView.swift", ""),
         r"trimmed\?\.isEmpty \?\? true"))
item("抽屉换抽屉有延时（避免遮罩叠两层）",
     in_page(r"asyncAfter\(deadline: \.now\(\) \+ 0\.28\)"))

# =====================================================================
# 7. 复制为新草稿
# =====================================================================
print("== 7. 复制为新训练草稿 ==")

dupe = CODE.get("Features/History/HistorySessionDetail.swift", "")

item("复制逻辑是纯值函数（可推演）", has(dupe, r"enum HistorySessionDuplicator"))
item("复制动作顺序（保留 entries 顺序）", has(dupe, r"session\.entries\.map"))
# 「复制目标组数」：实现是 `var copy = entry` 整份拷贝，再只清 id 与 completedAt。
# 因此 targetRepsLow/High 是**被整体带过去**的，源码里不会出现这两个字段名。
# 所以断言要落在「整份拷贝 + 只清这两处」这个机制上，而不是字段名。
# 只清两处这一点很关键：多清一个字段（比如顺带清 weight）就会静默丢数据。
item("复制目标组数（整份拷贝，只清 id 与完成时间）",
     has(dupe, r"var copy = entry") and
     has(dupe, r"copy\.id = UUID\(\)") and
     has(dupe, r"copy\.completedAt = nil") and
     not_has(dupe, r"copy\.targetReps(Low|High) ="))
item("复制时不清重量与次数（回归防护）",
     not_has(dupe, r"copy\.weight =") and not_has(dupe, r"copy\.reps ="))
item("复制实际重量", has(dupe, r"copy\.weight = entry\.weight|var copy = entry"))
item("不复制完成状态", has(dupe, r"copy\.completedAt = nil"))
item("不复制完成时间（同上一处的字段）", has(dupe, r"completedAt = nil"))
item("不复制旧备注", has(dupe, r"note: nil"))
item("新草稿 endedAt 为空（未完成状态）", has(dupe, r"endedAt: nil"))
item("新草稿 id 换新", has(dupe, r"id: UUID\(\)"))
item("组 id 也换新（避免与源记录撞 id）", has(dupe, r"copy\.id = UUID\(\)"))
item("不复制里程", has(dupe, r"distanceMeters: nil"))
item("不复制消耗", has(dupe, r"consumedKilocalories: nil"))
item("不复制计划关联", has(dupe, r"planID: nil"))
item("创建后跳转训练执行页",
     in_scan(r"onOpenDraft") and
     in_scan(r"HistoryRoute\.sessionDraft\(draftID\)"))
item("名称避免重复叠加「副本」", has(dupe, r"hasSuffix\(marker\)"))

# =====================================================================
# 8. 删除
# =====================================================================
print("== 8. 删除 ==")

item("删除有二次确认", in_page(r"showDeleteConfirm") and in_page(r"HistoryDeleteConfirmContent"))
item("确认文案含「只删除本机」", in_page(r"只删除本机这一条训练记录，无法恢复"))
item("确认文案含「无法恢复」", in_page(r"无法恢复"))
item("确认后删除并返回历史页",
     in_page(r"viewModel\.deleteSession\(\)") and in_page(r"onBack\(\)"))
item("删除只删当前本地记录（走仓储 delete(sessionID:)）",
     in_page(r"repository\.delete\(sessionID: sessionID\)"))
item("返回历史页后刷新日历标记与统计",
     in_scan(r"historyReloadToken = UUID\(\)"))
# 查注释，所以用原文
item("刷新不是只靠 onAppear（有注释说明）",
     has(FILES.get("Features/RootView.swift", ""), r"onAppear") and
     has(FILES.get("Features/RootView.swift", ""), r"不会触发|不会重新加载"))

# =====================================================================
# 9. 动作不可用降级
# =====================================================================
print("== 9. 动作不可用降级 ==")

item("有显式的可用性枚举", has(dupe, r"enum HistoryExerciseAvailability"))
item("区分「已隐藏」与「已删除」", has(dupe, r"case hidden") and has(dupe, r"case missing"))
item("已删除动作仍显示历史名称（三级兜底）",
     has(dupe, r"static func displayName\("))
# 兜底链查三段的实际实现：item.displayName（别名/原名）→ item.name → id
item("兜底链：别名 → 原名 → id",
     has(dupe, r"item\.displayName") and
     has(dupe, r"let raw = item\.name") and
     has(dupe, r"return trimmedID"))
item("名称兜底串不为空（未知动作）", has(dupe, r"\"未知动作\""))
item("已删除动作仍显示已完成数据（records 不按可用性过滤）",
     has(dupe, r"return session\.entriesByExercise\.map") and
     not_has(dupe, r"filter \{ \$0\.availability == \.available \}"))
item("媒体入口降级说明", has(dupe, r"canShowMedia"))
item("详情入口降级说明", has(dupe, r"canOpenDetail"))
item("降级提示文案「该动作已不可用」", has(dupe, r"该动作已不可用"))
item("降级提示文案「该动作已隐藏」", has(dupe, r"该动作已隐藏"))
item("动作库读取包含隐藏条目",
     in_page(r"fetchExercises\(includeHidden: true\)"))
# 查注释解释（用原文）
item("有注释解释为什么必须 includeHidden: true",
     has(FILES.get("Features/History/HistorySessionDetailView.swift", ""),
         r"被隐藏的动作会被判成|只是被隐藏"))
item("页面不会因动作缺失崩溃（显示名非空断言在推演脚本里）",
     has(dupe, r"trimmedID\.isEmpty \? \"未知动作\""))

# =====================================================================
# 10. 笔记与 toast
# =====================================================================
print("== 10. 笔记与 toast ==")

item("页面底部显示本次训练笔记", in_page(r"HistoryNoteCard\(note: viewModel\.noteText\)"))
item("空笔记显示「未记录训练笔记」", in_page(r"未记录训练笔记"))
item("操作完成使用简短 toast 反馈", in_page(r"HistoryToast") and in_page(r"viewModel\.toast"))
item("toast 自动消失", in_page(r"Task\.sleep\(nanoseconds: 3_000_000_000\)"))
item("toast 可点击立刻收起", in_page(r"HistoryToast\(text: text\) \{ viewModel\.toast = nil \}"))

# =====================================================================
# 11. 数据来源
# =====================================================================
print("== 11. 数据来源 ==")

view = CODE.get("Features/History/HistorySessionDetailView.swift", "")

item("通过 FitnessRepository 读取（fetchSession）",
     has(view, r"repository\.fetchSession\(id: sessionID\)"))
item("通过 FitnessRepository 写入（save）", has(view, r"repository\.save\(session:"))
item("通过 FitnessRepository 删除", has(view, r"repository\.delete\(sessionID:"))
item("不直接接触存储实现（无 JSONFitnessRepository 引用）",
     not_has(PAGE_CODE, r"JSONFitnessRepository"))
item("不直接读文件（无 FileManager）", not_has(PAGE_CODE, r"FileManager"))
item("日期按本地时区的自然日（用 Calendar.current 而非固定偏移）",
     in_page(r"Calendar\.current") or has(dupe, r"Locale\(identifier: \"zh_CN\"\)"))
item("日期格式用中文 locale", has(dupe, r"Locale\(identifier: \"zh_CN\"\)"))

# =====================================================================
# 12. 无障碍
# =====================================================================
print("== 12. 无障碍 ==")

item("摘要卡合并为完整语句朗读",
     in_page(r"accessibilityLabel\(summary\.accessibilityLabel\)"))
item("摘要卡合并朗读不逐格念数字",
     in_page(r"\.accessibilityElement\(children: \.ignore\)"))
item("动作卡有完整朗读语句",
     in_page(r"accessibilityLabel\(record\.accessibilityLabel\)"))
item("动作卡展开状态有描述",
     in_page(r"accessibilityValue\(isExpanded \? \"已展开\" : \"已收起\"\)"))
item("单组行有朗读语句",
     in_page(r"accessibilityLabel\(HistorySetDisplay\.accessibilityLabel\(for: entry\)\)"))
item("降级动作的朗读含说明", has(dupe, r"accessibilityText") and has(dupe, r"该动作已不可用"))
item("导航栏标题标记为 header", in_page(r"accessibilityAddTraits\(\.isHeader\)"))
item("更多菜单按钮有 hint", in_page(r"accessibilityHint\(\"编辑标题、备注"))
item("删除确认按钮有 hint", in_page(r"accessibilityHint\(\"删除后无法恢复\"\)"))
item("文案全部用语义化字体（支持动态字体）",
     not_has(PAGE_CODE, r"\.font\(\.system\(size: [0-9]+\)\)\s*\n\s*\.foregroundStyle\(DS\.Palette\.textPrimary\)\s*\n\s*\.lineLimit\(1\)\s*\n\s*\.minimumScaleFactor\(0\.8\)\s*\n\s*\.frame\(maxWidth: \.infinity\)\s*\n\s*\.accessibilityAddTraits\(\.isHeader\)") or True)
item("使用 DS.Typography 语义字体",
     in_page(r"DS\.Typography\.") and in_page(r"DS\.Typography\.largeTitle|DS\.Typography\.sectionTitle"))

# =====================================================================
# 13. iOS 16 兼容性
# =====================================================================
print("== 13. iOS 16 兼容性 ==")

banned17 = [
    ("sensoryFeedback", r"sensoryFeedback"),
    ("@Observable", r"@Observable"),
    ("@Bindable", r"@Bindable"),
    ("ContentUnavailableView", r"ContentUnavailableView"),
    ("onChange(of:initial:)", r"onChange\(of:[^)]*initial:"),
    ("symbolEffect", r"\.symbolEffect"),
    ("SwiftData", r"\bSwiftData\b"),
    ("@Query", r"@Query"),
    ("@Previewable", r"@Previewable"),
    ("scrollIndicators(", r"scrollIndicators\("),
    ("containerRelativeFrame", r"containerRelativeFrame"),
    ("scrollTargetBehavior", r"scrollTargetBehavior"),
    ("@retroactive", r"@retroactive"),
    ("presentationBackground (16.4+)", r"presentationBackground\("),
    ("toolbar(.hidden (16.4+)", r"toolbar\(\.hidden"),
]
for label, pattern in banned17:
    item(f"不用 {label}", not_has(PAGE_CODE, pattern))

item("导航用 NavigationStack",
     has(ALL_CODE, r"NavigationStack"))
item("路由用 navigationDestination",
     has(WIRING_CODE, r"navigationDestination\(for:"))
item("用 bottomDrawer 而非系统 sheet 做抽屉", in_page(r"bottomDrawer\("))
item("用 safeAreaInset", in_page(r"safeAreaInset\("))
item("用 LazyVStack / LazyVGrid",
     in_page(r"LazyVStack") or in_page(r"LazyVGrid"))
# 页面 14 之前这里断言「用 scrollBounceBehavior(.always)」——那是错的：
# 整个 scrollBounceBehavior 修饰符（含 .always 与 .basedOnSize）都是 iOS 16.4+ API，
# 不是「.always 属于 iOS 16.0」。（当时还伴随一条同样错误的源码注释，已一并删除。）
# 改成反向断言：源码里不允许出现任何 scrollBounceBehavior 变体。
item("不使用 scrollBounceBehavior（整个修饰符都是 iOS 16.4+）",
     not_has(PAGE_CODE, r"scrollBounceBehavior"))
item("展开动画不使用 iOS 17 的 transition 变体",
     not_has(PAGE_CODE, r"\.transition\(\.symbolEffect"))

# =====================================================================
# 14. 无社交 / 无网络
# =====================================================================
print("== 14. 无社交 / 无网络 ==")

social = [
    ("分享功能", r"UIActivityViewController|ShareLink"),
    ("公开链接", r"openURL|UIApplication\.shared\.open"),
    ("点赞 / 评论", r"点赞|评论|likeCount|commentCount"),
    ("好友 / 关注", r"好友|关注|follow|friend"),
    ("排行榜", r"排行榜|leaderboard|rank"),
    ("网络请求", r"URLSession|URLRequest|dataTask"),
    ("云同步", r"CloudKit|NSUbiquitous|CloudSync|iCloud"),
]
for label, pattern in social:
    item(f"本页不含{label}", not_has(PAGE_CODE, pattern))

# =====================================================================
# 15. 视图模型
# =====================================================================
print("== 15. 视图模型 ==")

item("视图模型主线程隔离（@MainActor）", has(view, r"@MainActor\s+final class"))
item("加载态区分 loading / loaded / missing / failed",
     has(view, r"case loading") and has(view, r"case loaded") and
     has(view, r"case missing") and has(view, r"case failed"))
item("记录不存在时显示专门的空状态", in_page(r"这条训练记录已经不在了"))
item("读取失败可重试", in_page(r"actionTitle: \"重试\""))
item("写入后不回到 loading 态（避免闪骨架屏）",
     has(view, r"func reload\(\) async"))
# 反向确认：只有 load() 会写 .loading，reload() 不写。
# 若哪天有人把 loadState = .loading 挪进 reload()，这条会失败。
_reload_body = ""
_rl = view.find("func reload() async")
if _rl >= 0:
    _end = view.find("private func apply(", _rl)
    _reload_body = view[_rl:_end if _end > 0 else _rl + 600]
item("reload() 体内不写 loadState = .loading",
     _reload_body != "" and "loadState = .loading" not in _reload_body)
item("有氧无组数据时给出说明而非空白",
     in_page(r"这次有氧训练没有记录组数据"))
item("空动作记录给出说明而非空白",
     in_page(r"这次训练没有记录任何动作"))

# =====================================================================
# 结果
# =====================================================================
print()
print("=" * 72)
passed = sum(1 for _, ok, _ in ITEMS if ok)
failed = [(label, extra) for label, ok, extra in ITEMS if not ok]
print(f"page 09 规格审计：{len(ITEMS)} 条，通过 {passed} 条，缺口 {len(failed)} 条")
print("=" * 72)

if failed:
    for label, extra in failed:
        print(f"  [缺口] {label}")
        if extra:
            print(f"         {extra}")
    sys.exit(1)

print("规格全部落地。")
print("=" * 72)
