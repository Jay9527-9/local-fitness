#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 14 规格审计（训练偏好设置）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–13 踩过假阳性换来的规则（详见 audit_page12.py / audit_page13.py 头部）：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判。
3. 查「注释里写了什么」的断言读原始 FILES。
4. 优先用结构性断言。
5. 跨行签名用两段式正则。
6. 作用域三选一（in_page / in_scan / in_value / in_view / in_subpages / in_model / in_token）。
7. 令牌声明两种写法：颜色 `static let x =`、尺寸 `static let x: CGFloat =`，正则要写 `static let {token}\\s*(:|=)`。

用法：
    python Tools/audit_page14.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")


def read(rel):
    path = os.path.join(SRC, rel.replace("/", os.sep))
    if not os.path.exists(path):
        return ""
    with open(path, encoding="utf-8") as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


# 页面 14 的值层仍落在 ProfileData.swift（与页面 13 共享，训练偏好是同一批 UserDefaults）。
# 视图落在 ProfileSubpages.swift 的 TrainingPreferencesView。
PAGE14_FILES = [
    "Features/Profile/ProfileData.swift",
    "Features/Profile/ProfileSubpages.swift",
    "Features/Profile/ProfileView.swift",
]

VALUE_FILE = "Features/Profile/ProfileData.swift"
SUBPAGES_FILE = "Features/Profile/ProfileSubpages.swift"
VIEW_FILE = "Features/Profile/ProfileView.swift"

# 设置真正生效的地方（训练执行页 + 组间休息面板 + 草稿预填）
WIRING_FILES = [
    "Features/Training/WorkoutSessionViewModel.swift",
    "Features/Training/WorkoutSessionView.swift",
    "Features/Training/WorkoutSessionComponents.swift",
    "Features/Training/RestCountdownPanel.swift",
    "Features/Plans/PlanDetailViewModel.swift",
    "Features/RootView.swift",
]
TOKEN_FILES = ["DesignSystem/DesignTokens.swift"]

FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE14_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
SUBPAGES_CODE = CODE.get(SUBPAGES_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
TOKEN_CODE = "\n".join(CODE.get(f, "") for f in TOKEN_FILES)
SCAN = PAGE_CODE + "\n" + WIRING_CODE + "\n" + TOKEN_CODE

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


def in_page(pattern, flags=0):
    return has(PAGE_CODE, pattern, flags)


def in_value(pattern, flags=0):
    return has(VALUE_CODE, pattern, flags)


def in_subpages(pattern, flags=0):
    return has(SUBPAGES_CODE, pattern, flags)


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_wiring(pattern, flags=0):
    return has(WIRING_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def in_token(pattern, flags=0):
    return has(TOKEN_CODE, pattern, flags)


def func_body(code, signature):
    start = code.find(signature)
    if start < 0:
        return ""
    brace = code.find("{", start)
    if brace < 0:
        return ""
    depth = 0
    for i in range(brace, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return code[brace:i + 1]
    return ""


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("训练偏好入口保留（页面 13 接的）", in_scan(r"ProfileRoute\.trainingPreferences") and in_scan(r"TrainingPreferencesView\(onBack"))
item("训练偏好视图在 ProfileSubpages", in_subpages(r"struct TrainingPreferencesView"))
item("标题「训练偏好」", in_subpages(r"Text\(\"训练偏好\"\)"))
item("左侧返回", in_subpages(r"chevron\.left") and in_subpages(r"accessibilityLabel\(\"返回\"\)"))

# =====================================================================
# 2. 第一组 训练记录
# =====================================================================
print("== 2. 第一组 训练记录 ==")

item("第一组标题「训练记录」", in_subpages(r"group\(title: \"训练记录\"\)"))
item("默认组间休息时间：点击打开秒数选择器",
     in_subpages(r"title: \"默认组间休息时间\"") and in_subpages(r"showRestPicker = true"))
item("秒数选择器复用预设档（30/45/60/90/120/180 + 自定义）",
     in_value(r"restPresets = \[30, 45, 60, 90, 120, 180\]") and in_scan(r"DefaultRestPickerContent\("))
item("自动复制上次记录：开关", in_subpages(r"title: \"自动复制上次记录\""))
item("自动复制上次记录复用页面 13 的 prefillWeights 键（不落两把键）",
     in_subpages(r"ProfileSettings\.prefillWeights = on") and in_value(r"prefillWeightsKey"))
item("完成一组后自动开始休息：开关", in_subpages(r"title: \"完成一组后自动开始休息\""))
item("显示训练容量：开关", in_subpages(r"title: \"显示训练容量\""))

# =====================================================================
# 3. 第二组 计时器
# =====================================================================
print("== 3. 第二组 计时器 ==")

item("第二组标题「计时器」", in_subpages(r"group\(title: \"计时器\"\)"))
item("倒计时提示音：开关", in_subpages(r"title: \"倒计时提示音\"") and in_subpages(r"ProfileSettings\.soundEnabled = on"))
item("触感反馈：开关", in_subpages(r"title: \"触感反馈\"") and in_subpages(r"ProfileSettings\.hapticsEnabled = on"))
item("倒计时最后 10 秒提醒：开关", in_subpages(r"title: \"倒计时最后 10 秒提醒\""))
item("倒计时数字样式：普通 / 大号", in_subpages(r"title: \"倒计时数字样式\"") and in_subpages(r"showCountdownStylePicker = true"))
item("数字样式单选底部抽屉", in_subpages(r"CountdownStylePickerContent") and in_subpages(r"CountdownNumberStyle\.allCases"))

# =====================================================================
# 4. 第三组 训练流程
# =====================================================================
print("== 4. 第三组 训练流程 ==")

item("第三组标题「训练流程」", in_subpages(r"group\(title: \"训练流程\"\)"))
item("完成当前动作后自动定位下一动作：开关", in_subpages(r"title: \"完成当前动作后自动定位下一动作\""))
item("新增组时复制上一组数值：开关", in_subpages(r"title: \"新增组时复制上一组数值\""))
item("默认显示热身组：开关", in_subpages(r"title: \"默认显示热身组\""))
item("最小化训练后保留计时器：开关", in_subpages(r"title: \"最小化训练后保留计时器\""))

# =====================================================================
# 5. 恢复默认
# =====================================================================
print("== 5. 恢复默认 ==")

item("底部「恢复默认训练偏好」危险操作", in_subpages(r"恢复默认训练偏好") and in_subpages(r"DS\.Palette\.danger"))
item("先展示将被重置的选项清单", in_value(r"trainingPreferenceDefaults") and in_subpages(r"ResetTrainingDefaultsContent"))
item("二次确认后才真正恢复", in_subpages(r"onConfirm:") and in_subpages(r"restoreTrainingDefaults\(\)"))
item("恢复默认只重置训练偏好，不碰单位 / 深色 / 减动效",
     in_value(r"restoreTrainingDefaults") and
     not_has(func_body(VALUE_CODE, "static func restoreTrainingDefaults()"), r"weightUnit|lengthUnit|darkAppearance|reduceMotion"))
item("不删除训练数据（恢复函数只写 UserDefaults，不触仓储）",
     not_has(func_body(VALUE_CODE, "static func restoreTrainingDefaults()"), r"repository|delete|plans|sessions|exercises|measurements"))

# =====================================================================
# 6. 原子写入本地偏好
# =====================================================================
print("== 6. 原子写入本地偏好 ==")

item("新增键用 UserDefaults 原子写", in_value(r"UserDefaults\.standard\.set"))
item("显示训练容量有独立键", in_value(r"showVolumeKey = \"preference\.showVolume\""))
item("最后 10 秒提醒有独立键", in_value(r"lastTenSecondsReminderKey = \"preference\.lastTenSecondsReminder\""))
item("倒计时数字样式有独立键", in_value(r"countdownStyleKey = \"preference\.countdownStyle\""))
item("自动定位下一动作有独立键", in_value(r"autoAdvanceExerciseKey = \"preference\.autoAdvanceExercise\""))
item("新增组复制上一组有独立键", in_value(r"copyPreviousSetKey = \"preference\.copyPreviousSet\""))
item("默认显示热身组有独立键", in_value(r"showWarmupSetsKey = \"preference\.showWarmupSets\""))
item("最小化保留计时器有独立键", in_value(r"keepTimerOnMinimizeKey = \"preference\.keepTimerOnMinimize\""))

# =====================================================================
# 7. 设置真正生效
# =====================================================================
print("== 7. 设置真正生效 ==")

item("显示训练容量：关闭后概览不显示总容量",
     in_wiring(r"if ProfileSettings\.showVolume") and in_wiring(r'metrics\.append\(\("总训练容量'))
item("显示训练容量：无障碍文案同步",
     in_wiring(r"if ProfileSettings\.showVolume \{\n            parts\.append"))
item("自动开始休息：关闭后完成组不自动开倒计时",
     in_wiring(r"if ProfileSettings\.autoStartRest \{\n                    startRest"))
item("自动复制上次记录：关闭后草稿不预填重量",
     in_wiring(r"guard ProfileSettings\.prefillWeights else \{ return \}"))
item("自动复制上次记录：两处草稿入口都接上",
     len(re.findall(r"guard ProfileSettings\.prefillWeights else \{ return \}", WIRING_CODE)) >= 2)
item("最后 10 秒提醒：关闭后不再转荧光绿",
     in_wiring(r"ProfileSettings\.lastTenSecondsReminder"))
item("倒计时数字样式：大号用更大字号",
     in_wiring(r"ProfileSettings\.countdownStyle") and in_token(r"restCountdownFontLarge"))
item("自动定位下一动作：完成整卡后滚动到下一张",
     in_wiring(r"scheduleAdvanceIfNeeded") and in_wiring(r"ScrollViewReader") and in_wiring(r"proxy\.scrollTo"))
item("新增组复制上一组：关闭后重量从 0 起填",
     in_wiring(r"ProfileSettings\.copyPreviousSet") and in_wiring(r"copiedWeight"))
item("默认显示热身组：关闭后热身组行隐藏",
     in_wiring(r"ProfileSettings\.showWarmupSets") and in_wiring(r"filter \{ !\$0\.isWarmup \}"))
item("最小化保留计时器：关闭后最小化停掉休息倒计时",
     in_wiring(r"if !ProfileSettings\.keepTimerOnMinimize") and in_wiring(r"restTimer = nil"))

# =====================================================================
# 8. 无障碍
# =====================================================================
print("== 8. 无障碍 ==")

item("每个开关 accessibility value 朗读「已开启 / 已关闭」",
     in_view(r"accessibilityValue\(isOn \? \"已开启\" : \"已关闭\"\)"))
item("影响数据行为的选项有低对比说明", in_subpages(r"subtitle:") )
item("倒计时数字样式有无障碍选中态", in_subpages(r"accessibilityAddTraits\(style == selected \? \[\.isSelected\] : \[\]\)"))
item("恢复默认按钮有无障碍提示", in_subpages(r"accessibilityHint\(\"只重置训练偏好"))
item("列表用语义化字体（动态字体自适应）",
     in_subpages(r"DS\.Typography\.body") or in_subpages(r"DS\.Typography\.callout"))

# =====================================================================
# 9. 反规格排除（无云同步 / 账号 / 社交）
# =====================================================================
print("== 9. 反规格排除 ==")

item("不含云同步 / 账号同步",
     not_has(PAGE_CODE, r"CloudKit|iCloud|NSUbiquitous|accountSync|signIn\(|ASAuthorization"))
item("不含社交偏好",
     not_has(PAGE_CODE, r"friend|Friend|follower|Follow\(|ShareLink|UIActivityViewController"))
item("不含联网", not_has(PAGE_CODE, r"URLSession|URLRequest|http"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollTargetBehavior|containerRelativeFrame|\.toolbar\(\.hidden, for:"))

# =====================================================================
# 10. 值层与工程约束
# =====================================================================
print("== 10. 值层与工程约束 ==")

item("值层不 import SwiftUI",
     not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("倒计时数字样式是纯值枚举", in_value(r"enum CountdownNumberStyle: String, CaseIterable, Identifiable, Equatable"))
item("恢复默认清单项是值结构", in_value(r"struct TrainingPreferenceResetItem: Identifiable, Equatable"))
item("没有重复定义同名类型",
     len(re.findall(r"enum CountdownNumberStyle\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct TrainingPreferenceResetItem\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct CountdownStylePickerContent\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct ResetTrainingDefaultsContent\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct TrainingPreferencesView\b", ALL_CODE)) == 1)
item("预览覆盖训练偏好页", in_subpages(r"#Preview\(\"训练偏好\"\)"))

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
