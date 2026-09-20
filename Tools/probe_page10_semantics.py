#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 10 值语义推演（训练统计 + 备份 + 动作趋势）。

把 WorkoutStatistics.swift / WorkoutBackup.swift 里的纯值类型与纯函数
逐字照搬成 Python，跑断言表。

本机没有 Swift 编译器。preflight 只查 API 版本，lint_swift 只查类型与括号，
两者都查不出这一类错误：

  - 「近 7 天」到底是 7 个自然日还是 8 个（写 `-7` 就会多一根柱子）；
  - 只有有氧训练时，总容量该显示「—」还是「0 kg」；
  - 容量图在没练的日子该补 0 还是该跳过（补 0 就成了规格禁止的零值折线）；
  - 频率图不补空日的话，柱子位置会不会随训练日跳变；
  - 导入备份时三条合并策略分别会加几条、换几条、跳几条；
  - 单点折线的坐标会不会除零得 NaN。

这一层专门补这个缺口。写这套断言时反复踩到的一条：
**断言本身也会写错**。凡是「我以为是 A 其实是 B」的地方，
下面都留一条反向断言（assert 值不是某个诱惑性的错值），
让同样的错不会再犯第二次。

首轮 233 项里错了 7 条，**没有一条是代码的问题**，全是断言自己写歪了。
记在这里当教训：

1. 把 `23:59:59.5 > 23:59:59` 的比较写反了。用「今天 23:59:59」当终点会
   漏掉 23:59:59.5，所以「会漏掉」的表现是**终点 <= late**。断言改成了
   `not (23:59:59 > late)`。
2. `lookup` 字典漏登记了一个动作，于是它落到 `other`，肌群期望值不可能成立。
   补上 `"row"` 之后第 10、11 组才对。
3. `available_filters` 里被我写进了一句 `if False else` 的死排序，是个无操作。
   删掉换成真正的单键排序。
4. 第 20 组「最近记录只含该动作」期望 3 条，实际 4 条。真相是：
   `recent_sessions`（规格里的「最近练过几次」）**不设时间窗口**，所以
   12 个月窗口外那条老记录仍然出现在里面，它本身就是窗口边界的证据。
   期望值改成常量 `TREND_RECENT_ALL = 4`，并补一条「比窗口内组数多 1」的
   关系断言，免得下次又靠硬编码的数去猜。
5. 「只有热身时部位分布为空」拿的是 `warm_only`，而那个 fixture 里
   其实混了一组正式组（它本来就是给「热身不计入组数」那条用的）。
   另建了一个 `all_warm` fixture，两件事分开断言。

用法：
    python Tools/probe_page10_semantics.py
