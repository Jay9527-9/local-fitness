#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 41 规格审计（默认休息时间选择器）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

PICKER_FILE = "Features/Profile/DefaultRestPicker.swift"
PREF_FILE = "Features/Profile/ProfileSubpages.swift"
PANEL_FILE = "Features/Training/RestCountdownPanel.swift"


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
PICKER = CODE.get(PICKER_FILE, "")
PREF = CODE.get(PREF_FILE, "")
PANEL = CODE.get(PANEL_FILE, "")
SCAN = "\n".join(CODE.values())

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("RestRange 下限 15 秒", has(PICKER, r"minSeconds = 15"))
item("RestRange 上限 600 秒", has(PICKER, r"maxSeconds = 600"))
item("预设档 30/45/60/90/120/180", has(PICKER, r"presets = \[30, 45, 60, 90, 120, 180\]"))
item("clamp 夹取", has(PICKER, r"func clamp"))
item("isValid 范围判定", has(PICKER, r"func isValid"))
item("parse 自定义解析", has(PICKER, r"func parse"))

print("== 2. 适用范围 ==")
item("appDefault 写 AppPreferences", has(PICKER, r"case appDefault"))
item("planExercise 写 PlanExercise", has(PICKER, r"case planExercise"))
item("appDefault 说明不影响历史", has(PICKER, r"不会修改现有计划动作、进行中训练或历史记录"))
item("planExercise 说明不动动作库本体", has(PICKER, r"不动动作库本体"))

print("== 3. 视图 ==")
item("统一 DefaultRestPickerContent", has(PICKER, r"struct DefaultRestPickerContent"))
item("取消按钮", has(PICKER, r"Text\(\"取消\"\)"))
item("保存按钮", has(PICKER, r"Text\(\"保存\"\)"))
item("VoiceOver 朗读当前秒数", has(PICKER, r"accessibilityLabel\(\"默认休息时间，当前"))
item("自定义输入 15–600 提示", has(PICKER, r"RestRange\.minSeconds.*RestRange\.maxSeconds"))

print("== 4. 两个入口接线 ==")
item("训练偏好 → 存 defaultRest", has(PREF, r"DefaultRestPickerContent") and has(PREF, r"ProfileSettings\.defaultRest = seconds"))
item("休息面板 → 经 RestRange 夹取", has(PANEL, r"RestRange\.clamp") and has(PANEL, r"RestRange\.parse"))

print("== 5. 反规格 ==")
item("不含网络 / 账号", not (re.search(r"URLSession|URLRequest|SignInWithApple|登录|账号", PICKER)))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
