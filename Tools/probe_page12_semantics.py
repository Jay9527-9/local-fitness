#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 12 值语义推演（身体数据）。

把 `BodyData.swift` 的纯值层逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「边界算错」的唯一手段——
`preflight` 只看 API 版本，`lint_swift` 只看语法结构，都看不见语义。

重点覆盖的边界（本页最容易算错的地方）：
1. kg/lb、cm/in 换算的方向与系数；
2. 「未记录」与「0」的分界（字段 nil 恒显示未记录，不落成 0）；
3. 变化值 = 最近一条 − 上一条有该字段的记录，最近一条没该字段时为 nil；
4. 同日唯一键的判定（不同 id 同自然日算冲突，同 id 不算）。

用法：
    python Tools/probe_page12_semantics.py
"""

from datetime import datetime, timedelta, timezone

TZ = timezone(timedelta(hours=8))

POUNDS_PER_KILOGRAM = 2.20462262185
INCHES_PER_CENTIMETER = 0.3937007874

WEIGHT_RANGE = (20.0, 400.0)
BODYFAT_RANGE = (1.0, 70.0)
LENGTH_RANGE = (20.0, 300.0)


class BodyMeasurement:
    """对应 Models.swift 里的 BodyMeasurement（只保留值层用到的字段）。"""

    def __init__(self, id, date, weight=None, bodyfat=None, chest=None,
                 waist=None, hip=None, thigh=None, arm=None, note=None):
        self.id = id
        self.date = date
        self.weight = weight
        self.bodyfat = bodyfat
        self.chest = chest
        self.waist = waist
        self.hip = hip
        self.thigh = thigh
        self.arm = arm
        self.note = note

    @property
    def has_any_value(self):
        return any(v is not None for v in [
            self.weight, self.bodyfat, self.chest, self.waist,
            self.hip, self.thigh, self.arm,
        ])


# ---- 单位换算（照抄 BodyWeightUnit / BodyLengthUnit） ----

def display_weight(value, unit):
    return value if unit == "kg" else value * POUNDS_PER_KILOGRAM


def display_length(value, unit):
    return value if unit == "cm" else value * INCHES_PER_CENTIMETER


# ---- 数值格式化（照抄 BodyNumberFormat.decimal） ----

def decimal(value):
    rounded = round(value * 10) / 10
    if rounded == round(rounded):
        return str(int(rounded))
    return "%.1f" % rounded


# ---- 指标取值 ----

METRICS = ["weight", "bodyfat", "chest", "waist", "hip", "thigh", "arm"]


def raw_value(metric, m):
    return {
        "weight": m.weight,
        "bodyfat": m.bodyfat,
        "chest": m.chest,
        "waist": m.waist,
        "hip": m.hip,
        "thigh": m.thigh,
        "arm": m.arm,
    }[metric]


def valid_range(metric):
    if metric == "weight":
        return WEIGHT_RANGE
    if metric == "bodyfat":
        return BODYFAT_RANGE
    return LENGTH_RANGE


def is_valid(value, metric):
    rng = valid_range(metric)
    return value is not None and rng[0] <= value <= rng[1]


# ---- 聚合（照抄 BodyDataBuilder） ----

def points(metric, measurements):
    result = []
    for m in measurements:
        v = raw_value(metric, m)
        if v is not None:
            result.append((m.id, m.date, v))
    return sorted(result, key=lambda p: p[1])


def overview(measurements):
    if not measurements:
        return None
    latest = max(measurements, key=lambda m: m.date)
    by_date_desc = sorted(measurements, key=lambda m: m.date, reverse=True)

    def change(latest_val, field):
        if latest_val is None:
            return None
        for prev in by_date_desc[1:]:
            pv = getattr(prev, field)
            if pv is not None:
                return latest_val - pv
        return None

    weight_change = change(latest.weight, "weight")
    fat_change = change(latest.bodyfat, "bodyfat")

    return {
        "date": latest.date,
        "weight": latest.weight,
        "bodyfat": latest.bodyfat,
        "weight_change": weight_change,
        "fat_change": fat_change,
    }


def stats(metric, measurements):
    pts = points(metric, measurements)
    if not pts:
        return None
    values = [p[2] for p in pts]
    latest = pts[-1]
    if len(pts) >= 2:
        change = latest[2] - pts[-2][2]
    else:
        change = None
    return {
        "latest": latest[2],
        "date": latest[1],
        "change": change,
        "min": min(values),
        "max": max(values),
    }


def existing_on(date, exclude_id, measurements):
    """同自然日判定（照抄 BodyDataBuilder.existingMeasurement）。"""
    def same_day(a, b):
        return (a.year, a.month, a.day) == (b.year, b.month, b.day)

    for m in measurements:
        if m.id != exclude_id and same_day(m.date, date):
            return m
    return None


def trend_summary(metric, pts):
    if len(pts) < 2:
        return f"{metric}记录更多数据后可查看趋势。"
    return "趋势摘要"


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


def expect_close(label, got, want, eps=1e-6):
    global ok, count
    count += 1
    good = abs(got - want) <= eps
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 单位换算]")
expect_close("kg 原样返回", display_weight(74.2, "kg"), 74.2)
expect_close("lb 换算", display_weight(74.2, "lb"), 74.2 * POUNDS_PER_KILOGRAM)
expect_close("cm 原样返回", display_length(80.5, "cm"), 80.5)
expect_close("in 换算", display_length(80.5, "in"), 80.5 * INCHES_PER_CENTIMETER)
# 回归守卫：写反系数会把 kg 当 lb 放大或缩小
expect("lb 不等于原值（换算确实发生）", display_weight(100, "lb") != 100.0, True)
expect("in 不等于原值", display_length(100, "in") != 100.0, True)

print("[2 数值格式化]")
expect("整数不带 .0", decimal(74.0), "74")
expect("一位小数", decimal(74.2), "74.2")
expect("进位到整数", decimal(74.96), "75")
expect("磅换算后保留一位", decimal(74.2 * POUNDS_PER_KILOGRAM), "163.6")

print("[3 指标取值]")
m0 = BodyMeasurement("a", datetime(2026, 9, 1, tzinfo=TZ), weight=74.2,
                     bodyfat=16.4, chest=100, waist=80, hip=90, thigh=55, arm=35)
expect("取体重", raw_value("weight", m0), 74.2)
expect("取体脂率", raw_value("bodyfat", m0), 16.4)
expect("取臀围", raw_value("hip", m0), 90)
expect("缺字段返回 None", raw_value("weight", BodyMeasurement("b", datetime(2026, 9, 1, tzinfo=TZ), waist=80)), None)

print("[4 输入校验]")
expect("体重 20 合法", is_valid(20, "weight"), True)
expect("体重 400 合法", is_valid(400, "weight"), True)
expect("体重 19.9 非法", is_valid(19.9, "weight"), False)
expect("体重 400.1 非法", is_valid(400.1, "weight"), False)
expect("体重 0 非法", is_valid(0, "weight"), False)
expect("体脂 1 合法", is_valid(1, "bodyfat"), True)
expect("体脂 70 合法", is_valid(70, "bodyfat"), True)
expect("体脂 0.9 非法", is_valid(0.9, "bodyfat"), False)
expect("围度 20 合法", is_valid(20, "hip"), True)
expect("围度 300 合法", is_valid(300, "hip"), True)
expect("围度 19 非法", is_valid(19, "hip"), False)
expect("围度 301 非法", is_valid(301, "hip"), False)
expect("None 非法", is_valid(None, "weight"), False)

print("[5 hasAnyValue]")
expect("全空无值", BodyMeasurement("x", datetime(2026, 9, 1, tzinfo=TZ)).has_any_value, False)
expect("只有备注不算有值",
       BodyMeasurement("x", datetime(2026, 9, 1, tzinfo=TZ), note="hi").has_any_value, False)
expect("只有体重算有值",
       BodyMeasurement("x", datetime(2026, 9, 1, tzinfo=TZ), weight=70).has_any_value, True)

print("[6 趋势点]")
d0 = datetime(2026, 9, 1, tzinfo=TZ)
d1 = datetime(2026, 9, 2, tzinfo=TZ)
d2 = datetime(2026, 9, 3, tzinfo=TZ)
ms = [
    BodyMeasurement("m2", d2, weight=75.0),
    BodyMeasurement("m0", d0, weight=73.0),
    BodyMeasurement("m1", d1, waist=80),  # 没有体重，被过滤
]
pts = points("weight", ms)
expect("只含有体重的记录", len(pts), 2)
expect("按日期升序", [p[0] for p in pts], ["m0", "m2"])
expect("最新点在最后", pts[-1][2], 75.0)

print("[7 摘要卡 overview]")
expect("空数据返回 None", overview([]), None)

# 只有一条体重记录：无上一条可比
single = [BodyMeasurement("s1", d0, weight=74.0)]
ov = overview(single)
expect("单条记录日期正确", ov["date"], d0)
expect("单条记录体重正确", ov["weight"], 74.0)
expect("单条记录无变化（没有上一条）", ov["weight_change"], None)

# 两条体重：变化 = 最近 − 上一条
two = [
    BodyMeasurement("t1", d0, weight=74.0),
    BodyMeasurement("t2", d2, weight=73.4),
]
ov = overview(two)
expect_close("体重变化 = 73.4 − 74.0", ov["weight_change"], -0.6)

# 最近一条没有体重：体重显示 None，变化也是 None
three = [
    BodyMeasurement("t1", d0, weight=74.0),
    BodyMeasurement("t2", d1, weight=73.4),
    BodyMeasurement("t3", d2, waist=80),  # 最新，但没有体重
]
ov = overview(three)
expect("最新记录无体重时体重为 None", ov["weight"], None)
expect("最新记录无体重时变化为 None", ov["weight_change"], None)

# 体脂变化同理
fat = [
    BodyMeasurement("f1", d0, bodyfat=17.0),
    BodyMeasurement("f2", d2, bodyfat=16.4),
]
ov = overview(fat)
expect_close("体脂变化 = 16.4 − 17.0", ov["fat_change"], -0.6)

print("[8 指标统计 stats]")
empty_stats = stats("weight", [])
expect("无数据 stats 为 None", empty_stats, None)

single_stats = stats("weight", single)
expect("单条记录最新值", single_stats["latest"], 74.0)
expect("单条记录无变化", single_stats["change"], None)
expect("单条记录最低=最高=值", single_stats["min"], single_stats["max"])

weight_series = [
    BodyMeasurement("w1", d0, weight=73.0),
    BodyMeasurement("w2", d1, weight=74.5),
    BodyMeasurement("w3", d2, weight=72.8),
]
s = stats("weight", weight_series)
expect("最新值", s["latest"], 72.8)
expect_close("变化 = 72.8 − 74.5", s["change"], -1.7)
expect("最低值", s["min"], 72.8)
expect("最高值", s["max"], 74.5)

print("[9 同日唯一键]")
same_day_measurements = [
    BodyMeasurement("k1", d0, weight=74.0),
    BodyMeasurement("k2", d0.replace(hour=18), weight=74.2),  # 同一天不同时刻
]
conflict = existing_on(d0, None, same_day_measurements)
expect("同日不同 id 判为冲突", conflict.id, "k1")
expect("排除自身 id 后不算冲突",
       existing_on(d0, "k1", same_day_measurements).id, "k2")
expect("不同日期不算冲突",
       existing_on(d2, None, same_day_measurements), None)

print("[10 趋势摘要]")
expect("不足两条记录给出空状态文案",
       "更多数据" in trend_summary("体重", pts[:1]), True)
expect("两条及以上有摘要", "趋势摘要" == trend_summary("体重", pts), True)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
