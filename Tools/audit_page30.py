#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 30 规格审计（新建有氧训练设置）。

用法：
    python Tools/audit_page30.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Training/NewCardioView.swift"
VALUE_FILE = "Features/Training/CardioSetup.swift"
MODEL_FILE = "Models/Models.swift"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
VIEW_CODE = CODE.get(VIEW_FILE, "")
VALUE_CODE = CODE.get(VALUE_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
PAGE_CODE = VIEW_CODE + "\n" + VALUE_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
print("== 1. 导航 ==")
item("左侧取消 / 中间新建有氧训练 / 右侧开始", has(VIEW_CODE, r"\"取消\"") and has(VIEW_CODE, r"\"新建有氧训练\"") and has(VIEW_CODE, r"\"开始\""))

# =====================================================================
print("== 2. 表单 ==")
item("训练名称", has(VIEW_CODE, r"训练名称"))
item("运动类型 8 选（跑步…其他）", has(VALUE_CODE, r"case run") and has(VALUE_CODE, r"case walk") and has(VALUE_CODE, r"case swim") and has(VALUE_CODE, r"case other") and has(VALUE_CODE, r"\"跳绳\""))
item("目标类型分段（自由 / 时长 / 距离 / 热量）", has(VALUE_CODE, r"case free") and has(VALUE_CODE, r"case duration") and has(VALUE_CODE, r"case distance") and has(VALUE_CODE, r"case calories"))
item("目标值输入", has(VIEW_CODE, r"goalValueText") and has(VIEW_CODE, r"目标数值"))
item("自由训练不要求目标值", has(VALUE_CODE, r"requiresGoalValue") and has(VALUE_CODE, r"self != \.free"))
item("备注", has(VIEW_CODE, r"备注"))

# =====================================================================
print("== 3. 模板 ==")
item("保存为个人模板开关", has(VIEW_CODE, r"保存为个人模板") and has(VIEW_CODE, r"saveAsTemplate"))

# =====================================================================
print("== 4. 校验与草稿 ==")
item("校验名称与目标值", has(VALUE_CODE, r"validationError") and has(VALUE_CODE, r"请填写训练名称"))
item("创建 kind: .cardio 草稿", has(VIEW_CODE, r"kind: \.cardio") and has(VIEW_CODE, r"WorkoutSession"))
item("取消 / 返回不创建草稿", has(VIEW_CODE, r"onCancel") and has(VIEW_CODE, r"createDraft"))

# =====================================================================
print("== 5. 反规格 ==")
item("默认不用 GPS / 健康 / 蓝牙 / 网络", not_has(PAGE_CODE, r"CoreLocation|CLLocation|HealthKit|CoreBluetooth|CBCentralManager|URLSession"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
