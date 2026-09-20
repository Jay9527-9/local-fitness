#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 49 规格审计（恢复进行中训练）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Training/ResumeSessionView.swift"
HOME_FILE = "Features/Training/TrainingHomeView.swift"
VM_FILE = "Features/Training/TrainingHomeViewModel.swift"


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
HOME = CODE.get(HOME_FILE, "")
VM = CODE.get(VM_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("ResumeDraft 摘要", has(VIEW, r"struct ResumeDraft"))
item("ResumeDraftMath 天数", has(VIEW, r"ageDays"))
item("暂停天数提醒", has(VIEW, r"该训练已暂停") and has(VIEW, r"ageReminder"))

print("== 2. 抽屉 ==")
item("标题「检测到未完成训练」", has(HOME, r"检测到未完成训练"))
item("展示时长 / 组数 / 类型", has(VIEW, r"完成组数") and has(VIEW, r"时长") and has(VIEW, r"kindTitle"))
item("三操作", has(VIEW, r"继续训练") and has(VIEW, r"稍后处理") and has(VIEW, r"放弃草稿"))
item("多条草稿列表", has(VIEW, r"draftList"))
item("放弃草稿二次确认", has(VIEW, r"放弃此训练草稿"))

print("== 3. 接线 ==")
item("首页加载后提示", has(HOME, r"didPromptResume") and has(HOME, r"showResumeDrawer = true"))
item("继续训练进执行页", has(HOME, r"onResumeSession"))
item("放弃草稿只删草稿", has(VM, r"func abandonDraft") and has(VM, r"delete\(sessionID"))

print("== 4. 反规格 ==")
item("不静默覆盖 / 自动删除", not (re.search(r"自动删除|静默覆盖", VIEW)))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
