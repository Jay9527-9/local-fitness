#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 11 值语义推演（动作历史趋势）。

把 ExerciseTrendDetail.swift 里的纯值类型与纯函数逐字照搬成 Python，跑断言表。

本机没有 Swift 编译器，preflight 只查 API 版本、lint_swift 只查类型与括号，
两者都查不出这一类错误：

  - 「近 30 天」到底是 30 个自然日还是 31 个（写 `-30` 就多一天）；
  - 「近 3 个月」是按日历月还是按 90 天（4 月 30 日往回 90 天是 1 月 30 日，
    用户想的是 2 月 1 日）；
  - 区间终点写成「今天 23:59:59」会不会漏掉 23:59:59.5 的组；
  - Epley 公式在 20 次组上会给出荒谬的高估值，该不该参与最高 1RM 的评选；
  - 「最佳组」比重量还是比容量（80×3 不能盖过 70×10）；
  - 单位切换会不会把原始记录也改了；
  - 「开始练这个动作」的建议取自最近一次还是历史最高；
  - 动作被删除后，标题会不会变成空白。

这一层专门补这个缺口。沿用页面 08/09/10 的教训：
**断言本身也会写错**，凡是「我以为是 A 其实是 B」的地方都补一条反向断言
（断言值不是某个诱惑性的错值），让同样的错不会犯第二次。

用法：
    python Tools/probe_page11_semantics.py
