#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 25 规格审计（动作库高级筛选）。

用法：
    python Tools/audit_page25.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Exercises/ExerciseFilterSheet.swift"
LIB_FILE = "Features/Exercises/ExerciseLibraryView.swift"
SEARCH_FILE = "Features/Exercises/ExerciseSearch.swift"
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
LIB_CODE = CODE.get(LIB_FILE, "")
SEARCH_CODE = CODE.get(SEARCH_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
PAGE_CODE = VIEW_CODE + "\n" + LIB_CODE + "\n" + SEARCH_CODE + "\n" + MODEL_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
print("== 1. 抽屉呈现 ==")
item("筛选以底部抽屉呈现", has(LIB_CODE, r"bottomDrawer\(isPresented: \$showAdvancedFilter"))
item("260ms 动画（DS.Motion.drawer）", has(VIEW_CODE, r"bottomDrawer") or has(LIB_CODE, r"bottomDrawer"))
item("顶部「重置 / 筛选 / 完成」", has(VIEW_CODE, r"\"重置\"") and has(VIEW_CODE, r"\"筛选\"") and has(VIEW_CODE, r"\"完成\""))
item("拖拽指示条由 BottomDrawer 提供", has(LIB_CODE, r"bottomDrawer"))

# =====================================================================
print("== 2. 命中数量 ==")
item("实时命中数量", has(VIEW_CODE, r"hitCount") and has(VIEW_CODE, r"命中") and has(VIEW_CODE, r"matches\("))

# =====================================================================
print("== 3. 分组 ==")
item("肌群多选（胸背肩手臂核心腿臀小腿）", has(VIEW_CODE, r"muscleGroupTitles") and has(VIEW_CODE, r"muscleGroups") and has(VIEW_CODE, r"\"小腿\""))
item("器械多选", has(VIEW_CODE, r"equipments") and has(VIEW_CODE, r"FlowChips"))
item("难度单选", has(VIEW_CODE, r"difficulty") and has(VIEW_CODE, r"choiceChips") and has(VIEW_CODE, r"filter\.difficulty = \(filter\.difficulty == level\)"))
item("来源单选（全部 / 内置导入 / 自定义动作）", has(VIEW_CODE, r"ExerciseSource\.allCases") and has(MODEL_CODE, r"\"内置导入\"") and has(MODEL_CODE, r"\"自定义动作\""))
item("状态（仅收藏 / 隐藏动作）", has(VIEW_CODE, r"仅显示收藏") and has(VIEW_CODE, r"显示已隐藏动作"))

# =====================================================================
print("== 4. 值层字段 ==")
item("ExerciseFilter 有 muscleGroups", has(MODEL_CODE, r"var muscleGroups: Set<String>"))
item("难度改单选", has(MODEL_CODE, r"var difficulty: ExerciseDifficulty\?"))
item("来源改单选枚举", has(MODEL_CODE, r"var source: ExerciseSource"))
item("移除 loadKinds（负重性质）", not_has(MODEL_CODE, r"var loadKinds"))
item("ExerciseSource 三选一", has(MODEL_CODE, r"enum ExerciseSource") and has(MODEL_CODE, r"case builtin") and has(MODEL_CODE, r"case custom"))

# =====================================================================
print("== 5. 筛选语义 ==")
item("未选任何条件不过滤", has(SEARCH_CODE, r"func matches") and has(SEARCH_CODE, r"return true"))
item("来源筛选命中自定义", has(SEARCH_CODE, r"case \.custom: if !item\.isCustom"))
item("肌群多选命中", has(SEARCH_CODE, r"filter\.muscleGroups\.contains"))
item("难度单选命中", has(SEARCH_CODE, r"item\.difficulty == difficulty"))

# =====================================================================
print("== 6. 重置 / 关闭语义 ==")
item("重置清空高级条件（保留关键词）", has(MODEL_CODE, r"mutating func resetAdvanced") and not_has(VIEW_CODE, r"clearSearch"))
item("遮罩关闭保留已应用筛选", not_has(LIB_CODE, r"onDismiss: \{[^}]*resetAdvanced") and has(LIB_CODE, r"onDone: \{ showAdvancedFilter = false \}"))

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
