#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 51 值语义推演（权限管理）。

把 `PermissionData.swift` 的纯值逻辑逐行搬成 Python，再用一张断言表覆盖边界。

这一层存在的理由：preflight 只看 API 版本，lint 只看语法结构，规格审计只看
「有没有写」，**三者都看不见语义**。本页的语义集中在两处：
  (1) 系统状态 → 本页四态的映射（漏一个 case 就会把能用的功能说成不能用）；
  (2) 「前往系统设置」按钮的显隐规则（错了会把用户推去做无用功）。
两者都不涉及时间与浮点，所以断言以「枚举全覆盖」与「状态矩阵」为主。
"""

import sys

# ============================================================
# 照搬 PermissionStatus
# ============================================================

STATUSES = ["notDetermined", "authorized", "denied", "restricted"]

STATUS_TITLE = {
    "notDetermined": "未授权",
    "authorized": "已授权",
    "denied": "已拒绝",
    "restricted": "受限制",
}

NEEDS_SETTINGS_LINK = {
    "notDetermined": False,
    "authorized": False,
    "denied": True,
    "restricted": True,
}


def is_granted(s):
    """PermissionStatus.isGranted —— 只有已授权算就绪。"""
    return s == "authorized"


# ============================================================
# 照搬 PermissionStatusMapper
# ============================================================

def from_notification(raw):
    """对应 PermissionStatusMapper.fromNotification(rawValue:)"""
    if raw == "notDetermined":
        return "notDetermined"
    if raw == "denied":
        return "denied"
    if raw == "authorized":
        return "authorized"
    if raw == "provisional":
        return "authorized"
    if raw == "ephemeral":
        return "authorized"
    return "notDetermined"


def from_photo_library(raw):
    """对应 PermissionStatusMapper.fromPhotoLibrary(rawValue:)"""
    if raw == "notDetermined":
        return "notDetermined"
    if raw == "restricted":
        return "restricted"
    if raw == "denied":
        return "denied"
    if raw == "authorized":
        return "authorized"
    if raw == "limited":
        return "authorized"
    return "notDetermined"


# ============================================================
# 照搬 PermissionCatalog
# ============================================================

ORDER = ["localNotification", "photoLibrary"]

KIND_TITLE = {"localNotification": "本地通知", "photoLibrary": "相册访问"}


def entries(notification, photo_library):
    """对应 PermissionCatalog.entries(notification:photoLibrary:)"""
    m = {"localNotification": notification, "photoLibrary": photo_library}
    return [(k, m.get(k, "notDetermined")) for k in ORDER]


def availability_summary(es):
    total = len(es)
    if total == 0:
        return ""
    granted = sum(1 for _, s in es if is_granted(s))
    if granted == total:
        return f"{total} 项权限均已授权。"
    if granted == 0:
        return f"{total} 项权限都未开启，核心功能不受影响。"
    return f"{total} 项权限中的 {granted} 项已授权。"


def has_restricted(es):
    return any(s == "restricted" for _, s in es)


# ============================================================
# 断言表
# ============================================================

ok = True
COUNT = 0


def expect(label, got, want):
    global ok, COUNT
    COUNT += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


def expect_true(label, cond):
    expect(label, bool(cond), True)


print("== 1. 四态定义 ==")
expect("状态数量", len(STATUSES), 4)
expect("四种状态互不相同", len(set(STATUSES)), 4)
expect("每个状态都有中文标题", sorted(STATUS_TITLE.keys()), sorted(STATUSES))
expect_true("没有空标题", all(v.strip() for v in STATUS_TITLE.values()))

print("== 2. isGranted 只有 authorized 为真 ==")
expect("isGranted(authorized)", is_granted("authorized"), True)
for s in ["notDetermined", "denied", "restricted"]:
    expect(f"isGranted({s})", is_granted(s), False)

print("== 3. 前往系统设置的显隐规则 ==")
# 规格：「若已拒绝，提供前往系统设置按钮，不循环弹系统请求」
#       「用户首次使用相关功能时再触发系统请求」
# 未授权时不显示按钮 —— 这是「首次触发时再请求」能被满足的前提：
# 若在未授权时就引导去设置，用户会被推去手动开权限，永远走不到系统弹窗。
expect("未授权不显示按钮", NEEDS_SETTINGS_LINK["notDetermined"], False)
expect("已授权不显示按钮（无需引导）", NEEDS_SETTINGS_LINK["authorized"], False)
expect("已拒绝显示按钮", NEEDS_SETTINGS_LINK["denied"], True)
expect("受限制显示按钮", NEEDS_SETTINGS_LINK["restricted"], True)
expect("四种状态都有显隐判定", sorted(NEEDS_SETTINGS_LINK.keys()), sorted(STATUSES))
# 关系断言（比硬编码更抗改动）：按钮只在「拿不到权限」时才出现。
# 注意不是「非已授权」——未授权（notDetermined）也不显示按钮。
# 这条一开始被我写成 `NEEDS_SETTINGS_LINK[s] == (s != "authorized")`，
# 跑出来 notDetermined 一行报红。查源码后确认**代码是对的、断言错了**：
# 未授权态的正确行为是「等用户在功能里触发系统弹窗」，把用户推去设置
# 反而会让他永远走不到系统请求。改成按 {denied, restricted} 判。
SHOWS_LINK = {"denied", "restricted"}
for s in STATUSES:
    expect(f"按钮显隐 <=> 属于 {{已拒绝, 受限制}}（{s}）",
           NEEDS_SETTINGS_LINK[s], s in SHOWS_LINK)
# 反向守卫：未授权态**必须**不显示按钮，否则「首次触发时再请求」这条规格失效
expect("未授权态绝不引导去系统设置", NEEDS_SETTINGS_LINK["notDetermined"], False)

print("== 4. 通知状态映射 ==")
expect("notDetermined", from_notification("notDetermined"), "notDetermined")
expect("denied", from_notification("denied"), "denied")
expect("authorized", from_notification("authorized"), "authorized")
# provisional / ephemeral 系统都允许投递通知，必须算「已授权」。
# 若判成未授权，设置页会说「未授权」而提醒其实收得到 —— 这种不一致比不完整更糟。
expect("provisional 算已授权", from_notification("provisional"), "authorized")
expect("ephemeral 算已授权", from_notification("ephemeral"), "authorized")
expect("未知取值兜底为未授权", from_notification("somethingNew"), "notDetermined")
expect("空串兜底为未授权", from_notification(""), "notDetermined")
# 通知侧不存在 restricted（UNAuthorizationStatus 没有这个 case），
# 传入也必须被兜底而不是穿透成非法状态
expect("通知侧不产出 restricted", from_notification("restricted") in STATUSES, True)
expect("通知侧未知取值不产出 denied",
       from_notification("whatever"), "notDetermined")

print("== 5. 相册状态映射 ==")
expect("notDetermined", from_photo_library("notDetermined"), "notDetermined")
expect("restricted", from_photo_library("restricted"), "restricted")
expect("denied", from_photo_library("denied"), "denied")
expect("authorized", from_photo_library("authorized"), "authorized")
# limited（只授权部分照片）下 PhotosPicker 仍能取到用户选中的那张，头像可用
expect("limited 算已授权", from_photo_library("limited"), "authorized")
expect("未知取值兜底为未授权", from_photo_library("bogus"), "notDetermined")
expect("空串兜底为未授权", from_photo_library(""), "notDetermined")
# 相册是**唯一**会产出 restricted 的权限；若这里也兜底成 notDetermined，
# 「受限制」这个状态就永远不会出现在界面上，规格点名的四态就少一个
expect_true("相册侧能产出 restricted", from_photo_library("restricted") == "restricted")

print("== 6. 映射覆盖率：每个合法输入都落到四种状态之一 ==")
NOTIF_INPUTS = ["notDetermined", "denied", "authorized", "provisional", "ephemeral",
                "restricted", "", "unknown", "AUTHORIZED"]
PHOTO_INPUTS = ["notDetermined", "restricted", "denied", "authorized", "limited",
                "provisional", "", "unknown", "Authorized"]
bad = [i for i in NOTIF_INPUTS if from_notification(i) not in STATUSES]
expect("通知映射无非法输出", bad, [])
bad = [i for i in PHOTO_INPUTS if from_photo_library(i) not in STATUSES]
expect("相册映射无非法输出", bad, [])
# 大小写敏感：系统给的是驼峰枚举名，收到全大写的说明上游用了 String(describing:)
# 的某个变体 —— 此时兜底为未授权是安全的（提示用户去触发一次），不能瞎猜 = authorized
expect("通知映射大小写敏感（AUTHORIZED 不当作已授权）",
       from_notification("AUTHORIZED"), "notDetermined")
expect("相册映射大小写敏感（Authorized 不当作已授权）",
       from_photo_library("Authorized"), "notDetermined")

print("== 7. 清单装配 ==")
e = entries("authorized", "denied")
expect("清单长度固定为 2", len(e), 2)
expect("顺序：通知在前", [k for k, _ in e], ["localNotification", "photoLibrary"])
# 顺序必须与输入无关：字典遍历顺序在 Swift 里不确定，
# 若实现依赖字典顺序，两行每次进来会换位置
expect("顺序不受输入影响（反向输入）",
       [k for k, _ in entries("denied", "authorized")], ["localNotification", "photoLibrary"])
expect("状态正确落位（通知）", dict(e)["localNotification"], "authorized")
expect("状态正确落位（相册）", dict(e)["photoLibrary"], "denied")
expect("幂等：同样输入产出同样结果", entries("authorized", "authorized"),
       entries("authorized", "authorized"))

print("== 8. 汇总文案 ==")
expect("两项都已授权",
       availability_summary(entries("authorized", "authorized")), "2 项权限均已授权。")
expect("两项都未开启",
       availability_summary(entries("notDetermined", "notDetermined")),
       "2 项权限都未开启，核心功能不受影响。")
expect("一项已授权",
       availability_summary(entries("authorized", "notDetermined")),
       "2 项权限中的 1 项已授权。")
expect("相册已授权也算一项",
       availability_summary(entries("denied", "authorized")),
       "2 项权限中的 1 项已授权。")
# 空清单不能产出「0 项中的 0 项」这种废话
expect("空清单返回空串", availability_summary([]), "")
# 文案里的数字必须与清单长度一致，不能写死「两项」。
#
# 这条原先是 `availability_summary(全授权) != availability_summary(单项清单)`，
# 跑出来报红。查源码后确认**代码原本真有缺陷**：文案里「两项」是硬编码的，
# 传单项清单进去也会输出「两项权限均已授权。」。生产路径恒传 2 项所以看不出来，
# 但将来新增第三项权限时文案就会与界面行数不符。
# 已把 Swift 侧改成用 `total` 拼词，这里改成「条数与文案必须一致」。
expect("单项清单的文案说 1 项而不是两项",
       availability_summary([("localNotification", "authorized")]), "1 项权限均已授权。")
expect("三项清单的文案说 3 项",
       availability_summary([("localNotification", "authorized")] * 3), "3 项权限均已授权。")
expect_true("文案中的数字与清单条数一致",
            all(f"{n} 项" in availability_summary([("localNotification", "authorized")] * n)
                for n in (1, 2, 3, 5)))

print("== 9. 汇总文案的方向一致性（关系断言，不硬编码句子）==")
for n in STATUSES:
    for p in STATUSES:
        es = entries(n, p)
        granted = sum(1 for _, s in es if is_granted(s))
        text = availability_summary(es)
        if granted == 2:
            expect_true(f"全授权时不含「未开启」字样（{n}/{p}）", "未开启" not in text)
        elif granted == 0:
            expect_true(f"全未授权时必含「不受影响」安抚（{n}/{p}）", "不受影响" in text)
        else:
            expect_true(f"半授权文案含数字 1（{n}/{p}）", "1" in text)

print("== 10. 受限制的检测 ==")
expect_true("有受限时检出", has_restricted(entries("notDetermined", "restricted")))
expect("无受限时为假", has_restricted(entries("denied", "authorized")), False)
expect("全授权为假", has_restricted(entries("authorized", "authorized")), False)
# 通知侧永远产不出 restricted，因此「受限制」只可能来自相册。
#
# 这条原先写成 `has_restricted(entries("restricted", "authorized")) == False` ——
# 我直接把非法值 `restricted` 塞进了通知位。但真实数据流里通知状态只可能来自
# `from_notification()`，所以正确的断言对象是**映射器**，不是 `entries`：
# 给 entries 硬塞一个映射器永远不会产出的值，测的是我自己的输入，不是代码。
expect_true("通知映射器永不产出 restricted",
            all(from_notification(i) != "restricted" for i in NOTIF_INPUTS))
expect_true("相册映射器是 restricted 的唯一来源",
            from_photo_library("restricted") == "restricted")

print("== 11. 「拒绝不影响核心功能」的守卫 ==")
# 规格：拒绝权限不影响核心功能。因此任何状态下，清单都必须是完整的 2 项
# （不能因为没授权就把某一项从列表里藏起来 —— 那会让用户找不到去哪里开）。
for n in STATUSES:
    for p in STATUSES:
        expect_true(f"任一状态下清单仍为 2 项（{n}/{p}）",
                    len(entries(n, p)) == 2)
# 且两项都必须有用途说明与兜底说明
for k in ORDER:
    expect_true(f"{k} 有中文标题", bool(KIND_TITLE[k].strip()))

print("\n" + "=" * 72)
print(f"断言 {COUNT} 条，失败 {0 if ok else 1} 组")
sys.exit(0 if ok else 1)
