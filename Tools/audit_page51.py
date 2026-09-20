#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 51 规格审计（权限管理）。

断言的是「规格里写的每一条，源码里有没有对应实现」。
写法沿用本项目的既有约定，特别注意下面几条踩过的坑：

- 先剥注释再判「代码里没有 X」（规则 C）；
- 要判「注释里说明了 Y」时必须读**原文**，不能读剥过的文本；
- 跨行函数签名用两段式 `fn\\(\\s*\\n?\\s*param`（规则 A）；
- 作用域三选一：值层 / 本页 / 全仓（规则 B）；
- 反规格排除查英文 API 标识符，不查中文词（规则 F）；
- 设计令牌的声明有两种写法 `static let x =` 与 `static let x: T =`（规则 D）。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

VALUE_FILE = "Features/Profile/PermissionData.swift"
CENTER_FILE = "Features/Profile/PermissionCenter.swift"
VIEW_FILE = "Features/Profile/PermissionSettingsView.swift"
SETTINGS_FILE = "Features/Profile/AppSettingsView.swift"
TOKEN_FILE = "DesignSystem/DesignTokens.swift"
ROOTVIEW_FILE = "Features/RootView.swift"
INFOPLIST = os.path.join(SRC, "Info.plist")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


FILES = {}
for dp, _, fns in os.walk(SRC):
    for name in fns:
        if name.endswith(".swift"):
            full = os.path.join(dp, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}

# 值层：只有 PermissionData.swift 是可被 Python 照搬的纯值层
VALUE = CODE.get(VALUE_FILE, "")
# 本页：值层 + 系统读取 + 视图
PAGE = VALUE + CODE.get(CENTER_FILE, "") + CODE.get(VIEW_FILE, "")
CENTERSRC = CODE.get(CENTER_FILE, "")
VIEW = CODE.get(VIEW_FILE, "")
SETTINGS = CODE.get(SETTINGS_FILE, "")
TOKEN = CODE.get(TOKEN_FILE, "")
ROOT = CODE.get(ROOTVIEW_FILE, "")
ALL = "\n".join(CODE.values())

PLIST_RAW = open(INFOPLIST, encoding="utf-8").read() if os.path.exists(INFOPLIST) else ""

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(t, p, f=0):
    return re.search(p, t, f) is not None


def in_file(rel, p):
    return has(CODE.get(rel, ""), p)


def in_raw(rel, p):
    """在**未剥注释**的原文里找（用于断言注释本身，规则 C）。"""
    return has(FILES.get(rel, ""), p)


# ============================================================
print("== 1. 值层：权限种类 ==")

item("PermissionKind 恰好两个 case",
     len(re.findall(r"\bcase\s+\w+",
                    (lambda s: s[s.find("{"):s.find("var id: String { rawValue }")])(VALUE))) == 2)
item("本地通知 case", has(VALUE, r"case localNotification"))
item("相册访问 case", has(VALUE, r"case photoLibrary"))
item("标题「本地通知」", has(VALUE, r'return "本地通知"'))
item("标题「相册访问」", has(VALUE, r'return "相册访问"'))

print("== 2. 值层：四种状态 ==")
item("四态齐全（未授权/已授权/已拒绝/受限制）",
     has(VALUE, r"case notDetermined") and has(VALUE, r"case authorized")
     and has(VALUE, r"case denied") and has(VALUE, r"case restricted"))
item("状态文案「未授权」", has(VALUE, r'return "未授权"'))
item("状态文案「已授权」", has(VALUE, r'return "已授权"'))
item("状态文案「已拒绝」", has(VALUE, r'return "已拒绝"'))
item("状态文案「受限制」", has(VALUE, r'return "受限制"'))

print("== 3. 值层：状态映射 ==")
item("通知映射独立函数",
     has(VALUE, r"static func fromNotification\(\s*\n?\s*rawValue: String\)"))
item("相册映射独立函数",
     has(VALUE, r"static func fromPhotoLibrary\(\s*\n?\s*rawValue: String\)"))
