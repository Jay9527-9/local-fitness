#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 20 规格审计（导入本地备份）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–19 踩过假阳性换来的规则（strip_comments / 作用域三选一 /
正则圆括号转义）。

用法：
    python Tools/audit_page20.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

PAGE20_FILES = [
    "Features/History/ImportBackupView.swift",
    "Features/History/ImportBackup.swift",
]

VIEW_FILE = "Features/History/ImportBackupView.swift"
VALUE_FILE = "Features/History/ImportBackup.swift"
MGMT_FILE = "Features/History/WorkoutDataManagementView.swift"
ROOTVIEW_FILE = "Features/RootView.swift"
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
    "Data/FitnessRepository.swift",
]


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
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE20_FILES)
VIEW_CODE = CODE.get(VIEW_FILE, "")
VALUE_CODE = CODE.get(VALUE_FILE, "")
MGMT_CODE = CODE.get(MGMT_FILE, "")
ROOT_CODE = CODE.get(ROOTVIEW_FILE, "")
REPO_CODE = "\n".join(CODE.get(f, "") for f in REPO_FILES)

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_mgmt(pattern, flags=0):
    return has(MGMT_CODE, pattern, flags)


def in_root(pattern, flags=0):
    return has(ROOT_CODE, pattern, flags)


def in_repo(pattern, flags=0):
    return has(REPO_CODE, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE20_FILES))
item("标题「导入本地备份」", in_view(r"Text\(\"导入本地备份\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("数据管理页入口进导入页", in_mgmt(r"导入本地备份") and in_mgmt(r"onOpenImportBackup"))
item("两个 Tab 都注册导入路由",
     in_root(r"ProfileRoute\.importBackup") and in_root(r"HistoryRoute\.importBackup"))


# =====================================================================
# 2. 首屏
# =====================================================================
print("== 2. 首屏 ==")

item("说明支持版本化 JSON 备份", in_view(r"版本化 JSON"))
item("说明不访问网络 / 云端账号", in_view(r"不会访问网络或云端账号"))
item("不支持未知来源或损坏文件", in_view(r"未知来源或损坏"))
item("主按钮「选择备份文件」", in_view(r"选择备份文件") and in_view(r"fileImporter"))


# =====================================================================
# 3. 预检
# =====================================================================
print("== 3. 预检 ==")

item("预检六步（枚举完整）",
     in_value(r"enum Step") and
     in_value(r"case format") and in_value(r"case schema") and
     in_value(r"case checksum") and in_value(r"case fields") and
     in_value(r"case counts") and in_value(r"case integrity"))
item("六步标题齐全",
     in_value(r"文件格式") and in_value(r"结构版本") and in_value(r"校验摘要") and
     in_value(r"数据字段") and in_value(r"数据数量") and in_value(r"文件完整性"))
item("预检只读不写", in_view(r"预检只读取文件，不会改动现有数据") and in_view(r"不会改动现有数据"))
item("校验摘要", in_value(r"checkChecksum") and in_value(r"ExportBackupChecksum\.isValid"))


# =====================================================================
# 4. 备份摘要
# =====================================================================
print("== 4. 备份摘要 ==")

item("创建日期", in_view(r"创建日期") and in_view(r"FormatterKit\.fullDate"))
item("App 数据版本", in_view(r"App 数据版本") and in_view(r"appVersion"))
item("训练记录数量", in_view(r"sessionCount"))
item("计划数量", in_view(r"planCount"))
item("自定义动作数量", in_value(r"customExerciseCount") and in_view(r"自定义动作"))
item("身体数据数量", in_view(r"measurementCount"))
item("是否包含个人资料", in_view(r"包含个人资料") and in_view(r"includeProfile"))
item("是否包含未完成草稿", in_view(r"包含未完成草稿") and in_view(r"includeDrafts"))


# =====================================================================
# 5. 导入方式与冲突处理
# =====================================================================
print("== 5. 导入方式与冲突处理 ==")

item("导入方式入口", in_view(r"导入方式") and in_view(r"showConflictSheet"))
# 页面 21 起「导入方式」升级为独立冲突处理页（ImportConflictView），
# 默认策略为「合并并保留本机数据」（ImportStrategy.mergeKeepLocal）。
item("默认「合并并保留本机数据」", in_view(r"importStrategy: ImportStrategy = \.mergeKeepLocal"))
item("冲突处理页（页面 21）", in_view(r"ImportConflictView") and in_view(r"冲突定义"))
item("导入方式两种", in_value(r"case merge") and in_value(r"case replace"))
item("冲突策略两种", in_value(r"case keepLocal") and in_value(r"case keepBackup"))
item("导入前提示自动创建临时备份", in_view(r"导入前将自动创建当前本地数据临时备份"))


# =====================================================================
# 6. 导入进度与结果
# =====================================================================
print("== 6. 导入进度与结果 ==")

item("底部主按钮「开始导入」", in_view(r"开始导入"))
item("六阶段进度",
     in_view(r"创建保护备份") and in_view(r"导入训练") and in_view(r"导入计划") and
     in_view(r"导入动作与设置") and in_view(r"验证结果") and in_view(r"完成"))
item("进度步为枚举", in_view(r"enum ImportProgressStep"))
item("成功页四计数", in_view(r"新增") and in_view(r"更新") and in_view(r"跳过") and in_view(r"冲突解决"))
item("计数含冲突解决", in_value(r"conflictsResolved"))
item("「返回数据管理」按钮", in_view(r"返回数据管理") and in_view(r"onDone"))
item("「查看训练历史」按钮", in_view(r"查看训练历史") and in_view(r"onViewHistory"))


# =====================================================================
# 7. 错误处理
# =====================================================================
print("== 7. 错误处理 ==")

item("只显示错误原因 + 重新选择文件", in_view(r"重新选择文件") and in_view(r"无法导入"))
item("错误不删不覆盖当前数据", in_view(r"当前数据未被删除或覆盖"))
item("预检失败不写盘（只读）", in_view(r"预检只读取文件") and not_has(VIEW_CODE, r"inspect\(.*replaceAll"))
item("导入失败回滚", in_view(r"rollback") and in_view(r"保护备份"))


# =====================================================================
# 8. 值层与仓储
# =====================================================================
print("== 8. 值层与仓储 ==")

item("合并计算是纯函数（无 SwiftUI）", not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("ImportMerge 通用合并", in_value(r"enum ImportMerge") and in_value(r"static func merge<"))
item("四类集合合并包装", in_value(r"mergeSessions") and in_value(r"mergePlans") and
     in_value(r"mergeExercises") and in_value(r"mergeMeasurements"))
item("仓储含 replaceAllExercises（协议 + 两实现）",
     in_repo(r"func replaceAllExercises") and
     len(re.findall(r"func replaceAllExercises", REPO_CODE)) == 3)
item("保护备份直接构造（不过滤草稿/动作库）", in_view(r"makeProtectionSnapshot") and in_view(r"includeDrafts: true"))


# =====================================================================
# 9. 无障碍与反规格
# =====================================================================
print("== 9. 无障碍与反规格 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("卡片 / 摘要有无障碍标签", in_view(r"accessibilityLabel"))
item("不含联网 / 账号 / 云同步 API",
     not_has(PAGE_CODE, r"URLSession|URLRequest|http://|https://|SignInWithApple|CloudKit|NSUbiquitous|AuthenticationServices"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
