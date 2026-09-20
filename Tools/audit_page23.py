#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 23/24 规格审计（新建 / 编辑自定义动作）。

两页共用 CustomExerciseEditor + CustomExerciseForm（值层），故合并审计。
用法：
    python Tools/audit_page23.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VIEW_FILE = "Features/Exercises/CustomExerciseEditor.swift"
VALUE_FILE = "Features/Exercises/CustomExerciseForm.swift"
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


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_model(pattern, flags=0):
    return has(MODEL_CODE, pattern, flags)


# =====================================================================
print("== 1. 页面与导航 ==")
item("编辑器文件在", os.path.exists(os.path.join(SRC, VIEW_FILE.replace("/", os.sep))))
item("标题「新建动作」/「编辑动作」", in_view(r"\"新建动作\"") and in_view(r"\"编辑动作\""))
item("左侧取消 / 右侧保存", in_view(r"\"取消\"") and in_view(r"\"保存\""))
item("未保存改动确认放弃", in_view(r"hasUnsavedChanges") and in_view(r"放弃修改"))

# =====================================================================
print("== 2. 表单字段 ==")
item("名称（必填）", in_view(r"名称") and in_view(r"required: true") and in_view(r"名称不能为空"))
item("别名", in_view(r"别名"))
item("主肌群单选", in_view(r"主肌群") and in_view(r"FlowChips") and in_view(r"isSelected: \{ \$0 == muscleCategory \}"))
item("协同肌群", in_view(r"协同肌群"))
item("器械", in_view(r"器械") and in_view(r"equipmentOptions"))
item("难度", in_view(r"难度") and in_view(r"ExerciseDifficulty\.allCases"))
item("默认组间休息时间", in_view(r"默认组间休息时间") and in_view(r"defaultRestSeconds"))
item("备注", in_view(r"备注"))

# =====================================================================
print("== 3. 肌群图标 ==")
item("代码绘制肌群图标", in_view(r"MuscleGlyph\("))

# =====================================================================
print("== 4. 分步说明 ==")
item("支持添加步骤", in_view(r"添加步骤") and in_view(r"steps\.append"))
item("支持删除步骤", in_view(r"steps\.remove\(at:") and in_view(r"trash"))
item("支持排序步骤", in_view(r"swapAt") and in_view(r"上移一步") and in_view(r"下移一步"))
item("删空保留空状态", in_view(r"还没有步骤"))

# =====================================================================
print("== 5. 名称校验 ==")
item("名称 1–50 字限制", in_value(r"nameMaxLength = 50") and in_view(r"prefix\(CustomExerciseValidation\.nameMaxLength\)"))
item("规范化名称（去空白截断）", in_value(r"normalizedName") and in_value(r"trimmingCharacters"))
item("重名检测", in_value(r"hasDuplicateName") and in_view(r"已存在同名动作"))
item("允许保存为副本", in_view(r"保存为副本") and in_view(r"forceDuplicate"))

# =====================================================================
print("== 6. 保存 ==")
item("保存创建 isCustom: true", in_view(r"isCustom: true"))
item("保留原 ID / 收藏 / 隐藏", in_view(r"editing\?\.id \?\?") and in_view(r"editing\?\.isFavorite \?\? false") and in_view(r"editing\?\.isHidden \?\? false"))
item("默认休息写入模型", in_model(r"var defaultRestSeconds") and in_view(r"defaultRestSeconds: defaultRestSeconds"))

# =====================================================================
print("== 7. 编辑专属（页面 24） ==")
item("非自定义动作只读提示", in_view(r"isReadonly") and in_view(r"内置动作不可编辑"))
item("删除按钮", in_view(r"删除自定义动作"))
item("删除二次确认", in_view(r"删除后不可恢复"))
item("计划引用处理（仅隐藏 / 同时从计划移除）", in_view(r"仅从动作库隐藏") and in_view(r"同时从未来计划移除"))
item("不影响历史训练记录", in_view(r"不会影响已完成训练"))

# =====================================================================
print("== 8. 值层与反规格 ==")
item("值层不 import SwiftUI", not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("计划引用判定纯函数", in_value(r"plansReferencing") and in_value(r"removingReferences"))
item("不含社交 / 发布 / 分享 / 云端", not_has(PAGE_CODE, r"URLSession|ShareLink|发布|分享|云端|公开"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
