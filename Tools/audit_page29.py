#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 29 规格审计（进行中训练选择菜单）。

用法：
    python Tools/audit_page29.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Training/ActiveSessionPicker.swift"


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
print("== 1. 抽屉 ==")
item("标题「添加到进行中训练」", has(VIEW_CODE, r"添加到进行中训练"))

# =====================================================================
print("== 2. 训练卡 ==")
item("卡片显示名称 / 开始时间 / 时长 / 组数 / 类型", has(VIEW_CODE, r"session\.name") and has(VIEW_CODE, r"已进行") and has(VIEW_CODE, r"组") and has(VIEW_CODE, r"kind\.title"))
item("当前训练标签", has(VIEW_CODE, r"当前训练") and has(VIEW_CODE, r"currentSessionID"))
item("当前训练优先排序", has(VIEW_CODE, r"sortedSessions") and has(VIEW_CODE, r"currentSessionID"))

# =====================================================================
print("== 3. 放弃草稿 ==")
item("长按「放弃此训练草稿」", has(VIEW_CODE, r"contextMenu") and has(VIEW_CODE, r"放弃此训练草稿"))
item("只删未完成草稿（onDiscard 由上层调用 delete）", has(VIEW_CODE, r"onDiscard"))

# =====================================================================
print("== 4. 空状态 ==")
item("空状态「没有进行中的训练」", has(VIEW_CODE, r"没有进行中的训练"))
item("新建力量训练 / 新建有氧训练按钮", has(VIEW_CODE, r"新建力量训练") and has(VIEW_CODE, r"新建有氧训练"))

# =====================================================================
print("== 5. 反规格 ==")
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
