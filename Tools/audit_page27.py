#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 27 规格审计（动作添加参数面板）。

用法：
    python Tools/audit_page27.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Exercises/AddToWorkoutSheet.swift"
VM_FILE = "Features/Exercises/ExerciseDetailViewModel.swift"
MODEL_FILE = "Models/Models.swift"


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
VM_CODE = CODE.get(VM_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
PAGE_CODE = VIEW_CODE + "\n" + VM_CODE + "\n" + MODEL_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
print("== 1. 头部 ==")
item("顶部动作名称与主肌群", has(VIEW_CODE, r"exerciseName") and has(VIEW_CODE, r"muscleText"))

# =====================================================================
print("== 2. 字段 ==")
item("正式组数 1-20", has(VIEW_CODE, r"正式组数") and has(VIEW_CODE, r"range: 1\.\.\.20"))
item("最低 / 最高次数 1-100", has(VIEW_CODE, r"range: 1\.\.\.100"))
item("下限不高于上限", has(VIEW_CODE, r"repsHigh < newValue"))
item("默认重量（可选，按单位显示）", has(VIEW_CODE, r"默认重量") and has(VIEW_CODE, r"weightText") and has(VIEW_CODE, r"weightUnit"))
item("组间休息 30-600 + 预设 Chip + 自定义", has(VIEW_CODE, r"restPresets") and has(VIEW_CODE, r"useCustomRest") and has(VIEW_CODE, r"30\.\.\.600"))
item("添加热身组 + 数量 + 重量百分比", has(VIEW_CODE, r"热身组数量") and has(VIEW_CODE, r"warmupPercent") and has(VIEW_CODE, r"添加热身组"))
item("训练备注多行", has(VIEW_CODE, r"训练备注") and has(VIEW_CODE, r"TextEditor"))

# =====================================================================
print("== 3. 上次记录 ==")
item("上次记录摘要", has(VIEW_CODE, r"lastRecordSummary") and has(VIEW_CODE, r"上次记录"))
item("使用上次参数按钮", has(VIEW_CODE, r"使用上次参数") and has(VIEW_CODE, r"onApplyLastRecord"))
item("使用上次参数只填参数不标记完成", has(VM_CODE, r"func applyLastRecord") and not_has(VM_CODE, r"applyLastRecord[\s\S]{0,80}completedAt"))

# =====================================================================
print("== 4. 底部按钮 ==")
item("按钮文案随来源（添加到训练 / 添加到计划）", has(VIEW_CODE, r"targetTitle") and has(VIEW_CODE, r"添加到训练") and has(VIEW_CODE, r"添加到计划"))
item("保存前校验数值（写回处方）", has(VIEW_CODE, r"private func commit") and has(VIEW_CODE, r"repsHigh = prescription\.repsLow"))

# =====================================================================
print("== 5. 值层 ==")
item("处方含重量 / 热身组数 / 百分比 / 备注", has(VM_CODE, r"var weight: Double\?") and has(VM_CODE, r"var warmupCount") and has(VM_CODE, r"var warmupPercent") and has(VM_CODE, r"var note"))
item("默认值来自动作配置（defaultRestSeconds）", has(VM_CODE, r"defaultRestSeconds") and has(VM_CODE, r"static func `default`"))
item("热身组按百分比计重量", has(VM_CODE, r"warmupPercent") and has(VM_CODE, r"expandEntries"))

# =====================================================================
print("== 6. 反规格 ==")
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
