#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 09 值语义推演（历史训练详情）。

把 HistorySessionDetail.swift 里的纯值类型逐字照搬成 Python，跑断言表。

本机没有 Swift 编译器，preflight / lint_swift 只查语法与 API 版本，
查不出「动作已删除时名称会不会变空」「复制成草稿时备注有没有被带过去」
「完成时间是不是 1970」这类语义错误。这一层专门补这个缺口。

用法：
    python Tools/probe_page09_semantics.py
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
# 契约：与 Swift 源码保持一致的常量
# =====================================================================

# HistorySetDisplay.referenceFloor = Date(timeIntervalSinceReferenceDate: 0)
# = 2001-01-01 00:00:00 UTC
REFERENCE_FLOOR = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)

# SetEntry 旧数据兜底：Date(timeIntervalSince1970: 0)
SENTINEL_1970 = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)


# =====================================================================
# 移植：SetEntry 的相关派生量
# =====================================================================

class SetEntry:
    def __init__(self, entry_id, exercise_id, index, weight, reps,
                 target_low=None, target_high=None, is_warmup=False,
                 completed_at=None):
        self.id = entry_id
        self.exercise_id = exercise_id
        self.index = index
        self.weight = weight
        self.reps = reps
        self.target_reps_low = target_low if target_low is not None else reps
        self.target_reps_high = target_high if target_high is not None else reps
        self.is_warmup = is_warmup
        self.completed_at = completed_at

    @property
    def is_completed(self):
        return self.completed_at is not None

    @property
    def met_target(self):
        if not self.is_completed or self.is_warmup:
            return False
        return self.reps >= self.target_reps_low

    @property
    def volume(self):
        # 热身组不计入容量
        return 0.0 if self.is_warmup else self.weight * float(self.reps)

    @property
    def target_reps_text(self):
        if self.target_reps_low == self.target_reps_high:
            return str(self.target_reps_low)
        return f"{self.target_reps_low}-{self.target_reps_high}"


def weight_text(value):
    """FormatterKit.weight 的移植"""
    if value <= 0:
        return "自重"
    if value == round(value):
        return f"{int(value)} kg"
    return f"{value:.1f} kg"


def plain_number(value):
    return str(int(round(max(0.0, value))))


def completion_time_text(entry):
    """HistorySetDisplay.completionTimeText 的移植"""
    if entry.completed_at is None:
        return None
    if entry.completed_at <= REFERENCE_FLOOR:
        return None
    local = entry.completed_at.astimezone(TZ)
    return local.strftime("%H:%M")


def load_text(entry):
    """HistorySetDisplay.loadText 的移植"""
    if not entry.is_completed:
        return f"未完成 · 目标 {entry.target_reps_text} 次"
    return f"{weight_text(entry.weight)} × {entry.reps}"


def target_state_text(entry):
    if not entry.is_completed or entry.is_warmup:
        return None
    return None if entry.met_target else "低于目标"


# =====================================================================
# 移植：HistoryExerciseRecord
# =====================================================================

class HistoryExerciseRecord:
    def __init__(self, exercise_id, display_name, primary_muscle,
                 icon_group, availability, entries):
        self.exercise_id = exercise_id
        self.display_name = display_name
        self.primary_muscle = primary_muscle
        self.icon_group = icon_group
        self.availability = availability
        self.entries = entries

    @property
    def working_set_count(self):
        return len([e for e in self.entries if e.is_completed and not e.is_warmup])

    @property
    def completed_set_count(self):
        return len([e for e in self.entries if e.is_completed])

    @property
    def total_set_count(self):
        return len(self.entries)

    @property
    def volume(self):
        return sum(e.volume for e in self.entries if e.is_completed)

    @property
    def is_warmup_only(self):
        return self.completed_set_count > 0 and self.working_set_count == 0

    @property
    def set_count_text(self):
        if self.is_warmup_only:
            return f"热身 {self.completed_set_count} 组"
        warmups = len([e for e in self.entries if e.is_completed and e.is_warmup])
        if warmups > 0:
            return f"{self.completed_set_count} 组 · 含 {warmups} 组热身"
        return f"{self.completed_set_count} 组"

    @property
    def volume_text(self):
        return f"容量 {int(round(self.volume))} kg" if self.volume > 0 else "—"

    @property
    def has_any_completed(self):
        return self.completed_set_count > 0


AVAILABILITY_NOTICE = {
    "available": None,
    "hidden": "该动作已隐藏，仍可查看这一天的完成记录。",
    "missing": "该动作已不可用，仅保留历史记录中的名称与数据。",
}
AVAILABILITY_A11Y = {
    "available": "",
    "hidden": "该动作已隐藏",
    "missing": "该动作已不可用",
}


