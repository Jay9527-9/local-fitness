#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 13 值语义推演（我的）。

把 `ProfileData.swift` 的纯值层逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「边界算错」的唯一手段。

重点覆盖（本页最容易算错的地方）：
1. 「已使用 N 天」的自然日计算（昨天开始 = 1 天，今天开始 = 0 天，时钟回拨不为负）；
2. 数据摘要的「— / 0」分界（没记录显示「—」，有记录是 0 才显示 0）；
3. 昵称的空白归一化（nil / 全空白 → nil）；
4. 默认休息时间的兜底（存了非法值回落到 90）。

用法：
    python Tools/probe_page13_semantics.py
"""

from datetime import datetime, timedelta, timezone

TZ = timezone(timedelta(hours=8))
POUNDS_PER_KILOGRAM = 2.20462262185


def start_of_day(d):
    return datetime(d.year, d.month, d.day, tzinfo=d.tzinfo)


def days_since(start, now):
    """照抄 ProfileMath.daysSince。"""
    from_d = start_of_day(start)
    to_d = start_of_day(now)
    delta = (to_d - from_d).days
    return max(0, delta)


def decimal(value):
    rounded = round(value * 10) / 10
    if rounded == round(rounded):
        return str(int(rounded))
    return "%.1f" % rounded


def weight_text(latest_kg, unit):
    """照抄 ProfileSummaryText.weightText。"""
    if latest_kg is None:
        return "—"
    converted = latest_kg if unit == "kg" else latest_kg * POUNDS_PER_KILOGRAM
    return f"{decimal(converted)} {unit}"


def count_text(count):
    return "—" if count <= 0 else str(count)


def duration_text(seconds):
    if seconds <= 0:
        return "—"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes} 分钟"
    hours = minutes // 60
    rem = minutes % 60
    return f"{hours} 小时" if rem == 0 else f"{hours} 小时 {rem} 分"


def trimmed_nickname(nickname):
    """照抄 UserProfile.trimmedNickname。"""
    if nickname is None:
        return None
    trimmed = nickname.strip()
    return None if trimmed == "" else trimmed


def default_rest(stored):
    """照抄 ProfileSettings.defaultRest 的读取兜底。"""
    return stored if (stored is not None and stored > 0) else 90


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 已使用天数]")
now = datetime(2026, 9, 19, 15, 30, tzinfo=TZ)
expect("今天开始 = 0 天", days_since(now, now), 0)
expect("昨天开始 = 1 天", days_since(now - timedelta(days=1), now), 1)
expect("60 天前开始 = 60 天", days_since(now - timedelta(days=60), now), 60)
# 跨自然日：昨天 23:00 到今天 01:00，按自然日是 1 天
expect("昨天深夜开始也是 1 天",
       days_since(datetime(2026, 9, 18, 23, 0, tzinfo=TZ), datetime(2026, 9, 19, 1, 0, tzinfo=TZ)), 1)
# 时钟回拨：未来日期开始，不能是负数
expect("未来开始回拨不为负", days_since(now + timedelta(days=3), now), 0)

print("[2 数据摘要 — / 0 分界]")
expect("没体重记录显示 —", weight_text(None, "kg"), "—")
expect("有体重 kg 显示数值", weight_text(74.2, "kg"), "74.2 kg")
expect("有体重 lb 换算", weight_text(74.2, "lb"), "163.6 lb")
expect("体重 0 也是 0（有记录）", weight_text(0.0, "kg"), "0 kg")
expect("累计训练 0 次显示 —", count_text(0), "—")
expect("累计训练 3 次显示 3", count_text(3), "3")
expect("累计时长 0 显示 —", duration_text(0), "—")
expect("累计时长 30 分钟", duration_text(1800), "30 分钟")
expect("累计时长 1 小时", duration_text(3600), "1 小时")
expect("累计时长 1 小时 30 分", duration_text(5400), "1 小时 30 分")

print("[3 昵称归一化]")
expect("nil 昵称 → nil", trimmed_nickname(None), None)
expect("全空白昵称 → nil", trimmed_nickname("   "), None)
expect("有昵称原样保留", trimmed_nickname("小健"), "小健")
expect("昵称两侧空白被修剪", trimmed_nickname("  小健  "), "小健")

print("[4 默认休息时间兜底]")
expect("正常值原样返回", default_rest(120), 120)
expect("存了 0 回落到 90", default_rest(0), 90)
expect("存了负数回落到 90", default_rest(-5), 90)
expect("未存（None）回落到 90", default_rest(None), 90)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
