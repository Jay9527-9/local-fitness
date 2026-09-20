#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 17 规格审计（个人资料编辑）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–16 踩过假阳性换来的规则：
1. 扫描前必须 strip_comments()。
2. 排除类断言按页面范围判，用英文 API 标识符不用中文否定陈述。
3. 跨行签名用两段式正则。
4. 作用域三选一（in_page / in_view / in_value / in_model / in_wiring / in_scan）。
5. 令牌声明两种写法，正则写 `static let {token}\\s*(:|=)`。

关于头像：本页用 `PhotosPicker`（iOS 16 原生、out-of-process），
它**不需要**相册权限——「照片权限被拒绝」这一态在系统层面就被避开了。
「降级提示」落在读取 / 压缩 / 落盘失败时，均提示「已保留原头像」。

用法：
    python Tools/audit_page17.py
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


PAGE17_FILES = [
    "Features/Profile/ProfileEditView.swift",
    "Features/Profile/AvatarStore.swift",
]

VALUE_FILE = "Features/Profile/ProfileData.swift"
VIEW_FILE = "Features/Profile/ProfileEditView.swift"
AVATAR_FILE = "Features/Profile/AvatarStore.swift"
OVERVIEW_FILE = "Features/Profile/ProfileView.swift"
MODEL_FILE = "Models/Models.swift"
WIRING_FILES = ["Features/RootView.swift"]

FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
ALL_CODE = "\n".join(CODE.values())

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE17_FILES)
VALUE_CODE = CODE.get(VALUE_FILE, "")
VIEW_CODE = CODE.get(VIEW_FILE, "")
AVATAR_CODE = CODE.get(AVATAR_FILE, "")
OVERVIEW_CODE = CODE.get(OVERVIEW_FILE, "")
MODEL_CODE = CODE.get(MODEL_FILE, "")
WIRING_CODE = "\n".join(CODE.get(f, "") for f in WIRING_FILES)
SCAN = PAGE_CODE + "\n" + VALUE_CODE + "\n" + OVERVIEW_CODE + "\n" + MODEL_CODE + "\n" + WIRING_CODE

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


def in_avatar(pattern, flags=0):
    return has(AVATAR_CODE, pattern, flags)


def in_overview(pattern, flags=0):
    return has(OVERVIEW_CODE, pattern, flags)


def in_model(pattern, flags=0):
    return has(MODEL_CODE, pattern, flags)


def in_wiring(pattern, flags=0):
    return has(WIRING_CODE, pattern, flags)


def in_scan(pattern, flags=0):
    return has(SCAN, pattern, flags)


def body_of(code, marker):
    """取某个类型声明的花括号体（用于把 case 计数限制在该类型内，避免重名 case 串味）。"""
    start = code.find(marker)
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

item("页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE17_FILES),
     f"缺失: {[f for f in PAGE17_FILES if not os.path.exists(os.path.join(SRC, f.replace('/', os.sep)))]}")
item("入口复用页面 13 的 ProfileRoute.profileEdit",
     in_wiring(r"ProfileRoute\.profileEdit") and in_wiring(r"ProfileEditView"))
item("左侧取消", in_view(r"Button\(\"取消\"\)"))
item("中间标题「个人资料」", in_view(r"Text\(\"个人资料\"\)"))
item("右侧保存", in_view(r"Button\(\"保存\"\)"))
item("存在未保存改动时弹「放弃修改？」", in_view(r"alert\(\s*\"放弃修改？\"") and in_view(r"showDiscardConfirm"))


# =====================================================================
# 2. 头像
# =====================================================================
print("== 2. 头像 ==")

item("头像可点按，从相册选照片", in_view(r"PhotosPicker\(selection:") and in_view(r"matching: \.images"))
item("默认头像：昵称首字母 + 渐变背景", in_view(r"struct ProfileAvatarView") and in_view(r"LinearGradient"))
item("支持移除照片 / 恢复默认", in_view(r"移除照片，恢复默认头像") and in_view(r"removeAvatar"))
item("图片压缩后保存本地", in_view(r"compressedJPEG") and in_avatar(r"func save\(_ data: Data"))
item("头像保存在本地目录", in_avatar(r"applicationSupportDirectory") and in_avatar(r"FitnessData"))
item("头像落盘失败保留原头像", in_view(r"头像保存失败，已保留原头像") and in_view(r"return false"))
item("读取失败降级提示", in_view(r"无法读取所选照片，已保留原头像"))


# =====================================================================
# 3. 表单字段
# =====================================================================
print("== 3. 表单字段 ==")