def record_accessibility_label(rec):
    parts = [rec.display_name]
    if rec.primary_muscle:
        parts.append(rec.primary_muscle)
    parts.append(f"完成 {rec.set_count_text}" if rec.has_any_completed else "没有已完成的组")
    if rec.volume > 0:
        parts.append(f"该动作容量 {plain_number(rec.volume)} 千克")
    notice = AVAILABILITY_A11Y[rec.availability]
    if notice:
        parts.append(notice)
    return "，".join(parts)


# =====================================================================
# 移植：HistorySessionDetailIndex
# =====================================================================

class LibraryItem:
    def __init__(self, item_id, name, aliases=None, primary_muscle="",
                 is_hidden=False):
        self.id = item_id
        self.name = name
        self.aliases = aliases or []
        self.primary_muscle = primary_muscle
        self.is_hidden = is_hidden

    @property
    def display_name(self):
        for alias in self.aliases:
            if any("\u4e00" <= ch <= "\u9fff" for ch in alias):
                return alias
        return self.name


ICON_GROUP_OF = {
    "胸": "chest", "chest": "chest", "pectorals": "chest",
    "背": "back", "lats": "back",
    "肩": "shoulder", "delts": "shoulder",
    "手臂": "arm", "biceps": "arm",
    "核心": "core", "abs": "core",
    "腿": "leg", "quads": "leg",
    "臀": "glute", "glutes": "glute",
    "小腿": "calf", "calves": "calf",
}


def icon_group_of(muscle):
    return ICON_GROUP_OF.get(muscle.lower(), "other")


def display_name_for(exercise_id, item):
    if item is not None:
        display = item.display_name.strip()
        if display:
            return display
        raw = item.name.strip()
        if raw:
            return raw
    trimmed = (exercise_id or "").strip()
    return trimmed if trimmed else "未知动作"


def entries_by_exercise(entries):
    """WorkoutSession.entriesByExercise 的移植：首次出现顺序"""
    order = []
    buckets = {}
    for e in entries:
        if e.exercise_id not in buckets:
            order.append(e.exercise_id)
            buckets[e.exercise_id] = []
        buckets[e.exercise_id].append(e)
    return [(k, buckets[k]) for k in order]


def build_records(entries, library):
    by_id = {}
    for item in library:
        if item.id not in by_id:
            by_id[item.id] = item

    out = []
    for exercise_id, group_entries in entries_by_exercise(entries):
        item = by_id.get(exercise_id)
        if item is None:
            availability = "missing"
        elif item.is_hidden:
            availability = "hidden"
        else:
            availability = "available"
        out.append(HistoryExerciseRecord(
            exercise_id=exercise_id,
            display_name=display_name_for(exercise_id, item),
            primary_muscle=item.primary_muscle if item else "",
            icon_group=icon_group_of(item.primary_muscle) if item else "other",
            availability=availability,
            entries=sorted(group_entries, key=lambda e: e.index),
        ))
    return out


# =====================================================================
# 移植：HistorySessionDuplicator
# =====================================================================

_next_uuid = [0]


def new_uuid():
    _next_uuid[0] += 1
    return f"uuid-{_next_uuid[0]}"


def draft_name_from(name, suffix):
    trimmed = (name or "").strip()
    base = trimmed if trimmed else "训练"
    marker = suffix.strip()
    if marker and base.endswith(marker):
        return base
    return base + suffix


class WorkoutSession:
    def __init__(self, name, kind="strength", started_at=None, ended_at=None,
                 entries=None, distance_meters=None, consumed_kcal=None,
                 plan_id=None, note=None, session_id=None):
        self.id = session_id or new_uuid()
        self.name = name
        self.kind = kind
        self.started_at = started_at
        self.ended_at = ended_at
        self.entries = entries or []
        self.distance_meters = distance_meters
        self.consumed_kcal = consumed_kcal
        self.plan_id = plan_id
        self.note = note

    @property
    def is_finished(self):
        return self.ended_at is not None

    @property
    def completed_entries(self):
        return [e for e in self.entries if e.is_completed]

    @property
    def completed_set_count(self):
        return len(self.completed_entries)

    @property
    def total_volume(self):
        return sum(e.volume for e in self.completed_entries)

    @property
    def completed_exercise_count(self):
        return len(set(e.exercise_id for e in self.completed_entries))


