#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 16 规格审计（收藏动作）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–15 踩过假阳性换来的规则：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判，用英文 API 标识符不用中文否定陈述。
3. 跨行签名用两段式正则。
4. 作用域三选一（in_page / in_view / in_value / in_wiring / in_repo / in_scan）。
5. 令牌声明两种写法，正则写 `static let {token}\\s*(:|=)`。

用法：
    python Tools/audit_page16.py
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


PAGE16_FILES = [
    "Features/Exercises/FavoriteExercisesView.swift",
    "Features/Exercises/FavoriteExercisesViewModel.swift",
    "Features/Exercises/FavoriteExercisesSort.swift",
]

VALUE_FILE = "Features/Exercises/FavoriteExercisesSort.swift"
VIEW_FILE = "Features/Exercises/FavoriteExercisesView.swift"
VM_FILE = "Features/Exercises/FavoriteExercisesViewModel.swift"

WIRING_FILES = ["Features/RootView.swift"]
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
    "Data/FitnessRepository.swift",
]
MODEL_FILE = "Models/Models.swift"

FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE16_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
VM_CODE = CODE.get(VM_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
REPO_CODE = "\n".join(CODE.get(f, "") for f in REPO_FILES)
MODEL_CODE = CODE.get(MODEL_FILE, "")
SCAN = PAGE_CODE + "\n" + WIRING_CODE + "\n" + REPO_CODE + "\n" + MODEL_CODE

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


def in_view(pattern, flags=0):
    return has(VIEW_CODE, pattern, flags)


def in_vm(pattern, flags=0):
    return has(VM_CODE, pattern, flags)


def in_wiring(pattern, flags=0):
    return has(WIRING_CODE, pattern, flags)


def in_repo(pattern, flags=0):
    return has(REPO_CODE, pattern, flags)


def in_model(pattern, flags=0):
    return has(MODEL_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("三个页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE16_FILES),
     f"缺失: {[f for f in PAGE16_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")
item("入口复用页面 13 的 ProfileRoute.favorites",
     in_wiring(r"ProfileRoute\.favorites") and in_wiring(r"FavoriteExercisesView"))
item("标题「收藏动作」", in_view(r"Text\(\"收藏动作\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("右侧排序按钮", in_view(r"Menu\s*\{") and in_view(r"arrow\.up\.arrow\.down"))


# =====================================================================
# 2. 排序
# =====================================================================
print("== 2. 排序 ==")

item("排序枚举四选一", in_value(r"enum FavoriteSortOrder"))
item("最近收藏", in_value(r"case recentlyFavorited") and in_value(r"最近收藏"))
item("动作名称", in_value(r"case name") and in_value(r"动作名称"))
item("主肌群", in_value(r"case primaryMuscle") and in_value(r"主肌群"))
item("最近使用", in_value(r"case recentlyUsed") and in_value(r"最近使用"))
item("排序菜单列出全部选项", in_view(r"ForEach\(FavoriteSortOrder\.allCases\)"))
item("最近收藏依据 favoritedAt 降序", in_value(r"favoritedAt") and in_value(r"l > r"))


# =====================================================================
# 3. 搜索与肌群筛选
# =====================================================================
print("== 3. 搜索与肌群筛选 ==")

item("搜索框", in_view(r"TextField\(\"搜索动作名称、别名、器械或肌群\""))
item("搜索覆盖别名 / 器械 / 肌群（复用评分器）", in_value(r"ExerciseSearch\.score"))
item("横向肌群 Chip", in_view(r"ScrollView\(\.horizontal") and in_view(r"muscleChips"))
item("肌群 Chip 含「全部」", in_view(r"title: \"全部\""))
item("肌群筛选按大类命中", in_value(r"categoryZh == category") and in_value(r"MuscleIconGroup\.of"))
item("150ms 防抖", in_vm(r"debounce\(for: \.seconds\(0\.15\)"))


# =====================================================================
# 4. 列表行
# =====================================================================
print("== 4. 列表行 ==")

item("行显示缩略图或肌群图标", in_view(r"ExerciseThumbnail\(item:"))
item("行显示动作名称", in_view(r"item\.displayName"))
item("行显示主肌群", in_view(r"item\.primaryMuscleText"))
item("行显示器械", in_view(r"item\.equipmentText"))
item("行显示难度", in_view(r"item\.difficulty\.title"))
item("点击进入详情", in_view(r"onOpen: \{ onOpenExercise\(item\) \}") or in_view(r"onOpenExercise\(item\)"))
item("右侧荧光绿已收藏星标", in_view(r"star\.fill") and in_view(r"DS\.Palette\.accent"))
item("星标独立可点取消收藏", in_view(r"accessibilityLabel\(\"取消收藏") and in_view(r"onUnfavorite"))


# =====================================================================
# 5. 取消收藏：淡出 + toast + 撤销 + 即时持久化
# =====================================================================
print("== 5. 取消收藏交互 ==")

item("取消收藏用 180ms 淡出（numberFade=0.18）",
     in_view(r"withAnimation\(DS\.Motion\.numberFade\)") and in_view(r"\.transition\(\.opacity\)"))
item("toast「已取消收藏」", in_view(r"Text\(\"已取消收藏\"\)"))
item("toast 提供「撤销」", in_view(r"Button\(\"撤销\"\)"))
item("撤销窗口 5 秒自动消失", in_vm(r"undoWindow: TimeInterval = 5") and in_vm(r"Task\.sleep"))
item("取消收藏即时落盘", in_vm(r"repository\.toggleFavorite") and in_vm(r"func unfavorite"))
item("撤销即重新收藏", in_vm(r"func undoUnfavorite") and in_vm(r"repository\.toggleFavorite"))
item("收藏时间在仓储层写入", in_repo(r"favoritedAt = ") and in_repo(r"\.isFavorite \? Date\(\) : nil"))


# =====================================================================
# 6. 长按菜单
# =====================================================================
print("== 6. 长按菜单 ==")

item("长按菜单", in_view(r"\.contextMenu"))
item("菜单：添加到训练", in_view(r"Label\(\"添加到训练\""))
item("菜单：查看详情", in_view(r"Label\(\"查看详情\""))
item("菜单：取消收藏", in_view(r"Label\(\"取消收藏\""))
item("自定义动作额外编辑入口", in_view(r"Label\(\"编辑\"") and in_view(r"item\.isCustom"))
item("添加到训练复用动作详情流程", in_view(r"AddToWorkoutSheet") and in_view(r"ExercisePrescriptionSheet"))


# =====================================================================
# 7. 空状态
# =====================================================================
print("== 7. 空状态 ==")

item("无收藏空状态「还没有收藏动作」", in_view(r"还没有收藏动作"))
item("空状态「浏览动作库」按钮", in_view(r"浏览动作库"))
item("浏览动作库跨 Tab 到动作栏", in_wiring(r"onBrowseExercises") and in_wiring(r"selection = \.exercises"))
item("查看详情跨 Tab 打开动作详情", in_wiring(r"pendingExerciseDetail") and in_wiring(r"onOpenExerciseDetail"))


# =====================================================================
# 8. 数据来源与持久化
# =====================================================================
print("== 8. 数据来源与持久化 ==")

item("只来自 isFavorite 状态", in_vm(r"filter\(\\\.isFavorite\)") or in_vm(r"\.isFavorite"))
item("favoritedAt 字段进模型", in_model(r"var favoritedAt: Date\?"))
item("favoritedAt 容错解码", in_model(r"favoritedAt = try\? c\.decode\(Date\.self, forKey: \.favoritedAt\)"))
item("两个仓储 toggleFavorite 都写收藏时间",
     len(re.findall(r"favoritedAt = ", REPO_CODE)) >= 2)


# =====================================================================
# 9. 无障碍与动态字体
# =====================================================================
print("== 9. 无障碍与动态字体 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("行有无障碍标签", in_view(r"accessibilityLabel\(accessibilityText\)"))
item("星标有无障碍标签", in_view(r"accessibilityLabel\(\"取消收藏"))
item("排序按钮有无障碍标签", in_view(r"accessibilityLabel\(\"排序方式"))


# =====================================================================
# 10. 反规格排除
# =====================================================================
print("== 10. 反规格排除 ==")

item("不展示公开收藏 / 好友收藏 / 点赞数",
     not_has(PAGE_CODE, r"公开收藏|好友|likes|Likes|likeCount"))
item("不含分享入口",
     not_has(PAGE_CODE, r"ShareSheet|ShareLink|分享|share|Share"))
item("不含登录 / 账号 / 社交",
     not_has(PAGE_CODE, r"SignInWithApple|AuthenticationServices|登录|社交"))
item("不含联网",
     not_has(PAGE_CODE, r"URLSession|URLRequest|http"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame"))


# =====================================================================
# 11. 值层与工程约束
# =====================================================================
print("== 11. 值层与工程约束 ==")

item("排序 / 筛选是纯函数", in_value(r"static func apply\(") and in_value(r"static func sorted\("))
item("值层不 import SwiftUI", not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("没有重复定义同名类型",
     len(re.findall(r"enum FavoriteSortOrder\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum FavoriteExercisesFilter\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct FavoriteExercisesView\b", ALL_CODE)) == 1 and
     len(re.findall(r"final class FavoriteExercisesViewModel\b", ALL_CODE)) == 1)
item("预览覆盖收藏页", in_view(r"#Preview\(\"收藏动作\"\)"))
item("预览覆盖空状态", in_view(r"#Preview\(\"收藏动作 · 空状态\"\)"))

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
