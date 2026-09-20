#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 19 值语义推演（导出本地备份）。

把 `ExportBackup.swift` 的纯函数逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「数据段裁剪 / 草稿过滤 / 动作并集去重 /
个人资料双开关 / 校验摘要 / 大小估算」边界算错的手段。

用法：
    python Tools/probe_page19_semantics.py
"""

FORMAT_ID = "fitness-export-backup"
SCHEMA_VERSION = 1

SEGMENTS = {"sessions", "plans", "exercises", "measurements", "preferences"}


# =====================================================================
# 照搬 ExportBackup.swift 的纯逻辑
# =====================================================================

def fnv1a64(text):
    h = 0xcbf29ce484222325
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF
    return h


def hex16(v):
    return format(v, "016x")


def prefs_canonical(p):
    return (
        "rest=%d;prefill=%s;autostart=%s;volume=%s;last10=%s;style=%s"
        ";advance=%s;copy=%s;warmup=%s;minimize=%s;sound=%s;haptics=%s"
        % (
            p["rest"], p["prefill"], p["autostart"], p["volume"], p["last10"],
            p["style"], p["advance"], p["copy"], p["warmup"], p["minimize"],
            p["sound"], p["haptics"],
        )
    )


def dedupe_exercises(items):
    seen = set()
    out = []
    for it in items:
        if it["id"] not in seen:
            seen.add(it["id"])
            out.append(it)
    return sorted(out, key=lambda x: x["id"])


def make_backup(sessions, plans, exercises, measurements, preferences, profile,
                segments, include_profile, include_drafts, app_version):
    finished = sorted([s for s in sessions if s["finished"]], key=lambda s: s["started"])
    drafts = sorted([s for s in sessions if not s["finished"]], key=lambda s: s["started"])

    if "sessions" in segments:
        included_sessions = finished + drafts if include_drafts else finished
    else:
        included_sessions = []

    if "exercises" in segments:
        included_exercises = dedupe_exercises(
            [e for e in exercises if e["custom"] or e["favorite"]]
        )
    else:
        included_exercises = []

    export_prefs = preferences if "preferences" in segments else None
    export_profile = profile if ("preferences" in segments and include_profile) else None

    return {
        "schemaVersion": SCHEMA_VERSION,
        "format": FORMAT_ID,
        "appVersion": app_version,
        "dataSegments": sorted(segments),
        "includeProfile": include_profile,
        "includeDrafts": include_drafts,
        "sessions": included_sessions,
        "plans": plans if "plans" in segments else [],
        "exercises": included_exercises,
        "measurements": measurements if "measurements" in segments else [],
        "trainingPreferences": export_prefs,
        "profile": export_profile,
    }


def has_content(b):
    return bool(
        b["sessions"] or b["plans"] or b["exercises"] or b["measurements"]
        or b["trainingPreferences"] is not None or b["profile"] is not None
    )


def count_summary(b):
    parts = []
    if b["sessions"]:
        parts.append("训练记录 %d 条" % len(b["sessions"]))
    if b["plans"]:
        parts.append("计划 %d 个" % len(b["plans"]))
    if b["exercises"]:
        parts.append("动作 %d 个" % len(b["exercises"]))
    if b["measurements"]:
        parts.append("身体数据 %d 条" % len(b["measurements"]))
    if b["trainingPreferences"] is not None:
        parts.append("训练偏好")
    if b["profile"] is not None:
        parts.append("个人资料")
    return "，".join(parts) if parts else "无内容"


def estimate(session_count, plan_count, exercise_count, measurement_count,
             include_prefs, include_profile):
    total = 0
    total += max(0, session_count) * 2600
    total += max(0, plan_count) * 900
    total += max(0, exercise_count) * 1200
    total += max(0, measurement_count) * 260
    if include_prefs:
        total += 600
    if include_profile:
        total += 900
    total += 400
    return total


def session(sid, started, finished=True):
    return {"id": sid, "started": started, "finished": finished}


def exercise(eid, custom=False, favorite=False):
    return {"id": eid, "custom": custom, "favorite": favorite}


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 FNV-1a 校验摘要]")
expect("空串", hex16(fnv1a64("")), "cbf29ce484222325")
expect("'a'", hex16(fnv1a64("a")), "af63dc4c8601ec8c")
expect("'hello'", hex16(fnv1a64("hello")), "a430d84680aabd0b")
expect("确定性（同一输入同哈希）", fnv1a64("训练记录"), fnv1a64("训练记录"))

print("[2 草稿过滤]")
ss = [session("a", 1), session("b", 2), session("c", 3, finished=False)]
b = make_backup(ss, [], [], [], None, None, {"sessions"}, False, False, "1.0.0")
expect("默认跳过草稿", [s["id"] for s in b["sessions"]], ["a", "b"])
b = make_backup(ss, [], [], [], None, None, {"sessions"}, False, True, "1.0.0")
expect("包含草稿时并入", [s["id"] for s in b["sessions"]], ["a", "b", "c"])

print("[3 数据段裁剪]")
plans = [{"id": "p1"}]
ms = [{"id": "m1"}]
prof = {"nickname": "小健"}
b = make_backup(ss, plans, [], ms, {"rest": 90}, prof, {"sessions"}, False, False, "1.0.0")
expect("只选训练记录时其余为空",
       (len(b["plans"]), len(b["measurements"]), b["trainingPreferences"], b["profile"]),
       (0, 0, None, None))

print("[4 动作并集去重]")
ex = [exercise("e1", custom=True), exercise("e2", favorite=True),
      exercise("e1", custom=True), exercise("e3")]
b = make_backup(ss, [], ex, [], None, None, {"exercises"}, False, False, "1.0.0")
expect("自定义∪收藏，按 id 去重升序", [e["id"] for e in b["exercises"]], ["e1", "e2"])

print("[5 个人资料双开关]")
b = make_backup(ss, [], [], [], {"rest": 90}, prof, {"preferences"}, False, False, "1.0.0")
expect("勾选偏好但未开个人资料 → 无资料", b["profile"], None)
b = make_backup(ss, [], [], [], {"rest": 90}, prof, {"preferences"}, True, False, "1.0.0")
expect("两者都开 → 有资料", b["profile"] is not None, True)
b = make_backup(ss, [], [], [], None, prof, {"sessions"}, True, False, "1.0.0")
expect("未勾选偏好段 → 即便开了资料开关也不导", b["profile"], None)

print("[6 内容判定与摘要]")
b = make_backup([], [], [], [], None, None, {"sessions"}, False, False, "1.0.0")
expect("全空 → 无内容", has_content(b), False)
b = make_backup(ss, plans, ex, ms, {"rest": 90}, prof, SEGMENTS, True, False, "1.0.0")
expect("全选且含资料 → 摘要含五类", count_summary(b), "训练记录 2 条，计划 1 个，动作 2 个，身体数据 1 条，训练偏好，个人资料")

print("[7 大小估算]")
expect("空导出仍有头部", estimate(0, 0, 0, 0, False, False), 400)
expect("10 次训练 + 偏好", estimate(10, 0, 0, 0, True, False), 10 * 2600 + 600 + 400)

print("[8 数据段排序]")
b = make_backup(ss, [], [], [], None, None, {"measurements", "sessions", "plans"}, False, False, "1.0.0")
expect("段名升序", b["dataSegments"], ["measurements", "plans", "sessions"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