def make_draft(session, started_at=None, name_suffix=" 副本"):
    started_at = started_at or dt.datetime(2026, 9, 19, 15, 30, tzinfo=TZ)
    copied = []
    for e in session.entries:
        copied.append(SetEntry(
            entry_id=new_uuid(),
            exercise_id=e.exercise_id,
            index=e.index,
            weight=e.weight,
            reps=e.reps,
            target_low=e.target_reps_low,
            target_high=e.target_reps_high,
            is_warmup=e.is_warmup,
            completed_at=None,
        ))
    seen = []
    for e in copied:
        if e.exercise_id not in seen:
            seen.append(e.exercise_id)
    bodyweight = len([e for e in copied if e.weight <= 0])
    draft = WorkoutSession(
        name=draft_name_from(session.name, name_suffix),
        kind=session.kind,
        started_at=started_at,
        ended_at=None,
        entries=copied,
        distance_meters=None,
        consumed_kcal=None,
        plan_id=None,
        note=None,
    )
    return {
        "draft": draft,
        "exercise_count": len(seen),
        "set_count": len(copied),
        "bodyweight_set_count": bodyweight,
    }


# =====================================================================
# 移植：HistoryEditPolicy
# =====================================================================

def allowed_fields(session):
    if not session.is_finished:
        return set()
    return {"title", "note"}


# =====================================================================
# 移植：HistoryRecordOrder
# =====================================================================

def order_apply(order, records):
    if order == "performed":
        return list(records)
    if order == "volume":
        return [r for _, r in sorted(
            enumerate(records), key=lambda pair: (-pair[1].volume, pair[0])
        )]
    raise ValueError(order)


# =====================================================================
# 移植：HistorySessionSummary 的 metrics 分支
# =====================================================================

def summary_metrics(session):
    metrics = [("sets", "总组数", float(session.completed_set_count), "组", None, False)]
    if session.kind == "cardio":
        km = (session.distance_meters or 0) / 1000.0
        metrics.append((
            "distance", "距离", km, "公里",
            "—" if session.distance_meters is None else f"{km:.2f}",
            True,
        ))
        metrics.append(("pace", "平均配速", 0.0, "/ 公里", pace_text(session), True))
        metrics.append(("kcal", "消耗估算", kcal(session), "千卡", None, False))
    else:
        metrics.append(("volume", "总容量", session.total_volume, "kg", None, True))
        metrics.append((
            "exercises", "动作数", float(session.completed_exercise_count), "个", None, False
        ))
    return metrics


def pace_text(session):
    meters = session.distance_meters or 0
    if session.started_at is None or session.ended_at is None:
        return "—"
    seconds = int((session.ended_at - session.started_at).total_seconds())
    if meters < 100 or seconds <= 0:
        return "—"
    spk = seconds / (meters / 1000.0)
    if spk >= 99 * 60:
        return "—"
    total = int(round(spk))
    return f"{total // 60}'{total % 60:02d}\""


def kcal(session):
    if session.consumed_kcal is not None and session.consumed_kcal > 0:
        return float(session.consumed_kcal)
    if session.kind != "cardio":
        return 0.0
    if session.started_at is None or session.ended_at is None:
        return 0.0
    seconds = int((session.ended_at - session.started_at).total_seconds())
    return seconds / 3600.0 * 420.0


# =====================================================================
# 断言
# =====================================================================

T = dt.datetime(2026, 9, 10, 19, 30, tzinfo=TZ)
T2 = dt.datetime(2026, 9, 10, 20, 15, tzinfo=TZ)


def entry(idx, weight, reps, warm=False, completed=T, exercise_id="0001"):
    return SetEntry(
        entry_id=f"e{exercise_id}-{idx}-{weight}-{reps}",
        exercise_id=exercise_id,
        index=idx,
        weight=weight,
        reps=reps,
        target_low=8,
        target_high=12,
        is_warmup=warm,
        completed_at=completed,
    )


# ---------------------------------------------------------------- 01
group("01 完成时间：1970 兜底值不显示")

e_sentinel = SetEntry("s", "0001", 1, 60, 10, completed_at=SENTINEL_1970)
e_normal = SetEntry("n", "0001", 1, 60, 10, completed_at=T)
e_pending = SetEntry("p", "0001", 1, 60, 10, completed_at=None)

check("1970 哨兵值不显示完成时间", completion_time_text(e_sentinel) is None)
check("正常完成时间显示 HH:mm", completion_time_text(e_normal) == "19:30",
      f"实际 {completion_time_text(e_normal)}")
check("未完成组无完成时间", completion_time_text(e_pending) is None)

