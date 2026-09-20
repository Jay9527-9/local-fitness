#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 18 规格审计（本地数据管理）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–17 踩过假阳性换来的规则（strip_comments / 作用域三选一 /
跨行签名两段式 / 枚举 case 计数限定枚举体 / 正则圆括号转义）。

用法：
    python Tools/audit_page18.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


PAGE18_FILES = [
    "Features/History/WorkoutDataManagementView.swift",
    "Features/History/LocalDataBackup.swift",
]

VIEW_FILE = "Features/History/WorkoutDataManagementView.swift"
VALUE_FILE = "Features/History/LocalDataBackup.swift"
PROFILE_DATA_FILE = "Features/Profile/ProfileData.swift"
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
    "Data/FitnessRepository.swift",
]

FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE18_FILES)
VIEW_CODE = CODE.get(VIEW_FILE, "")
VALUE_CODE = CODE.get(VALUE_FILE, "")
PROFILE_CODE = CODE.get(PROFILE_DATA_FILE, "")
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


def in_profile(pattern, flags=0):
    return has(PROFILE_CODE, pattern, flags)


def in_repo(pattern, flags=0):
    return has(REPO_CODE, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE18_FILES))
item("标题「本地数据管理」", in_view(r"Text\(\"本地数据管理\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))


# =====================================================================
# 2. 概览卡
# =====================================================================
print("== 2. 概览卡 ==")

item("训练记录数量", in_view(r"metricCell\(\"训练记录\""))
item("计划数量", in_view(r"metricCell\(\"训练计划\""))
item("自定义动作数量", in_view(r"customExerciseCount") and in_view(r"metricCell\(\"自定义动作\""))
item("身体数据数量", in_view(r"metricCell\(\"身体数据\""))
item("动作库版本", in_view(r"exerciseLibraryVersion") and in_view(r"metricCell\(\"动作库版本\""))
item("估算存储占用", in_view(r"storageSizeText") and in_view(r"metricCell\(\"存储占用\""))
item("加载失败显示「暂时无法读取」+ 重试",
     in_view(r"暂时无法读取") and in_view(r"actionTitle: \"重试\""))


# =====================================================================
# 3. 备份与恢复
# =====================================================================
print("== 3. 备份与恢复 ==")

item("「备份与恢复」分组", in_view(r"备份与恢复"))
item("导出进入导出页（页面 19）", in_view(r"导出本地备份") and in_view(r"onOpenExportBackup"))
item("导入进入导入页（页面 20）", in_view(r"导入本地备份") and in_view(r"onOpenImportBackup"))
item("备份范围可勾选",
     in_value(r"enum LocalDataBackupScope") and
     in_value(r"case sessions") and in_value(r"case plans") and
     in_value(r"case measurements") and in_value(r"case profile"))


# =====================================================================
# 4. 数据维护
# =====================================================================
print("== 4. 数据维护 ==")

item("「数据维护」分组", in_view(r"数据维护"))
item("重建统计缓存", in_view(r"重建统计缓存") and in_view(r"rebuildStats"))
item("重新导入动作库种子", in_view(r"重新导入动作库种子") and in_view(r"reseedLibrary"))
item("清理未使用的本地媒体缓存", in_view(r"清理未使用的本地媒体缓存") and in_view(r"clearMediaCache"))
item("维护说明明确不影响训练 / 计划 / 身体数据",
     in_view(r"不影响训练、计划与身体数据"))


# =====================================================================
# 5. 删除数据
# =====================================================================
print("== 5. 删除数据 ==")

item("「删除数据」分组", in_view(r"删除数据"))
item("删除全部训练记录", in_view(r"删除全部训练记录") and in_view(r"clearAllRecords"))
item("删除全部个人计划", in_view(r"删除全部个人计划") and in_view(r"deleteAllPlans"))
item("删除全部身体数据", in_view(r"删除全部身体数据") and in_view(r"deleteAllMeasurements"))
item("清除全部本地数据", in_view(r"清除全部本地数据") and in_view(r"clearAllData"))
item("每项红色危险操作", in_view(r"tint: DS\.Palette\.danger"))
item("进入二次确认页", in_view(r"DestructiveConfirmSheet"))
item("清除全部需输入「清除」", in_view(r"输入「清除」") and in_view(r"typedText == \"清除\""))
item("清除全部说明含偏好 / 资料 / 本地媒体 / 种子重新导入",
     has(CODE.get("Features/History/ClearDataView.swift", ""), r"训练偏好") and
     has(CODE.get("Features/History/ClearDataView.swift", ""), r"个人资料") and
     has(CODE.get("Features/History/ClearDataView.swift", ""), r"本地媒体") and
     has(CODE.get("Features/History/ClearDataView.swift", ""), r"重新导入"))


# =====================================================================
# 6. 原子性与结果反馈
# =====================================================================
print("== 6. 原子性与结果反馈 ==")

item("破坏性操作先写临时恢复快照", in_view(r"writeRecoverySnapshot") and in_view(r"recoverySnapshotURL"))
item("快照用原子写", in_view(r"options: \.atomic"))
item("结果提示含恢复快照位置", in_view(r"恢复快照"))
item("清除全部数据同时重置偏好", in_view(r"ProfileSettings\.resetAll"))
item("结果用 toast 反馈", in_view(r"var toast: String\?") and in_view(r"toastIsError"))
item("危险操作不用滑动删除（用按钮）", in_view(r"Button") and not_has(VIEW_CODE, r"swipeActions"))


# =====================================================================
# 7. 仓储协议与实现
# =====================================================================
print("== 7. 仓储协议与实现 ==")

item("协议含 8 个页面 18 方法",
     in_repo(r"func deleteAllPlans\(\)") and
     in_repo(r"func deleteAllMeasurements\(\)") and
     in_repo(r"func deleteAllData\(\)") and
     in_repo(r"func reseedExerciseLibrary\(\)") and
     in_repo(r"func localDataSizeBytes\(\)") and
     in_repo(r"func clearUnusedMediaCache\(\)") and
     in_repo(r"func replaceAllPlans\(_") and
     in_repo(r"func replaceAllMeasurements\(_"))
item("两个实现都覆盖新方法",
     len(re.findall(r"func deleteAllPlans\(\)", REPO_CODE)) == 3 and
     len(re.findall(r"func deleteAllMeasurements\(\)", REPO_CODE)) == 3 and
     len(re.findall(r"func reseedExerciseLibrary\(\)", REPO_CODE)) == 3)


# =====================================================================
# 8. 完整备份值层
# =====================================================================
print("== 8. 完整备份值层 ==")

item("LocalDataBackup 含四类数据", in_value(r"struct LocalDataBackup") and
     in_value(r"var sessions") and in_value(r"var plans") and
     in_value(r"var measurements") and in_value(r"var profile"))
item("格式与版本标识", in_value(r"formatIdentifier") and in_value(r"currentVersion = 1"))
item("按范围构造备份（未勾选置空）", in_value(r"scope\.contains\(\.sessions\)") and in_value(r"makeBackup"))
item("解码校验空文件 / 非 JSON / 格式 / 版本",
     in_value(r"emptyFile") and in_value(r"notJSON") and in_value(r"wrongFormat") and in_value(r"unsupportedVersion"))
item("存储占用文案是纯函数", in_value(r"enum StorageSize") and in_value(r"static func format"))
item("值层不 import SwiftUI", not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))


# =====================================================================
# 9. 偏好重置
# =====================================================================
print("== 9. 偏好重置 ==")

item("ProfileSettings.resetAll 存在", in_profile(r"static func resetAll"))
item("重置用移除键的方式（回落默认值）", in_profile(r"removeObject\(forKey:") and in_profile(r"allKeys"))


# =====================================================================
# 10. 无障碍与反规格
# =====================================================================
print("== 10. 无障碍与反规格 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("菜单行有无障碍标签", in_view(r"accessibilityElement\(children: \.combine\)"))
item("不含联网 / 账号 / 云同步",
     not_has(PAGE_CODE, r"URLSession|URLRequest|http|SignInWithApple|cloud|Cloud|登录|账号"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame"))

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
