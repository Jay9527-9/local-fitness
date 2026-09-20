#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 39 规格审计（计划动作替换）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/Plans/ReplaceExerciseView.swift"]


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


print("== 1. 导航 / 头部 ==")
item("取消 / 替换动作 / 当前动作信息", has(VIEW, r"\"取消\"") and has(VIEW, r"\"替换动作\"") and has(VIEW, r"currentHeader"))

print("== 2. 推荐替换 ==")
item("推荐替换（同肌群/相近器械）", has(VIEW, r"推荐替换") and has(VIEW, r"ReplaceRecommendation"))
item("全部动作入口", has(VIEW, r"全部动作") and has(VIEW, r"showAll"))

print("== 3. 确认抽屉 ==")
item("新旧对比", has(VIEW, r"原动作") and has(VIEW, r"新动作"))
item("三种参数迁移策略", has(VIEW, r"保留现有组数、次数和休息时间") and has(VIEW, r"仅保留组数与次数") and has(VIEW, r"使用新动作的默认参数"))

print("== 4. 重复检测 ==")
item("替换目标已在计划中提示", has(VIEW, r"已在计划中") and has(VIEW, r"existingIDsInPlan"))

print("== 5. 反规格 ==")
item("不调用网络 / AI", not_has(VIEW, r"URLSession|URLRequest|OpenAI|AI"))
item("不含 iOS 17 API", not_has(VIEW, r"@Observable|sensoryFeedback|ContentUnavailableView"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
