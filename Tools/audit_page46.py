#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 46 规格审计（清除全部本地数据确认）。"""

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
item("确认短语「清除全部」", has(VIEW, r'return "清除全部"'))
item("标题「清除全部本地数据」", has(VIEW, r'return "清除全部本地数据"'))

print("== 2. 风险卡 ==")
item("删除内容清单", has(VIEW, r"训练记录与草稿、个人计划、自定义动作、收藏和隐藏状态、身体数据、休息日、训练偏好、个人资料、已下载本地媒体与统计缓存"))
item("内置种子可重新导入", has(VIEW, r"内置动作库种子不会永久丢失"))

print("== 3. 数量与占用 ==")
item("展示占用空间", has(VIEW, r"storageSizeText"))
item("先导出备份入口", has(VIEW, r"先导出备份"))

print("== 4. 二次确认 ==")
item("勾选「我理解此操作无法撤销」", has(VIEW, r"我理解此操作无法撤销") and has(VIEW, r"acknowledged"))
item("输入「清除全部」", has(VIEW, r'typedText == ClearDataScope\.all\.confirmPhrase'))
item("二次系统确认", has(VIEW, r"systemConfirmTitle") and has(VIEW, r"确认清除"))

print("== 5. 重置引导接线 ==")
item("成功后回调 onClearedAllData", has(VIEW, r"onClearedAllData\(\)"))
item("路由注册", has(ROOT, r"ProfileRoute\.clearAllData") and has(ROOT, r"ClearAllDataView\("))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