item("provisional 算已授权", has(VALUE, r'case "provisional": return \.authorized'))
item("ephemeral 算已授权", has(VALUE, r'case "ephemeral": return \.authorized'))
item("limited 算已授权", has(VALUE, r'case "limited": return \.authorized'))
item("restricted 保留为独立状态", has(VALUE, r'case "restricted": return \.restricted'))
item("未知取值兜底为未授权", has(VALUE, r"default: return \.notDetermined"))

print("== 4. 值层：设置按钮的显隐规则 ==")
item("needsSystemSettingsLink 纯属性", has(VALUE, r"var needsSystemSettingsLink: Bool"))
# 未授权时**不**显示按钮：这是「首次触发时再请求」的落点，必须逐条断言
item("未授权不显示前往设置",
     has(VALUE, r"case \.notDetermined, \.authorized: return false"))
item("已拒绝显示前往设置",
     has(VALUE, r"case \.denied, \.restricted: return true"))

print("== 5. 值层：清单与文案 ==")
item("固定顺序 order 两项",
     has(VALUE, r"static let order: \[PermissionKind\] = \[\.localNotification, \.photoLibrary\]"))
item("entries 纯函数",
     has(VALUE, r"static func entries\(\s*\n?\s*notification: PermissionStatus,\s*\n?\s*photoLibrary: PermissionStatus"))
item("不申请定位/通讯录/蓝牙/麦克风/健康数据/网络的声明",
     has(VALUE, r"不申请定位、通讯录、蓝牙、麦克风、健康数据或网络权限"))
item("不上传与不追踪声明", has(VALUE, r"权限信息不会上传，也不用于任何形式的追踪"))
item("离线 / 无账号 / 无第三方登录声明", has(VALUE, r"App 完全离线运行，不联网、无账号、无第三方登录"))
item("汇总文案纯函数",
     has(VALUE, r"static func availabilitySummary\(\s*\n?\s*_ entries: \[PermissionEntry\]\)"))
item("受限制检测纯函数",
     has(VALUE, r"static func hasRestricted\(\s*\n?\s*_ entries: \[PermissionEntry\]\)"))

print("== 6. 功能说明（每项都要说清用途）==")
item("通知用于后台休息结束提醒", has(VALUE, r"提醒你组间休息已经结束"))
item("相册仅用于本地头像", has(VALUE, r"仅用于从相册挑选一张照片作为本地头像"))
item("拒绝通知不影响前台倒计时", has(VALUE, r"前台的休息倒计时、提示音与触感都不受影响"))
item("拒绝相册仍可用默认头像", has(VALUE, r"头像会使用代码绘制的默认样式"))

print("== 7. 系统读取：只读，不申请 ==")
item("读取入口 read(completion:)",
     has(CENTERSRC, r"static func read\(\s*\n?\s*completion: @escaping \(\[PermissionEntry\]\) -> Void\)"))
item("读通知走 getNotificationSettings", has(CENTERSRC, r"getNotificationSettings"))
item("读相册走 authorizationStatus", has(CENTERSRC, r"PHPhotoLibrary\.authorizationStatus\(\)"))
item("打开系统设置走 openSettingsURLString",
     has(CENTERSRC, r"UIApplication\.openSettingsURLString"))
item("提供 openSystemSettings", has(CENTERSRC, r"static func openSystemSettings\(\)"))
# 规格第一句就是「不循环弹系统请求」：本页不能出现任何 request 调用
item("本页不申请任何权限（无 requestAuthorization / requestAuthorizationForAccessLevel）",
     not has(CENTERSRC, r"requestAuthorization|requestAuthorizationForAccessLevel"))
item("整页都不出现 request 类 API（含视图）",
     not has(PAGE, r"requestAuthorization|PHPhotoLibrary\.requestAuthorization"))

print("== 8. 视图 ==")
item("导航标题「权限管理」", has(VIEW, r'Text\("权限管理"\)'))
item("状态徽章", has(VIEW, r"statusBadge") and has(VIEW, r"Capsule\(\)"))
item("前往系统设置按钮", has(VIEW, r'Text\("前往系统设置"\)'))
item("按钮受 needsSystemSettingsLink 控制",
     has(VIEW, r"if entry\.status\.needsSystemSettingsLink"))
