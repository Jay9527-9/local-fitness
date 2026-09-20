#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 40 规格审计（计划递增规则设置）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/Plans/ProgressionRuleView.swift", "Models/Models.swift"]


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
MODEL = CODE.get(FILES[1], "")
PAGE = VIEW + "\n" + MODEL

ITEMS = []


def item(label, ok):
    ITEMS.append((label, bool(ok)))


def has(text, p):
    return re.search(p, text) is not None


def not_has(text, p):
    return re.search(p, text) is None


print("== 1. 导航 / 说明 ==")
item("返回 / 递增规则 / 保存", has(VIEW, r"\"递增规则\"") and has(VIEW, r"\"保存\""))
item("说明卡（只建议不强制）", has(VIEW, r"不自动修改已完成训练") and has(VIEW, r"不强制变更"))

print("== 2. 启用开关 ==")
item("启用递增建议开关", has(VIEW, r"启用递增建议") and has(VIEW, r"isEnabled"))

print("== 3. 配置项 ==")
item("达标条件", has(VIEW, r"达标条件") and has(VIEW, r"ProgressionCondition"))
item("递增方式", has(VIEW, r"递增方式") and has(VIEW, r"ProgressionMethod"))
item("重量 / 次数增幅", has(VIEW, r"重量增幅") and has(VIEW, r"次数增幅"))
item("未达标处理", has(VIEW, r"未达标处理") and has(VIEW, r"MissedTargetAction"))
item("降载规则", has(VIEW, r"降载规则") and has(VIEW, r"deloadEnabled"))

print("== 4. 示例预览 ==")
item("两条示例预览", has(VIEW, r"示例预览") and has(VIEW, r"若本次完成") and has(VIEW, r"若未完成目标"))
item("预览不写入数据", has(VIEW, r"不写入训练数据"))

print("== 5. 校验 ==")
item("校验失败显示中文原因", has(MODEL, r"validationError") and has(MODEL, r"重量增幅需在") and has(VIEW, r"validationMessage"))

print("== 6. 反规格 ==")
item("不含 iOS 17 API", not_has(PAGE, r"@Observable|sensoryFeedback|ContentUnavailableView"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
