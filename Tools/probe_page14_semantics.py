#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 14 值语义推演（训练偏好设置）。

把 `ProfileData.swift` 里页面 14 新增的纯值层逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「边界算错」的唯一手段。

重点覆盖（本页最容易算错的地方）：
1. `CountdownNumberStyle` 的 rawValue / title 映射（普通 / 大号不能串）；
2. `restoreTrainingDefaults()` 恢复的完整键清单——多写一个（把单位/深色也重置）
   或少写一个（某项偏好没恢复）都是 bug；
3. 「恢复默认」的默认值语义：哪些默认开、哪些默认关（自动定位下一动作应默认关）；
4. `trainingPreferenceDefaults` 清单与真正恢复的键一一对应，不能出现
   「清单里说要恢复、函数里却没写」或反过来的漂移。

用法：
    python Tools/probe_page14_semantics.py
"""

# =====================================================================
# 照搬 ProfileData.swift 的纯值层
# =====================================================================

# 默认休息时间（秒）
DEFAULT_REST_SECONDS = 90


def rest_text(seconds):
    """照抄 FormatterKit.rest：>=60 秒写「N 分」/「N 分 M 秒」，否则「N 秒」。"""
    total = max(0, seconds)
    if total < 60:
        return f"{total} 秒"
    minutes = total // 60
    remainder = total % 60
    if remainder == 0:
        return f"{minutes} 分"
    return f"{minutes} 分 {remainder} 秒"


# CountdownNumberStyle 照搬
COUNTDOWN_STYLES = {"normal": "普通", "large": "大号"}


def countdown_title(raw):
    return COUNTDOWN_STYLES[raw]


# restoreTrainingDefaults 照搬：每一项 (key -> 默认值)
# 键名只取可读后缀，方便断言
def restore_training_defaults():
    return {
        "defaultRest": DEFAULT_REST_SECONDS,
        "prefillWeights": True,
        "autoStartRest": True,
        "showVolume": True,
        "lastTenSecondsReminder": True,
        "countdownStyle": "normal",
        "autoAdvanceExercise": False,
        "copyPreviousSet": True,
        "showWarmupSets": True,
        "keepTimerOnMinimize": True,
    }


# trainingPreferenceDefaults 照搬：(title, default-value-text) 清单
def training_preference_defaults():
    return [
        ("默认组间休息时间", rest_text(DEFAULT_REST_SECONDS)),
        ("完成一组后自动开始休息", "开启"),
        ("自动复制上次记录", "开启"),
        ("显示训练容量", "开启"),
        ("倒计时提示音", "开启"),
        ("触感反馈", "开启"),
        ("倒计时最后 10 秒提醒", "开启"),
        ("倒计时数字样式", "普通"),
        ("完成当前动作后自动定位下一动作", "关闭"),
        ("新增组时复制上一组数值", "开启"),
        ("默认显示热身组", "开启"),
        ("最小化训练后保留计时器", "开启"),
    ]


# 会被恢复的键与「默认开/关」的期望值，用于交叉核对
EXPECTED_DEFAULTS = {
    "defaultRest": 90,
    "prefillWeights": True,
    "autoStartRest": True,
    "showVolume": True,
    "lastTenSecondsReminder": True,
    "countdownStyle": "normal",
    "autoAdvanceExercise": False,
    "copyPreviousSet": True,
    "showWarmupSets": True,
    "keepTimerOnMinimize": True,
}

# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 倒计时数字样式映射]")
expect("normal → 普通", countdown_title("normal"), "普通")
expect("large → 大号", countdown_title("large"), "大号")
expect("只有两种样式", sorted(COUNTDOWN_STYLES.keys()), ["large", "normal"])

print("[2 恢复默认的键清单]")
got_defaults = restore_training_defaults()
expect("恢复的键数量 = 10", len(got_defaults), 10)
expect("键清单与期望完全一致", set(got_defaults.keys()), set(EXPECTED_DEFAULTS.keys()))
for key, want in EXPECTED_DEFAULTS.items():
    expect(f"恢复 {key} = {want!r}", got_defaults[key], want)

print("[3 恢复默认不碰非训练偏好]")
# 单位 / 深色 / 减动效 / 通知都不该在恢复默认清单里
for forbidden in ("weightUnit", "lengthUnit", "darkAppearance", "reduceMotion", "soundEnabled", "hapticsEnabled", "restNotification"):
    expect(f"不含 {forbidden}", forbidden in got_defaults, False)

print("[4 自动定位下一动作默认关（最容易被想当然写成开）]")
expect("autoAdvanceExercise 默认 False", got_defaults["autoAdvanceExercise"], False)
expect("其余布尔默认 True", all(
    got_defaults[k] for k in (
        "prefillWeights", "autoStartRest", "showVolume",
        "lastTenSecondsReminder", "copyPreviousSet", "showWarmupSets",
        "keepTimerOnMinimize",
    )
), True)

print("[5 恢复默认清单与函数交叉核对]")
items = training_preference_defaults()
expect("清单条数 = 12", len(items), 12)
titles = [t for t, _ in items]
expect("清单标题无重复", len(titles), len(set(titles)))
# 清单里「默认组间休息时间」的值必须是 rest_text(90)
rest_row = next((v for t, v in items if t == "默认组间休息时间"), None)
expect("默认组间休息时间文案 = 1 分 30 秒", rest_row, rest_text(90))
# 「自动定位下一动作」必须显示「关闭」
adv_row = next((v for t, v in items if t == "完成当前动作后自动定位下一动作"), None)
expect("自动定位下一动作默认文案 = 关闭", adv_row, "关闭")
# 其余「开启」项的数量：12 项里，休息时间是「1 分 30 秒」、自动定位是「关闭」、
# 数字样式是「普通」，剩下 9 项都是「开启」。
on_count = sum(1 for _, v in items if v == "开启")
expect("「开启」项 = 9", on_count, 9)
expect("「关闭」项 = 1", sum(1 for _, v in items if v == "关闭"), 1)

print("[6 清单与函数语义一致（无漂移）]")
# 清单里每个「开启/关闭/普通」都能在恢复函数里找到对应的默认值
# 清单 12 项 ↔ 函数 10 项：清单里「倒计时提示音」「触感反馈」两项
# 走的是 soundEnabled/hapticsEnabled（页面 13 键），不在本页 restore 函数里。
list_controlled_keys = {
    "默认组间休息时间": "defaultRest",
    "完成一组后自动开始休息": "autoStartRest",
    "自动复制上次记录": "prefillWeights",
    "显示训练容量": "showVolume",
    "倒计时最后 10 秒提醒": "lastTenSecondsReminder",
    "倒计时数字样式": "countdownStyle",
    "完成当前动作后自动定位下一动作": "autoAdvanceExercise",
    "新增组时复制上一组数值": "copyPreviousSet",
    "默认显示热身组": "showWarmupSets",
    "最小化训练后保留计时器": "keepTimerOnMinimize",
}
expect("清单里 10 项能映射到恢复函数的键", len(list_controlled_keys), 10)
for title, key in list_controlled_keys.items():
    expect(f"「{title}」对应键 {key} 存在", key in got_defaults, True)

print("[7 休息时间文案边界]")
expect("rest_text(90) = 1 分 30 秒", rest_text(90), "1 分 30 秒")
expect("rest_text(60) = 1 分", rest_text(60), "1 分")
expect("rest_text(45) = 45 秒", rest_text(45), "45 秒")
expect("rest_text(120) = 2 分", rest_text(120), "2 分")

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
