#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 27 值语义推演（动作参数面板）。

把 `ExercisePrescription.expandEntries` 的展开逻辑照搬成 Python。
用法：
    python Tools/probe_page27_semantics.py
"""


def expand_entries(sets, reps_low, weight, is_warmup, warmup_count, warmup_percent, start_index=1):
    entries = []
    index = start_index
    if is_warmup:
        for _ in range(max(1, warmup_count)):
            entries.append({
                "weight": (weight or 0) * warmup_percent / 100,
                "reps": reps_low,
                "is_warmup": True,
            })
            index += 1
    for _ in range(max(1, sets)):
        entries.append({
            "weight": weight or 0,
            "reps": reps_low,
            "is_warmup": False,
        })
        index += 1
    return entries


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 展开正式组]")
expect("3 组无热身", len(expand_entries(3, 10, 0, False, 1, 50)), 3)
expect("正式组重量=默认重量", expand_entries(1, 10, 60, False, 1, 50)[0]["weight"], 60)

print("[2 展开热身组]")
r = expand_entries(3, 10, 60, True, 2, 50)
expect("热身组 2 + 正式组 3 = 5", len(r), 5)
expect("热身组重量按 50%", r[0]["weight"], 30)
expect("正式组重量不变", r[2]["weight"], 60)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
