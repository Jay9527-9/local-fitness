#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 43 规格审计（声音与触感设置）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Profile/SoundAndHapticsView.swift"
CENTER_FILE = "Features/Profile/FeedbackCenter.swift"
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
CENTER = CODE.get(CENTER_FILE, "")
VALUE = CODE.get(VALUE_FILE, "")
ROOT = CODE.get(ROOTVIEW_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


print("== 1. 值层 ==")
item("FeedbackPolicy 纯判定", has(VALUE, r"enum FeedbackPolicy"))
item("声音 = 总开关 && 子开关", has(VALUE, r"master && sub"))
item("触感 = 总开关 && 子开关 && 设备支持", has(VALUE, r"master && sub && available"))
item("三档声音子键", has(VALUE, r"soundRestEndKey") and has(VALUE, r"soundLastTenKey") and has(VALUE, r"soundSetCompleteKey"))
item("三档触感子键", has(VALUE, r"hapticSetCompleteKey") and has(VALUE, r"hapticRestEndKey") and has(VALUE, r"hapticWorkoutCompleteKey"))

print("== 2. 触发中心 ==")
item("FeedbackCenter 系统音", has(CENTER, r"AudioServicesPlaySystemSound"))
item("系统音无第三方音频", has(CENTER, r"systemSoundID"))
item("设备触感能力探测", has(CENTER, r"hapticsAvailable"))

print("== 3. 视图三组 ==")
item("声音组", has(VIEW, r"组间休息结束提示音") and has(VIEW, r"最后 10 秒提示音") and has(VIEW, r"动作完成提示音"))
item("触感组", has(VIEW, r"完成一组触感反馈") and has(VIEW, r"休息结束触感反馈") and has(VIEW, r"训练完成触感反馈"))
item("总提示音关闭置灰但保留配置", has(VIEW, r"opacity\(enabled \? 1 : 0\.4\)"))
item("试听组", has(VIEW, r"试听休息结束提示音") and has(VIEW, r"测试触感反馈"))
item("不请求网络", has(VIEW, r"不请求网络"))

print("== 4. 接线 ==")
item("路由注册", has(ROOT, r"ProfileRoute\.soundAndHaptics") and has(ROOT, r"SoundAndHapticsView\("))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
