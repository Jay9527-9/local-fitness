#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 19 规格审计（导出本地备份）。

逐条核对规格要求，对照源码。本机没有 Swift 编译器，这是唯一能证明
「规格里的每一条都真的落地了」的手段。

沿用页面 08–18 踩过假阳性换来的规则（strip_comments / 作用域三选一 /
跨行签名两段式 / 枚举 case 计数限定枚举体 / 正则圆括号转义）。

用法：
    python Tools/audit_page19.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

PAGE19_FILES = [
    "Features/History/ExportBackupView.swift",
    "Features/History/ExportBackup.swift",
]

VIEW_FILE = "Features/History/ExportBackupView.swift"
VALUE_FILE = "Features/History/ExportBackup.swift"
MGMT_FILE = "Features/History/WorkoutDataManagementView.swift"
ROOTVIEW_FILE = "Features/RootView.swift"


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

PAGE_CODE = "\n".join(CODE.get(f, "") for f in PAGE19_FILES)
VIEW_CODE = CODE.get(VIEW_FILE, "")
VALUE_CODE = CODE.get(VALUE_FILE, "")
MGMT_CODE = CODE.get(MGMT_FILE, "")
ROOT_CODE = CODE.get(ROOTVIEW_FILE, "")

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


# =====================================================================
# 1. 入口与导航
# =====================================================================
print("== 1. 入口与导航 ==")

item("页面文件都在",
     all(os.path.exists(os.path.join(SRC, f.replace("/", os.sep))) for f in PAGE19_FILES))
item("标题「导出本地备份」", in_view(r"Text\(\"导出本地备份\"\)"))
item("左侧返回", in_view(r"chevron\.left") and in_view(r"accessibilityLabel\(\"返回\"\)"))
item("数据管理页入口进导出页", in_mgmt(r"导出本地备份") and in_mgmt(r"onOpenExportBackup"))
item("两个 Tab 都注册导出路由",
     in_root(r"ProfileRoute\.exportBackup") and in_root(r"HistoryRoute\.exportBackup"))


# =====================================================================
# 2. 说明卡
# =====================================================================
print("== 2. 说明卡 ==")

item("备份用途说明（仅本地、不上传）",
     in_view(r"只保存在本机") and in_view(r"不会上传") and in_view(r"不连网盘") and in_view(r"不连账号"))
item("当前数据摘要", in_view(r"当前数据") and in_view(r"dataSummaryText"))
item("预计文件大小", in_view(r"预计大小") and in_view(r"estimatedSizeText"))


# =====================================================================
# 3. 导出内容列表
# =====================================================================
print("== 3. 导出内容列表 ==")

item("五段都有开关（枚举完整）",
     in_value(r"enum ExportBackupSegment") and
     in_value(r"case sessions") and in_value(r"case plans") and
     in_value(r"case exercises") and in_value(r"case measurements") and
     in_value(r"case preferences"))
item("训练记录段", in_value(r"case sessions") and in_value(r"训练记录"))
item("个人计划段", in_value(r"case plans") and in_value(r"个人计划"))
item("自定义动作与收藏段", in_value(r"case exercises") and in_value(r"自定义动作与收藏"))
item("身体数据段", in_value(r"case measurements") and in_value(r"身体数据"))
item("训练偏好与个人资料段", in_value(r"case preferences") and in_value(r"训练偏好与个人资料"))
item("每项带数量说明", in_view(r"countText\(for:") and in_view(r"finishedCount") and in_view(r"planCount"))
item("开关用 Toggle", in_view(r"Toggle") and in_view(r"toggleStyle\(\.switch\)"))
item("动作库种子默认不导出说明", in_view(r"动作库种子不随备份导出"))
item("媒体默认不导出说明 + 可重新导入", in_view(r"媒体文件不导出") and in_view(r"重新安装后重新导入"))


# =====================================================================
# 4. 个人资料独立开关
# =====================================================================
print("== 4. 个人资料独立开关 ==")

