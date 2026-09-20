#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 32 规格审计（有氧训练完成总结）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/Training/CardioSummaryView.swift", "Models/Models.swift"]


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


print("== 1. 头部 ==")
item("完成勾选图标 + 标题 + 日期与名称", has(VIEW, r"checkmark") and has(VIEW, r"有氧训练完成") and has(VIEW, r"finishedAt"))

print("== 2. 统计卡 ==")
item("时长 / 距离 / 热量 / 平均配速", has(VIEW, r"时长") and has(VIEW, r"距离") and has(VIEW, r"热量") and has(VIEW, r"平均配速"))
item("未填写显示 —", has(VIEW, r"—"))

print("== 3. 分段 / 笔记 ==")
item("分段记录（无则「未记录分段」）", has(VIEW, r"分段记录") and has(VIEW, r"未记录分段"))
item("训练笔记可编辑保存", has(VIEW, r"训练笔记") and has(VIEW, r"saveNote"))

print("== 4. 模板 ==")
item("保存为模板入口", has(VIEW, r"保存为模板") and has(VIEW, r"saveAsTemplate"))
item("模板名输入", has(VIEW, r"模板名称"))

print("== 5. 底部 ==")
item("返回训练首页 / 查看历史记录", has(VIEW, r"返回训练首页") and has(VIEW, r"查看历史记录"))

print("== 6. 原子持久化 ==")
item("CardioTemplate 模型", has(MODEL, r"struct CardioTemplate"))
item("无分享 / 社交 / 排行榜", not_has(PAGE, r"ShareLink|社交|排行榜|分享|URLSession"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
