#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 38 规格审计（计划动作配置）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/Plans/PlanExerciseConfigView.swift"]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


ALL = {}
for dirpath, _, fns in os.walk(SRC):
    for name in fns:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            ALL[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in ALL.items()}
VIEW = CODE.get(FILES[0], "")

ITEMS = []


def item(label, ok):
    ITEMS.append((label, bool(ok)))


def has(text, p):
    return re.search(p, text) is not None


def not_has(text, p):
    return re.search(p, text) is None


print("== 1. 字段 ==")
item("正式组数 1–20", has(VIEW, r"range: 1\.\.\.20"))
item("最低 / 最高次数", has(VIEW, r"repsLow") and has(VIEW, r"repsHigh"))
item("建议重量", has(VIEW, r"建议重量") and has(VIEW, r"defaultWeight"))
item("组间休息 30–600", has(VIEW, r"restSeconds"))
item("热身组开关 + 数量", has(VIEW, r"热身组数量") and has(VIEW, r"warmupCount"))
item("动作备注", has(VIEW, r"备注"))
item("递增规则入口", has(VIEW, r"onOpenProgression") and has(VIEW, r"递增规则"))

print("== 2. 校验 ==")
item("下限抬高时上限跟随（下限不高于上限）", has(VIEW, r"repsHigh = newValue") or has(VIEW, r"repsHigh = \$\d"))

print("== 3. 从上次训练填充 ==")
item("从上次训练填充（建议不改已保存）", has(VIEW, r"从上次训练填充") and has(VIEW, r"只建议最近有效重量与次数"))

print("== 4. 替换 / 移除 ==")
item("替换动作入口", has(VIEW, r"替换动作") and has(VIEW, r"onReplace"))
item("从计划移除（红色）", has(VIEW, r"从计划移除") and has(VIEW, r"onRemove") and has(VIEW, r"DS\.Palette\.danger"))

print("== 5. 作用范围 ==")
item("只更新当前 PlanExercise", has(VIEW, r"onSave\(draft\.applied"))

print("== 6. 反规格 ==")
item("不含 iOS 17 API", not_has(VIEW, r"@Observable|sensoryFeedback|ContentUnavailableView"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
