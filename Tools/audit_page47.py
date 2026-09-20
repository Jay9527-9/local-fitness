#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 47 规格审计（首次启动引导）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Onboarding/OnboardingView.swift"
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


print("== 1. 页面结构 ==")
item("四页引导", has(VIEW, r"case record") and has(VIEW, r"case profile") and has(VIEW, r"case goal") and has(VIEW, r"case privacy"))
item("第 1 页标题", has(VIEW, r"记录每一次训练"))
item("第 4 页「进入训练」", has(VIEW, r"进入训练"))
item("页码指示器", has(VIEW, r"pageIndicator") and has(VIEW, r"第"))
item("跳过按钮", has(VIEW, r"跳过"))

print("== 2. 可选资料 ==")
item("昵称可跳过", has(VIEW, r"昵称（可选）"))
item("重量 / 长度单位", has(VIEW, r"BodyWeightUnit") and has(VIEW, r"BodyLengthUnit"))
item("训练目标五选（不含自定义）", has(VIEW, r"goalOptions") and has(VIEW, r"!= \.custom"))

print("== 3. 完成 ==")
item("创建默认 UserProfile", has(VIEW, r"UserProfile\(\)"))
item("不生成默认训练 / 计划", not (re.search(r"save\(session|createPlan", VIEW)))
item("写入 AppPreferences", has(VIEW, r"ProfileSettings\.weightUnit = weightUnit") and has(VIEW, r"ProfileSettings\.lengthUnit = lengthUnit"))

print("== 4. 键与接线 ==")
item("hasCompletedOnboarding 键", has(VALUE, r"hasCompletedOnboardingKey") and has(VALUE, r"preference\.hasCompletedOnboarding"))
item("RootView fullScreenCover", has(ROOT, r"fullScreenCover") and has(ROOT, r"OnboardingView"))
item("完成标记 hasCompletedOnboarding", has(ROOT, r"ProfileSettings\.hasCompletedOnboarding = true"))

print("== 5. 反规格 ==")
item("不使用第三方插画 / 登录 / 社交", not (re.search(r"URLSession|SignInWithApple|登录|社交邀请|第三方插画", VIEW)))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