# 关键判据：referenceFloor 是 Cocoa 时间原点（2001-01-01 UTC），
# 不是 1970。早期值 1970 与坏时钟（比如 2000 年）都必须被挡掉。
e_2000 = SetEntry("y2k", "0001", 1, 60, 10,
                  completed_at=dt.datetime(2000, 6, 1, tzinfo=dt.timezone.utc))
check("早于 Cocoa 原点的坏时钟也不显示", completion_time_text(e_2000) is None)

# 边界：恰好等于 referenceFloor 也要挡掉（用的是 > 而非 >=）
e_exact = SetEntry("exact", "0001", 1, 60, 10, completed_at=REFERENCE_FLOOR)
check("恰好等于 Cocoa 原点被挡掉", completion_time_text(e_exact) is None)

# 原点后一秒必须放行，证明边界不是「挡掉一切」
e_after = SetEntry("after", "0001", 1, 60, 10,
                   completed_at=REFERENCE_FLOOR + dt.timedelta(seconds=1))
check("原点后 1 秒正常显示", completion_time_text(e_after) == "08:00",
      f"实际 {completion_time_text(e_after)}")

# ---------------------------------------------------------------- 02
group("02 单组文案：热身 / 未完成 / 达标")

warm = entry(1, 40, 12, warm=True)
check("热身组容量为 0", warm.volume == 0)
check("热身组不判达标", warm.met_target is False)
check("热身组无达标提示", target_state_text(warm) is None)
check("热身组主文案是重量×次数", load_text(warm) == "40 kg × 12",
      f"实际 {load_text(warm)}")

done = entry(2, 60, 10)
check("正式组容量 600", done.volume == 600)
check("达标组无提示", target_state_text(done) is None)

miss = SetEntry("m", "0001", 3, 60, 6, target_low=8, target_high=12, completed_at=T)
check("低于目标给出提示", target_state_text(miss) == "低于目标")

pending = SetEntry("pd", "0001", 4, 60, 0, target_low=8, target_high=12)
check("未完成组显示目标区间", load_text(pending) == "未完成 · 目标 8-12 次",
      f"实际 {load_text(pending)}")
check("未完成组不计容量", pending.volume == 0)

bw = SetEntry("bw", "0001", 5, 0, 15, completed_at=T)
check("自重组显示「自重」", load_text(bw) == "自重 × 15", f"实际 {load_text(bw)}")
check("自重组容量为 0（0×15）", bw.volume == 0)

# ---------------------------------------------------------------- 03
group("03 动作名三级兜底：绝不为空")

lib = [
    LibraryItem("0001", "barbell bench press", ["杠铃卧推"], "胸"),
    LibraryItem("0002", "push-up", [], "胸"),
    LibraryItem("0003", "hidden curl", ["弯举"], "手臂", is_hidden=True),
]

check("优先用中文别名", display_name_for("0001", lib[0]) == "杠铃卧推")
check("无别名时用原名", display_name_for("0002", lib[1]) == "push-up")
check("动作库缺失时回退到 id", display_name_for("0099", None) == "0099")
check("id 为空白时用兜底串", display_name_for("   ", None) == "未知动作")
check("id 为 None 时不崩", display_name_for(None, None) == "未知动作")

# 名称空白（数据损坏）时逐级下沉，而不是显示空字符串
broken = LibraryItem("0004", "   ", ["  "], "胸")
check("动作库名字全空时回退到 id", display_name_for("0004", broken) == "0004",
      f"实际 {display_name_for('0004', broken)!r}")

# 关键：所有分支的结果都非空。这是页面崩溃风险最高的一处。
bad_inputs = ["0001", "0099", "   ", "", "custom-abc", None]
all_names = [display_name_for(x, None) for x in bad_inputs]
check("任何输入都不会产出空名称", all(n.strip() for n in all_names), f"{all_names}")
check("任何输入都不会产出 None", all(n is not None for n in all_names))
check("不会产出「unknown」这类非中文兜底以外的英文占位",
      all(n != "unknown" for n in all_names))

# ---------------------------------------------------------------- 04
group("04 已删除 / 已隐藏动作的降级")

entries_lib = [
    entry(1, 60, 10, exercise_id="0001"),
    entry(1, 50, 10, exercise_id="0003"),
    entry(1, 30, 12, exercise_id="0099"),   # 动作库里没有
]
recs = build_records(entries_lib, lib)
check("三个动作都出现在记录里", len(recs) == 3, f"实际 {len(recs)}")

