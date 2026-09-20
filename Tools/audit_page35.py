#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 35/36 规格审计（历史列表视图 / 日历当天操作菜单）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/History/HistoryView.swift", "Features/History/HistoryCalendar.swift"]


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
VIEW = CODE.get(FILES[0], "") + "\n" + CODE.get(FILES[1], "")

ITEMS = []


def item(label, ok):
    ITEMS.append((label, bool(ok)))


def has(text, p):
    return re.search(p, text) is not None


def not_has(text, p):
    return re.search(p, text) is None


print("== 1. 分段控件 ==")
item("日历 / 列表 / 统计分段", has(VIEW, r"enum HistorySegment") and has(VIEW, r"case \.calendar") and has(VIEW, r"case \.list") and has(VIEW, r"case \.stats"))

print("== 2. 列表视图 ==")
item("列表按分组展示", has(VIEW, r"listSection") and has(VIEW, r"monthSections"))
item("训练卡", has(VIEW, r"HistoryListRow"))
item("空状态「还没有训练记录」", has(VIEW, r"还没有完成的训练记录"))

print("== 3. 当天操作菜单（页面 36） ==")
item("日期与星期标题", has(VIEW, r"FormatterKit\.fullDate"))
item("新建力量 / 有氧 / 添加休息日", has(VIEW, r"新建力量训练") and has(VIEW, r"新建有氧训练") and has(VIEW, r"添加休息日"))
item("导入计划到当天", has(VIEW, r"导入个人计划到当天"))
item("查看当天记录（有记录时）", has(VIEW, r"查看当天记录") and has(VIEW, r"hasSessions"))
item("休息日切换为编辑备注", has(VIEW, r"编辑休息日备注") and has(VIEW, r"restDay\(on:"))

print("== 4. 反规格 ==")
item("无社交 / 他人日程", not_has(VIEW, r"好友|社交|分享|URLSession"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
