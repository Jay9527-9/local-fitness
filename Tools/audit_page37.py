#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 37 规格审计（复制训练记录为草稿）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/History/SessionCopySheet.swift", "Features/History/HistorySessionDetail.swift"]


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
PAGE = VIEW + "\n" + CODE.get(FILES[1], "")

ITEMS = []


def item(label, ok):
    ITEMS.append((label, bool(ok)))


def has(text, p):
    return re.search(p, text) is not None


def not_has(text, p):
    return re.search(p, text) is None


print("== 1. 头部 ==")
item("标题「复制为新训练」+ 来源摘要", has(VIEW, r"复制为新训练") and has(VIEW, r"sourceName") and has(VIEW, r"个动作"))

print("== 2. 复制选项 ==")
item("动作顺序与组数（默认开不可关）", has(VIEW, r"复制动作顺序与组数") and has(VIEW, r"默认开启，不可关闭"))
item("复制最近重量与次数（默认开）", has(VIEW, r"复制最近实际重量与次数") and has(VIEW, r"copyWeightsAndReps = true"))
item("复制热身组（默认关）", has(VIEW, r"复制热身组") and has(VIEW, r"copyWarmupSets = false"))
item("复制训练备注（默认关）", has(VIEW, r"复制训练备注") and has(VIEW, r"copyNote = false"))
item("复制每组备注（默认关）", has(VIEW, r"复制每组备注") and has(VIEW, r"copySetNotes = false"))

print("== 3. 未完成说明 ==")
item("所有组未完成 + 不复制完成时间/历史ID", has(VIEW, r"未完成状态") and has(VIEW, r"不会复制"))

print("== 4. 冲突处理 ==")
item("存在未结束训练时提示", has(VIEW, r"hasActiveSession") and has(VIEW, r"继续现有训练") and has(VIEW, r"放弃现有草稿后创建"))

print("== 5. 反规格 ==")
item("无分享 / 公开副本", not_has(PAGE, r"ShareLink|分享|公开"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