item("不开权限会怎样的兜底卡", has(VIEW, r'Text\("不开权限会怎样"\)'))
item("隐私声明", has(VIEW, r"PermissionCatalog\.privacyNote"))
item("从系统设置返回时重读（scenePhase）",
     has(VIEW, r"scenePhase") and has(VIEW, r"phase == \.active"))
item("加载态骨架", has(VIEW, r"SkeletonBlock\(height:"))
item("失败态可重试", has(VIEW, r'actionTitle: "重试"'))
item("返回按钮", has(VIEW, r'onBack\(\)'))
item("隐藏系统导航栏（16.3.1 上必须用 navigationBarHidden）",
     has(VIEW, r"\.navigationBarHidden\(true\)"))
item("VoiceOver 整行朗读", has(VALUE, r"var accessibilityLabel: String") and has(VIEW, r"entry\.accessibilityLabel"))

print("== 9. 反规格（规则 F：查英文 API 标识符，不查中文词）==")
# 规格：「不上传权限信息、不提供第三方登录或隐私追踪选项」
item("不含网络上传 API", not has(PAGE, r"URLSession|URLRequest|Network\.framework"))
# 注意：openSystemSettings 里合法地用了 URL(string:)（系统设置链接），
# 所以只禁「网络请求」相关的类型，不禁 URL 本身。
item("不含第三方登录 / 追踪 API",
     not has(PAGE, r"ASAuthorization|AuthenticationServices|SignInWithApple|"
                   r"AppTrackingTransparency|ATTrackingManager|AdSupport|IDFA"))
item("不含社交 / 订阅 API",
     not has(PAGE, r"StoreKit|SKPayment|GameCenter|friend|Social"))
item("不申请其它系统权限的 API 一律不出现",
     not has(PAGE, r"CLLocationManager|CoreLocation|AVAudioSession|CoreBluetooth|"
                   r"CNContactStore|Contacts|HKHealthStore|HealthKit|"
                   r"AVCaptureDevice|CoreMotion|CMMotionManager"))
item("plist 里没有其它权限 UsageDescription",
     not has(PLIST_RAW, r"NSLocation\w*UsageDescription|NSContactsUsageDescription|"
                        r"NSBluetoothAlwaysUsageDescription|NSMicrophoneUsageDescription|"
                        r"NSHealth\w*UsageDescription|NSCameraUsageDescription"))
item("plist 有相册用途说明", has(PLIST_RAW, r"NSPhotoLibraryUsageDescription"))

print("== 10. 接线 ==")
item("路由注册（case permissions）", has(ROOT, r"case permissions"))
item("路由装配视图", has(ROOT, r"PermissionSettingsView\(onBack:"))
item("应用设置入口回调", has(ROOT, r"onOpenPermissions:") and has(SETTINGS, r"let onOpenPermissions: \(\) -> Void"))
item("应用设置里有「权限管理」行",
     has(SETTINGS, r'Text\("权限管理"\)') and has(SETTINGS, r"privacyGroup"))
item("入口在 privacyGroup 内（不是混在别组）",
     has(SETTINGS, r"private var privacyGroup: some View") and has(SETTINGS, r"onOpenPermissions\(\)"))

print("== 11. 设计令牌（规则 D：`=` 与 `: T =` 两种声明都要认）==")
for tok in ["permissionGranted", "permissionIdle", "permissionDenied",
            "permissionRestricted", "permissionBadgeFill"]:
    item(f"令牌 {tok} 已声明",
         has(TOKEN, rf"static let {tok}\s*(:|=)"))
    item(f"令牌 {tok} 被本页引用", has(VIEW, rf"DS\.Palette\.{tok}"))

item("四种状态各有颜色分支",
     has(VIEW, r"case \.authorized: return DS\.Palette\.permissionGranted")
     and has(VIEW, r"case \.notDetermined: return DS\.Palette\.permissionIdle")
     and has(VIEW, r"case \.denied: return DS\.Palette\.permissionDenied")
     and has(VIEW, r"case \.restricted: return DS\.Palette\.permissionRestricted"))

print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
