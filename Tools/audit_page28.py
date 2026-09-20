#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 28 规格审计（选择要添加到的计划）。

用法：
    python Tools/audit_page28.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Plans/SelectPlanView.swift"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
VIEW_CODE = CODE.get(VIEW_FILE, "")
PAGE_CODE = VIEW_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
print("== 1. 导航 ==")
item("左侧取消 / 中间选择计划 / 右侧新建计划", has(VIEW_CODE, r"\"取消\"") and has(VIEW_CODE, r"\"选择计划\"") and has(VIEW_CODE, r"\"新建计划\""))

# =====================================================================
print("== 2. 搜索与排序 ==")
item("搜索框按名称实时筛选", has(VIEW_CODE, r"searchField") and has(VIEW_CODE, r"按计划名称筛选"))
item("排序（最近使用 / 最近创建 / 名称）", has(VIEW_CODE, r"case recentlyUsed") and has(VIEW_CODE, r"case recentlyCreated") and has(VIEW_CODE, r"case name"))

# =====================================================================
print("== 3. 列表 ==")
item("行显示名称 / 天数 / 动作数 / 上次使用 / chevron", has(VIEW_CODE, r"frequencyText") and has(VIEW_CODE, r"个动作") and has(VIEW_CODE, r"上次") and has(VIEW_CODE, r"chevron\.right"))

# =====================================================================
print("== 4. 冲突处理 ==")
item("检测计划已含该动作", has(VIEW_CODE, r"planContains") and has(VIEW_CODE, r"containsExercise"))
item("提示「计划已包含该动作」", has(VIEW_CODE, r"计划已包含该动作"))
item("三个选项（新增一份 / 替换原配置 / 取消）", has(VIEW_CODE, r"新增一份") and has(VIEW_CODE, r"替换原配置") and has(VIEW_CODE, r"取消"))

# =====================================================================
print("== 5. 新建计划 ==")
item("简化新建：名称 + 每周训练天数", has(VIEW_CODE, r"计划名称") and has(VIEW_CODE, r"每周训练天数"))

# =====================================================================
print("== 6. 空状态与反规格 ==")
item("空状态「还没有训练计划」+ 新建计划", has(VIEW_CODE, r"还没有训练计划") and has(VIEW_CODE, r"新建计划"))
item("不展示官方 / 公开 / 他人计划", not_has(VIEW_CODE, r"官方计划|公开计划|好友计划|社区|URLSession"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