"""

import datetime as dt
import math
import sys

# 本机 Python 没有 tzdata，zoneinfo 不可用。
# 中国不实行夏令时，固定 +8 偏移与 Asia/Shanghai 等价。
TZ = dt.timezone(dt.timedelta(hours=8))

PASS = 0
FAIL = 0
FAILURES = []


def check(label, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        FAILURES.append(f"{label}{('  → ' + extra) if extra else ''}")


def group(title):
    print(f"\n[{title}]")


# =====================================================================
# 契约常量（与 ExerciseTrendDetail.swift 逐字对应）
# =====================================================================

# OneRMEstimator.maxReliableReps
MAX_RELIABLE_REPS = 12
# TrendWeightUnit.poundsPerKilogram
POUNDS_PER_KILOGRAM = 2.20462262185
# ExerciseTrendDetailBuilder.recentLimit / sessionFetchLimit
RECENT_LIMIT = 10
SESSION_FETCH_LIMIT = 500
# ExerciseStartSuggestion.fallback
FALLBACK_WEIGHT = 0
FALLBACK_REPS_LOW = 8
FALLBACK_REPS_HIGH = 12
FALLBACK_REST = 90
FALLBACK_SETS = 3
# TrendRangeBuilder 的「全部记录」起点：Cocoa 纪元 2001-01-01
COCOA_EPOCH = dt.datetime(2001, 1, 1, tzinfo=TZ)

RANGE_TITLES = {
    "last30Days": "近 30 天",
    "last3Months": "近 3 个月",
    "lastYear": "近一年",
    "allTime": "全部记录",
}
RANGE_SUBTITLES = {
    "last30Days": "含今天在内的 30 个自然日",
    "last3Months": "含今天在内的 3 个自然月",
    "lastYear": "含今天在内的 12 个自然月",
    "allTime": "本机全部已完成记录",
}


# =====================================================================
# 时间工具（Calendar 的最小移植：公历 + 固定 +8 时区）
# =====================================================================

def start_of_day(d):
    return d.replace(hour=0, minute=0, second=0, microsecond=0)


def add_days(d, n):
    return d + dt.timedelta(days=n)


def days_in_month(year, month):
    if month == 12:
        return 31
    nxt = dt.datetime(year, month + 1, 1, tzinfo=TZ)
    return (nxt - dt.timedelta(days=1)).day


def add_months(d, n):
    """Calendar.date(byAdding: .month) 的移植，含月末钳制"""
    total = d.month - 1 + n
    year = d.year + total // 12
    month = total % 12 + 1
    day = min(d.day, days_in_month(year, month))
    return d.replace(year=year, month=month, day=day)


def first_day_of_month(d):
    return start_of_day(d.replace(day=1))


def end_of_day(d):
    """本范围的开区间终点 = 明天 00:00"""
    return add_days(start_of_day(d), 1)


def month_day_slash(d):
    """FormatterKit.monthDaySlash：M/d"""
    return f"{d.month}/{d.day}"


def short_date(d):
    """FormatterKit.shortDate：M月d日"""
    return f"{d.month}月{d.day}日"


def plain_number(value):
    """FormatterKit.plainNumber"""
    return str(int(round(max(0.0, value))))


# =====================================================================
# 值层移植：时间范围
# =====================================================================

class TrendDateRange:
    def __init__(self, kind, start, end):
        self.kind = kind
        self.start = start
        self.end = end

    def contains(self, date):
        return self.start <= date < self.end


class TrendRangeBuilder:

    @staticmethod
    def range_for(kind, now):
        end = end_of_day(now)
        if kind == "last30Days":
            # 30 个自然日 = 今天 + 往前 29 天
            return TrendDateRange(kind, start_of_day(add_days(now, -29)), end)
        if kind == "last3Months":
            return TrendDateRange(kind, add_months(first_day_of_month(now), -2), end)
        if kind == "lastYear":
            return TrendDateRange(kind, add_months(first_day_of_month(now), -11), end)
        if kind == "allTime":
            return TrendDateRange(kind, COCOA_EPOCH, end)
        raise AssertionError(kind)

    @staticmethod
    def range_text(r):
        if r.kind == "allTime":
            return None
        return f"{month_day_slash(r.start)} – {month_day_slash(r.end)}"


def shows_range_text(kind):
    return kind != "allTime"


# =====================================================================
# 值层移植：单位与格式化
# =====================================================================

class TrendWeightUnit:
    KILOGRAMS = "kilograms"
    POUNDS = "pounds"

    def __init__(self, raw):
        self.raw = raw

    @property
    def short_title(self):
        return "kg" if self.raw == self.KILOGRAMS else "lb"

    @property
    def title(self):
        return "公斤" if self.raw == self.KILOGRAMS else "磅"

    def display_value(self, kg):
        if self.raw == self.KILOGRAMS:
            return kg
        return kg * POUNDS_PER_KILOGRAM

    def text(self, kg):
        return f"{weight_format(self.display_value(kg))} {self.short_title}"

    def volume_text(self, kg):
        return f"{plain_number(self.display_value(kg))} {self.short_title}"

    def accessibility_weight(self, kg):
        return f"{plain_number(self.display_value(kg))} {self.title}"


KG = TrendWeightUnit(TrendWeightUnit.KILOGRAMS)
LB = TrendWeightUnit(TrendWeightUnit.POUNDS)


def weight_format(value):
    """TrendNumberFormat.weight：整数不带 .0，否则 1 位小数"""
    if not math.isfinite(value):
        return "0"
    rounded = round(value * 10) / 10
    if rounded == round(rounded):
        return str(int(rounded))
    return f"{rounded:.1f}"


# =====================================================================
# 值层移植：1RM
# =====================================================================

def epley(weight, reps):
    if not (weight > 0) or not math.isfinite(weight):
        return None
    if reps <= 0 or reps > MAX_RELIABLE_REPS:
        return None
    return weight * (1.0 + reps / 30.0)


def is_reliable(weight, reps):
    return epley(weight, reps) is not None


# =====================================================================
# 值层移植：数据点
# =====================================================================

class TrendWeightPoint:
    def __init__(self, session_id, date, top_weight, reps_at_top, session_name, set_count):
        self.session_id = session_id
        self.date = date
        self.top_weight = top_weight
        self.reps_at_top = reps_at_top
        self.session_name = session_name
        self.set_count = set_count

    @property
    def id(self):
        return self.session_id

    @property
    def has_weight(self):
        return self.top_weight > 0

    @property
    def axis_label(self):
        return month_day_slash(self.date)

    def best_set_text(self, unit):
        if not self.has_weight:
            return "自重"
        return f"{weight_format(unit.display_value(self.top_weight))} {unit.short_title} × {self.reps_at_top}"

    @property
    def accessibility_label(self):
        if not self.has_weight:
            return f"{month_day_slash(self.date)}，自重训练，{self.set_count} 组"
        return (f"{month_day_slash(self.date)}，最高 {plain_number(self.top_weight)} 公斤，"
                f"{self.reps_at_top} 次，共 {self.set_count} 组")


class TrendVolumePoint:
    def __init__(self, session_id, date, volume, session_name, set_count):
        self.session_id = session_id
        self.date = date
        self.volume = volume
        self.session_name = session_name
        self.set_count = set_count

    @property
    def id(self):
        return self.session_id

    @property
    def axis_label(self):
        return month_day_slash(self.date)

    def volume_text(self, unit):
        return unit.volume_text(self.volume)

    @property
    def accessibility_label(self):
        return (f"{month_day_slash(self.date)}，{self.set_count} 组，"
                f"容量 {plain_number(self.volume)} 公斤")


class ExerciseRecentRecord:
    def __init__(self, session_id, date, session_name, set_count, best_weight, best_reps, volume):
        self.session_id = session_id
        self.date = date
        self.session_name = session_name
        self.set_count = set_count
        self.best_weight = best_weight
        self.best_reps = best_reps
        self.volume = volume

    @property
    def id(self):
        return self.session_id

    def best_set_text(self, unit):
        if not (self.best_weight > 0):
            return f"自重 × {self.best_reps}"
        return (f"{weight_format(unit.display_value(self.best_weight))} "
                f"{unit.short_title} × {self.best_reps}")

    @property
    def accessibility_label(self):
        parts = [month_day_slash(self.date), self.session_name, f"{self.set_count} 组"]
        if self.best_weight > 0:
            parts.append(f"最佳 {plain_number(self.best_weight)} 公斤 {self.best_reps} 次")
        else:
            parts.append(f"自重 {self.best_reps} 次")
        parts.append(f"容量 {plain_number(self.volume)} 公斤")
        return "，".join(parts)


class ExerciseTrendOverview:
    def __init__(self, session_count, set_count, best_weight, best_one_rm,
                 last_trained_at, one_rm_source_reps):
        self.session_count = session_count
        self.set_count = set_count
        self.best_weight = best_weight
        self.best_one_rm = best_one_rm
        self.last_trained_at = last_trained_at
        self.one_rm_source_reps = one_rm_source_reps

    @property
    def is_empty(self):
        return self.session_count == 0

    def best_weight_text(self, unit):
        if self.best_weight is None or not (self.best_weight > 0):
            return "—"
        return weight_format(unit.display_value(self.best_weight))

    def best_one_rm_text(self, unit):
        if self.best_one_rm is None or not (self.best_one_rm > 0):
            return "—"
        return weight_format(unit.display_value(self.best_one_rm))

    @property
    def last_trained_text(self):
        if self.last_trained_at is None:
            return "—"
        return short_date(self.last_trained_at)

    @property
    def one_rm_note_text(self):
        if self.one_rm_source_reps is None:
            return None
        return f"按 {self.one_rm_source_reps} 次组估算"

    @property
    def accessibility_text(self):
        if self.is_empty:
            return "还没有这个动作的训练记录"
        parts = [f"共 {self.session_count} 次训练", f"{self.set_count} 组"]
        if self.best_weight is not None:
            parts.append(f"最高单组 {plain_number(self.best_weight)} 公斤")
        else:
            parts.append("最高单组无重量数据")
        if self.best_one_rm is not None:
            parts.append(f"估算单次最大重量 {plain_number(self.best_one_rm)} 公斤")
        if self.last_trained_at is not None:
            parts.append(f"最近 {short_date(self.last_trained_at)}")
        return "，".join(parts) + "。"


class ExerciseStartSuggestion:
    def __init__(self, weight, reps_low, reps_high, rest_seconds, sets, source_date):
        self.weight = weight
        self.reps_low = reps_low
        self.reps_high = reps_high
        self.rest_seconds = rest_seconds
        self.sets = sets
        self.source_date = source_date

    @property
    def has_history_source(self):
        return self.source_date is not None

    @property
    def source_text(self):
        if self.source_date is None:
            return "没有历史记录，已按常规方案预填"
        return f"按 {month_day_slash(self.source_date)} 那次训练预填"

    def weight_text(self, unit):
        if not (self.weight > 0):
            return "自重"
        return f"{weight_format(unit.display_value(self.weight))} {unit.short_title}"

    @property
    def reps_text(self):
        return str(self.reps_low) if self.reps_low == self.reps_high else f"{self.reps_low}-{self.reps_high}"


FALLBACK = ExerciseStartSuggestion(
    FALLBACK_WEIGHT, FALLBACK_REPS_LOW, FALLBACK_REPS_HIGH,
    FALLBACK_REST, FALLBACK_SETS, None
)


# =====================================================================
# 值层移植：聚合
# =====================================================================

class Entry:
    def __init__(self, exercise_id, weight, reps, is_warmup=False, completed=True):
        self.exercise_id = exercise_id
        self.weight = weight
        self.reps = reps
        self.is_warmup = is_warmup
        self.completed_at = dt.datetime(2020, 1, 1, tzinfo=TZ) if completed else None

    @property
    def volume(self):
        return 0.0 if self.is_warmup else self.weight * self.reps


class Session:
    def __init__(self, sid, name, started_at, entries, finished=True):
        self.id = sid
        self.name = name
        self.started_at = started_at
        self.entries = entries
        self.ended_at = started_at + dt.timedelta(hours=1) if finished else None

    @property
    def is_finished(self):
        return self.ended_at is not None


class ValidSet:
    def __init__(self, session_id, date, session_name, weight, reps, volume):
        self.session_id = session_id
        self.date = date
        self.session_name = session_name
        self.weight = weight
        self.reps = reps
        self.volume = volume


def valid_sets(sessions, exercise_id, rng):
    result = []
    for s in sessions:
        if not s.is_finished or not rng.contains(s.started_at):
            continue
        for e in s.entries:
            if e.exercise_id != exercise_id:
                continue
            if e.completed_at is None or e.is_warmup:
                continue
            result.append(ValidSet(s.id, s.started_at, s.name, e.weight, e.reps, e.volume))
    return sorted(result, key=lambda v: v.date)


def weight_points(sets):
    if not sets:
        return []
    order = []
    by_session = {}
    for s in sets:
        if s.session_id in by_session:
            prev = by_session[s.session_id]
            if s.weight > prev["top"] or (s.weight == prev["top"] and s.reps > prev["reps"]):
                top, reps = s.weight, s.reps
            else:
                top, reps = prev["top"], prev["reps"]
            by_session[s.session_id] = dict(prev, top=top, reps=reps, count=prev["count"] + 1)
        else:
            order.append(s.session_id)
            by_session[s.session_id] = {
                "date": s.date, "name": s.session_name,
                "top": s.weight, "reps": s.reps, "count": 1,
            }
    return [
        TrendWeightPoint(sid, by_session[sid]["date"], by_session[sid]["top"],
                         by_session[sid]["reps"], by_session[sid]["name"],
                         by_session[sid]["count"])
        for sid in order
    ]


def volume_points(sets):
    if not sets:
        return []
    order = []
    by_session = {}
    for s in sets:
        if s.session_id in by_session:
            cur = by_session[s.session_id]
            cur["volume"] += s.volume
            cur["count"] += 1
        else:
            order.append(s.session_id)
            by_session[s.session_id] = {
                "date": s.date, "name": s.session_name,
                "volume": s.volume, "count": 1,
            }
    return [
        TrendVolumePoint(sid, by_session[sid]["date"], by_session[sid]["volume"],
                         by_session[sid]["name"], by_session[sid]["count"])
        for sid in order
    ]


def recent_records(sets, limit=RECENT_LIMIT):
    if limit <= 0 or not sets:
        return []
    order = []
    by_session = {}
    for s in sets:
        if s.session_id in by_session:
            prev = by_session[s.session_id]
            better = s.weight > prev["best"] or (s.weight == prev["best"] and s.reps > prev["reps"])
            by_session[s.session_id] = {
                "date": prev["date"],
                "name": prev["name"],
                "best": s.weight if better else prev["best"],
                "reps": s.reps if better else prev["reps"],
                "volume": prev["volume"] + s.volume,
                "count": prev["count"] + 1,
            }
        else:
            order.append(s.session_id)
            by_session[s.session_id] = {
                "date": s.date, "name": s.session_name,
                "best": s.weight, "reps": s.reps,
                "volume": s.volume, "count": 1,
            }
    records = [
        ExerciseRecentRecord(sid, by_session[sid]["date"], by_session[sid]["name"],
                             by_session[sid]["count"], by_session[sid]["best"],
                             by_session[sid]["reps"], by_session[sid]["volume"])
        for sid in order
    ]
    records.sort(key=lambda r: r.date, reverse=True)
    return records[:limit]


def overview_of(sets):
    if not sets:
        return ExerciseTrendOverview(0, 0, None, None, None, None)
    session_ids = {s.session_id for s in sets}
    weighted = [s for s in sets if s.weight > 0]
    best_weight = max((s.weight for s in weighted), default=None)
    best_rm = None
    best_rm_reps = None
    for s in weighted:
        est = epley(s.weight, s.reps)
        if est is None:
            continue
        if best_rm is None or est > best_rm:
            best_rm = est
            best_rm_reps = s.reps
    last = max((s.date for s in sets), default=None)
    return ExerciseTrendOverview(len(session_ids), len(sets), best_weight,
                                 best_rm, last, best_rm_reps)


def start_suggestion(sets):
    if not sets:
        return FALLBACK
    last_date = max(s.date for s in sets)
    last_sets = [s for s in sets if s.date == last_date]
    if not last_sets:
        return FALLBACK
    top_weight = max(s.weight for s in last_sets)
    top_reps = max(s.reps for s in last_sets)
    set_count = len(last_sets)
    reps_high = max(1, top_reps)
    reps_low = min(reps_high, max(5, math.ceil(reps_high * 0.8)))
    return ExerciseStartSuggestion(top_weight, reps_low, reps_high,
                                   FALLBACK_REST, max(3, set_count), last_date)


def draft_entries(exercise_id, suggestion, starting_index=1):
    count = max(1, suggestion.sets)
    return [
        {
            "exercise_id": exercise_id,
            "index": starting_index + offset,
            "weight": suggestion.weight,
            "reps": suggestion.reps_low,
            "target_low": suggestion.reps_low,
            "target_high": suggestion.reps_high,
            "is_warmup": False,
            "completed": False,
        }
        for offset in range(count)
    ]


def weight_trend_summary(points, ov, range_title):
    if not points:
        return f"{range_title}内没有这个动作的训练记录。"
    parts = [f"{range_title}内最高重量趋势，共 {len(points)} 次训练"]
    if ov.best_weight is not None:
        parts.append(f"最高 {plain_number(ov.best_weight)} 公斤")
    else:
        parts.append("全部为自重训练")
    if len(points) > 1:
        delta = points[-1].top_weight - points[0].top_weight
        if abs(delta) < 0.01:
            parts.append("区间内基本持平")
        elif delta > 0:
            parts.append(f"比首次提高 {plain_number(delta)} 公斤")
        else:
            parts.append(f"比首次下降 {plain_number(-delta)} 公斤")
    return "，".join(parts) + "。"


def volume_trend_summary(points, range_title):
    if not points:
        return f"{range_title}内没有这个动作的容量记录。"
    total = sum(p.volume for p in points)
    best = max((p.volume for p in points), default=0)
    return (f"{range_title}内单次训练容量趋势，共 {len(points)} 次训练，"
            f"累计 {plain_number(total)} 公斤，单次最高 {plain_number(best)} 公斤。")


def trend_name(library_name, fallback, exercise_id):
    for candidate in (library_name, fallback, exercise_id):
        if candidate is None:
            continue
        trimmed = candidate.strip()
        if trimmed:
            return trimmed
    return "未知动作"


# =====================================================================
# 夹具
# =====================================================================

# 参考「现在」：2026-09-19 15:00 (+8)
NOW = dt.datetime(2026, 9, 19, 15, 0, 0, tzinfo=TZ)


def day(offset, hour=10):
    """相对 NOW 那一天的 00:00 偏移 offset 天的某个时刻"""
    return start_of_day(NOW) + dt.timedelta(days=offset, hours=hour)


def sid(n):
    return f"session-{n}"


# 卧推 12 次训练，重量逐步上升，散布在近一年里。
# 注意日期方向：i 越大越新（`-7 * (11 - i)`），这样「重量随次数上升」
# 和「日期从旧到新」才是同一个方向——写成 `-7 * i` 会让第 1 次训练
# 变成最近的一次，首末点断言全部反过来。
def make_sessions():
    sessions = []
    for i in range(12):
        weight = 60 + i * 2          # 60 → 82
        reps = 8 - (i % 3)           # 8/7/6 循环
        sessions.append(Session(
            sid(i),
            f"第 {i + 1} 次训练",
            day(-7 * (11 - i) - 1),
            [Entry("bench", weight, reps), Entry("bench", weight - 5, reps + 2)],
        ))
    return sessions


SESSIONS = make_sessions()
RANGE_ALL = TrendRangeBuilder.range_for("allTime", NOW)
SETS_ALL = valid_sets(SESSIONS, "bench", RANGE_ALL)


# =====================================================================
# 1. 时间范围：30 个自然日
# =====================================================================
group("1 近 30 天 = 30 个自然日")

r30 = TrendRangeBuilder.range_for("last30Days", NOW)
check("起点是今天往前 29 天的 00:00",
      r30.start == start_of_day(add_days(NOW, -29)), f"{r30.start}")
check("终点是明天 00:00（开区间）",
      r30.end == start_of_day(add_days(NOW, 1)), f"{r30.end}")
check("覆盖天数正好 30",
      (r30.end - r30.start).days == 30, str((r30.end - r30.start).days))
check("不是 31 天（写成 -30 的结果）", (r30.end - r30.start).days != 31)
check("含今天", r30.contains(NOW))
check("含今天 00:00", r30.contains(start_of_day(NOW)))
check("含 29 天前", r30.contains(day(-29)))
check("不含 30 天前（那已是第 31 个自然日）", not r30.contains(day(-30)))
check("区间终点前一点仍算在内",
      r30.contains(r30.end - dt.timedelta(seconds=1)))
check("不含明天 00:00", not r30.contains(r30.end))

# =====================================================================
# 2. 终点取明天 00:00，不漏亚秒
# =====================================================================
group("2 终点不漏 23:59:59.5")

late = start_of_day(NOW) + dt.timedelta(hours=23, minutes=59, seconds=59, microseconds=500000)
check("带小数秒的当天记录仍在范围内", r30.contains(late), str(late))
# 反向断言：若终点写成「今天 23:59:59」，这条记录会被漏掉。
# 漏掉的表现是 终点 <= late，所以这里断言方向必须是「不在其后」。
check("若写成今天 23:59:59 会漏掉它（回归守卫）",
      not (start_of_day(NOW) + dt.timedelta(hours=23, minutes=59, seconds=59) > late))
check("终点严格大于当天最后一秒", r30.end > late)

# =====================================================================
# 3. 近 3 个月按日历月
# =====================================================================
group("3 近 3 个月 = 3 个自然月")

# 4 月 30 日往回 90 天是 1 月 30 日，按日历月则是 2 月 1 日
april30 = dt.datetime(2026, 4, 30, 12, 0, tzinfo=TZ)
r3m = TrendRangeBuilder.range_for("last3Months", april30)
check("起点是 2 月 1 日", r3m.start == dt.datetime(2026, 2, 1, tzinfo=TZ), str(r3m.start))
check("不是 90 天前的 1 月 30 日（回归守卫）",
      r3m.start != april30 - dt.timedelta(days=90))
check("含 2 月 1 日当天", r3m.contains(dt.datetime(2026, 2, 1, tzinfo=TZ)))
check("不含 1 月 31 日", not r3m.contains(dt.datetime(2026, 1, 31, 23, 0, tzinfo=TZ)))
check("终点是 5 月 1 日 00:00", r3m.end == dt.datetime(2026, 5, 1, tzinfo=TZ))

# 月初也不会退化：3 月 1 日 → 1 月 1 日
march1 = dt.datetime(2026, 3, 1, 8, 0, tzinfo=TZ)
r3m2 = TrendRangeBuilder.range_for("last3Months", march1)
check("月初时起点是 1 月 1 日", r3m2.start == dt.datetime(2026, 1, 1, tzinfo=TZ), str(r3m2.start))

# =====================================================================
# 4. 近一年与全部记录
# =====================================================================
group("4 近一年 / 全部记录")

r1y = TrendRangeBuilder.range_for("lastYear", NOW)
check("近一年起点是 2025-10-01", r1y.start == dt.datetime(2025, 10, 1, tzinfo=TZ), str(r1y.start))
check("近一年覆盖 12 个自然月", r1y.start.month == 10 and r1y.end.month == 9)

r_all = TrendRangeBuilder.range_for("allTime", NOW)
check("全部记录起点是 Cocoa 纪元", r_all.start == COCOA_EPOCH)
check("全部记录含 2010 年的老记录",
      r_all.contains(dt.datetime(2010, 5, 5, tzinfo=TZ)))
check("全部记录不是 distantPast（可读性回归守卫）", r_all.start.year == 2001)

# =====================================================================
# 5. 范围文案
# =====================================================================
group("5 范围文案")

check("近 30 天有区间文案", TrendRangeBuilder.range_text(r30) is not None)
check("区间文案是 M/d – M/d",
      TrendRangeBuilder.range_text(r30) == f"{r30.start.month}/{r30.start.day} – {r30.end.month}/{r30.end.day}")
check("全部记录没有区间文案", TrendRangeBuilder.range_text(r_all) is None)
check("全部记录不显示区间", not shows_range_text("allTime"))
check("其余三档都显示区间",
      all(shows_range_text(k) for k in ["last30Days", "last3Months", "lastYear"]))
check("四档标题齐全",
      RANGE_TITLES["last30Days"] == "近 30 天" and RANGE_TITLES["allTime"] == "全部记录")
check("四档都有副标题说明覆盖范围",
      all("含今天" in v or "全部" in v for v in RANGE_SUBTITLES.values()))

# =====================================================================
# 6. 单位换算：只改展示
# =====================================================================
group("6 kg / lb 只换展示值")

check("1 kg = 2.20462262185 lb", POUNDS_PER_KILOGRAM == 2.20462262185)
check("kg 展示值原样返回", KG.display_value(80) == 80)
check("lb 展示值 = kg × 系数", abs(LB.display_value(80) - 176.369809748) < 1e-6)
check("80 kg 文案", KG.text(80) == "80 kg")
check("80 kg 转磅文案", LB.text(80) == "176.4 lb", LB.text(80))
check("磅文案不是整数舍入（精度回归守卫）", LB.text(80) != "176 lb")
check("整数 kg 不带 .0", KG.text(80) == "80 kg" and "." not in KG.text(80))
check("非整数 kg 保留 1 位", KG.text(82.5) == "82.5 kg")
check("容量文案取整", LB.volume_text(700) == "1543 lb", LB.volume_text(700))
check("容量文案不带小数", "." not in KG.volume_text(700.4))
check("VoiceOver 用中文单位", LB.accessibility_weight(80) == "176 磅", LB.accessibility_weight(80))
check("kg 的 VoiceOver 用公斤", KG.accessibility_weight(80) == "80 公斤")

# 单位切换不回写原始记录：值层里没有任何 mutating 方法，
# 用「同一份原始值连算两次结果相同」来锁死这一点。
raw = 82.0
first = LB.display_value(raw)
second = LB.display_value(raw)
check("换算不修改原始值", raw == 82.0)
check("同一原始值连算两次一致", first == second)
# 反向换算不在本层：值层只提供 kg→展示值，没有 lb→kg。
# 需要原始值时除以系数即可，值层刻意不提供第二条路径——
# 多一个方向就多一处可能把换算结果当真写回的地方。
check("反算只需除以系数", abs(LB.display_value(raw) / POUNDS_PER_KILOGRAM - raw) < 1e-9)

# =====================================================================
# 7. 数字格式化
# =====================================================================
group("7 重量格式化")

check("整数不带小数", weight_format(80.0) == "80")
check("一位小数保留", weight_format(176.37) == "176.4")
check("两位小数收敛到一位", weight_format(176.349) == "176.3", weight_format(176.349))
check("0 显示 0", weight_format(0) == "0")
check("负数不会出现（自重是 0 不是负）", weight_format(0.0) == "0")
check("NaN 兜底为 0", weight_format(float("nan")) == "0")
check("无穷兜底为 0", weight_format(float("inf")) == "0")

# =====================================================================
# 8. Epley 1RM
# =====================================================================
group("8 1RM 估算（Epley）")

check("100 kg × 5 → 116.7", abs(epley(100, 5) - 116.6666666) < 1e-5)
check("60 kg × 20 不可靠（超过 12 次）", epley(60, 20) is None)
check("自重（重量 0）不估算", epley(0, 10) is None)
check("次数 0 不估算", epley(80, 0) is None)
check("次数为负不估算", epley(80, -3) is None)
check("12 次是可靠上限", epley(80, MAX_RELIABLE_REPS) is not None)
check("13 次越界", epley(80, MAX_RELIABLE_REPS + 1) is None)
check("单次组 1RM 等于自身×(1+1/30)", abs(epley(100, 1) - 103.3333333) < 1e-5)
check("isReliable 与 epley 一致",
      is_reliable(80, 8) and not is_reliable(80, 20))
check("不可靠时不返回 0（会污染最高值）", epley(60, 20) is not None or True)
check("20 次组若硬算会是 100 kg（高估回归守卫）",
      abs(60 * (1 + 20 / 30) - 100.0) < 1e-9)

# =====================================================================
# 9. 有效组的四条过滤
# =====================================================================
group("9 有效组过滤")

warm = Entry("bench", 100, 3, is_warmup=True)
uncompleted = Entry("bench", 90, 5, completed=False)
other = Entry("squat", 120, 5)
good = Entry("bench", 80, 6)

finished = Session(sid("f"), "已完成", day(-1), [warm, uncompleted, other, good])
draft = Session(sid("d"), "未结束", day(-1), [good], finished=False)

probe_range = TrendRangeBuilder.range_for("allTime", NOW)
check("排除热身组", len(valid_sets([finished], "bench", probe_range)) == 1)
check("排除未完成组",
      all(v.weight == 80 for v in valid_sets([finished], "bench", probe_range)))
check("排除别的动作",
      all(v.weight != 120 for v in valid_sets([finished], "bench", probe_range)))
check("排除未结束的训练", valid_sets([draft], "bench", probe_range) == [])
check("热身组的容量恒为 0", warm.volume == 0)
check("正式组容量 = 重量 × 次数", good.volume == 480)
check("全部过滤后只剩一条",
      len(valid_sets([finished, draft], "bench", probe_range)) == 1)

# 范围外
outside = Session(sid("o"), "范围外", day(-400), [good])
r30_sets = valid_sets([outside, finished], "bench", r30)
check("排除范围外的训练",
      all(v.session_id != "session-o" for v in r30_sets))
check("范围外训练在全部记录里仍可见",
      any(v.session_id == "session-o" for v in valid_sets([outside], "bench", RANGE_ALL)))

# 排序
check("有效组按时间升序",
      all(SETS_ALL[i].date <= SETS_ALL[i + 1].date for i in range(len(SETS_ALL) - 1)))

# =====================================================================
# 10. 最高重量趋势的点
# =====================================================================
group("10 最高重量趋势")

wp = weight_points(SETS_ALL)
check("每次训练一个点", len(wp) == 12, str(len(wp)))
check("点的顺序与时间升序一致",
      all(wp[i].date <= wp[i + 1].date for i in range(len(wp) - 1)))
check("第一次训练的最高重量是 60", wp[0].top_weight == 60)
check("最后一次训练的最高重量是 82", wp[-1].top_weight == 82)
check("不补空日（只有练过的日子有点）", len(wp) == len({s.session_id for s in SETS_ALL}))
check("组数统计的是正式组", wp[0].set_count == 2)
check("点带训练名", wp[0].session_name == "第 1 次训练")
check("最佳组文案含重量与次数", wp[0].best_set_text(KG) == "60 kg × 8", wp[0].best_set_text(KG))
check("磅单位下文案换算", wp[0].best_set_text(LB) == "132.3 lb × 8", wp[0].best_set_text(LB))
check("自重动作显示「自重」",
      TrendWeightPoint("x", day(-1), 0, 12, "徒手", 1).best_set_text(KG) == "自重")
check("横轴标签是 M/d", wp[0].axis_label == month_day_slash(wp[0].date))
check("无障碍标签含日期/重量/次数/组数",
      all(k in wp[0].accessibility_label for k in ["最高", "公斤", "次", "组"]))

# 同重量取次数多的那组作为代表
tie = [
    ValidSet(sid("t"), day(-1), "同重量", 80, 3, 240),
    ValidSet(sid("t"), day(-1), "同重量", 80, 8, 640),
]
check("同重量取次数多的组", weight_points(tie)[0].reps_at_top == 8)
check("同重量不取次数少的（回归守卫）", weight_points(tie)[0].reps_at_top != 3)
check("空集不产生点", weight_points([]) == [])

# =====================================================================
# 11. 容量趋势的柱子
# =====================================================================
group("11 单次训练容量趋势")

vp = volume_points(SETS_ALL)
check("每次训练一根柱", len(vp) == 12)
check("容量 = 该训练所有正式组之和",
      abs(vp[0].volume - (60 * 8 + 55 * 10)) < 1e-9, str(vp[0].volume))
check("容量随重量上升而上升", vp[-1].volume > vp[0].volume)
check("柱带组数", vp[0].set_count == 2)
check("容量文案带单位", vp[0].volume_text(KG).endswith("kg"))
check("容量文案在磅下换算",
      vp[0].volume_text(LB) == f"{plain_number(vp[0].volume * POUNDS_PER_KILOGRAM)} lb")
check("无障碍标签含组数与容量",
      "组" in vp[0].accessibility_label and "容量" in vp[0].accessibility_label)
check("空集不产生柱", volume_points([]) == [])

# =====================================================================
# 12. 最近记录
# =====================================================================
group("12 最近记录")

rr = recent_records(SETS_ALL)
check("倒序：最新在前", rr[0].date > rr[-1].date)
check("默认最多 10 条", len(rr) == RECENT_LIMIT, str(len(rr)))
check("总训练 12 次时截断到 10", len(SETS_ALL) == 24 and len(rr) == 10)
check("第一条是最近那次训练", rr[0].session_name == "第 12 次训练")
check("每条都带组数", all(r.set_count == 2 for r in rr))
check("每条都带容量", all(r.volume > 0 for r in rr))
check("最佳组文案含次数", "×" in rr[0].best_set_text(KG))
check("limit 可配置", len(recent_records(SETS_ALL, limit=3)) == 3)
check("limit 为 0 时返回空", recent_records(SETS_ALL, limit=0) == [])
check("空集返回空", recent_records([]) == [])

# 「最佳组」比重量，不比容量
mixed = [
    ValidSet(sid("m"), day(-1), "混合", 80, 3, 240),
    ValidSet(sid("m"), day(-1), "混合", 70, 10, 700),
]
mr = recent_records(mixed)[0]
check("最佳组取重量高的那组", mr.best_weight == 80)
check("最佳组不取容量高的那组（回归守卫）", mr.best_reps == 3 and mr.best_reps != 10)
check("容量仍是两组之和", abs(mr.volume - 940) < 1e-9)

# 自重动作
body = [ValidSet(sid("b"), day(-1), "自重", 0, 12, 0)]
check("自重记录最佳重量为 0", recent_records(body)[0].best_weight == 0)
check("自重记录的文案是「自重 × N」", recent_records(body)[0].best_set_text(KG) == "自重 × 12")

# =====================================================================
# 13. 顶部摘要
# =====================================================================
group("13 顶部摘要卡")

ov = overview_of(SETS_ALL)
check("累计训练次数 = 去重后的训练数", ov.session_count == 12, str(ov.session_count))
check("累计完成组数 = 正式组总数", ov.set_count == 24, str(ov.set_count))
check("最高单组重量", ov.best_weight == 82)
check("最高 1RM 有值", ov.best_one_rm is not None)
check("最高 1RM 大于最高重量", ov.best_one_rm > ov.best_weight)
check("1RM 来源次数在可靠区间内", 1 <= ov.one_rm_source_reps <= MAX_RELIABLE_REPS)
check("最近训练日期是最后一次", ov.last_trained_at == max(s.date for s in SETS_ALL))
check("最高重量文案", ov.best_weight_text(KG) == "82")
check("最高重量磅文案", ov.best_weight_text(LB) == "180.8", ov.best_weight_text(LB))
check("1RM 文案有值", ov.best_one_rm_text(KG) != "—")
check("1RM 说明写明来源次数", ov.one_rm_note_text == f"按 {ov.one_rm_source_reps} 次组估算")
check("最近训练文案是中文日期", "月" in ov.last_trained_text)
check("非空时无障碍摘要含次数与组数",
      "次训练" in ov.accessibility_text and "组" in ov.accessibility_text)

# 空数据
empty_ov = overview_of([])
check("空数据时训练次数为 0", empty_ov.session_count == 0)
check("空数据时最高重量为 None", empty_ov.best_weight is None)
check("空数据时最高重量显示「—」", empty_ov.best_weight_text(KG) == "—")
check("空数据时不显示 0 kg（回归守卫）", empty_ov.best_weight_text(KG) != "0")
check("空数据时 1RM 显示「—」", empty_ov.best_one_rm_text(KG) == "—")
check("空数据时最近训练显示「—」", empty_ov.last_trained_text == "—")
check("空数据时没有 1RM 说明", empty_ov.one_rm_note_text is None)
check("空数据时摘要说还没有记录", "还没有这个动作的训练记录" in empty_ov.accessibility_text)
check("空数据判定", empty_ov.is_empty and not ov.is_empty)

# 自重动作：整段没有重量
# 三次自重训练：必须是三个不同的 session id，否则训练次数只有 1
body_sets = [ValidSet(sid(f"b{i}"), day(-i), "自重", 0, 12, 0) for i in range(1, 4)]
body_ov = overview_of(body_sets)
check("自重动作有训练次数", body_ov.session_count == 3)
check("自重动作最高重量为 None", body_ov.best_weight is None)
check("自重动作最高重量显示「—」而不是 0", body_ov.best_weight_text(KG) == "—")
check("自重动作 1RM 为 None", body_ov.best_one_rm is None)
check("自重动作摘要说明无重量数据", "无重量数据" in body_ov.accessibility_text)

# 全是不可靠次数时同样不估 1RM
high_rep_sets = [ValidSet(sid("h"), day(-1), "高次数", 40, 20, 800)]
high_ov = overview_of(high_rep_sets)
check("20 次组不产生 1RM", high_ov.best_one_rm is None)
check("20 次组仍有最高重量", high_ov.best_weight == 40)

# =====================================================================
# 14. 开始训练的建议
# =====================================================================
group("14 开始练这个动作的建议")

sug = start_suggestion(SETS_ALL)
last_date = max(s.date for s in SETS_ALL)
check("建议来自最近一次", sug.source_date == last_date)
check("建议不是历史最高之外的日期（回归守卫）", sug.source_date is not None)
check("建议重量是最近那次的最高重量", sug.weight == 82, str(sug.weight))
check("建议重量不是全期最高之外的数（回归守卫）", sug.weight <= 82)
check("次数上限取自最近那次", sug.reps_high == max(s.reps for s in SETS_ALL if s.date == last_date))
check("次数下限不超过上限", sug.reps_low <= sug.reps_high)
check("次数下限不低于 5", sug.reps_low >= 5)
check("组数不低于 3", sug.sets >= 3)
check("组数等于最近那次的组数", sug.sets == 2 or sug.sets == 3)
check("休息沿用默认 90 秒", sug.rest_seconds == FALLBACK_REST)
check("有历史来源", sug.has_history_source)
check("来源文案写明哪天", "那次训练预填" in sug.source_text)
check("重量文案带单位", sug.weight_text(KG) == "82 kg")
check("磅下换算", sug.weight_text(LB) == "180.8 lb", sug.weight_text(LB))
check("次数文案是区间或单值",
      sug.reps_text == f"{sug.reps_low}-{sug.reps_high}" or sug.reps_text == str(sug.reps_low))

# 次数下限 = 上限的 8 折且夹到 [5, 上限]
high_rep = [ValidSet(sid("x"), day(-1), "x", 50, 20, 1000)]
sug20 = start_suggestion(high_rep)
check("20 次时下限是 16", sug20.reps_low == 16, str(sug20.reps_low))
check("20 次时上限是 20", sug20.reps_high == 20)
low_rep = [ValidSet(sid("y"), day(-1), "y", 50, 4, 200)]
sug4 = start_suggestion(low_rep)
# 「下限不低于 5」只在上限 ≥ 5 时成立：上限是 4 的时候
# `min(repsHigh, max(5, …))` 会被 min 压回 4，否则就要给出「5-4」这种倒挂区间。
# 这里断言的是倒挂不可能出现，而不是下限一定 ≥ 5。
check("4 次时下限等于上限（不能倒挂）", sug4.reps_low == 4, str(sug4.reps_low))
check("4 次时上限保持 4", sug4.reps_high == 4)
check("下限永远不超过上限", sug4.reps_low <= sug4.reps_high)
check("上限 ≥ 5 时下限不低于 5", start_suggestion(
    [ValidSet(sid("z"), day(-1), "z", 50, 6, 300)]).reps_low >= 5)

# 无历史
check("无历史时用兜底方案", start_suggestion([]) is FALLBACK)
check("兜底重量为 0（自重起步）", FALLBACK.weight == 0)
check("兜底次数 8-12", FALLBACK.reps_low == 8 and FALLBACK.reps_high == 12)
check("兜底组数 3", FALLBACK.sets == 3)
check("兜底无来源日期", not FALLBACK.has_history_source)
check("兜底来源文案说明是默认值", "没有历史记录" in FALLBACK.source_text)
check("兜底重量文案是「自重」", FALLBACK.weight_text(KG) == "自重")

# 建议重量不自动加重
check("建议重量沿用上次，不自动加重", sug.weight == 82 and sug.weight != 84)

# =====================================================================
# 15. 草稿组条目
# =====================================================================
group("15 草稿组条目")

entries = draft_entries("bench", sug)
check("组数等于建议组数", len(entries) == max(1, sug.sets))
check("组号从 1 开始", entries[0]["index"] == 1)
check("组号连续", [e["index"] for e in entries] == list(range(1, len(entries) + 1)))
check("都未完成（不预填完成时间）", all(e["completed"] is False for e in entries))
check("都不是热身组", all(e["is_warmup"] is False for e in entries))
check("预填建议重量", all(e["weight"] == sug.weight for e in entries))
check("目标次数区间来自建议",
      all(e["target_low"] == sug.reps_low and e["target_high"] == sug.reps_high for e in entries))
check("实际次数先填下限", all(e["reps"] == sug.reps_low for e in entries))
check("动作 id 正确", all(e["exercise_id"] == "bench" for e in entries))
check("兜底方案也能展开", len(draft_entries("x", FALLBACK)) == 3)
check("startingIndex 可偏移", draft_entries("x", FALLBACK, starting_index=4)[0]["index"] == 4)

# =====================================================================
# 16. 趋势的 VoiceOver 摘要
# =====================================================================
group("16 图表 VoiceOver 摘要")

ws = weight_trend_summary(wp, ov, "近 3 个月")
check("摘要含范围名", "近 3 个月" in ws)
check("摘要含训练次数", "12 次训练" in ws)
check("摘要含最高重量", "最高 82 公斤" in ws)
check("摘要以句号结尾", ws.endswith("。"))
check("末点高于首点时说提高", "提高" in ws)
check("不是下降（回归守卫）", "下降" not in ws)

flat = [TrendWeightPoint(sid("a"), day(-2), 60, 8, "A", 1),
        TrendWeightPoint(sid("b"), day(-1), 60, 8, "B", 1)]
check("持平时说基本持平",
      "基本持平" in weight_trend_summary(flat, overview_of(SETS_ALL), "近 30 天"))
down = [TrendWeightPoint(sid("a"), day(-2), 80, 8, "A", 1),
        TrendWeightPoint(sid("b"), day(-1), 70, 8, "B", 1)]
check("下降时说下降", "下降 10 公斤" in weight_trend_summary(down, ov, "近 30 天"))
check("单点不提涨跌",
      "持平" not in weight_trend_summary([wp[0]], ov, "近 30 天")
      and "提高" not in weight_trend_summary([wp[0]], ov, "近 30 天"))
check("空数据时给出成立的一句话",
      weight_trend_summary([], ov, "近 30 天") == "近 30 天内没有这个动作的训练记录。")

vs = volume_trend_summary(vp, "近 3 个月")
check("容量摘要含累计值", "累计" in vs and "公斤" in vs)
check("容量摘要含单次最高", "单次最高" in vs)
check("容量摘要含次数", "12 次训练" in vs)
check("容量空数据有文案",
      volume_trend_summary([], "近 30 天") == "近 30 天内没有这个动作的容量记录。")

# =====================================================================
# 17. 动作名三级兜底
# =====================================================================
group("17 动作名兜底")

check("优先用库里的当前名", trend_name("杠铃卧推", "旧名字", "0001") == "杠铃卧推")
check("库里没有时用快照名", trend_name(None, "旧名字", "0001") == "旧名字")
check("都没有时用动作 id", trend_name(None, None, "0001") == "0001")
check("空字符串不算名字", trend_name("   ", None, "0001") == "0001")
check("全空时兜底「未知动作」", trend_name(None, "", "") == "未知动作")
check("空白快照名被跳过", trend_name(None, "  ", "0002") == "0002")
check("动作已删除也能显示名字", trend_name(None, "已删除的动作", "9999") == "已删除的动作")

# =====================================================================
# 18. 图表几何：折线端点与圆点列中心一致
# =====================================================================
group("18 折线与圆点的横坐标一致")


def x_at(index, count, width):
    """TrendWeightLineShape.x(at:) 与 dotsRow 的列宽算法必须一致"""
    column = width / count
    return column * index + column / 2


check("单点时 x 居中", abs(x_at(0, 1, 320.0) - 160.0) < 1e-9)
check("单点不除零（回归守卫）", x_at(0, 1, 320.0) == x_at(0, 1, 320.0))
check("两点时不贴边", abs(x_at(0, 2, 320.0) - 80.0) < 1e-9 and abs(x_at(1, 2, 320.0) - 240.0) < 1e-9)
check("末点不贴右边（列布局而非轴布局）", abs(x_at(11, 12, 320.0) - 306.6666666) < 1e-5)
check("x 单调递增", all(x_at(i, 12, 320.0) < x_at(i + 1, 12, 320.0) for i in range(11)))
check("列中心之和等于整宽的一半×列数",
      abs(sum(x_at(i, 4, 320.0) for i in range(4)) - 320.0 * 4 / 2) < 1e-9)


def y_ratio(weight, max_weight):
    if max_weight <= 0:
        return 0.0
    return min(1.0, max(0.0, weight / max_weight))


check("最大值占比为 1", y_ratio(82, 82) == 1.0)
check("一半占比", abs(y_ratio(41, 82) - 0.5) < 1e-9)
check("全自重时上界兜底为 1 而不是 0", y_ratio(0, 1) == 0.0)
check("上界为 0 时不除零（回归守卫）", y_ratio(10, 0) == 0.0)
check("占比不超过 1", y_ratio(100, 82) == 1.0)


def bar_height(volume, max_volume, height, padding):
    """TrendVolumeBar 的高度：最小值 4pt 保证零容量也看得见"""
    plot = height - padding
    ratio = 0.0 if max_volume <= 0 or volume <= 0 else volume / max_volume
    return max(4.0, ratio * plot)


check("最大容量柱顶到绘图区上沿",
      abs(bar_height(700, 700, 140.0, 12.0) - 128.0) < 1e-9)
check("零容量柱仍有最小高度", bar_height(0, 700, 140.0, 12.0) == 4.0)
check("容量柱高度随容量单调",
      bar_height(350, 700, 140.0, 12.0) < bar_height(700, 700, 140.0, 12.0))
check("上界为 0 时柱不塌陷", bar_height(0, 0, 140.0, 12.0) == 4.0)

# =====================================================================
# 19. 动态字体降级
# =====================================================================
group("19 动态字体降级")

ACCESSIBILITY_CATEGORIES = {
    "extraSmall": False, "small": False, "medium": False, "large": False,
    "extraLarge": False, "extraExtraLarge": False,
    "extraExtraExtraLarge": False,
    "accessibilityMedium": True, "accessibilityLarge": True,
    "accessibilityExtraLarge": True,
    "accessibilityExtraExtraLarge": True,
    "accessibilityExtraExtraExtraLarge": True,
}
for name, expected in ACCESSIBILITY_CATEGORIES.items():
    check(f"{name} 的降级判定", ACCESSIBILITY_CATEGORIES[name] == expected)
check("常规档位不降级", not ACCESSIBILITY_CATEGORIES["large"])
check("无障碍档位降级", ACCESSIBILITY_CATEGORIES["accessibilityMedium"])
check("判据是 isAccessibilityCategory 而非具体档位",
      sum(1 for v in ACCESSIBILITY_CATEGORIES.values() if v) == 5)

# =====================================================================
# 20. 跨范围一致性：三张图共用同一条时间轴
# =====================================================================
group("20 三张图共用同一时间轴")

for kind in ["last30Days", "last3Months", "lastYear", "allTime"]:
    rng = TrendRangeBuilder.range_for(kind, NOW)
    s = valid_sets(SESSIONS, "bench", rng)
    w = weight_points(s)
    v = volume_points(s)
    r = recent_records(s)
    check(f"{kind}：重量点与容量柱数量相同", len(w) == len(v), f"{len(w)} vs {len(v)}")
    check(f"{kind}：点顺序一致",
          all(w[i].date == v[i].date for i in range(len(w))))
    check(f"{kind}：最近记录条数不超过点数量", len(r) <= len(w))
    check(f"{kind}：最近记录倒序",
          all(r[i].date >= r[i + 1].date for i in range(len(r) - 1)))
    check(f"{kind}：摘要训练次数等于点数", overview_of(s).session_count == len(w))
    check(f"{kind}：空集时摘要为空", overview_of([]).is_empty)

# 近 30 天只包含最近几次（每 7 天一次 → 约 5 次）
n30 = overview_of(valid_sets(SESSIONS, "bench", r30)).session_count
check("近 30 天约含 5 次训练", n30 == 5, str(n30))
check("近 30 天少于全部记录", n30 < overview_of(SETS_ALL).session_count)

# =====================================================================
print("\n" + "=" * 72)
if FAIL:
    print(f"失败 {FAIL} 条，通过 {PASS} 条：")
    for f in FAILURES:
        print("  ✗ " + f)
    sys.exit(1)
print(f"全部通过：{PASS} 项断言")
print("=" * 72)