item("独立开关「是否包含个人资料」", in_view(r"是否包含个人资料"))
item("默认关闭", in_view(r"includeProfile = false") and in_view(r"默认关闭"))
item("开启前提示昵称 / 头像 / 说明", in_view(r"昵称、头像与个人说明") and in_view(r"confirmProfile"))
item("开启用 alert 确认", in_view(r"\.alert\(\"包含个人资料\""))
item("只有该段被勾选才导出资料", in_value(r"segments\.contains\(\.preferences\) && includeProfile"))


# =====================================================================
# 5. 生成与进度
# =====================================================================
print("== 5. 生成与进度 ==")

item("底部主按钮「生成备份」", in_view(r"生成备份"))
item("进度四步（整理 / 校验 / 写入 / 完成）",
     in_view(r"整理数据") and in_view(r"校验结构") and in_view(r"写入文件") and
     in_view(r"case done") and in_view(r"\"完成\""))
item("进度步为枚举", in_view(r"enum ExportProgressStep"))


# =====================================================================
# 6. 版本化 JSON 与校验摘要
# =====================================================================
print("== 6. 版本化 JSON 与校验摘要 ==")

item("含 schemaVersion", in_value(r"var schemaVersion"))
item("含 createdAt", in_value(r"var createdAt"))
item("含 appVersion", in_value(r"var appVersion"))
item("含所选数据段", in_value(r"var dataSegments"))
item("版本化 JSON（版本常量 + 格式标识）",
     in_value(r"static let schemaVersion = 1") and in_value(r"formatIdentifier = \"fitness-export-backup\""))
item("校验摘要用哈希", in_value(r"enum ExportBackupChecksum") and in_value(r"fnv1a64"))
item("结果展示名称 / 大小 / 创建时间 / 校验摘要",
     in_view(r"备份名称") and in_view(r"文件大小") and in_view(r"创建时间") and in_view(r"校验摘要"))


# =====================================================================
# 7. 完成后动作
# =====================================================================
print("== 7. 完成后动作 ==")

item("「保存到文件」按钮", in_view(r"保存到文件"))
item("「使用系统分享」按钮", in_view(r"使用系统分享"))
item("保存到文件走 fileExporter", in_view(r"fileExporter") and in_view(r"struct BackupDocument"))
item("系统分享走系统面板（ShareSheet + 文件 URL）", in_view(r"ShareSheet") and in_view(r"ExportedFile\(url:"))


# =====================================================================
# 8. 进行中训练过滤
# =====================================================================
print("== 8. 进行中训练过滤 ==")

item("导出前提示「是否包含未完成训练草稿」", in_view(r"是否包含未完成训练草稿"))
item("提供包含 / 跳过两选项", in_view(r"包含未完成草稿") and in_view(r"跳过未完成草稿"))
item("默认跳过草稿", in_view(r"includeDrafts = false"))
item("不修改当前训练状态（纯读取，不写会话）",
     not_has(VIEW_CODE, r"save\(session:|updateSessionDraft|finishSession") and
     in_view(r"不会改动当前训练状态"))


# =====================================================================
# 9. 失败处理
# =====================================================================
print("== 9. 失败处理 ==")

item("失败保留原始数据 + 清理临时文件 + 说明",
     in_view(r"原始数据未被改动") and in_view(r"临时文件已清理"))
item("清理未完成临时文件", in_view(r"removeItem\(at:") and in_view(r"pendingTempURL"))
item("失败给出重试按钮", in_view(r"重试") and in_view(r"case \.failed"))


# =====================================================================
# 10. 无障碍与反规格
# =====================================================================
print("== 10. 无障碍与反规格 ==")

item("语义化字体", in_view(r"DS\.Typography\.body") and in_view(r"DS\.Typography\.caption"))
item("开关带无障碍值", in_view(r"accessibilityValue"))
item("不含联网 / 账号 / 云同步 API",
     not_has(PAGE_CODE, r"URLSession|URLRequest|http://|https://|SignInWithApple|CloudKit|NSUbiquitous|AuthenticationServices"))
item("不含 iOS 17 / 16.4+ 专属 API",
     not_has(PAGE_CODE, r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView|\.presentationBackground|scrollBounceBehavior|scrollTargetBehavior|containerRelativeFrame|\.scrollIndicators"))


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
