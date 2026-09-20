#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 21 规格审计（导入冲突处理）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

用法：
    python Tools/audit_page21.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VALUE_FILE = "Features/History/ImportConflict.swift"
VIEW_FILE = "Features/History/ImportBackupView.swift"


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
VALUE_CODE = CODE.get(VALUE_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
PAGE_CODE = VALUE_CODE + "\n" + VIEW_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("值层文件在", os.path.exists(os.path.join(SRC, VALUE_FILE.replace("/", os.sep))))
item("标题「导入方式」", in_view(r"navigationTitle\(\"导入方式\"\)"))
item("左侧返回", in_view(r"\"返回\"") and in_view(r"cancellationAction"))
item("从导入页「导入方式」进入", in_view(r"showConflictSheet") and in_view(r"ImportConflictView\("))


# =====================================================================
# 2. 说明卡（冲突定义）
# =====================================================================
print("== 2. 说明卡 ==")

item("冲突定义说明", in_view(r"冲突定义") and in_view(r"相同 ID"))
item("覆盖自然日 / 同名计划等冲突来源", in_view(r"同一自然日") and in_view(r"同名"))


# =====================================================================
# 3. 三种策略
# =====================================================================
print("== 3. 三种策略 ==")

item("三策略枚举完整",
     in_value(r"enum ImportStrategy") and
     in_value(r"case mergeKeepLocal") and
     in_value(r"case mergeKeepBackup") and
     in_value(r"case replaceAll"))
item("合并并保留本机数据", in_value(r"合并并保留本机数据"))
item("合并并优先备份数据", in_value(r"合并并优先备份数据"))
item("覆盖本机全部数据", in_value(r"覆盖本机全部数据"))
item("策略映射到 mode/policy", in_value(r"var mode: ImportMode") and in_value(r"var policy: ConflictPolicy"))
item("破坏性标记", in_value(r"isDestructive") and in_value(r"replaceAll"))


# =====================================================================
# 4. 影响数量
# =====================================================================
print("== 4. 影响数量 ==")

item("影响数量结构", in_value(r"struct ImportImpact") and in_value(r"struct CategoryImpact"))
item("影响分析按 ID 判冲突", in_value(r"enum ImportConflictAnalysis") and in_value(r"existingKeys\.contains"))
item("每策略下展示影响文案", in_view(r"impactText\(for:") and in_view(r"summaryText"))
item("影响文案区分合并 / 覆盖", in_value(r"case \.merge") and in_value(r"case \.replace"))


# =====================================================================
# 5. 覆盖二次确认
# =====================================================================
print("== 5. 覆盖二次确认 ==")

item("覆盖显示红色风险提示", in_view(r"不可撤销") and in_view(r"DS\.Palette\.danger"))
item("要求输入「覆盖」", in_view(r"输入「覆盖」") and in_view(r"replaceConfirmText == \"覆盖\""))
item("确认前禁用「确认导入方式」", in_view(r"canConfirm") and in_view(r"isEnabled: canConfirm"))


# =====================================================================
# 6. 确认返回（不写数据）
# =====================================================================
print("== 6. 确认返回 ==")

item("底部主按钮「确认导入方式」", in_view(r"确认导入方式"))
item("确认后传回策略、不写数据", in_view(r"onConfirm\(viewModel\.strategy\)") and in_view(r"dismiss"))
item("导入页回填策略", in_view(r"importStrategy = strategy"))


# =====================================================================
# 7. 破坏性覆盖语义
# =====================================================================
print("== 7. 破坏性覆盖语义 ==")

item("ImportMerge 的 replace 破坏性覆盖（丢弃本机）",
     has(CODE.get("Features/History/ImportBackup.swift", ""), r"mode == \.replace") and
     has(CODE.get("Features/History/ImportBackup.swift", ""), r"incomingDeduped\.count"))


# =====================================================================
# 8. 无障碍与反规格
# =====================================================================
print("== 8. 无障碍与反规格 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("危险选项有无障碍提示", in_view(r"accessibilityHint\(strategy\.isDestructive"))
item("不含云端 / 多人协作 / 账号",
     not_has(PAGE_CODE, r"URLSession|CloudKit|SignInWithApple|云端同步|多人协作|账号冲突"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
