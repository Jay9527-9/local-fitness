#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 45 规格审计（清除全部训练记录确认）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/History/ClearDataView.swift"
ROOTVIEW_FILE = "Features/RootView.swift"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


FILES = {}
for dp, _, fns in os.walk(SRC):
    for name in fns:
        if name.endswith(".swift"):
            full = os.path.join(dp, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
VIEW = CODE.get(VIEW_FILE, "")
ROOT = CODE.get(ROOTVIEW_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("确认短语「删除训练」", has(VIEW, r'return "删除训练"'))
item("标题「清除训练记录」", has(VIEW, r'return "清除训练记录"'))
item("ClearDataCounts 纯计算", has(VIEW, r"struct ClearDataCounts") and has(VIEW, r"func compute"))
item("区分力量 / 有氧 / 草稿 / 休息日", has(VIEW, r"finishedStrength") and has(VIEW, r"finishedCardio") and has(VIEW, r"drafts") and has(VIEW, r"restDays"))

print("== 2. 风险卡 ==")
item("删除内容清单", has(VIEW, r"已完成的力量训练、有氧训练、未完成训练草稿、训练笔记、组记录、统计缓存与休息日标记"))
item("不删除清单", has(VIEW, r"个人计划、动作库、自定义动作、收藏动作、身体数据、个人资料与应用设置"))

print("== 3. 受影响数量 ==")
item("四格数量", has(VIEW, r"完成训练") and has(VIEW, r"进行中草稿") and has(VIEW, r"有氧记录") and has(VIEW, r"休息日"))
item("无法读取禁止删除", has(VIEW, r"暂时无法读取本地数据，无法执行删除"))

print("== 4. 二次确认 ==")
item("输入「删除训练」才可删", has(VIEW, r'typedText == ClearDataScope\.records\.confirmPhrase'))
item("二次系统确认弹窗", has(VIEW, r"systemConfirmTitle") and has(VIEW, r"永久删除"))
item("先导出备份入口", has(VIEW, r"先导出备份"))

print("== 5. 接线 ==")
item("路由注册", has(ROOT, r"ProfileRoute\.clearRecords") and has(ROOT, r"ClearWorkoutRecordsView\("))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
