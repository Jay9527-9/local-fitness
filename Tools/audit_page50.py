#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 50 规格审计（错误与数据恢复）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/History/DataRecoveryView.swift"
TOKEN_FILE = "DesignSystem/DesignTokens.swift"
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
TOKEN = CODE.get(TOKEN_FILE, "")
ROOT = CODE.get(ROOTVIEW_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 警示 ==")
item("黄色警示色", has(TOKEN, r"warning = Color\(hex: 0xFFC53D\)"))
item("标题「发现数据异常」", has(VIEW, r"发现数据异常"))
item("友好位置说明（不展示原始路径）", has(VIEW, r"文件无法读取") and not (re.search(r"filePath|rawPath|/Application Support", VIEW)))

print("== 2. 操作 ==")
item("重试读取", has(VIEW, r"重试读取"))
item("导出诊断副本", has(VIEW, r"导出诊断副本") and has(VIEW, r"fileExporter"))
item("从备份恢复", has(VIEW, r"从备份恢复"))
item("跳过并继续", has(VIEW, r"跳过并继续"))
item("重置受影响数据（二次确认）", has(VIEW, r"重置受影响数据") and has(VIEW, r"showResetConfirm"))

print("== 3. 恢复 ==")
item("恢复结果与数量", has(VIEW, r"RecoveryReport") and has(VIEW, r"训练记录"))
item("关键文件重置需确认", has(VIEW, r"重置受影响数据？"))

print("== 4. 接线 ==")
item("路由注册", has(ROOT, r"TrainingRoute\.recovery") and has(ROOT, r"DataRecoveryView\("))

print("== 5. 反规格 ==")
item("不自动上传日志 / 连接网络", not (re.search(r"URLSession|URLRequest", VIEW)) and has(VIEW, r"不会自动上传日志"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
