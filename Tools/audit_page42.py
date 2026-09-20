#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 42 规格审计（单位设置）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Profile/UnitSettingsView.swift"
VALUE_FILE = "Features/Profile/ProfileData.swift"
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
ROOT = CODE.get(ROOTVIEW_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("DistanceUnit 枚举", has(VALUE, r"enum DistanceUnit"))
item("公里 / 英里两档", has(VALUE, r"case kilometers") and has(VALUE, r"case miles"))
item("内部以米保存", has(VALUE, r"metersPerMile") and has(VALUE, r"displayValue\(fromMeters"))
item("cardioDistanceUnit 键", has(VALUE, r"cardioDistanceUnitKey") and has(VALUE, r"preference\.cardioDistanceUnit"))
item("纳入 allKeys（清除全部时重置）", has(VALUE, r"cardioDistanceUnitKey,"))

print("== 2. 三组 ==")
item("重量单位 kg / lb", has(VIEW, r"BodyWeightUnit\.allCases"))
item("长度单位 cm / in", has(VIEW, r"BodyLengthUnit\.allCases"))
item("有氧距离 公里 / 英里", has(VIEW, r"DistanceUnit\.allCases"))
item("荧光绿勾选", has(VIEW, r"checkmark\.circle\.fill"))

print("== 3. 说明 ==")
item("内部 kg/cm/m 不重复换算", has(VIEW, r"kg、cm、m") and has(VIEW, r"不会改写历史值"))

print("== 4. 接线 ==")
item("路由注册", has(ROOT, r"ProfileRoute\.unitSettings") and has(ROOT, r"UnitSettingsView\("))

print("== 5. 反规格 ==")
item("不含网络 / 账号", not (re.search(r"URLSession|SignInWithApple|登录|账号", VIEW + VALUE)))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
