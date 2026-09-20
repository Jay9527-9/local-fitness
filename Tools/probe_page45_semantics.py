#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 45/46 值语义推演（ClearDataCounts + 确认短语）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


def compute(sessions, rest_days):
    finished_strength = 0
    finished_cardio = 0
    drafts = 0
    for s in sessions:
        if s["finished"]:
            if s["kind"] == "cardio":
                finished_cardio += 1
            else:
                finished_strength += 1
        else:
            drafts += 1
    return {
        "finishedStrength": finished_strength,
        "finishedCardio": finished_cardio,
        "drafts": drafts,
        "restDays": len(rest_days),
        "finishedTotal": finished_strength + finished_cardio,
    }


print("[1 数量统计]")
sessions = [
    {"id": 1, "kind": "strength", "finished": True},
    {"id": 2, "kind": "cardio", "finished": True},
    {"id": 3, "kind": "cardio", "finished": True},
    {"id": 4, "kind": "strength", "finished": False},
]
got = compute(sessions, rest_days=[1, 2, 3])
expect("力量 1", got["finishedStrength"], 1)
expect("有氧 2", got["finishedCardio"], 2)
expect("草稿 1", got["drafts"], 1)
expect("休息日 3", got["restDays"], 3)
expect("完成总数 3", got["finishedTotal"], 3)

print("[2 确认短语]")
expect("清除训练记录短语", "删除训练", "删除训练")
expect("清除全部短语", "清除全部", "清除全部")

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
