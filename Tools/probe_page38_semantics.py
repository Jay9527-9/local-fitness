#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 38 值语义推演（计划动作配置：ExerciseDraft 应用/覆盖）。"""


def make_plan_exercise(draft, exercise_id):
    note = draft.get("note", "").strip()
    return {
        "exerciseID": exercise_id,
        "sets": draft["sets"],
        "repsLow": draft["repsLow"],
        "repsHigh": draft["repsHigh"],
        "restSeconds": draft["restSeconds"],
        "isWarmup": draft["isWarmup"],
        "defaultWeight": draft.get("defaultWeight"),
        "warmupCount": draft.get("warmupCount", 1),
        "warmupPercent": draft.get("warmupPercent", 50),
        "note": note if note else None,
        "progression": draft.get("progression", "none"),
        "progressionConfig": draft.get("progressionConfig"),
    }


def applied(draft, entry):
    updated = dict(entry)
    note = draft.get("note", "").strip()
    updated["sets"] = draft["sets"]
    updated["repsLow"] = draft["repsLow"]
    updated["repsHigh"] = draft["repsHigh"]
    updated["restSeconds"] = draft["restSeconds"]
    updated["isWarmup"] = draft["isWarmup"]
    updated["defaultWeight"] = draft.get("defaultWeight")
    updated["warmupCount"] = draft.get("warmupCount", 1)
    updated["warmupPercent"] = draft.get("warmupPercent", 50)
    updated["note"] = note if note else None
    updated["progression"] = draft.get("progression", "none")
    updated["progressionConfig"] = draft.get("progressionConfig")
    return updated


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


draft = {"sets": 4, "repsLow": 6, "repsHigh": 10, "restSeconds": 120, "isWarmup": False,
         "defaultWeight": 60.0, "warmupCount": 2, "warmupPercent": 50,
         "note": "  肩不适改哑铃  ", "progression": "addWeight", "progressionConfig": {"isEnabled": True}}

print("[1 makePlanExercise]")
pe = make_plan_exercise(draft, "0025")
expect("组数 4", pe["sets"], 4)
expect("默认重量 60", pe["defaultWeight"], 60.0)
expect("备注去空白", pe["note"], "肩不适改哑铃")
expect("热身组数 2", pe["warmupCount"], 2)

print("[2 applied 保留 id]")
entry = {"id": "e1", "exerciseID": "0025", "sets": 3, "repsLow": 8, "repsHigh": 12,
         "restSeconds": 90, "isWarmup": False, "defaultWeight": None, "warmupCount": 1,
         "warmupPercent": 50, "note": None, "progression": "none", "progressionConfig": None}
updated = applied(draft, entry)
expect("保留 id", updated["id"], "e1")
expect("覆盖组数", updated["sets"], 4)
expect("递增规则写入", updated["progression"], "addWeight")

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