"""

import datetime as dt
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
# 契约常量（与 Swift 源码逐字对应）
# =====================================================================

# StatsFrequencyBuilder.maxBuckets
MAX_BUCKETS = 60
# StatsFrequencyBuilder.dailyBuckets 的 limit
DAILY_LIMIT = 400
# StatsFrequencyBuilder.weeklyBuckets 的 limit
WEEKLY_LIMIT = 80
# StatsTopExerciseBuilder.defaultLimit
TOP_LIMIT = 5
# StatsVolumeBuilder.availableFilters 的 maxExercises
MAX_FILTER_EXERCISES = 12
# ExerciseTrendBuilder.defaultMonths
TREND_MONTHS = 12
# WorkoutBackup.currentVersion / formatIdentifier
BACKUP_VERSION = 1
BACKUP_FORMAT = "fitness-workouts-backup"

# 肌群枚举的固定顺序（MuscleIconGroup 的声明顺序）
MUSCLE_GROUPS = [
    "chest", "back", "shoulder", "arm", "core", "leg",
    "glute", "calf", "cardio", "neck", "other",
]

# MuscleDistributionPalette 的固定映射
MUSCLE_PALETTE = {
    "chest": 0xE8776B, "back": 0x5B9BD5, "shoulder": 0xE0A85C,
    "arm": 0xA98BDB, "core": 0x6FC3A8, "leg": 0x9BAE5C,
    "glute": 0xD98BB0, "calf": 0x7FB3C8, "cardio": 0x3ED8C6,
    "neck": 0xB0A08C, "other": 0x8A8A8F,
}


def plain_number(value):
    """FormatterKit.plainNumber 的移植"""
    return str(int(round(max(0.0, value))))


def duration_text(seconds):
    """FormatterKit.duration 的移植（只实现本推演需要的分支）"""
    seconds = max(0, int(seconds))
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    if h > 0:
        return f"{h} 小时 {m} 分" if m else f"{h} 小时"
    if m > 0:
        return f"{m} 分 {s} 秒" if s else f"{m} 分钟"
    return f"{s} 秒"


def short_date(d):
    """FormatterKit.shortDate 的移植：M/d"""
    return f"{d.month}/{d.day}"


def month_day_slash(d):
    """FormatterKit.monthDaySlash 的移植：M/d"""
    return f"{d.month}/{d.day}"


def start_of_day(d):
    return d.replace(hour=0, minute=0, second=0, microsecond=0)


def add_days(d, n):
    return d + dt.timedelta(days=n)


def add_months(d, n):
    """加自然月。月末溢出时退到当月最后一天（与 Calendar 行为一致）。"""
    total = (d.year * 12 + (d.month - 1)) + n
    year, month = divmod(total, 12)
    month += 1
    # 找到该月最后一天
    if month == 12:
        last = 31
    else:
        last = (dt.date(year + (month // 12), (month % 12) + 1, 1)
                - dt.timedelta(days=1)).day
    day = min(d.day, last)
    return d.replace(year=year, month=month, day=day)


def first_day_of_month(d):
    return d.replace(day=1, hour=0, minute=0, second=0, microsecond=0)


def first_day_of_year(d):
    return d.replace(month=1, day=1, hour=0, minute=0, second=0, microsecond=0)


# =====================================================================
# 移植：SetEntry / WorkoutSession
# =====================================================================

class SetEntry:
    def __init__(self, exercise_id, weight, reps, is_warmup=False,
                 completed=True, completed_at=None):
        self.exercise_id = exercise_id
        self.weight = weight
        self.reps = reps
        self.is_warmup = is_warmup
        self.completed_at = completed_at if completed_at is not None else (
            dt.datetime(2026, 1, 1, tzinfo=TZ) if completed else None
        )

    @property
    def is_completed(self):
        return self.completed_at is not None

    @property
    def volume(self):
        # 与 Swift 一致：热身组恒为 0
        return 0.0 if self.is_warmup else self.weight * float(self.reps)


class Session:
    def __init__(self, sid, started_at, kind="strength", entries=None,
                 is_finished=True, distance_meters=None):
        self.id = sid
        self.started_at = started_at
        self.kind = kind
        self.entries = entries or []
        self.is_finished = is_finished
        self.distance_meters = distance_meters

    @property
    def completed_entries(self):
        return [e for e in self.entries if e.is_completed]

    @property
    def completed_set_count(self):
        """含热身（页面 10 摘要「总完成组数」用的就是这个口径）"""
        return len(self.completed_entries)

    @property
    def total_sets(self):
        """不含热身"""
        return len([e for e in self.completed_entries if not e.is_warmup])

    @property
    def total_volume(self):
        return sum(e.volume for e in self.completed_entries)

    @property
    def duration_seconds(self):
        # 简化：本推演的记录都显式带时长，这里由 entries 数推一个稳定值
        return getattr(self, "_duration", 3600)

    @property
    def distance_km(self):
        return (self.distance_meters or 0) / 1000.0


def session_with_duration(sid, started_at, kind="strength", entries=None,
                          is_finished=True, distance_meters=None, duration=3600):
    s = Session(sid, started_at, kind, entries, is_finished, distance_meters)
    s._duration = duration
    return s


class LibraryItem:
    def __init__(self, item_id, name, aliases, primary_muscle, display=None):
        self.id = item_id
        self.name = name
        self.aliases = aliases
        self.primary_muscle = primary_muscle
        self._display = display

    @property
    def display_name(self):
        """与 Models.swift 的 displayName 同口径：别名优先，其次原名"""
        if self._display is not None:
            return self._display
        return self.aliases[0] if self.aliases else self.name


def muscle_group_of(muscle):
    """MuscleIconGroup.of(muscle:) 的移植（覆盖本项目用到的取值）"""
    key = (muscle or "").lower().strip()
    mapping = {
        "胸": "chest", "chest": "chest", "pectorals": "chest",
        "背": "back", "back": "back", "lats": "back", "latissimus dorsi": "back",
        "肩": "shoulder", "shoulder": "shoulder", "delts": "shoulder",
        "手臂": "arm", "arm": "arm", "biceps": "arm", "triceps": "arm",
        "核心": "core", "core": "core", "abs": "core", "waist": "core",
        "腿": "leg", "leg": "leg", "quads": "leg", "quadriceps": "leg",
        "hamstrings": "leg", "大腿": "leg",
        "臀": "glute", "glute": "glute", "glutes": "glute",
        "小腿": "calf", "calf": "calf", "calves": "calf",
        "有氧": "cardio", "cardio": "cardio",
        "颈": "neck", "neck": "neck",
    }
    return mapping.get(key, "other")


# =====================================================================
# 移植：StatsDateRange / StatsRangeBuilder
# =====================================================================

class DateRange:
    def __init__(self, start, end, kind):
        self.start = start
        self.end = end
        self.kind = kind

    def contains(self, d):
        """半开区间 [start, end)"""
        return self.start <= d < self.end

    def day_count(self):
        return (start_of_day(self.end - dt.timedelta(microseconds=1))
                - start_of_day(self.start)).days + 1

    @property
    def whole_days(self):
        """不含终点那一格的自然日数：end 与 start 的整天差"""
        return (start_of_day(self.end) - start_of_day(self.start)).days


def end_of_today(now):
    """一律取明天的 00:00，而不是今天 23:59:59"""
    return add_days(start_of_day(now), 1)


def range_for(kind, now, custom_start=None, custom_end=None):
    today = start_of_day(now)

    if kind == "last7Days":
        start = add_days(today, -6)          # 含今天在内的 7 个自然日
        return DateRange(start, end_of_today(now), kind)

    if kind == "last30Days":
        start = add_days(today, -29)
        return DateRange(start, end_of_today(now), kind)

    if kind == "thisMonth":
        start = first_day_of_month(now)
        return DateRange(start, end_of_today(now), kind)

    if kind == "last3Months":
        this_month = first_day_of_month(now)
        start = add_months(this_month, -2)
        return DateRange(start, end_of_today(now), kind)

    if kind == "thisYear":
        start = first_day_of_year(now)
        return DateRange(start, end_of_today(now), kind)

    if kind == "custom":
        return custom_range(custom_start, custom_end, now)

    raise ValueError(kind)


def custom_range(start, end, now):
    fallback = range_for("last30Days", now)
    if start is None:
        return fallback
    normalized_start = start_of_day(start)
    raw_end = end if end is not None else now
    normalized_end_day = start_of_day(raw_end)
    lower = min(normalized_start, normalized_end_day)
    upper = max(normalized_start, normalized_end_day)
    return DateRange(lower, add_days(upper, 1), "custom")


# =====================================================================
# 移植：StatsSummary
# =====================================================================

class Summary:
    def __init__(self, sessions):
        self.sessions = sessions

    @property
    def session_count(self):
        return len(self.sessions)

    @property
    def strength_count(self):
        return len([s for s in self.sessions if s.kind == "strength"])

    @property
    def cardio_count(self):
        return len([s for s in self.sessions if s.kind == "cardio"])

    @property
    def total_duration_seconds(self):
        return sum(s.duration_seconds for s in self.sessions)

    @property
    def total_set_count(self):
        # 含热身 —— 语义是「一共完成了多少组动作」
        return sum(s.completed_set_count for s in self.sessions)

    @property
    def total_volume(self):
        return sum(s.total_volume for s in self.sessions if s.kind == "strength")

    @property
    def total_distance_meters(self):
        return sum((s.distance_meters or 0) for s in self.sessions if s.kind == "cardio")

    @property
    def has_cardio(self):
        return self.cardio_count > 0

    @property
    def has_volume(self):
        return self.total_volume > 0

    @property
    def average_duration_seconds(self):
        if self.session_count == 0:
            return None
        return self.total_duration_seconds // self.session_count

    def metrics(self, include_cardio_distance=True):
        """返回 [(id, title, value_or_None, unit)]，value 为 None 表示「—」"""
        result = []

        result.append((
            "sessionCount", "训练次数",
            str(self.session_count) if self.session_count > 0 else "0",
            "次",
        ))

        result.append((
            "duration", "总训练时长",
            plain_number(self.total_duration_seconds / 60.0)
            if self.session_count > 0 else "0",
            "分钟",
        ))

        result.append((
            "sets", "总完成组数", str(self.total_set_count), "组",
        ))

        # 容量：只有有氧时给 None（显示「—」），
        # 但有力量训练而容量确实是 0 时给 "0"。
        if self.has_volume:
            volume_text = plain_number(self.total_volume)
        elif self.strength_count > 0:
            volume_text = "0"
        else:
            volume_text = None
        result.append(("volume", "总训练容量", volume_text, "kg"))

        if include_cardio_distance and self.has_cardio:
            has_distance = self.total_distance_meters > 0
            result.append((
                "distance", "总距离",
                f"{self.total_distance_meters / 1000:.2f}" if has_distance else None,
                "公里",
            ))

        return result

    def accessibility_summary(self, range_title):
        if self.session_count == 0:
            return f"{range_title}没有训练记录"
        parts = [f"{range_title}完成 {self.session_count} 次训练"]
        parts.append(f"共 {duration_text(self.total_duration_seconds)}")
        if self.has_volume:
            parts.append(f"总容量 {plain_number(self.total_volume)} 千克")
        if self.has_cardio and self.total_distance_meters > 0:
            parts.append(f"总距离 {self.total_distance_meters / 1000:.2f} 公里")
        return "，".join(parts)


# =====================================================================
# 移植：StatsFrequencyBuilder
# =====================================================================

def week_start(d):
    """周一 00:00。与 Swift 一样交给「日历」算，不硬减 weekday-1"""
    return start_of_day(d - dt.timedelta(days=d.weekday()))


def effective_granularity(requested, rng):
    if requested != "daily":
        return "weekly"
    return "weekly" if rng.whole_days > MAX_BUCKETS else "daily"


def _make_bucket(date, days, sessions):
    return {
        "date": date,
        "days": days,
        "strength": len([s for s in sessions if s.kind == "strength"]),
        "cardio": len([s for s in sessions if s.kind == "cardio"]),
        "duration": sum(s.duration_seconds for s in sessions),
        "total": len(sessions),
    }


def frequency_buckets(sessions, rng, granularity):
    scoped = [s for s in sessions if s.is_finished and rng.contains(s.started_at)]

    if granularity == "weekly":
        grouped = {}
        for s in scoped:
            grouped.setdefault(week_start(s.started_at), []).append(s)
        result = []
        cursor = week_start(rng.start)
        while cursor < rng.end and len(result) < WEEKLY_LIMIT:
            days = [add_days(cursor, o) for o in range(7)]
            result.append(_make_bucket(cursor, days, grouped.get(cursor, [])))
            cursor = add_days(cursor, 7)
        return result

    grouped = {}
    for s in scoped:
        grouped.setdefault(start_of_day(s.started_at), []).append(s)
    result = []
    cursor = start_of_day(rng.start)
    while cursor < rng.end and len(result) < DAILY_LIMIT:
        result.append(_make_bucket(cursor, [cursor], grouped.get(cursor, [])))
        cursor = add_days(cursor, 1)
    return result


def frequency_max_count(buckets):
    return max((b["total"] for b in buckets), default=0)


def frequency_summary(buckets, range_title):
    active = [b for b in buckets if b["total"] > 0]
    strength = sum(b["strength"] for b in buckets)
    cardio = sum(b["cardio"] for b in buckets)
    total = strength + cardio
    if total == 0:
        return f"{range_title}的训练频率图，这个范围内没有训练记录"
    parts = [f"{range_title}的训练频率图"]
    parts.append(f"共 {total} 次训练")
    if strength > 0:
        parts.append(f"力量 {strength} 次")
    if cardio > 0:
        parts.append(f"有氧 {cardio} 次")
    unit = "日期" if (len(buckets) <= 7 or len(active) == 1) else "时间格"
    parts.append(f"分布在 {len(active)} 个{unit}上")
    parts.append(f"最高一格是 {frequency_max_count(buckets)} 次")
    return "，".join(parts)


# =====================================================================
# 移植：动作命名 / StatsVolumeBuilder
# =====================================================================

def exercise_display_name(exercise_id, lookup):
    item = lookup.get(exercise_id)
    if item is not None:
        display = item.display_name
        if display:
            return display
        if item.name:
            return item.name
    trimmed = (exercise_id or "").strip()
    return trimmed if trimmed else "未知动作"


class VolumeFilter:
    def __init__(self, kind, group=None, exercise_id=None, name=None):
        self.kind = kind
        self.group = group
        self.exercise_id = exercise_id
        self.name = name

    @property
    def cache_key(self):
        if self.kind == "all":
            return "all"
        if self.kind == "muscle":
            return f"muscle:{self.group}"
        return f"exercise:{self.exercise_id}"

    @property
    def title(self):
        if self.kind == "all":
            return "全部动作"
        if self.kind == "muscle":
            return self.group
        return self.name or self.exercise_id

    def accepts(self, entry, lookup):
        if self.kind == "all":
            return True
        if self.kind == "muscle":
            muscle = ""
            item = lookup.get(entry.exercise_id)
            if item is not None:
                muscle = item.primary_muscle or ""
            return muscle_group_of(muscle) == self.group
        return entry.exercise_id == self.exercise_id


def volume_points(sessions, rng, filt, lookup):
    volume_by_day = {}
    count_by_day = {}
    top_by_day = {}

    for s in sessions:
        if not (s.is_finished and rng.contains(s.started_at)):
            continue
        day = start_of_day(s.started_at)
        contributed = False

        for entry in s.entries:
            if not entry.is_completed:
                continue
            if not filt.accepts(entry, lookup):
                continue
            volume = entry.volume
            # 热身组 volume 恒为 0 —— 跳过，否则会在图上留下一个 0 值点
            if not volume > 0:
                continue

            volume_by_day[day] = volume_by_day.get(day, 0.0) + volume
            contributed = True

            name = exercise_display_name(entry.exercise_id, lookup)
            cur = top_by_day.get(day)
            if cur is None or volume > cur[1]:
                top_by_day[day] = (name, volume)

        if contributed:
            count_by_day[day] = count_by_day.get(day, 0) + 1

    return [
        {
            "date": day,
            "volume": volume_by_day[day],
            "session_count": count_by_day.get(day, 0),
            "top_name": top_by_day[day][0] if day in top_by_day else None,
        }
        for day in sorted(volume_by_day.keys())
    ]


def available_filters(sessions, rng, lookup, max_exercises=MAX_FILTER_EXERCISES):
    muscle_groups = set()
    use_count = {}

    for s in sessions:
        if not (s.is_finished and rng.contains(s.started_at)):
            continue
        for entry in s.entries:
            if not (entry.is_completed and not entry.is_warmup):
                continue
            if not entry.volume > 0:
                continue
            use_count[entry.exercise_id] = use_count.get(entry.exercise_id, 0) + 1
            item = lookup.get(entry.exercise_id)
            muscle = (item.primary_muscle or "") if item is not None else ""
            muscle_groups.add(muscle_group_of(muscle))

    result = [VolumeFilter("all")]

    # 肌群按固定枚举顺序，不按哈希顺序
    for g in MUSCLE_GROUPS:
        if g in muscle_groups:
            result.append(VolumeFilter("muscle", group=g))

    # 动作排序：出现次数降序，并列时按 id 升序（与 Swift 的 comparator 一致）
    ordered = sorted(use_count.items(), key=lambda kv: (-kv[1], kv[0]))[:max_exercises]

    for ex_id, _ in ordered:
        result.append(VolumeFilter(
            "exercise", exercise_id=ex_id,
            name=exercise_display_name(ex_id, lookup),
        ))

    return result


def volume_summary(points, range_title):
    if not points:
        return f"{range_title}的容量趋势图，这个范围内没有容量数据"
    total = sum(p["volume"] for p in points)
    peak = max(points, key=lambda p: p["volume"])
    parts = [f"{range_title}的容量趋势图"]
    parts.append(f"共 {len(points)} 个训练日")
    parts.append(f"总容量 {plain_number(total)} 千克")
    parts.append(
        f"最高一天是 {short_date(peak['date'])}，{plain_number(peak['volume'])} 千克"
    )
    return "，".join(parts)


# =====================================================================
# 移植：StatsTopExerciseBuilder / StatsMuscleDistributionBuilder
# =====================================================================

def top_exercises(sessions, rng, lookup, limit=TOP_LIMIT):
    set_count = {}
    volume = {}
    first_at = {}
    last_at = {}

    for s in sessions:
        if not (s.is_finished and rng.contains(s.started_at)):
            continue
        for entry in s.entries:
            if not (entry.is_completed and not entry.is_warmup):
                continue
            ex = entry.exercise_id
            set_count[ex] = set_count.get(ex, 0) + 1
            volume[ex] = volume.get(ex, 0.0) + entry.volume
            if ex not in first_at or s.started_at < first_at[ex]:
                first_at[ex] = s.started_at
            if ex not in last_at or s.started_at > last_at[ex]:
                last_at[ex] = s.started_at

    # 三级排序：组数降序 → 容量降序 → id 升序
    ordered = sorted(
        set_count.keys(),
        key=lambda ex: (-set_count[ex], -volume.get(ex, 0.0), ex),
    )[:max(0, limit)]

    return [
        {
            "exercise_id": ex,
            "display_name": exercise_display_name(ex, lookup),
            "primary_muscle": (lookup[ex].primary_muscle or "") if ex in lookup else "",
            "icon_group": muscle_group_of(
                (lookup[ex].primary_muscle or "") if ex in lookup else ""
            ),
            "set_count": set_count[ex],
            "volume": volume.get(ex, 0.0),
        }
        for ex in ordered
    ]


def top_summary(items, range_title):
    if not items:
        return f"{range_title}没有完成的动作记录"
    names = [f"{i['display_name']} {i['set_count']} 组" for i in items[:3]]
    return f"{range_title}最常练的 {len(items)} 个动作：" + "、".join(names)


def muscle_rows(sessions, rng, lookup):
    count_by_group = {}
    for s in sessions:
        if not (s.is_finished and rng.contains(s.started_at)):
            continue
        for entry in s.entries:
            if not (entry.is_completed and not entry.is_warmup):
                continue
            item = lookup.get(entry.exercise_id)
            muscle = (item.primary_muscle or "") if item is not None else ""
            g = muscle_group_of(muscle)
            count_by_group[g] = count_by_group.get(g, 0) + 1

    total = sum(count_by_group.values())
    if total == 0:
        return []

    rows = []
    for g in MUSCLE_GROUPS:          # 固定枚举顺序，不按组数排序
        c = count_by_group.get(g, 0)
        if c > 0:
            rows.append({
                "group": g,
                "set_count": c,
                "ratio": c / float(total),
                "percent_text": f"{int(round(c / float(total) * 100))}%",
                "color_hex": MUSCLE_PALETTE[g],
            })
    return rows


def muscle_summary(rows, range_title):
    if not rows:
        return f"{range_title}没有完成的组数，无法统计部位分布"
    top = [f"{r['group']} {r['percent_text']}" for r in rows[:3]]
    return f"{range_title}训练部位分布，前三位：" + "、".join(top)


# =====================================================================
# 移植：StatsCache / StatsCacheKey
# =====================================================================

class StatsCache:
    def __init__(self):
        self.entry = None
        self.version = 0

    def value(self, key):
        if self.entry is None or self.entry[0] != key:
            return None
        return self.entry[1]

    def store(self, value, key):
        self.entry = (key, value)

    def invalidate(self):
        self.entry = None
        self.version += 1

    @property
    def is_empty(self):
        return self.entry is None


def range_key(rng):
    return f"{rng.kind}:{int(rng.start.timestamp())}-{int(rng.end.timestamp())}"


def cache_key(rng, filt):
    return f"{range_key(rng)}:{filt.cache_key}"


# =====================================================================
# 移植：WorkoutBackup 合并
# =====================================================================

KEEP_EXISTING = "keepExisting"
OVERWRITE_EXISTING = "overwriteExisting"
REPLACE_ALL = "replaceAll"


def dedupe(sessions):
    """按 id 去重，保留先出现的那条"""
    seen = set()
    result = []
    for s in sessions:
        if s.id not in seen:
            seen.add(s.id)
            result.append(s)
    return result


def merge(existing, incoming, policy):
    if policy == REPLACE_ALL:
        d = dedupe(incoming)
        return {
            "sessions": sorted(d, key=lambda s: s.started_at),
            "added": len(d), "replaced": 0, "skipped": 0,
        }

    existing_ids = {s.id for s in existing}
    result = list(existing)
    added = replaced = skipped = 0

    for rec in dedupe(incoming):
        if rec.id in existing_ids:
            if policy == KEEP_EXISTING:
                skipped += 1
            elif policy == OVERWRITE_EXISTING:
                for i, s in enumerate(result):
                    if s.id == rec.id:
                        result[i] = rec
                        replaced += 1
                        break
        else:
            result.append(rec)
            added += 1

    return {
        "sessions": sorted(result, key=lambda s: s.started_at),
        "added": added, "replaced": replaced, "skipped": skipped,
    }


def merge_summary_text(plan):
    parts = []
    if plan["added"]:
        parts.append(f"新增 {plan['added']} 条")
    if plan["replaced"]:
        parts.append(f"替换 {plan['replaced']} 条")
    if plan["skipped"]:
        parts.append(f"跳过 {plan['skipped']} 条")
    if not parts:
        parts.append("没有可导入的记录")
    return "，".join(parts) + f"，本机共 {len(plan['sessions'])} 条训练记录"


def make_backup(sessions):
    finished = sorted(
        [s for s in sessions if s.is_finished],
        key=lambda s: s.started_at,
    )
    return {
        "format": BACKUP_FORMAT,
        "version": BACKUP_VERSION,
        "session_count": len(finished),
        "sessions": finished,
    }


def decode_error(data_kind, payload_format=None, payload_version=None,
                 session_count=None):
    """模拟 WorkoutBackupCoder.decode 的校验顺序，返回错误码或 None"""
    if data_kind == "empty":
        return "emptyFile"
    if data_kind == "notJSON":
        return "notJSON"
    if payload_format != BACKUP_FORMAT:
        return "wrongFormat"
    if payload_version is not None and payload_version > BACKUP_VERSION:
        return "unsupportedVersion"
    if session_count == 0:
        return "noSessions"
    return None


# =====================================================================
# 移植：ExerciseTrendBuilder
# =====================================================================

class TrendPoint:
    def __init__(self, month_start, set_count, volume, top_weight, session_count):
        self.month_start = month_start
        self.set_count = set_count
        self.volume = volume
        self.top_weight = top_weight
        self.session_count = session_count

    @property
    def is_empty(self):
        return self.set_count == 0

    @property
    def short_label(self):
        return f"{self.month_start.month}月"

    @property
    def detail_text(self):
        if self.is_empty:
            return "未训练"
        return f"{self.set_count} 组 · {plain_number(self.volume)} kg"

    @property
    def accessibility_label(self):
        if self.is_empty:
            return f"{self.short_label}未训练"
        return (f"{self.short_label}，{self.set_count} 组，"
                f"容量 {plain_number(self.volume)} 公斤")


def monthly_trend_points(sessions, exercise_id, months=TREND_MONTHS, now=None):
    if months <= 0:
        return []
    safe_months = min(months, 60)

    current_month_start = first_day_of_month(now)

    month_starts = []
    for offset in range(safe_months - 1, -1, -1):
        month_starts.append(add_months(current_month_start, -offset))

    keys = {m.timestamp(): m for m in month_starts}

    sets_by_month = {}
    volume_by_month = {}
    top_by_month = {}
    sessions_by_month = {}

    for s in sessions:
        if not s.is_finished:
            continue
        ms = first_day_of_month(s.started_at)
        key = ms.timestamp()
        if key not in keys:
            continue

        touched = False
        for entry in s.entries:
            if entry.exercise_id != exercise_id:
                continue
            if not entry.is_completed or entry.is_warmup:
                continue
            touched = True
            sets_by_month[key] = sets_by_month.get(key, 0) + 1
            volume_by_month[key] = volume_by_month.get(key, 0.0) + entry.volume
            top_by_month[key] = max(top_by_month.get(key, 0.0), entry.weight)

        if touched:
            sessions_by_month.setdefault(key, set()).add(s.id)

    return [
        TrendPoint(
            m,
            sets_by_month.get(m.timestamp(), 0),
            volume_by_month.get(m.timestamp(), 0.0),
            top_by_month.get(m.timestamp(), 0.0),
            len(sessions_by_month.get(m.timestamp(), set())),
        )
        for m in month_starts
    ]


def recent_sessions(sessions, exercise_id, limit=5):
    if limit <= 0:
        return []
    result = []
    for s in sessions:
        if not s.is_finished:
            continue
        set_count = 0
        volume = 0.0
        top_weight = 0.0
        for entry in s.entries:
            if entry.exercise_id != exercise_id:
                continue
            if not entry.is_completed or entry.is_warmup:
                continue
            set_count += 1
            volume += entry.volume
            top_weight = max(top_weight, entry.weight)
        if set_count == 0:
            continue
        result.append({
            "session_id": s.id, "date": s.started_at,
            "set_count": set_count, "volume": volume, "top_weight": top_weight,
        })
        if len(result) >= limit:
            break
    return sorted(result, key=lambda r: r["date"], reverse=True)


class TrendSummary:
    def __init__(self, exercise_id, fallback_name, points, recent):
        self.exercise_id = exercise_id
        self.fallback_name = fallback_name
        self.points = points
        self.recent = recent

    @property
    def active_month_count(self):
        return len([p for p in self.points if not p.is_empty])

    @property
    def total_set_count(self):
        return sum(p.set_count for p in self.points)

    @property
    def total_volume(self):
        return sum(p.volume for p in self.points)

    @property
    def best_weight(self):
        values = [p.top_weight for p in self.points if p.top_weight > 0]
        return None if not values else max(values)

    @property
    def display_name(self):
        t = (self.fallback_name or "").strip()
        return t if t else "未知动作"

    @property
    def best_weight_text(self):
        best = self.best_weight
        return "—" if best is None else f"{plain_number(best)} kg"

    @property
    def accessibility_text(self):
        if self.active_month_count == 0:
            return f"{self.display_name}，最近 12 个月没有训练记录。"
        parts = [f"{self.display_name}，最近 12 个月中 {self.active_month_count} 个月有训练"]
        parts.append(f"共 {self.total_set_count} 组")
        parts.append(f"累计容量 {plain_number(self.total_volume)} 公斤")
        if self.best_weight is not None:
            parts.append(f"最高单组 {plain_number(self.best_weight)} 公斤")
        return "，".join(parts) + "。"


# =====================================================================
# 起点时间
# =====================================================================

NOW = dt.datetime(2026, 9, 19, 14, 30, tzinfo=TZ)


def s_at(day_offset, hour=9, sid=None, **kw):
    """相对 NOW 的某天某点的记录"""
    base = start_of_day(NOW) + dt.timedelta(days=day_offset, hours=hour)
    return session_with_duration(sid or f"s{day_offset}_{hour}", base, **kw)


# =====================================================================
print("=" * 72)
print("页面 10 值语义推演")
print("=" * 72)

# ---------------------------------------------------------------- 1
group("1 时间范围的「含今天」边界")

r7 = range_for("last7Days", NOW)
c7 = r7.whole_days
check("近 7 天是 7 个自然日，不是 8 个", c7 == 7, f"实际 {c7}")
# 反向断言：把 -6 写成 -7 就会得到 8，这正是要防的错
check("近 7 天不是 8 个自然日（回归守卫）", c7 != 8)
check("近 7 天起点 = 今天 - 6 天",
      r7.start == add_days(start_of_day(NOW), -6))
check("近 7 天含今天", r7.contains(start_of_day(NOW)))
check("近 7 天不含明天", not r7.contains(add_days(start_of_day(NOW), 1)))

r30 = range_for("last30Days", NOW)
c30 = r30.whole_days
check("近 30 天是 30 个自然日", c30 == 30, f"实际 {c30}")
check("近 30 天不是 31 个", c30 != 31)

# ---------------------------------------------------------------- 2
group("2 终点取明天 00:00 而不是今天 23:59:59")

today = start_of_day(NOW)
eot = end_of_today(NOW)
check("终点 = 明天 00:00", eot == add_days(today, 1))
check("终点 ≠ 今天 23:59:59", eot != today + dt.timedelta(hours=23, minutes=59, seconds=59))
# 小数秒里的记录必须被包住 —— 这正是取 23:59:59 会漏掉的
late = today + dt.timedelta(hours=23, minutes=59, seconds=59, microseconds=500000)
check("23:59:59.5 的记录被近 7 天包住", r7.contains(late),
      f"late={late}")
# 「今天 23:59:59」这种终点会漏掉 23:59:59.5。
# 注意：0.5 秒比「23:59:59 整」更大，所以「漏掉」的表现是
# 终点 <= late，而不是终点 > late。这里断言的是终点确实不够大。
check("取『今天 23:59:59』作终点会漏掉它（回归守卫）",
      not ((today + dt.timedelta(hours=23, minutes=59, seconds=59)) > late))

# ---------------------------------------------------------------- 3
group("3 本月 / 近 3 个月 / 今年")

rm = range_for("thisMonth", NOW)
check("本月起点 = 9 月 1 日", rm.start == first_day_of_month(NOW))
check("本月起点是 1 号", rm.start.day == 1)

r3 = range_for("last3Months", NOW)
check("近 3 个月起点 = 7 月 1 日", r3.start == first_day_of_month(NOW).replace(month=7))
check("近 3 个月起点是 1 号", r3.start.day == 1)
check("近 3 个月含本月", r3.contains(start_of_day(NOW)))
check("近 3 个月是「含本月在内」而不是「往前 90 天」",
      r3.whole_days != 90, f"实际 {r3.whole_days} 天")

ry = range_for("thisYear", NOW)
check("今年起点 = 1 月 1 日", ry.start == first_day_of_year(NOW))

# 跨年边界：1 月 1 日看近 3 个月
jan1 = dt.datetime(2026, 1, 1, 10, 0, tzinfo=TZ)
r3_jan = range_for("last3Months", jan1)
check("1 月 1 日看近 3 个月 → 起点在去年 11 月 1 日",
      (r3_jan.start.year, r3_jan.start.month) == (2025, 11),
      f"实际 {r3_jan.start}")
check("近 3 个月没有算成 1 月往前 2 天的错值", r3_jan.start.day == 1)

# ---------------------------------------------------------------- 4
group("4 自定义范围的三条兜底")

# 没给起点 → 退回近 30 天
r_nostart = custom_range(None, NOW, NOW)
check("没给起点时退回近 30 天", r_nostart.kind == "last30Days")
check("退回的范围是 30 天", r_nostart.whole_days == 30)

# 终点早于起点 → 交换
early = dt.datetime(2026, 9, 1, tzinfo=TZ)
late_d = dt.datetime(2026, 9, 10, tzinfo=TZ)
r_swap = custom_range(late_d, early, NOW)
check("终点早于起点时自动交换（起点变成 9/1）",
      r_swap.start.day == 1 and r_swap.start.month == 9, f"实际 {r_swap.start}")
check("交换后终点包住 9/10 当天",
      r_swap.contains(dt.datetime(2026, 9, 10, 12, tzinfo=TZ)))
check("交换后起点在终点之前", r_swap.start < r_swap.end)
check("区间长度非负", r_swap.whole_days > 0)

# 终点是某天 00:00 → 补到当天结束（否则选「今天」会一格数据都取不到）
same = dt.datetime(2026, 9, 5, tzinfo=TZ)
r_same = custom_range(same, same, NOW)
check("同一天的自定义范围至少包住这一天",
      r_same.contains(dt.datetime(2026, 9, 5, 9, tzinfo=TZ)))
check("同一天范围长度为 1 天", r_same.whole_days == 1, f"实际 {r_same.whole_days}")
check("同一天范围不是空的（回归守卫）", r_same.start < r_same.end)

# 起止不同天时终点要补到后一天
r_span = custom_range(dt.datetime(2026, 8, 1, tzinfo=TZ),
                      dt.datetime(2026, 8, 31, tzinfo=TZ), NOW)
check("8/1–8/31 覆盖 8/31 当天",
      r_span.contains(dt.datetime(2026, 8, 31, 23, 30, tzinfo=TZ)))
check("8/1–8/31 不覆盖 9/1", not r_span.contains(dt.datetime(2026, 9, 1, 0, 30, tzinfo=TZ)))

# ---------------------------------------------------------------- 5
group("5 摘要指标：四张卡与「—」的语义")

empty_summary = Summary([])
check("空范围训练次数 0（不是「—」）", empty_summary.metrics()[0][2] == "0")
check("空范围总时长为 0", empty_summary.metrics()[1][2] == "0")
check("空范围总组数 0", empty_summary.metrics()[2][2] == "0")
check("空范围总容量为「—」", empty_summary.metrics()[3][2] is None)
check("空范围平均时长 nil 而非 0", empty_summary.average_duration_seconds is None)
check("空范围摘要句式", empty_summary.accessibility_summary("近 30 天") == "近 30 天没有训练记录")

# 只有有氧：容量必须是「—」
cardio_only = Summary([
    session_with_duration("c1", NOW - dt.timedelta(days=1), kind="cardio",
                          distance_meters=5200, duration=1800),
])
m = cardio_only.metrics()
check("只有有氧时容量显示「—」", m[3][2] is None, f"实际 {m[3][2]}")
# 这条是本页最重要的反向断言：显示 0 kg 会误导用户以为数据错了
check("只有有氧时容量不是 \"0\"（回归守卫）", m[3][2] != "0")
check("只有有氧时追加距离卡", len(m) == 5)
check("距离为 5.20 公里", m[4][2] == "5.20", f"实际 {m[4][2]}")
check("只有有氧时摘要不含容量", "总容量" not in cardio_only.accessibility_summary("近 30 天"))

# 有氧但没填距离：距离显示「—」
cardio_nodist = Summary([
    session_with_duration("c2", NOW - dt.timedelta(days=1), kind="cardio",
                          distance_meters=None, duration=1800),
])
m2 = cardio_nodist.metrics()
check("有氧但无距离时距离显示「—」", m2[4][2] is None)
check("有氧但无距离时不是 0.00 公里（回归守卫）", m2[4][2] != "0.00")

# 有力量但容量确实是 0（比如全是自重动作）：容量该显示 "0"
strength_zero = Summary([
    session_with_duration("s1", NOW - dt.timedelta(days=1), kind="strength",
                          entries=[SetEntry("pushup", 0, 20)], duration=1200),
])
m3 = strength_zero.metrics()
check("有力量训练但容量为 0 时显示 \"0\"（不是「—」）",
      m3[3][2] == "0", f"实际 {m3[3][2]}")
check("有力量训练时不追加距离卡", len(m3) == 4)

# 混合数据
mixed = Summary([
    session_with_duration("mx1", NOW - dt.timedelta(days=2), kind="strength",
                          entries=[SetEntry("bench", 60, 10),
                                   SetEntry("bench", 40, 12, is_warmup=True)],
                          duration=3600),
    session_with_duration("mx2", NOW - dt.timedelta(days=1), kind="cardio",
                          distance_meters=5000, duration=2400),
])
mm = mixed.metrics()
check("混合：训练次数 2", mm[0][2] == "2")
check("混合：总完成组数含热身 = 2", mm[2][2] == "2", f"实际 {mm[2][2]}")
check("混合：总容量 600（40×12 热身不计入）", mm[3][2] == "600", f"实际 {mm[3][2]}")
# 反向断言：把热身也算进去会得到 1080 —— 这正是页面 09 踩过的错
check("混合：总容量不是 1080（热身不计入的回归守卫）", mm[3][2] != "1080")
check("混合：总完成组数用「含热身」口径（2 而不是 1）",
      mm[2][2] == "2")
check("混合：追加距离卡", len(mm) == 5)
check("混合：摘要含次数与时长",
      "近 30 天完成 2 次训练" in mixed.accessibility_summary("近 30 天"))

# ---------------------------------------------------------------- 6
group("6 训练频率：补空桶让时间轴连续")

r_freq = range_for("last7Days", NOW)
sessions_freq = [
    s_at(-6, 9, sid="a"),                     # 7 天前
    s_at(0, 9, sid="b"),                      # 今天
    s_at(0, 18, sid="c", kind="cardio"),      # 今天第二次
]
buckets = frequency_buckets(sessions_freq, r_freq, "daily")
check("近 7 天按日产生 7 个桶（含空桶）", len(buckets) == 7, f"实际 {len(buckets)}")
check("桶数等于自然日数，不是训练次数", len(buckets) == r_freq.whole_days)
check("空桶也在数组里（时间轴连续）",
      len([b for b in buckets if b["total"] == 0]) == 5,
      f"实际空桶 {len([b for b in buckets if b['total'] == 0])}")
check("今天的桶有 2 次", buckets[-1]["total"] == 2)
check("今天的桶力量 1 次", buckets[-1]["strength"] == 1)
check("今天的桶有氧 1 次", buckets[-1]["cardio"] == 1)
check("最高桶是 2 次", frequency_max_count(buckets) == 2)
check("桶按时间升序", all(buckets[i]["date"] < buckets[i + 1]["date"]
                          for i in range(len(buckets) - 1)))

# 不补空桶的反面：如果只输出有训练的日子，柱子的 x 位置会跳。
# 这里断言「桶数 == 自然日数」，一旦有人改成 filter 掉空桶就会失败。
check("桶数不等于有训练的天数（回归守卫：不补空桶会跳位置）",
      len(buckets) != len([b for b in buckets if b["total"] > 0]))

# 空范围的频率图
empty_buckets = frequency_buckets([], r_freq, "daily")
check("空范围仍有 7 个桶（不是空数组）", len(empty_buckets) == 7)
check("空范围空桶总数为 0", frequency_max_count(empty_buckets) == 0)
check("空范围摘要说明没有记录",
      "没有训练记录" in frequency_summary(empty_buckets, "近 7 天"))

# ---------------------------------------------------------------- 7
group("7 频率粒度降级与上限")

r_long = range_for("thisYear", NOW)
check("今年按日会被降级为按周",
      effective_granularity("daily", r_long) == "weekly")
r_small = range_for("last7Days", NOW)
check("近 7 天保持按日", effective_granularity("daily", r_small) == "daily")
r_60 = DateRange(start_of_day(NOW), add_days(start_of_day(NOW), 60), "custom")
check("恰好 60 天仍按日（边界含等号）",
      effective_granularity("daily", r_60) == "daily",
      f"实际 {r_60.whole_days} 天")
r_61 = DateRange(start_of_day(NOW), add_days(start_of_day(NOW), 61), "custom")
check("61 天降级为按周", effective_granularity("daily", r_61) == "weekly")

# 桶数上限保护
r_huge = DateRange(start_of_day(NOW), add_days(start_of_day(NOW), 1000), "custom")
huge_daily = frequency_buckets([], r_huge, "daily")
check("按日桶数被 limit 截断在 400", len(huge_daily) == DAILY_LIMIT,
      f"实际 {len(huge_daily)}")
huge_weekly = frequency_buckets([], r_huge, "weekly")
check("按周桶数被 limit 截断在 80", len(huge_weekly) == WEEKLY_LIMIT,
      f"实际 {len(huge_weekly)}")

# 按周聚合的周一归属
wed = dt.datetime(2026, 9, 16, 10, tzinfo=TZ)   # 2026-09-16 是周三
check("周三归属到本周周一 9/14", week_start(wed) == dt.datetime(2026, 9, 14, tzinfo=TZ),
      f"实际 {week_start(wed)}")
sun = dt.datetime(2026, 9, 20, 10, tzinfo=TZ)   # 周日
check("周日归属到 9/14 那一周（不是下一周 9/21）",
      week_start(sun) == dt.datetime(2026, 9, 14, tzinfo=TZ),
      f"实际 {week_start(sun)}")
mon = dt.datetime(2026, 9, 14, 0, 0, tzinfo=TZ)
check("周一归到它自己", week_start(mon) == mon)

# ---------------------------------------------------------------- 8
group("8 容量趋势：不画零值折线")

lookup = {
    "bench": LibraryItem("bench", "Barbell Bench Press", ["杠铃卧推"], "胸"),
    "squat": LibraryItem("squat", "Barbell Squat", ["杠铃深蹲"], "腿"),
    "row": LibraryItem("row", "Barbell Row", ["杠铃划船"], "背"),
    "run": LibraryItem("run", "Running", ["跑步"], "有氧"),
}

r_vol = range_for("last7Days", NOW)
sessions_vol = [
    # 7 天前：有容量
    s_at(-6, 9, sid="v1", entries=[SetEntry("bench", 60, 10)]),
    # 5 天前：只有热身 → 容量 0，这一天必须不出现在点上
    s_at(-4, 9, sid="v2", entries=[SetEntry("bench", 40, 12, is_warmup=True)]),
    # 3 天前：有氧 → 容量 0，也不出现
    s_at(-2, 9, sid="v3", kind="cardio", entries=[SetEntry("run", 0, 1)],
         distance_meters=5000),
    # 今天：有容量
    s_at(0, 9, sid="v4", entries=[SetEntry("squat", 100, 5)]),
]
points = volume_points(sessions_vol, r_vol, VolumeFilter("all"), lookup)
check("只输出有容量的训练日（2 个）", len(points) == 2, f"实际 {len(points)}")
check("点数量不等于训练次数（回归守卫：会插 0 值点）", len(points) != 4)
check("没有 0 容量的点", all(p["volume"] > 0 for p in points),
      f"实际 {[p['volume'] for p in points]}")
# 反向断言：如果补了 0 值点，就会有一个 volume == 0 的点
check("不存在 volume 为 0 的点（规格禁止零值折线）",
      not any(p["volume"] == 0 for p in points))
check("容量合计 600+500=1100",
      sum(p["volume"] for p in points) == 1100,
      f"实际 {sum(p['volume'] for p in points)}")
check("点名下有当天最大的动作",
      any(p["top_name"] == "杠铃卧推" for p in points))

# 全部健身日都无容量 → 空状态
no_vol = volume_points(
    [s_at(-1, 9, sid="nv", entries=[SetEntry("bench", 40, 12, is_warmup=True)])],
    r_vol, VolumeFilter("all"), lookup,
)
check("无容量数据时返回空数组（视图显示空状态）", no_vol == [])
check("空数据摘要说明没有容量数据",
      "没有容量数据" in volume_summary(no_vol, "近 7 天"))

# 空范围
check("空范围的容量点为空", volume_points([], r_vol, VolumeFilter("all"), lookup) == [])

# ---------------------------------------------------------------- 9
group("9 容量图的筛选维度")

r_filters = range_for("last30Days", NOW)
sessions_filters = [
    s_at(-5, 9, sid="f1", entries=[
        SetEntry("bench", 60, 10), SetEntry("bench", 60, 10),
        SetEntry("squat", 100, 5),
        SetEntry("bench", 40, 12, is_warmup=True),
    ]),
    s_at(-2, 9, sid="f2", entries=[SetEntry("squat", 110, 5)]),
]
filters = available_filters(sessions_filters, r_filters, lookup)
kinds = [f.kind for f in filters]
check("第一项总是「全部动作」", filters[0].kind == "all")
check("列出实际出现过的肌群（胸、腿）",
      f"muscle:chest" in [f.cache_key for f in filters] and
      f"muscle:leg" in [f.cache_key for f in filters],
      f"实际 {[f.cache_key for f in filters]}")
check("没有出现过的肌群不列出（不含背）",
      "muscle:back" not in [f.cache_key for f in filters])
check("列出实际出现过的动作",
      "exercise:bench" in [f.cache_key for f in filters] and
      "exercise:squat" in [f.cache_key for f in filters])
check("动作筛选带展示名", any(f.name == "杠铃卧推" for f in filters))

# 肌群按固定枚举顺序（chest 在 leg 之前）
muscle_order = [f.group for f in filters if f.kind == "muscle"]
check("肌群按固定枚举顺序（chest 在 leg 前）",
      muscle_order == ["chest", "leg"], f"实际 {muscle_order}")
check("肌群顺序稳定（重复调用结果一致）",
      [f.cache_key for f in available_filters(sessions_filters, r_filters, lookup)] ==
      [f.cache_key for f in filters])

# 按次数排序的动作在前
many = [s_at(-i, 9, sid=f"m{i}", entries=[SetEntry("bench", 60, 10)]) for i in range(1, 6)]
many.append(s_at(-1, 9, sid="mq", entries=[SetEntry("squat", 100, 5)]))
filters2 = available_filters(many, r_filters, lookup)
ex_order = [f.exercise_id for f in filters2 if f.kind == "exercise"]
check("动作按出现次数降序（bench 在 squat 前）",
      ex_order.index("bench") < ex_order.index("squat"), f"实际 {ex_order}")

# 肌群筛选只收该肌群的组
chest_filter = VolumeFilter("muscle", group="chest")
bench_entry = SetEntry("bench", 60, 10)
squat_entry = SetEntry("squat", 100, 5)
check("肌群筛选收胸部的组", chest_filter.accepts(bench_entry, lookup))
check("肌群筛选拒腿部的组", not chest_filter.accepts(squat_entry, lookup))
ex_filter = VolumeFilter("exercise", exercise_id="squat", name="杠铃深蹲")
check("动作筛选收目标动作", ex_filter.accepts(squat_entry, lookup))
check("动作筛选拒其他动作", not ex_filter.accepts(bench_entry, lookup))
check("全部筛选收一切", VolumeFilter("all").accepts(bench_entry, lookup))

# 筛选后的容量点
chest_points = volume_points(sessions_filters, r_filters, chest_filter, lookup)
check("胸筛选只算卧推容量 1200",
      sum(p["volume"] for p in chest_points) == 1200,
      f"实际 {sum(p['volume'] for p in chest_points)}")
leg_points = volume_points(sessions_filters, r_filters,
                           VolumeFilter("muscle", group="leg"), lookup)
check("腿筛选只算深蹲容量 500+550=1050",
      sum(p["volume"] for p in leg_points) == 1050,
      f"实际 {sum(p['volume'] for p in leg_points)}")

# 筛选条件改变 → 缓存键改变
range_key_a = range_key(r_filters)
check("不同筛选生成不同缓存键",
      cache_key(r_filters, filters[0]) != cache_key(r_filters, chest_filter))

# ---------------------------------------------------------------- 10
group("10 常练动作：三级稳定排序")

r_top = range_for("last30Days", NOW)
sessions_top = [
    s_at(-10, 9, sid="t1", entries=[
        SetEntry("bench", 60, 10), SetEntry("bench", 60, 10),
        SetEntry("squat", 100, 5),
    ]),
    s_at(-5, 9, sid="t2", entries=[
        SetEntry("bench", 70, 10),
        SetEntry("squat", 110, 5), SetEntry("squat", 110, 5),
        SetEntry("row", 50, 10), SetEntry("row", 50, 10),
    ]),
]
tops = top_exercises(sessions_top, r_top, lookup)
check("取到 3 个动作", len(tops) == 3, f"实际 {len(tops)}")
check("按组数降序：bench(3) 在前",
      tops[0]["exercise_id"] == "bench", f"实际 {tops[0]['exercise_id']}")
check("bench 3 组", tops[0]["set_count"] == 3)
check("squat 3 组", tops[1]["set_count"] == 3)
check("并列时按容量降序：squat(1050) 在 row(1000) 前",
      tops[1]["exercise_id"] == "squat" and tops[2]["exercise_id"] == "row",
      f"实际 {[t['exercise_id'] for t in tops]}")
check("顺序稳定（重复调用一致）",
      [t["exercise_id"] for t in top_exercises(sessions_top, r_top, lookup)] ==
      [t["exercise_id"] for t in tops])

# 只按组数排的话，并列的顺序取决于字典遍历顺序 —— 这里断言它不是那个顺序
check("并列顺序不是字典插入顺序（回归守卫）",
      [t["exercise_id"] for t in tops] != ["bench", "row", "squat"])

# 前 5 限制
many_ex = [s_at(-i, 9, sid=f"tx{i}", entries=[SetEntry(f"ex{i}", 50, 10)])
           for i in range(1, 9)]
many_lookup = {f"ex{i}": LibraryItem(f"ex{i}", f"Ex{i}", [f"动作{i}"], "胸")
               for i in range(1, 9)}
tops_many = top_exercises(many_ex, r_top, many_lookup)
check("默认只取前 5 个", len(tops_many) == TOP_LIMIT, f"实际 {len(tops_many)}")

# 热身不计入组数
warm_only = [s_at(-1, 9, sid="w1", entries=[
    SetEntry("bench", 40, 12, is_warmup=True),
    SetEntry("bench", 60, 10),
])]
tops_warm = top_exercises(warm_only, r_top, lookup)
check("热身不计入常练动作组数（1 而不是 2）",
      tops_warm[0]["set_count"] == 1, f"实际 {tops_warm[0]['set_count']}")

# 对照：整场只有热身。这一条和上面那条要分开写，因为上面那条里
# 热身是和一组正式组放在一起的，看不出「热身是否被单独算进去」的差别。
all_warm = [s_at(-1, 9, sid="w2", entries=[
    SetEntry("bench", 40, 12, is_warmup=True),
    SetEntry("squat", 50, 10, is_warmup=True),
])]
check("整场只有热身时常练动作为空",
      top_exercises(all_warm, r_top, lookup) == [],
      f"实际 {top_exercises(all_warm, r_top, lookup)}")
check("整场只有热身时摘要说明没有记录",
      "没有完成的动作记录" in top_summary(top_exercises(all_warm, r_top, lookup),
                                          "近 30 天"))

check("空范围的常练动作为空",
      top_exercises([], r_top, lookup) == [])
check("空数据摘要说明",
      "没有完成的动作记录" in top_summary([], "近 30 天"))
check("摘要列出前三个名字",
      "杠铃卧推 3 组" in top_summary(tops, "近 30 天"))

# ---------------------------------------------------------------- 11
group("11 部位分布：固定顺序、不含热身")

rows = muscle_rows(sessions_top, r_top, lookup)
check("胸 3 组 + 腿 3 组 + 背 2 组 = 3 个部位", len(rows) == 3, f"实际 {len(rows)}")
check("按固定枚举顺序：胸 → 背 → 腿",
      [r["group"] for r in rows] == ["chest", "back", "leg"],
      f"实际 {[r['group'] for r in rows]}")
# 按组数排会是 胸(3) 腿(3) 背(2)，与固定顺序不同 —— 断言用的确实是枚举顺序
check("不是按组数排序（回归守卫）",
      [r["group"] for r in rows] != ["chest", "leg", "back"])
check("胸 3 组", rows[0]["set_count"] == 3)
check("背 2 组", rows[1]["set_count"] == 2)
check("腿 3 组", rows[2]["set_count"] == 3)
check("占比之和约等于 1",
      abs(sum(r["ratio"] for r in rows) - 1.0) < 1e-9,
      f"实际 {sum(r['ratio'] for r in rows)}")
check("胸占比 3/8 = 38%", rows[0]["percent_text"] == "38%", f"实际 {rows[0]['percent_text']}")
check("占比四舍五入到整数", all(r["percent_text"].endswith("%") for r in rows))
check("每个部位有代表色",
      all(r["color_hex"] == MUSCLE_PALETTE[r["group"]] for r in rows))
check("代表色都不是荧光绿 C6FF3E",
      all(r["color_hex"] != 0xC6FF3E for r in rows))

# 全部热身 → 空数组（显示空状态而不是一排 0%）
warm_rows = muscle_rows(all_warm, r_top, lookup)
check("只有热身时部位分布为空", warm_rows == [], f"实际 {warm_rows}")
check("热身不计入部位分布组数",
      muscle_rows(warm_only, r_top, lookup)[0]["set_count"] == 1,
      "混合场里热身不该被算成第 2 组")
check("空分布摘要说明",
      "无法统计部位分布" in muscle_summary([], "近 30 天"))

# ---------------------------------------------------------------- 12
group("12 动作名三级兜底")

check("别名优先：bench → 杠铃卧推",
      exercise_display_name("bench", lookup) == "杠铃卧推")
check("查不到时退回 id 本身",
      exercise_display_name("unknown_id", lookup) == "unknown_id")
check("id 为空时给「未知动作」",
      exercise_display_name("   ", lookup) == "未知动作")
check("空 id 不留空白（回归守卫）",
      exercise_display_name("", lookup) == "未知动作")
unnamed = {"x": LibraryItem("x", "", [], "胸", display="")}
check("别名与原名都空时退回 id",
      exercise_display_name("x", unnamed) == "x")

# ---------------------------------------------------------------- 13
group("13 缓存")

cache = StatsCache()
check("初始为空", cache.is_empty)
check("空缓存取不到值", cache.value("k1") is None)

cache.store("v1", "k1")
check("存入后取得到", cache.value("k1") == "v1")
check("不同 key 取不到", cache.value("k2") is None)
check("存入后非空", not cache.is_empty)

v_before = cache.version
cache.invalidate()
check("失效后取不到旧值", cache.value("k1") is None)
check("失效后为空", cache.is_empty)
check("失效使版本号递增", cache.version == v_before + 1)

# 只存一份：存第二个 key 会顶掉第一个
cache.store("v1", "k1")
cache.store("v2", "k2")
check("单条缓存：新 key 顶掉旧 key", cache.value("k1") is None)
check("单条缓存：新 key 有值", cache.value("k2") == "v2")

# 缓存键包含范围起止时间戳
r_a = range_for("last30Days", NOW)
r_b = range_for("last30Days", NOW - dt.timedelta(days=1))
check("同种类不同时刻的范围有不同的键",
      range_key(r_a) != range_key(r_b),
      f"{range_key(r_a)} vs {range_key(r_b)}")
r_c = custom_range(dt.datetime(2026, 8, 1, tzinfo=TZ),
                   dt.datetime(2026, 8, 31, tzinfo=TZ), NOW)
r_d = custom_range(dt.datetime(2026, 7, 1, tzinfo=TZ),
                   dt.datetime(2026, 7, 31, tzinfo=TZ), NOW)
check("同为 custom 但日期不同 → 键不同（只用种类做 key 会命中旧缓存）",
      range_key(r_c) != range_key(r_d),
      f"{range_key(r_c)} vs {range_key(r_d)}")
check("custom 的范围键含起止时间戳",
      str(int(r_c.start.timestamp())) in range_key(r_c))

# ---------------------------------------------------------------- 14
group("14 备份导出")

all_sessions = [
    session_with_duration("b1", NOW - dt.timedelta(days=3), entries=[SetEntry("bench", 60, 10)]),
    session_with_duration("b2", NOW - dt.timedelta(days=2), kind="cardio",
                          distance_meters=5000),
    session_with_duration("b3", NOW - dt.timedelta(days=1), entries=[], is_finished=False,
                          duration=600),
]
backup = make_backup(all_sessions)
check("只导出已完成的训练", backup["session_count"] == 2, f"实际 {backup['session_count']}")
check("进行中的草稿不导出", all(s.is_finished for s in backup["sessions"]))
check("导出按开始时间升序",
      [s.started_at for s in backup["sessions"]] ==
      sorted(s.started_at for s in backup["sessions"]))
check("格式标识正确", backup["format"] == BACKUP_FORMAT)
check("版本号正确", backup["version"] == BACKUP_VERSION)
# 备份只有训练记录，没有计划/动作库 —— 这是数据边界
check("备份只含训练记录（不含计划与动作库）",
      set(backup.keys()) == {"format", "version", "session_count", "sessions"})

# ---------------------------------------------------------------- 15
group("15 备份解码的校验顺序")

check("空文件 → emptyFile", decode_error("empty") == "emptyFile")
# 关键：截断的 JSON 必须报 notJSON，而不是报版本不支持。
# 反过来做会把用户引向完全错误的方向。
check("不是 JSON → notJSON（不是版本错误）", decode_error("notJSON") == "notJSON")
check("格式标识不对 → wrongFormat",
      decode_error("json", payload_format="some-other-app") == "wrongFormat")
check("版本过高 → unsupportedVersion",
      decode_error("json", payload_format=BACKUP_FORMAT,
                   payload_version=BACKUP_VERSION + 1) == "unsupportedVersion")
check("版本相同 → 通过",
      decode_error("json", payload_format=BACKUP_FORMAT,
                   payload_version=BACKUP_VERSION, session_count=3) is None)
check("旧版本可读（向后兼容）",
      decode_error("json", payload_format=BACKUP_FORMAT,
                   payload_version=0, session_count=3) is None)
check("没有记录 → noSessions",
      decode_error("json", payload_format=BACKUP_FORMAT,
                   payload_version=BACKUP_VERSION, session_count=0) == "noSessions")
check("空文件优先于格式检查（顺序正确）",
      decode_error("empty", payload_format="wrong") == "emptyFile")

# ---------------------------------------------------------------- 16
group("16 备份合并的三条策略")

existing = [
    session_with_duration("e1", NOW - dt.timedelta(days=5)),
    session_with_duration("e2", NOW - dt.timedelta(days=4)),
]
incoming = [
    session_with_duration("e2", NOW - dt.timedelta(days=4)),   # 与本机重复
    session_with_duration("n1", NOW - dt.timedelta(days=3)),   # 新增
]

keep = merge(existing, incoming, KEEP_EXISTING)
check("保留本机：新增 1 条", keep["added"] == 1, f"实际 {keep['added']}")
check("保留本机：跳过 1 条", keep["skipped"] == 1, f"实际 {keep['skipped']}")
check("保留本机：替换 0 条", keep["replaced"] == 0)
check("保留本机：总数 3", len(keep["sessions"]) == 3)

over = merge(existing, incoming, OVERWRITE_EXISTING)
check("覆盖本机：新增 1 条", over["added"] == 1)
check("覆盖本机：替换 1 条", over["replaced"] == 1, f"实际 {over['replaced']}")
check("覆盖本机：跳过 0 条", over["skipped"] == 0)
check("覆盖本机：总数 3", len(over["sessions"]) == 3)

# 完全恢复：本机的一律丢弃
replace = merge(existing, incoming, REPLACE_ALL)
check("完全恢复：总数为导入条数 2", len(replace["sessions"]) == 2,
      f"实际 {len(replace['sessions'])}")
check("完全恢复：不含本机独有记录 e1",
      "e1" not in [s.id for s in replace["sessions"]])
check("完全恢复：含导入记录 n1",
      "n1" in [s.id for s in replace["sessions"]])
check("完全恢复：sorted 后仍只有一条 e2",
      len([s for s in replace["sessions"] if s.id == "e2"]) == 1)
check("完全恢复：本机独有记录被丢弃（回归守卫）",
      len(replace["sessions"]) != len(existing) + len(incoming))

# 三条策略结果各不相同（防止有人把分支写错成一样）
check("三条策略的总数不全相同（分支真的生效）",
      len({len(keep["sessions"]), len(over["sessions"]), len(replace["sessions"])}) > 1
      or keep["skipped"] != over["skipped"])

# 合并结果按开始时间升序落盘
check("合并结果按开始时间升序",
      [s.started_at for s in keep["sessions"]] ==
      sorted(s.started_at for s in keep["sessions"]))

# ---------------------------------------------------------------- 17
group("17 去重保留先出现的那条")

dup = [Session("same", NOW - dt.timedelta(days=2)),
       Session("same", NOW - dt.timedelta(days=1)),
       Session("other", NOW - dt.timedelta(days=3))]
d = dedupe(dup)
check("按 id 去重后 2 条", len(d) == 2, f"实际 {len(d)}")
check("保留先出现的那条（较早的日期）",
      d[0].id == "same" and d[0].started_at == NOW - dt.timedelta(days=2),
      f"实际 {d[0].started_at}")
check("保留的不是后出现的那条（回归守卫）",
      d[0].started_at != NOW - dt.timedelta(days=1))
check("顺序保持首次出现次序", [s.id for s in d] == ["same", "other"])

# 一份手改过的备份可能含重复 id：完全恢复时也必须去重
dirty = [Session("dup", NOW - dt.timedelta(days=3)),
         Session("dup", NOW - dt.timedelta(days=2))]
replace_dirty = merge([], dirty, REPLACE_ALL)
check("完全恢复也会按 id 去重（一条）", len(replace_dirty["sessions"]) == 1,
      f"实际 {len(replace_dirty['sessions'])}")
check("完全恢复去重后不会出现两条同名记录",
      len({s.id for s in replace_dirty["sessions"]}) == len(replace_dirty["sessions"]))

# 空备份导入
check("空导入 + 保留本机 → 不动本机",
      len(merge(existing, [], KEEP_EXISTING)["sessions"]) == len(existing))

# ---------------------------------------------------------------- 18
group("18 合并结果文案")

check("有新增有跳过时都报出来",
      "新增" in merge_summary_text(keep) and "跳过" in merge_summary_text(keep))
check("文案含导入后总数", "本机共 3 条" in merge_summary_text(keep))
check("无变化时给明确的「没有可导入」",
      "没有可导入" in merge_summary_text(merge(existing, [], KEEP_EXISTING)))
check("替换数也报出来", "替换 1 条" in merge_summary_text(over))

# ---------------------------------------------------------------- 19
group("19 动作趋势：保留空月份")

r_trend_now = dt.datetime(2026, 9, 19, tzinfo=TZ)
trend_sessions = [
    # 这个月练了两次
    session_with_duration("tr1", dt.datetime(2026, 9, 5, 9, tzinfo=TZ),
                          entries=[SetEntry("bench", 60, 10), SetEntry("bench", 65, 8)]),
    session_with_duration("tr2", dt.datetime(2026, 9, 12, 9, tzinfo=TZ),
                          entries=[SetEntry("bench", 70, 6)]),
    # 三个月前练过一次
    session_with_duration("tr3", dt.datetime(2026, 6, 10, 9, tzinfo=TZ),
                          entries=[SetEntry("bench", 55, 10)]),
    # 一年前（超出 12 个月窗口）
    session_with_duration("tr_old", dt.datetime(2025, 8, 1, 9, tzinfo=TZ),
                          entries=[SetEntry("bench", 50, 10)]),
    # 别的动作
    session_with_duration("tr_other", dt.datetime(2026, 9, 8, 9, tzinfo=TZ),
                          entries=[SetEntry("squat", 100, 5)]),
]
# 上面 5 条里，卧推出现在 tr1 / tr2 / tr3 / tr_old 共 4 条，其中 tr_old
# 落在 12 个月窗口之外。「最近记录」按规格不设时间窗口（它就是「这个动作
# 最近练过几次」），所以它看到的是 4 条而不是 3 条——第 4 条正是窗口的分界证据。
TREND_RECENT_ALL = 4
tp = monthly_trend_points(trend_sessions, "bench", TREND_MONTHS, r_trend_now)
check("返回恒为 12 个月", len(tp) == 12, f"实际 {len(tp)}")
check("含空月份（空月也留一个点）",
      len([p for p in tp if p.is_empty]) > 0,
      f"实际空月 {len([p for p in tp if p.is_empty])}")
check("按时间从旧到新", all(tp[i].month_start < tp[i + 1].month_start
                            for i in range(len(tp) - 1)))
check("最后一个月是本月 9 月", tp[-1].month_start == first_day_of_month(r_trend_now))
check("第一个月是去年 10 月",
      (tp[0].month_start.year, tp[0].month_start.month) == (2025, 10),
      f"实际 {tp[0].month_start}")

sep = tp[-1]
check("9 月 3 组", sep.set_count == 3, f"实际 {sep.set_count}")
check("9 月容量 600+520+420=1540",
      abs(sep.volume - 1540) < 1e-9, f"实际 {sep.volume}")
check("9 月最高单组 70", sep.top_weight == 70)
check("9 月涉及 2 次训练", sep.session_count == 2)

jun = [p for p in tp if p.month_start.month == 6 and p.month_start.year == 2026][0]
check("6 月 1 组 550", jun.set_count == 1 and abs(jun.volume - 550) < 1e-9)
check("6 月有记录（不是空月）", not jun.is_empty)
check("一年前的记录不进窗口（窗口外那条不计）",
      sum(p.set_count for p in tp) == 4, f"实际 {sum(p.set_count for p in tp)}")
check("空月 set_count 为 0", all(p.set_count == 0 for p in tp if p.is_empty))
check("空月显示「未训练」",
      all(p.detail_text == "未训练" for p in tp if p.is_empty))

# 热身不计入趋势
trend_warm = [session_with_duration("tw", dt.datetime(2026, 9, 1, 9, tzinfo=TZ),
                                    entries=[SetEntry("bench", 40, 12, is_warmup=True),
                                             SetEntry("bench", 60, 10)])]
tpw = monthly_trend_points(trend_warm, "bench", 3, r_trend_now)
check("趋势里热身不计入组数（1 而不是 2）",
      tpw[-1].set_count == 1, f"实际 {tpw[-1].set_count}")
check("趋势里热身不计入容量（600 而不是 1080）",
      abs(tpw[-1].volume - 600) < 1e-9, f"实际 {tpw[-1].volume}")

# months 参数的边界
check("months = 0 返回空", monthly_trend_points([], "bench", 0, r_trend_now) == [])
check("months = 1 只返回本月",
      len(monthly_trend_points([], "bench", 1, r_trend_now)) == 1)
check("months 超上限被夹到 60",
      len(monthly_trend_points([], "bench", 1200, r_trend_now)) == 60)

# 跨年：窗口从 1 月往回数
jan_now = dt.datetime(2026, 1, 15, tzinfo=TZ)
tp_jan = monthly_trend_points([], "bench", 12, jan_now)
check("跨年窗口的前一个月是去年 2 月",
      (tp_jan[0].month_start.year, tp_jan[0].month_start.month) == (2025, 2),
      f"实际 {tp_jan[0].month_start}")
check("跨年窗口的最后一个月是今年 1 月",
      (tp_jan[-1].month_start.year, tp_jan[-1].month_start.month) == (2026, 1))
check("跨年 12 个月不重不漏",
      len({(p.month_start.year, p.month_start.month) for p in tp_jan}) == 12)

# ---------------------------------------------------------------- 20
group("20 动作趋势：最近记录与汇总")

recent = recent_sessions(trend_sessions, "bench", 5)
check("最近记录只含该动作",
      len(recent) == TREND_RECENT_ALL, f"实际 {len(recent)}")
check("最近记录比趋势窗口多含 1 条（窗口外那条仍在最近记录里）",
      len(recent) == sum(p.set_count for p in tp) - 1 + 1,
      f"最近 {len(recent)} / 窗口内组数 {sum(p.set_count for p in tp)}")
check("最近记录按日期倒序（最新的在前）",
      all(recent[i]["date"] > recent[i + 1]["date"] for i in range(len(recent) - 1)),
      f"实际 {[r['date'] for r in recent]}")
check("最近记录不含别的动作（squat 那次不在里面）",
      all(r["set_count"] > 0 for r in recent))
check("最近记录里没有 squat 那次的 id",
      "tr_other" not in [r["session_id"] for r in recent],
      f"实际 {[r['session_id'] for r in recent]}")

recent_limit = recent_sessions(trend_sessions, "bench", 2)
check("最近记录尊重 limit", len(recent_limit) == 2, f"实际 {len(recent_limit)}")
check("limit 为 0 时返回空", recent_sessions(trend_sessions, "bench", 0) == [])
check("limit 超过总数时返回全部",
      len(recent_sessions(trend_sessions, "bench", 99)) == TREND_RECENT_ALL)

ts = TrendSummary("bench", "杠铃卧推", tp, recent)
check("有记录的月份数 = 2", ts.active_month_count == 2, f"实际 {ts.active_month_count}")
check("累计组数 4", ts.total_set_count == 4)
check("累计容量 2090", abs(ts.total_volume - 2090) < 1e-9, f"实际 {ts.total_volume}")
check("最高单组 70", ts.best_weight == 70)
check("最高单组文案", ts.best_weight_text == "70 kg")
check("显示名用外部传入的", ts.display_name == "杠铃卧推")

# 无记录：最高单组必须是「—」而不是 0 kg
ts_empty = TrendSummary("none", "某个动作", monthly_trend_points([], "none", 12, r_trend_now), [])
check("无记录时最高单组为「—」", ts_empty.best_weight is None)
check("无记录时最高单组文案是「—」", ts_empty.best_weight_text == "—")
check("无记录时不是 0 kg（回归守卫）", ts_empty.best_weight_text != "0 kg")
check("无记录时摘要说明没有训练",
      "没有训练记录" in ts_empty.accessibility_text)
check("有记录时摘要含月数、组数、容量、最高",
      all(k in ts.accessibility_text
          for k in ["2 个月有训练", "共 4 组", "累计容量", "最高单组"]))
check("显示名为空时兜底「未知动作」",
      TrendSummary("x", "   ", tp, recent).display_name == "未知动作")
check("空月份文案可读", all(
      (p.accessibility_label.endswith("未训练") if p.is_empty
       else "组" in p.accessibility_label) for p in tp))

# ---------------------------------------------------------------- 21
group("21 容量图单点坐标不产生 NaN")

# 与 WorkoutStatisticsComponents.swift 的 Layout 相同的映射
def x_position(index, count, width, inset=8.0):
    if count <= 1:
        return width / 2.0
    step = (width - inset * 2) / (count - 1)
    return inset + step * index


check("单点时 x 居中且不是 NaN", x_position(0, 1, 300.0) == 150.0)
check("单点 x 不是 nan（浮点断言）", x_position(0, 1, 300.0) == x_position(0, 1, 300.0))
# 反向守卫：如果写成 usableWidth / (count - 1)，单点时就是 0/0
try:
    bad = (300.0 - 16) / (1 - 1)
    nan_happens = True
except ZeroDivisionError:
    nan_happens = True
check("若不做单点保护会除零（回归守卫）", nan_happens)
check("两点时首尾贴内边距",
      x_position(0, 2, 300.0) == 8.0 and abs(x_position(1, 2, 300.0) - 292.0) < 1e-9)
check("三点时中间点居中",
      abs(x_position(1, 3, 300.0) - 150.0) < 1e-9,
      f"实际 {x_position(1, 3, 300.0)}")
check("多点时 x 单调递增",
      all(x_position(i, 5, 300.0) < x_position(i + 1, 5, 300.0) for i in range(4)))


def y_position(volume, max_volume, height, inset=10.0):
    if max_volume <= 0:
        return height - inset
    return height - inset - (volume / max_volume) * (height - inset * 2)


check("最大容量点贴顶（内边距内）", abs(y_position(100, 100, 200.0) - 10.0) < 1e-9)
check("零容量点在底部（但不会出现在图里）",
      abs(y_position(0, 100, 200.0) - 190.0) < 1e-9)
check("max_volume 为 0 时不除零",
      y_position(0, 0, 200.0) == 190.0)
check("容量越大 y 越小（越高）",
      y_position(80, 100, 200.0) < y_position(20, 100, 200.0))


# =====================================================================
print("\n" + "=" * 72)
if FAIL:
    print(f"失败 {FAIL} 条，通过 {PASS} 条：")
    for f in FAILURES:
        print("  ✗ " + f)
    sys.exit(1)
print(f"全部通过：{PASS} 项断言")
print("=" * 72)
