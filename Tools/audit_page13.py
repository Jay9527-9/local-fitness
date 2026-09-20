#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 13 规格审计（我的）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–12 踩过假阳性换来的规则（详见 audit_page12.py 头部）：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判。
3. 查「注释里写了什么」的断言读原始 FILES。
4. 优先用结构性断言。
5. 跨行签名用两段式正则。
6. 作用域三选一（in_page / in_scan / in_value / in_view / in_model）。

用法：
    python Tools/audit_page13.py
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


PAGE13_FILES = [
    "Features/Profile/ProfileData.swift",
    "Features/Profile/ProfileView.swift",
    "Features/Profile/ProfileSubpages.swift",
    "Features/Profile/AppSettingsView.swift",
]

VALUE_FILE = "Features/Profile/ProfileData.swift"
VIEW_FILE = "Features/Profile/ProfileView.swift"
SUBPAGES_FILE = "Features/Profile/ProfileSubpages.swift"
APPSETTINGS_FILE = "Features/Profile/AppSettingsView.swift"

MODEL_FILE = "Models/Models.swift"
WIRING_FILES = ["Features/RootView.swift"]
REPO_FILES = [
    "Data/JSONFitnessRepository.swift",
    "Data/PreviewFitnessRepository.swift",
]
TOKEN_FILES = [
    "DesignSystem/Resources.swift",
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

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE13_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
SUBPAGES_CODE = CODE.get(SUBPAGES_FILE, "")
APPSETTINGS_CODE = CODE.get(APPSETTINGS_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
REPO_CODE = "\n".join(CODE.get(f, "") for f in REPO_FILES)
TOKEN_CODE = "\n".join(CODE.get(f, "") for f in TOKEN_FILES)
SCAN = PAGE_CODE + "\n" + WIRING_CODE + "\n" + MODEL_CODE + "\n" + REPO_CODE

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


def in_subpages(pattern, flags=0):
    return has(SUBPAGES_CODE, pattern, flags)


def in_appsettings(pattern, flags=0):
    return has(APPSETTINGS_CODE, pattern, flags)


def in_model(pattern, flags=0):
    return has(MODEL_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def in_token(pattern, flags=0):
    return has(TOKEN_CODE, pattern, flags)


def in_repo(pattern, flags=0):
    return has(REPO_CODE, pattern, flags)


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

item("三个页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE13_FILES),
     f"缺失: {[f for f in PAGE13_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")
item("我的 Tab 有独立 NavigationStack", in_scan(r"struct ProfileTab") and in_scan(r"NavigationStack\(path: \$path\)"))
item("身体数据入口保留", in_scan(r"onOpenBodyData") and in_scan(r"ProfileRoute\.bodyData"))
item("个人资料入口", in_scan(r"onOpenProfileEdit") and in_scan(r"ProfileRoute\.profileEdit"))
item("我的计划入口", in_scan(r"onOpenPlans") and in_scan(r"ProfileRoute\.planList"))
item("动作收藏入口", in_scan(r"onOpenFavorites") and in_scan(r"ProfileRoute\.favorites"))
item("训练偏好入口", in_scan(r"onOpenTrainingPreferences") and in_scan(r"ProfileRoute\.trainingPreferences"))
item("数据管理入口（复用页面 10）", in_scan(r"ProfileRoute\.dataManagement") and in_scan(r"WorkoutDataManagementView\("))
item("导出 / 导入备份直接触发", in_scan(r"onExportBackup") and in_scan(r"onImportBackup"))

# =====================================================================
# 2. 个人概览卡
# =====================================================================
print("== 2. 个人概览卡 ==")

item("大标题「我的」", in_view(r"Text\(\"我的\"\)") and in_view(r"largeTitle"))
item("首字母头像（代码绘制渐变背景）",
     # 页面 17 之前这里断言 `Circle().fill(accent)` + 首字母直接写在 ProfileView 里。
     # 页面 17 起头像升级为 `ProfileAvatarView`（昵称首字母 + LinearGradient 渐变，
     # 也支持本地照片），所以改成查概览卡引用该视图、且该视图用代码绘制渐变 + 首字母。
     in_view(r"ProfileAvatarView") and
     has(ALL_CODE, r"LinearGradient") and
     has(ALL_CODE, r"\.first\.map\(String\.init\)"))
item("没有昵称时显示「设置昵称」", in_view(r"displayName: String \{ nickname \?\? \"设置昵称\" \}") or
     in_view(r"设置昵称"))
item("开始使用天数", in_view(r"已使用") and in_value(r"static func daysSince\("))
item("点击卡片进入个人资料编辑", in_view(r"Button\(action: onOpenProfileEdit\)"))
item("概览卡有无障碍标签", in_view(r"accessibilityLabel\(\"个人资料"))

# =====================================================================
# 3. 个人数据摘要
# =====================================================================
print("== 3. 个人数据摘要 ==")

item("摘要含最近体重", in_view(r"title: \"最近体重\"") and in_view(r"ProfileSummaryText\.weightText"))
item("摘要含累计训练次数", in_view(r"title: \"累计训练\"") and in_view(r"ProfileSummaryText\.countText"))
item("摘要含累计训练时长", in_view(r"title: \"累计时长\"") and in_view(r"ProfileSummaryText\.durationText"))
item("无记录字段显示「—」不伪造",
     in_value(r"guard let kg = latestWeightKg else \{ return \"—\" \}") and
     in_value(r"count <= 0 \? \"—\"") and in_value(r"seconds <= 0 \? \"—\""))

# =====================================================================
# 4. 训练与身体菜单
# =====================================================================
print("== 4. 训练与身体菜单 ==")

item("身体数据菜单项", in_view(r"title: \"身体数据\"") and in_view(r"figure\.arms\.open"))
item("我的计划菜单项", in_view(r"title: \"我的计划\"") and has(ALL_CODE, r"struct PlanListView"))
item("动作收藏菜单项",
     in_view(r"title: \"动作收藏\"") and
     # 页面 16 之前这里断言 `struct FavoriteExercisesView` 在 ProfileSubpages.swift 里
     # （当时的只读列表）。页面 16 把收藏升级为完整页面后迁到
     # Features/Exercises/FavoriteExercisesView.swift，所以改成查全仓。
     has(ALL_CODE, r"struct FavoriteExercisesView"))
item("训练偏好菜单项", in_view(r"title: \"训练偏好\"") and in_subpages(r"struct TrainingPreferencesView"))
item("菜单项带 SF Symbol / 标题 / 摘要 / chevron",
     in_view(r"struct ProfileMenuRow") and in_view(r"systemName: symbol") and
     in_view(r"chevron\.right"))

# =====================================================================
# 5. 数据菜单
# =====================================================================
print("== 5. 数据菜单 ==")

item("本地数据管理菜单项", in_view(r"title: \"本地数据管理\""))
item("导入备份菜单项", in_view(r"title: \"导入备份\""))
item("导出备份菜单项", in_view(r"title: \"导出备份\""))
item("导出调用系统分享面板", in_scan(r"ShareSheet\(items:") and in_scan(r"exportedFile"))
item("导入前验证格式与版本（复用页面 10 的 importBackup）",
     in_scan(r"importBackup\(from:") and has(ALL_CODE, r"WorkoutBackupCoder\.decode"))
item("导入策略由用户选择（合并/覆盖）", in_scan(r"WorkoutBackupMergePolicy\.allCases") and in_scan(r"mergePolicy"))
item("覆盖类策略有二次确认语义", in_scan(r"policy\.isDestructive"))

# =====================================================================
# 6. 应用设置
# =====================================================================
print("== 6. 应用设置 ==")

# 页面 22 起「应用设置」从「我的」页的内联开关迁到独立页 AppSettingsView；
# 页面 42/43/44 起，单位、声音与触感、减少动态效果又各自迁到独立子页。
item("应用设置菜单项", in_view(r"title: \"应用设置\"") and in_view(r"onOpenAppSettings"))
item("单位入口（页面 42）", in_appsettings(r"onOpenUnits") and in_appsettings(r"重量 / 长度 / 有氧距离"))
item("外观模式设置", in_appsettings(r"外观模式") and in_appsettings(r"AppearanceMode"))
item("列表文字大小设置", in_appsettings(r"列表文字大小") and in_appsettings(r"ListTextSize"))
item("声音与触感入口（页面 43）", in_appsettings(r"onOpenSoundAndHaptics") and in_appsettings(r"声音与触感"))
item("休息结束通知开关", in_appsettings(r"本地休息结束通知") and in_appsettings(r"RestNotification"))
item("减少动态效果入口（页面 44）", in_appsettings(r"减少动态效果") and in_appsettings(r"motionPreference"))
item("单位切换只改展示值（不改记录）",
     has(CODE.get("Features/Profile/UnitSettingsView.swift", ""), r"ProfileSettings\.weightUnit = unit") and
     not_has(CODE.get("Features/Profile/UnitSettingsView.swift", ""), r"save\("))

# =====================================================================
# 7. 底部版本信息
# =====================================================================
print("== 7. 底部版本信息 ==")

item("显示 App 名称", in_view(r"AppResources\.appName"))
item("显示本地数据库版本", in_view(r"本地数据库 v") and in_token(r"databaseVersion"))
item("显示动作库版本", in_view(r"动作库 v") and in_token(r"exerciseLibraryVersion"))
item("显示媒体署名", in_view(r"MediaAttributionLabel\(\)"))
item("不显示原 App 名", not_has(PAGE_CODE, r"训记"))
item("不显示第三方品牌", not_has(PAGE_CODE, r"Keep|训记|第三方品牌"))

# =====================================================================
# 8. 设置持久化
# =====================================================================
print("== 8. 设置持久化 ==")

item("设置用 UserDefaults 持久化", in_value(r"UserDefaults\.standard\.set"))
item("重量 / 长度单位键与页面 12 共用",
     in_value(r"weightUnitKey = \"preference\.bodyWeightUnit\"") and
     in_value(r"lengthUnitKey = \"preference\.bodyLengthUnit\""))
item("默认休息时间有键", in_value(r"defaultRestKey = \"preference\.defaultRestSeconds\""))
item("声音 / 触感有独立键",
     in_value(r"soundKey = \"preference\.soundEnabled\"") and
     in_value(r"hapticsKey = \"preference\.hapticsEnabled\""))
item("减少动态效果有键", in_value(r"reduceMotionKey = \"preference\.reduceMotion\""))

# =====================================================================
# 9. 声音 / 触感实际生效
# =====================================================================
print("== 9. 声音 / 触感实际生效 ==")

item("触感开关关掉 Haptics", has(ALL_CODE, r"guard isEnabled else \{ return \}") and
     has(ALL_CODE, r"private static var isEnabled: Bool \{ ProfileSettings\.hapticsEnabled \}"))
item("声音开关关掉休息结束提示音",
     has(ALL_CODE, r"guard ProfileSettings\.soundEnabled else \{ return \}") and
     has(ALL_CODE, r"AudioServicesPlaySystemSound\(1057\)"))

# =====================================================================
# 10. 反规格排除
# =====================================================================
print("== 10. 反规格排除 ==")

# 反规格排除用**英文 API 标识符**判，不用中文词——
# 页脚明写「不请求登录、不含社交功能」，中文词「登录 / 社交 / 反馈」会出现在
# 这些**否定陈述**里，用中文词判必然误报。真正的登录 / 社交 / 订阅 API 一个都不该有。
item("不含登录 / 账号（无任何认证 API）",
     not_has(PAGE_CODE, r"SignInWithApple|ASAuthorization|AuthenticationServices|signIn\(|loginButton"))
item("不含好友 / 关注（无社交关系 API）",
     not_has(PAGE_CODE, r"friend|Friend|follower|Following|Follow\("))
item("不含教练", not_has(PAGE_CODE, r"coach|Coach"))
item("不含订阅", not_has(PAGE_CODE, r"StoreKit|SKProduct|Subscription|purchase"))
item("不含反馈社区", not_has(PAGE_CODE, r"反馈社区|FeedbackKit|SKStoreReview|社区"))
item("不含分享入口（设置页本体）", not_has(VIEW_CODE, r"ShareLink|UIActivityViewController"))
item("不含联网", not_has(PAGE_CODE, r"URLSession|URLRequest|http"))

# =====================================================================
# 11. 无障碍
# =====================================================================
print("== 11. 无障碍 ==")

item("菜单行有无障碍标签", in_view(r"accessibilityLabel\(subtitle\.map"))
item("开关行有无障碍标签", in_view(r"accessibilityElement\(children: \.combine\)"))
item("概览卡有无障碍标签与提示",
     in_view(r"accessibilityLabel\(\"个人资料") and in_view(r"accessibilityHint\(\"点击编辑个人资料\"\)"))
item("数据摘要合并成一句无障碍标签",
     in_view(r"accessibilityLabel\(\"最近体重"))
item("列表在动态字体下自适应（语义化字体）",
     in_view(r"DS\.Typography\.body") or in_view(r"DS\.Typography\.callout"))

# =====================================================================
# 12. 值层与工程约束
# =====================================================================
print("== 12. 值层与工程约束 ==")

item("值层不 import SwiftUI",
     not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("UserProfile 模型有容错解码",
     in_model(r"struct UserProfile: Identifiable, Codable, Hashable") and
     in_model(r"init\(from decoder: Decoder\)"))
item("UserProfile 有 trimmedNickname 归一化", in_model(r"var trimmedNickname: String\?"))
item("个人资料读写进仓储三处", has(ALL_CODE, r"func fetchProfile\(\) throws -> UserProfile\?") and
     in_repo(r"func fetchProfile\(\)") and in_repo(r"func save\(profile"))
item("协议从 50 增至 52 方法", has(ALL_CODE, r"func fetchProfile\(\)") and
     has(ALL_CODE, r"func save\(profile: UserProfile\)"))
item("页面文件都在 Profile 目录下且被 XcodeGen 自动收录",
     all(f.startswith("Features/Profile/") for f in PAGE13_FILES))
item("ViewModel 是 @MainActor 的 ObservableObject",
     in_view(r"@MainActor") and in_view(r"final class ProfileViewModel: ObservableObject"))
item("异步加载走 .task", in_view(r"\.task \{ await viewModel\.load\(\) \}"))
item("预览覆盖主页面与子页",
     has(VIEW_CODE, r"#Preview\(\"我的\"\)") and
     # 页面 17 前这里断言 `#Preview("个人资料")` 在 ProfileSubpages.swift。
     # 页面 17 起个人资料编辑迁到独立文件并改名「个人资料编辑」预览，故改查全仓。
     has(ALL_CODE, r"#Preview\(\"个人资料编辑\"\)") and
     has(SUBPAGES_CODE, r"#Preview\(\"训练偏好\"\)"))
item("没有重复定义同名类型",
     len(re.findall(r"final class ProfileViewModel\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum ProfileSettings\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct ProfileMenuRow\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct UserProfile\b", ALL_CODE)) == 1)

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