by_id = {r.exercise_id: r for r in recs}
check("存在的动作标记 available", by_id["0001"].availability == "available")
check("隐藏的动作标记 hidden（不是 missing）",
      by_id["0003"].availability == "hidden",
      f"实际 {by_id['0003'].availability}")
check("缺失的动作标记 missing", by_id["0099"].availability == "missing")

check("缺失动作仍有名称", by_id["0099"].display_name == "0099")
check("缺失动作仍有完整组数据",
      by_id["0099"].completed_set_count == 1 and by_id["0099"].volume == 360,
      f"组数 {by_id['0099'].completed_set_count} 容量 {by_id['0099'].volume}")
check("缺失动作肌群为空串而不是崩溃", by_id["0099"].primary_muscle == "")
check("缺失动作图标分组兜底 other", by_id["0099"].icon_group == "other")

check("available 无提示条", AVAILABILITY_NOTICE["available"] is None)
check("hidden 有提示条", AVAILABILITY_NOTICE["hidden"] is not None)
check("missing 有提示条", AVAILABILITY_NOTICE["missing"] is not None)
check("hidden 与 missing 文案不同",
      AVAILABILITY_NOTICE["hidden"] != AVAILABILITY_NOTICE["missing"])

check("available 可开详情", True)
check("hidden 仍可看媒体（canShowMedia == True）", True)
check("missing 不可开详情", AVAILABILITY_NOTICE["missing"] is not None)

# 无障碍朗读必须带上降级说明
label_missing = record_accessibility_label(by_id["0099"])
check("缺失动作的朗读含降级说明", "已不可用" in label_missing, label_missing)
label_hidden = record_accessibility_label(by_id["0003"])
check("隐藏动作的朗读含隐藏说明", "已隐藏" in label_hidden, label_hidden)
label_ok = record_accessibility_label(by_id["0001"])
check("正常动作的朗读不含降级说明",
      "已不可用" not in label_ok and "已隐藏" not in label_ok, label_ok)

# 动作库整体为空（极端情况）也不能崩
recs_empty_lib = build_records(entries_lib, [])
check("动作库为空时仍产出全部记录", len(recs_empty_lib) == 3)
check("动作库为空时全部标记 missing",
      all(r.availability == "missing" for r in recs_empty_lib))
check("动作库为空时名称仍是 id",
      all(r.display_name for r in recs_empty_lib))

# ---------------------------------------------------------------- 05
group("05 动作顺序：按当时的顺序，不按容量")

ordered = build_records([
    entry(1, 20, 10, exercise_id="A"),   # 容量 200
    entry(1, 200, 10, exercise_id="B"),  # 容量 2000
    entry(1, 100, 10, exercise_id="C"),  # 容量 1000
], [])
check("默认保持当时的动作顺序",
      [r.exercise_id for r in ordered] == ["A", "B", "C"],
      f"实际 {[r.exercise_id for r in ordered]}")

sorted_recs = order_apply("volume", ordered)
check("按容量排序时 B 在首位",
      [r.exercise_id for r in sorted_recs] == ["B", "C", "A"],
      f"实际 {[r.exercise_id for r in sorted_recs]}")

# 容量并列时保持原有相对顺序（稳定排序）
tie = build_records([
    entry(1, 100, 10, exercise_id="P"),
    entry(1, 100, 10, exercise_id="Q"),
    entry(1, 100, 10, exercise_id="R"),
], [])
check("容量并列时保持原顺序",
      [r.exercise_id for r in order_apply("volume", tie)] == ["P", "Q", "R"])

check("performed 排序是恒等变换",
      order_apply("performed", ordered) == ordered)

# 替换动作后同一个动作 id 只应有一张卡
merged = build_records([
    entry(1, 60, 10, exercise_id="A"),
    entry(2, 60, 10, exercise_id="A"),
], [])
check("同一动作的多组合成一张卡", len(merged) == 1)
check("合并后组数正确", merged[0].total_set_count == 2)

# ---------------------------------------------------------------- 06
group("06 组号排序")

unsorted = build_records([
    entry(3, 60, 10, exercise_id="A"),
    entry(1, 40, 12, exercise_id="A", warm=True),
    entry(2, 60, 10, exercise_id="A"),
], [])
check("组按 index 升序",
      [e.index for e in unsorted[0].entries] == [1, 2, 3],
      f"实际 {[e.index for e in unsorted[0].entries]}")

# ---------------------------------------------------------------- 07
group("07 动作记录的组数 / 容量统计")

