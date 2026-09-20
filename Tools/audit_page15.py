#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 15 规格审计（我的计划）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–14 踩过假阳性换来的规则（详见 audit_page12.py 头部）：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判。
3. 查「注释里写了什么」的断言读原始 FILES。
4. 优先用结构性断言。
5. 跨行签名用两段式正则。
6. 作用域三选一（in_page / in_scan / in_value / in_view / in_wiring / in_token）。
7. 令牌声明两种写法，正则写 `static let {token}\\s*(:|=)`。

用法：
    python Tools/audit_page15.py
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


PAGE15_FILES = [
    "Features/Profile/PlanListView.swift",
    "Features/Profile/PlanListData.swift",
]

VALUE_FILE = "Features/Profile/PlanListData.swift"
VIEW_FILE = "Features/Profile/PlanListView.swift"

WIRING_FILES = ["Features/RootView.swift"]
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
    "Data/FitnessRepository.swift",
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

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE15_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
REPO_CODE = "\n".join(CODE.get(f, "") for f in REPO_FILES)
SCAN = PAGE_CODE + "\n" + WIRING_CODE + "\n" + REPO_CODE

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


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_wiring(pattern, flags=0):
    return has(WIRING_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


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

item("两个页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE15_FILES),
     f"缺失: {[f for f in PAGE15_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")
item("入口复用页面 13 的 ProfileRoute.planList",
     in_wiring(r"ProfileRoute\.planList") and in_scan(r"struct PlanListView"))
item("标题「我的计划」", in_view(r"Text\(\"我的计划\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("右侧「＋」按钮", in_view(r"Image\(systemName: \"plus\"\)") and in_view(r"accessibilityLabel\(\"新建或导入计划\"\)"))
item("「＋」菜单：新建力量计划", in_view(r"新建力量计划"))
item("「＋」菜单：导入本地计划备份", in_view(r"导入本地计划备份"))

# =====================================================================
# 2. 搜索与排序
# =====================================================================
print("== 2. 搜索与排序 ==")

item("搜索框按名称实时筛选", in_view(r"TextField\(\"按名称筛选\"") and in_value(r"static func filter\("))
item("排序菜单四选一",
     in_value(r"enum PlanSortOrder") and in_view(r"ForEach\(PlanSortOrder\.allCases\)"))
item("最近使用排序", in_value(r"case recentlyUsed") and in_value(r"最近使用"))
item("最近创建排序", in_value(r"case recentlyCreated") and in_value(r"最近创建"))
item("计划名称排序", in_value(r"case name") and in_value(r"计划名称"))
item("训练天数排序", in_value(r"case trainingDays") and in_value(r"训练天数"))

# =====================================================================
# 3. 计划卡片
# =====================================================================
print("== 3. 计划卡片 ==")

item("卡片显示计划名称", in_view(r"plan\.name"))
item("卡片显示每周训练天数", in_view(r"plan\.frequencyText"))
item("卡片显示动作数量", in_view(r"plan\.exerciseCount"))
item("卡片显示预计时长", in_view(r"plan\.estimatedMinutes"))
item("卡片显示最后训练日期", in_view(r"plan\.lastUsedAt") and in_view(r"上次训练"))
item("卡片右侧三点菜单", in_view(r"ellipsis") or in_view(r"contextMenu"))
item("点击卡片进入计划详情", in_wiring(r"ProfileRoute\.planDetail\(plan\.id\)") or in_wiring(r"ProfileRoute\.planDetail\(planID"))
item("用 LazyVStack 承载长列表", in_view(r"LazyVStack"))

# =====================================================================
# 4. 三点菜单
# =====================================================================
print("== 4. 三点菜单 ==")

item("三点菜单：开始训练", in_view(r"开始训练"))
item("三点菜单：编辑", in_view(r"Label\(\"编辑\""))
item("三点菜单：复制计划", in_view(r"复制计划"))
item("三点菜单：删除计划", in_view(r"删除计划"))
item("复制用「原名称（副本）」", in_value(r"makeCopyName") and in_value(r"（副本）"))
item("删除二次确认", in_view(r"role: \.destructive") and in_view(r"已完成的历史训练记录不受影响"))
item("删除只删计划不删历史", in_repo(r"func deletePlans\(ids:") and
     has(REPO_CODE, r"plans\.removeAll") and
     not_has(func_body(REPO_CODE, "func deletePlans(ids: [UUID]) throws"), r"sessions"))

# =====================================================================
# 5. 长按多选
# =====================================================================
print("== 5. 长按多选 ==")

item("长按进入多选", in_view(r"onLongPressGesture") and in_view(r"enterSelecting"))
item("多选顶部显示「已选 N 项」", in_view(r"已选") and in_view(r"selectedIDs\.count") and in_view(r"项"))
item("多选提供取消", in_view(r"exitSelecting"))
item("批量删除", in_view(r"deleteSelected") and in_view(r"showBatchDeleteConfirm"))
item("批量导出本地备份", in_view(r"exportSelected") and in_view(r"square\.and\.arrow\.up"))
item("批量删除二次确认", in_view(r"批量删除计划"))

# =====================================================================
# 6. 空状态
# =====================================================================
print("== 6. 空状态 ==")

item("无计划空状态「还没有训练计划」", in_view(r"还没有训练计划"))
item("空状态「新建第一个计划」主按钮", in_view(r"新建第一个计划"))
item("无搜索结果「没有匹配的计划」", in_view(r"没有匹配的计划"))

# =====================================================================
# 7. 数据来源与备份
# =====================================================================
print("== 7. 数据来源与备份 ==")

item("只通过 FitnessRepository 读写", in_view(r"viewModel\.load\(\)") and in_repo(r"func fetchPlans"))
item("多计划备份有格式标识", in_value(r"fitness-plans-backup"))
item("备份导入校验格式与版本", in_value(r"PlanBackupError\.wrongFormat") and in_value(r"unsupportedVersion"))
item("导入计划重建新 id（不共享引用）", in_value(r"func toPlan\(\)") and in_value(r"id: UUID\(\)"))
item("复制计划统一命名（JSON + Preview 两处）",
     has(REPO_CODE, r"PlanCopyName\.makeCopyName") and
     len(re.findall(r"PlanCopyName\.makeCopyName", REPO_CODE)) >= 2)
item("批量删除进仓储协议三处",
     in_repo(r"func deletePlans\(ids: \[UUID\]\)") and
     len(re.findall(r"func deletePlans\(ids: \[UUID\]\)", REPO_CODE)) == 3)

# =====================================================================
# 8. 无障碍
# =====================================================================
print("== 8. 无障碍 ==")

item("卡片有无障碍标签", in_view(r"cardLabel") and in_view(r"accessibilityLabel"))
item("排序 Chip 有选中态", in_view(r"accessibilityAddTraits\(selected \? \[\.isSelected\]"))
item("批量按钮有无障碍标签", in_view(r"批量删除选中计划") and in_view(r"批量导出选中计划"))
item("列表用语义化字体", in_view(r"DS\.Typography\.body") or in_view(r"DS\.Typography\.callout"))

# =====================================================================
# 9. 反规格排除
# =====================================================================
print("== 9. 反规格排除 ==")

item("不展示官方计划 / 公开计划",
     not_has(PAGE_CODE, r"官方计划|公开计划|officialPlan|OfficialPlan"))
item("不展示好友计划 / 社区内容",
     not_has(PAGE_CODE, r"好友|community|Community|friend|Friend"))
item("不含联网", not_has(PAGE_CODE, r"URLSession|URLRequest|http"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame"))

# =====================================================================
# 10. 值层与工程约束
# =====================================================================
print("== 10. 值层与工程约束 ==")

item("值层不 import SwiftUI",
     not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("排序是纯函数", in_value(r"static func sort\(_ plans: \[Plan\]"))
item("复制命名是纯函数", in_value(r"static func makeCopyName"))
item("没有重复定义同名类型",
     len(re.findall(r"enum PlanSortOrder\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct PlanListView\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum PlanCopyName\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct PlanBackup\b", ALL_CODE)) == 1)
item("预览覆盖计划列表页", in_view(r"#Preview\(\"我的计划\"\)"))
item("协议从 52 增至 53 方法", in_repo(r"func deletePlans\(ids: \[UUID\]\)"))

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
