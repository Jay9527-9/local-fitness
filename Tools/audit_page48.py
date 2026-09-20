#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 48 规格审计（统一空状态组件）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Components.swift"


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

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 预设 ==")
item("EmptyStatePreset 枚举", has(VIEW, r"enum EmptyStatePreset"))
item("七种预设", all(has(VIEW, r"case " + c) for c in ["noPlans", "noHistory", "noFavorites", "noSearchResults", "noBodyData", "noActiveSession", "noBackupSelected"]))
item("无计划预设文案", has(VIEW, r"还没有训练计划") and has(VIEW, r"新建第一个计划"))
item("无历史预设文案", has(VIEW, r"还没有训练记录") and has(VIEW, r"开始一次训练"))
item("无收藏预设文案", has(VIEW, r"还没有收藏动作") and has(VIEW, r"浏览动作库"))
item("无搜索预设文案", has(VIEW, r"没有找到匹配动作") and has(VIEW, r"清除筛选"))
item("无身体数据预设文案", has(VIEW, r"还没有身体数据") and has(VIEW, r"记录身体数据"))
item("无进行中预设文案", has(VIEW, r"没有进行中的训练") and has(VIEW, r"新建力量训练"))
item("无可导入备份预设文案", has(VIEW, r"尚未选择备份文件") and has(VIEW, r"选择文件"))

print("== 2. 组件 ==")
item("代码绘制图标", has(VIEW, r"Image\(systemName: icon\)"))
item("标题 + 说明", has(VIEW, r"title") and has(VIEW, r"message"))
item("按钮回调由页面传入", has(VIEW, r"action: \(\(\) -> Void\)\? = nil"))
item("减少动态不播淡入动画", has(VIEW, r"MotionConfig\.fade"))

print("== 3. 兼容 ==")
item("兼容旧调用 message 形态", has(VIEW, r"init\(\s*message: String"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