item("昵称输入框", in_view(r"TextField\(\"输入昵称\"") and in_view(r"nicknameText"))
item("昵称上限 20 字符", in_value(r"nicknameMaxLength = 20"))
item("昵称去前后空格", in_value(r"trimmingCharacters\(in: \.whitespacesAndNewlines\)") and in_value(r"normalizedNickname"))
item("训练开始日期 DatePicker", in_view(r"DatePicker") and in_view(r"训练开始日期"))
item("训练目标单选 Chip", in_view(r"FlowChips") and in_view(r"TrainingGoal\.allCases"))
item("训练目标六选一",
     len(re.findall(r"\bcase\s+\w+", body_of(MODEL_CODE, "enum TrainingGoal"))) == 6 and
     all(t in body_of(MODEL_CODE, "enum TrainingGoal") for t in ["增肌", "减脂", "力量", "体能", "保持健康", "自定义"]))
item("自定义目标可填文字", in_view(r"TextField\(\"输入你的训练目标\"") and in_model(r"customGoal"))
item("个人说明多行输入", in_view(r"TextEditor\(text: \$viewModel\.bioText\)"))
item("个人说明上限 200 字", in_value(r"bioMaxLength = 200"))
item("个人说明仅本机展示", in_view(r"仅用于本机展示") and in_model(r"var bio: String\?"))


# =====================================================================
# 4. 保存与同步
# =====================================================================
print("== 4. 保存与同步 ==")

item("保存写入本地 UserProfile", in_view(r"repository\.save\(profile:") and in_view(r"UserProfile\("))
item("昵称变化同步「我的」概览", in_wiring(r"profileReloadToken = UUID\(\)") and in_wiring(r"onSaved"))
item("概览卡显示本地头像", in_overview(r"ProfileAvatarView") and in_overview(r"AvatarStore\.data"))


# =====================================================================
# 5. 数据模型
# =====================================================================
print("== 5. 数据模型 ==")

item("UserProfile 含训练目标 / 说明 / 头像字段",
     in_model(r"var trainingGoal: TrainingGoal\?") and
     in_model(r"var bio: String\?") and
     in_model(r"var avatarFileName: String\?"))
item("旧版本 profile.json 容错解码",
     in_model(r"decodeIfPresent\(String\.self, forKey: \.bio\)") and
     in_model(r"decodeIfPresent\(String\.self, forKey: \.avatarFileName\)"))
item("TrainingGoal 枚举", in_model(r"enum TrainingGoal: String, Codable, CaseIterable, Identifiable"))


# =====================================================================
# 6. 底部说明与反规格排除
# =====================================================================
print("== 6. 底部说明与反规格排除 ==")

item("底部「本地资料说明」", in_view(r"这些资料仅保存在本设备"))
item("不显示账号 ID / 手机号 / 邮箱",
     not_has(PAGE_CODE, r"accountID|userId|phoneNumber|手机号|邮箱|email|Email"))
item("不显示好友 / 关注 / 主页 / 社交统计",
     not_has(PAGE_CODE, r"好友|关注|follow|Follow|个人主页|粉丝|social|Social"))
item("不含登录 / 上传云端",
     not_has(PAGE_CODE, r"SignInWithApple|AuthenticationServices|登录|upload|Upload|cloud|Cloud|http"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame"))


# =====================================================================
# 7. 无障碍与动态字体
# =====================================================================
print("== 7. 无障碍与动态字体 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("头像有无障碍标签", in_view(r"accessibilityLabel\(\"头像\"\)"))
item("字符计数有无障碍", in_view(r"accessibilityLabel\(\"已输入"))
item("取消 / 保存按钮可点按", in_view(r"accessibilityLabel\(\"取消\"\)") and in_view(r"accessibilityLabel\(\"保存个人资料\"\)"))


# =====================================================================
# 8. 值层与工程约束
# =====================================================================
print("== 8. 值层与工程约束 ==")

item("校验是纯函数", in_value(r"static func normalizedNickname") and in_value(r"static func normalizedBio"))
item("值层不 import SwiftUI", not_has(VALUE_CODE, r"import SwiftUI") and has(VALUE_CODE, r"import Foundation"))
item("头像存储不 import SwiftUI", not_has(AVATAR_CODE, r"import SwiftUI") and has(AVATAR_CODE, r"import Foundation"))
item("没有重复定义同名类型",
     len(re.findall(r"struct ProfileEditView\b", ALL_CODE)) == 1 and
     len(re.findall(r"final class ProfileEditViewModel\b", ALL_CODE)) == 1 and
     len(re.findall(r"struct ProfileAvatarView\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum AvatarStore\b", ALL_CODE)) == 1 and
     len(re.findall(r"enum TrainingGoal\b", ALL_CODE)) == 1)
item("预览覆盖个人资料编辑页", in_view(r"#Preview\(\"个人资料编辑\"\)"))

# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
