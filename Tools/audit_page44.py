#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 44 规格审计（减少动态效果设置）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Profile/ReduceMotionView.swift"
VALUE_FILE = "Features/Profile/ProfileData.swift"
MOTION_FILE = "Features/Profile/MotionConfig.swift"
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
VALUE = CODE.get(VALUE_FILE, "")
MOTION = CODE.get(MOTION_FILE, "")
ROOT = CODE.get(ROOTVIEW_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("MotionPreference 三模式", has(VALUE, r"case followSystem") and has(VALUE, r"case alwaysReduced") and has(VALUE, r"case normal"))
item("motionPreference 键", has(VALUE, r"motionPreferenceKey") and has(VALUE, r"preference\.motionPreference"))
item("纯函数 isReduced(system:)", has(VALUE, r"func isReduced\(systemReduceMotion"))

print("== 2. 统一动画配置 ==")
item("MotionConfig.isReduced", has(MOTION, r"static var isReduced"))
item("animation 返回 nil 禁用", has(MOTION, r"isReduced \? nil : standard"))
item("全 App 单一入口", has(MOTION, r"enum MotionConfig"))

print("== 3. 视图 ==")
item("受影响内容说明", has(VIEW, r"页面切换淡入") and has(VIEW, r"骨架屏 shimmer"))
item("三种模式单选", has(VIEW, r"ForEach\(MotionPreference\.allCases\)"))
item("勾选图标", has(VIEW, r"checkmark\.circle\.fill"))
item("VoiceOver 朗读当前模式", has(VIEW, r"当前模式"))

print("== 4. 接线 ==")
item("路由注册", has(ROOT, r"ProfileRoute\.reduceMotion") and has(ROOT, r"ReduceMotionView\("))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