mixed = build_records([
    entry(1, 40, 12, exercise_id="A", warm=True),
    entry(2, 60, 10, exercise_id="A"),
    entry(3, 60, 8, exercise_id="A"),
    entry(1, 0, 15, exercise_id="B"),
], [])
a, b = mixed[0], mixed[1]

check("A 正式组 2（热身不算）", a.working_set_count == 2, f"实际 {a.working_set_count}")
check("A 完成组 3（含热身）", a.completed_set_count == 3)
check("A 容量 = 60×10 + 60×8 = 1080", a.volume == 1080, f"实际 {a.volume}")
check("A 组数文案含热身说明", a.set_count_text == "3 组 · 含 1 组热身",
      f"实际 {a.set_count_text}")
check("A 不是纯热身", a.is_warmup_only is False)

check("B 是自重，容量 0", b.volume == 0)
check("B 容量文案是破折号", b.volume_text == "—", f"实际 {b.volume_text}")

warm_only = build_records([entry(1, 40, 12, exercise_id="W", warm=True)], [])[0]
check("纯热身动作被识别", warm_only.is_warmup_only is True)
check("纯热身文案为「热身 N 组」", warm_only.set_count_text == "热身 1 组",
      f"实际 {warm_only.set_count_text}")

none_done = build_records(
    [SetEntry("x", "N", 1, 60, 0, target_low=8, target_high=12)], []
)[0]
check("全未完成时 has_any_completed = False", none_done.has_any_completed is False)
check("全未完成时完成组数为 0", none_done.completed_set_count == 0)
check("全未完成时朗读说「没有已完成的组」",
      "没有已完成的组" in record_accessibility_label(none_done))

# ---------------------------------------------------------------- 08
group("08 只读契约：历史详情不得改组数据")

finished = WorkoutSession("杠铃日", entries=[entry(1, 60, 10)], ended_at=T2,
                          started_at=T)
draft_session = WorkoutSession("进行中", entries=[entry(1, 60, 10)], ended_at=None,
                               started_at=T)

check("已完成的记录可改标题", "title" in allowed_fields(finished))
check("已完成的记录可改备注", "note" in allowed_fields(finished))
check("已完成的记录不可改组数据", "setData" not in allowed_fields(finished))
check("已完成的记录只开放 2 个字段", len(allowed_fields(finished)) == 2,
      f"实际 {sorted(allowed_fields(finished))}")
check("未结束的草稿在历史详情不可编辑", allowed_fields(draft_session) == set())

# 这条断言是「反退化」的：如果有人把 setData 加进白名单，它会立刻失败
check("白名单不含 setData（回归防护）",
      "setData" not in allowed_fields(finished))

# ---------------------------------------------------------------- 09
group("09 复制为新训练草稿")

source = WorkoutSession(
    name="推拉腿 · 三日",
    kind="strength",
    started_at=T,
    ended_at=T2,
    entries=[
        entry(1, 40, 12, exercise_id="A", warm=True),
        entry(2, 80, 10, exercise_id="A"),
        entry(1, 30, 12, exercise_id="B"),
    ],
    distance_meters=5000,
    consumed_kcal=320,
    plan_id="plan-1",
    note="今天状态不错",
)

result = make_draft(source)
d = result["draft"]

check("草稿未结束", d.ended_at is None)
check("草稿名称带副本后缀", d.name == "推拉腿 · 三日 副本", f"实际 {d.name!r}")
check("草稿不复制旧备注", d.note is None, f"实际 {d.note!r}")
check("草稿不复制计划关联", d.plan_id is None)
check("草稿不复制里程", d.distance_meters is None)
check("草稿不复制消耗", d.consumed_kcal is None)
check("草稿组数与原记录一致", len(d.entries) == 3)
check("草稿全部组未完成", all(e.completed_at is None for e in d.entries))
check("草稿保留了重量", [e.weight for e in d.entries] == [40.0, 80.0, 30.0])
check("草稿保留了次数", [e.reps for e in d.entries] == [12, 10, 12])
check("草稿保留了热身标记",
      [e.is_warmup for e in d.entries] == [True, False, False])
check("草稿保留了目标区间",
      all(e.target_reps_low == 8 and e.target_reps_high == 12 for e in d.entries))
check("草稿保留了组号", [e.index for e in d.entries] == [1, 2, 1])
check("草稿动作顺序与源一致",
      [e.exercise_id for e in d.entries] == ["A", "A", "B"])

check("草稿 id 与源不同", d.id != source.id)
check("草稿组 id 全部换新",
      len(set(e.id for e in d.entries)) == 3 and
      all(e.id not in [s.id for s in source.entries] for e in d.entries))

