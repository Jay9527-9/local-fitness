#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 33/34 规格审计（新增休息日 / 编辑休息日备注）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/History/RestDaySheets.swift", "Models/Models.swift"]


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


print("== 1. 页面 33 新增休息日 ==")
item("标题「添加休息日」+ 取消/保存", has(VIEW, r"添加休息日") and has(VIEW, r"\"取消\"") and has(VIEW, r"\"保存\""))
item("日期选择器 + 备注", has(VIEW, r"DatePicker") and has(VIEW, r"备注"))
item("重复检测（当天已标记）", has(VIEW, r"当天已标记为休息日") and has(VIEW, r"编辑已有备注"))
item("当天有训练非阻断提示", has(VIEW, r"当天已有训练记录"))

print("== 2. 页面 34 编辑休息日备注 ==")
item("日期 + 休息日 + 关闭按钮", has(VIEW, r"休息日") and has(VIEW, r"xmark"))
item("创建时间展示", has(VIEW, r"创建于") and has(MODEL, r"var createdAt"))
item("备注多行 + 300 字限制", has(VIEW, r"TextEditor") and has(VIEW, r"noteMaxLength = 300"))
item("保存备注未修改置灰", has(VIEW, r"hasChanges") and has(VIEW, r"保存备注"))
item("取消休息日标记 + 二次确认", has(VIEW, r"取消休息日标记") and has(VIEW, r"showDeleteConfirm"))
item("只删 RestDay 不删训练", has(VIEW, r"只删除该休息日标记"))
item("同日训练入口", has(VIEW, r"sessionsOnDay") and has(VIEW, r"onOpenSession"))

print("== 3. 自然日归一化 ==")
item("startOfDay 归一化", has(VIEW, r"startOfDay"))

print("== 4. 反规格 ==")
item("无社交 / 排行", not_has(PAGE, r"好友|排行|社交|分享|URLSession"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
