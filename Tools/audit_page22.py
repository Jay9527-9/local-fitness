#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 22 规格审计（应用设置）。

用法：
    python Tools/audit_page22.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Profile/AppSettingsView.swift"
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
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
VIEW_CODE = CODE.get(VIEW_FILE, "")
VALUE_CODE = CODE.get(VALUE_FILE, "")
ROOT_CODE = CODE.get(ROOTVIEW_FILE, "")
PAGE_CODE = VIEW_CODE + "\n" + VALUE_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


# =====================================================================
print("== 1. 入口与导航 ==")
item("页面文件在", os.path.exists(os.path.join(SRC, VIEW_FILE.replace("/", os.sep))))
item("标题「应用设置」", in_view(r"Text\(\"应用设置\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("路由注册", has(ROOT_CODE, r"ProfileRoute\.appSettings") and has(ROOT_CODE, r"AppSettingsView\("))

# =====================================================================
print("== 2. 四组 ==")
item("显示组", in_view(r"显示"))
item("单位组", in_view(r"单位"))
item("提醒组", in_view(r"提醒"))
item("关于组", in_view(r"关于"))

# =====================================================================
print("== 3. 显示 ==")
item("外观模式（深色 / 跟随系统）", in_view(r"外观模式") and in_value(r"case dark") and in_value(r"case system"))
item("减少动态效果入口（页面 44）", in_view(r"减少动态效果") and in_view(r"motionPreference"))
item("列表文字大小（系统默认 / 较大）", in_view(r"列表文字大小") and in_value(r"case normal") and in_value(r"case large"))

# =====================================================================
print("== 4. 单位 ==")
item("单位入口（页面 42）", in_view(r"onOpenUnits") and in_view(r"重量 / 长度 / 有氧距离") and in_value(r"cardioDistanceUnit"))

# =====================================================================
print("== 5. 提醒 ==")
item("声音与触感入口（页面 43）", in_view(r"onOpenSoundAndHaptics") and in_view(r"声音与触感"))
item("本地休息结束通知开关", in_view(r"本地休息结束通知") and in_view(r"RestNotification"))

# =====================================================================
print("== 6. 关于 ==")
item("App 版本", in_view(r"App 版本") and in_view(r"appVersion"))
item("数据结构版本", in_view(r"数据结构版本") and in_view(r"databaseVersion"))
item("动作库版本", in_view(r"动作库版本") and in_view(r"exerciseLibraryVersion"))
item("开源许可与媒体署名", in_view(r"开源许可") and in_view(r"媒体署名"))

# =====================================================================
print("== 7. 持久化 ==")
item("外观模式键", in_value(r"appearanceModeKey") and in_value(r"preference\.appearanceMode"))
item("列表文字大小键", in_value(r"listTextSizeKey") and in_value(r"preference\.listTextSize"))
item("默认外观深色", in_value(r"AppearanceMode\(rawValue: raw\) \?\? \.dark"))
item("默认文字系统默认", in_value(r"ListTextSize\(rawValue: raw\) \?\? \.normal"))
item("修改后立即写入", in_view(r"ProfileSettings\.appearanceMode = mode") and in_view(r"ProfileSettings\.listTextSize = size"))

# =====================================================================
print("== 8. 反规格与无障碍 ==")
item("不提供评分 / 反馈社区 / 账号 / 分享",
     not_has(PAGE_CODE, r"评分|反馈社区|SKStoreReview|ShareLink|SignInWithApple|登录"))
item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