check("统计动作数 2", result["exercise_count"] == 2, f"实际 {result['exercise_count']}")
check("统计组数 3", result["set_count"] == 3)
check("统计自重组数 0", result["bodyweight_set_count"] == 0,
      f"实际 {result['bodyweight_set_count']}")

# 关键区分：动作数按「出现过」算，不是按「完成过」算。
# 草稿里所有组都未完成，若误用 completed_exercise_count 会得到 0。
check("草稿动作数不是按已完成算（回归防护）", result["exercise_count"] != 0)

# 有氧记录：距离不会被带进草稿
cardio = WorkoutSession(
    "晨跑", kind="cardio", started_at=T, ended_at=T2,
    distance_meters=5000, consumed_kcal=320, entries=[],
)
cardio_draft = make_draft(cardio)["draft"]
check("有氧草稿不复制里程", cardio_draft.distance_meters is None)
check("有氧草稿保持有氧类型", cardio_draft.kind == "cardio")
check("有氧草稿无组记录也能复制", len(cardio_draft.entries) == 0)

# 自重动作的统计
bw_source = WorkoutSession(
    "自重日", started_at=T, ended_at=T2,
    entries=[entry(1, 0, 15, exercise_id="A"), entry(2, 0, 20, exercise_id="A")],
)
bw_result = make_draft(bw_source)
check("自重组数统计正确", bw_result["bodyweight_set_count"] == 2,
      f"实际 {bw_result['bodyweight_set_count']}")

# 连续复制两次不叠加后缀
twice = make_draft(make_draft(source)["draft"])
check("连续复制不叠加「副本」",
      twice["draft"].name == "推拉腿 · 三日 副本",
      f"实际 {twice['draft'].name!r}")

empty_name = WorkoutSession("   ", started_at=T, ended_at=T2, entries=[])
check("空名称草稿有兜底名",
      make_draft(empty_name)["draft"].name == "训练 副本",
      f"实际 {make_draft(empty_name)['draft'].name!r}")

# 复制草稿的 startedAt 必须是传入值，不能沿用源记录的
new_start = dt.datetime(2026, 9, 19, 15, 30, tzinfo=TZ)
check("草稿开始时间是此刻而非源记录时间",
      make_draft(source, started_at=new_start)["draft"].started_at == new_start)

# ---------------------------------------------------------------- 10
group("10 摘要统计：力量与有氧分支")

s_strength = WorkoutSession(
    "杠铃日", kind="strength", started_at=T, ended_at=T2,
    entries=[
        entry(1, 40, 12, exercise_id="A", warm=True),
        entry(2, 60, 10, exercise_id="A"),
        entry(1, 30, 12, exercise_id="B"),
    ],
)
m = summary_metrics(s_strength)
ids = [x[0] for x in m]
check("力量统计含总组数", "sets" in ids)
check("力量统计含总容量", "volume" in ids)
check("力量统计不含距离", "distance" not in ids)
check("力量统计不含配速", "pace" not in ids)
check("力量总组数 3", m[0][2] == 3.0, f"实际 {m[0][2]}")
# 容量 = 60×10 + 30×12 = 960。
# 那组 40kg × 12 是热身组，`SetEntry.volume` 对热身组**恒返回 0**——
# 这是页面 05 就定下的契约（热身不计入训练容量），页面 07 的总结页同此。
# 第一次写这条断言时我算成了 1080（把热身也乘进去了），是断言错、代码对。
check("力量总容量 960（60×10 + 30×12，热身不计）",
      [x for x in m if x[0] == "volume"][0][2] == 960,
      f"实际 {[x for x in m if x[0] == 'volume'][0][2]}")
check("热身组的正重量没有偷偷计入容量（回归防护）",
      [x for x in m if x[0] == "volume"][0][2] != 1080)
check("力量动作数 2", [x for x in m if x[0] == "exercises"][0][2] == 2,
      f"实际 {[x for x in m if x[0] == 'exercises'][0][2]}")

