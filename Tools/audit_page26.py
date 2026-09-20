#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 26 规格审计（动作库排序菜单）。

用法：
    python Tools/audit_page26.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

MENU_FILE = "Features/Exercises/ExerciseSortMenu.swift"
LIB_FILE = "Features/Exercises/ExerciseLibraryView.swift"
VM_FILE = "Features/Exercises/ExerciseLibraryViewModel.swift"
SEARCH_FILE = "Features/Exercises/ExerciseSearch.swift"
MODEL_FILE = "Models/Models.swift"
PROFILE_FILE = "Features/Profile/ProfileData.swift"


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
MENU_CODE = CODE.get(MENU_FILE, "")
LIB_CODE = CODE.get(LIB_FILE, "")
VM_CODE = CODE.get(VM_FILE, "")
SEARCH_CODE = CODE.get(SEARCH_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
PROFILE_CODE = CODE.get(PROFILE_FILE, "")
PAGE_CODE = MENU_CODE + "\n" + LIB_CODE + "\n" + VM_CODE + "\n" + SEARCH_CODE + "\n" + MODEL_CODE + "\n" + PROFILE_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
print("== 1. 菜单呈现 ==")
item("底部菜单 + 标题「排序方式」", has(LIB_CODE, r"bottomDrawer\(isPresented: \$showSortMenu") and has(MENU_CODE, r"\"排序方式\""))
item("遮罩或「取消」关闭", has(MENU_CODE, r"\"取消\"") and has(MENU_CODE, r"onCancel"))

# =====================================================================
print("== 2. 排序项 ==")
item("默认推荐", has(MODEL_CODE, r"case defaultOrder") and has(MODEL_CODE, r"\"默认推荐\""))
item("名称 A-Z", has(MODEL_CODE, r"case name") and has(MODEL_CODE, r"\"名称 A-Z\""))
item("最近使用", has(MODEL_CODE, r"case recentlyUsed") and has(MODEL_CODE, r"\"最近使用\""))
item("最近收藏", has(MODEL_CODE, r"case recentlyFavorited") and has(MODEL_CODE, r"\"最近收藏\""))
item("难度（入门到高级）", has(MODEL_CODE, r"case difficulty") and has(MODEL_CODE, r"\"难度\""))

# =====================================================================
print("== 3. 选中反馈 ==")
item("当前项荧光绿勾选", has(MENU_CODE, r"checkmark") and has(MENU_CODE, r"DS\.Palette\.accent"))
item("选中后 180ms 淡入", has(LIB_CODE, r"numberFade"))

# =====================================================================
print("== 4. 持久化 ==")
item("排序偏好写本地 AppPreferences", has(PROFILE_CODE, r"exerciseSortKey") and has(PROFILE_CODE, r"static var exerciseSort"))
item("setSort 持久化", has(VM_CODE, r"func setSort") and has(VM_CODE, r"ProfileSettings\.exerciseSort = order"))
item("启动时恢复偏好", has(VM_CODE, r"ProfileSettings\.exerciseSort"))

# =====================================================================
print("== 5. 无数据回退 ==")
item("最近使用 / 最近收藏无数据仍可选", has(MENU_CODE, r"mayFallBackToDefault") and has(MENU_CODE, r"暂无数据"))
item("回退默认顺序 + 顶部提示", has(VM_CODE, r"isSortFallback") and has(LIB_CODE, r"sortFallbackHint") and has(LIB_CODE, r"已按默认顺序显示"))

# =====================================================================
print("== 6. 排序语义 ==")
item("默认推荐保持内置顺序", has(SEARCH_CODE, r"case \.defaultOrder:") and has(SEARCH_CODE, r"return items"))
item("最近收藏按 favoritedAt 降序", has(SEARCH_CODE, r"recentlyFavorited") and has(SEARCH_CODE, r"favoritedAt"))
item("只影响显示（不写数据）", has(VM_CODE, r"func setSort") and not_has(VM_CODE, r"setSort[\s\S]{0,120}save\("))

# =====================================================================
print("== 7. 反规格 ==")
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