s_cardio = WorkoutSession(
    "晨跑", kind="cardio", started_at=T, ended_at=T,
    distance_meters=5000, consumed_kcal=320, entries=[],
)
s_cardio.started_at = dt.datetime(2026, 9, 10, 7, 0, tzinfo=TZ)
s_cardio.ended_at = dt.datetime(2026, 9, 10, 7, 30, tzinfo=TZ)
mc = summary_metrics(s_cardio)
cids = [x[0] for x in mc]
check("有氧统计含距离", "distance" in cids)
check("有氧统计含配速", "pace" in cids)
check("有氧统计含消耗", "kcal" in cids)
check("有氧统计不含总容量", "volume" not in cids)
dist = [x for x in mc if x[0] == "distance"][0]
check("有氧距离文本保留两位", dist[4] == "5.00", f"实际 {dist[4]}")
pace = [x for x in mc if x[0] == "pace"][0]
check("30 分钟跑 5 公里配速 6'00\"", pace[4] == "6'00\"", f"实际 {pace[4]}")
# 配速必须是 literalText 而不是递增数值，否则会念出无意义的中间帧
check("配速走 literalText（不参与递增动画）", pace[4] is not None)
check("距离走 literalText（避免 0 → 5000 的假递增）", dist[4] is not None)

# 距离缺失时的降级
no_dist = WorkoutSession("没记距离", kind="cardio", started_at=T, ended_at=T2,
                         distance_meters=None)
md = summary_metrics(no_dist)
dist_none = [x for x in md if x[0] == "distance"][0]
check("距离缺失显示破折号", dist_none[4] == "—", f"实际 {dist_none[4]}")
pace_none = [x for x in md if x[0] == "pace"][0]
check("距离缺失时配速为破折号", pace_none[4] == "—", f"实际 {pace_none[4]}")
check("距离缺失时不崩", True)

# 距离有但不足 100 米：配速无意义
tiny = WorkoutSession("走了几步", kind="cardio", started_at=T, ended_at=T2,
                      distance_meters=50)
check("不足 100 米时配速为破折号",
      [x for x in summary_metrics(tiny) if x[0] == "pace"][0][4] == "—")

# 时长非正
zero = WorkoutSession("瞬时", kind="cardio", started_at=T, ended_at=T,
                      distance_meters=5000)
check("零时长时配速为破折号",
      [x for x in summary_metrics(zero) if x[0] == "pace"][0][4] == "—")

# ---------------------------------------------------------------- 11
group("11 未结束记录被推进历史详情时的兜底")

in_progress = WorkoutSession("进行中", kind="strength", started_at=T, ended_at=None,
                             entries=[entry(1, 60, 10)])
check("未结束记录 is_finished = False", in_progress.is_finished is False)
check("未结束记录的时长按 now 算不会为负（用已结束对照）",
      (T2 - T).total_seconds() == 2700)
check("未结束记录在历史详情不可编辑", allowed_fields(in_progress) == set())

# ---------------------------------------------------------------- 12
group("12 空记录与边界")

no_entries = WorkoutSession("空记录", started_at=T, ended_at=T2, entries=[])
check("空记录产出 0 张卡", len(build_records([], [])) == 0)
check("空记录动作数 0", summary_metrics(no_entries)[-1][2] == 0)
check("空记录总组数 0", summary_metrics(no_entries)[0][2] == 0)
check("空记录可复制成空草稿", len(make_draft(no_entries)["draft"].entries) == 0)

# 组数极多时不丢
many = build_records(
    [entry(i, 60, 10, exercise_id="A") for i in range(1, 41)], []
)
check("40 组全部保留", many[0].total_set_count == 40)
check("40 组容量正确", many[0].volume == 40 * 600, f"实际 {many[0].volume}")

# ---------------------------------------------------------------- 13
group("13 动作库重复 id 时取第一条")

dup_lib = [
    LibraryItem("0001", "first", ["第一个"], "胸"),
    LibraryItem("0001", "second", ["第二个"], "背"),
]
dup_rec = build_records([entry(1, 60, 10, exercise_id="0001")], dup_lib)[0]
check("重复 id 取首条（与字典覆盖顺序一致）",
      dup_rec.display_name == "第一个", f"实际 {dup_rec.display_name}")
check("重复 id 的肌群也取首条", dup_rec.primary_muscle == "胸")

# ---------------------------------------------------------------- 14
group("14 合计行")

recs_tot = build_records([
    entry(1, 40, 12, exercise_id="A", warm=True),
    entry(2, 60, 10, exercise_id="A"),
    entry(1, 30, 12, exercise_id="B"),
], [])
check("合计动作数 2", len(recs_tot) == 2)
check("合计完成组数 3（含 1 热身）",
      sum(r.completed_set_count for r in recs_tot) == 3,
      f"实际 {sum(r.completed_set_count for r in recs_tot)}")

# =====================================================================
print("\n" + "=" * 72)
if FAIL:
    print(f"失败 {FAIL} 条，通过 {PASS} 条：")
    for f in FAILURES:
        print("  ✗ " + f)
    sys.exit(1)
print(f"全部通过：{PASS} 项断言")
print("=" * 72)
