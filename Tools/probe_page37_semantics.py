#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 37 值语义推演（复制训练为草稿：选项过滤）。"""


def apply_options(opts, entries, note):
    entries = list(entries)
    if not opts["copy_warmup_sets"]:
        entries = [e for e in entries if not e["is_warmup"]]
    if not opts["copy_weights_reps"]:
        out = []
        for e in entries:
            e = dict(e)
            e["weight"] = 0
            e["reps"] = 0
            out.append(e)
        entries = out
    result_note = note if opts["copy_note"] else None
    return entries, result_note


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


entries = [
    {"is_warmup": False, "weight": 60, "reps": 8},
    {"is_warmup": False, "weight": 60, "reps": 8},
    {"is_warmup": True, "weight": 30, "reps": 12},
]

print("[1 默认选项]")
r, n = apply_options({"copy_warmup_sets": False, "copy_weights_reps": True, "copy_note": False}, entries, "备注")
expect("默认剔除热身组", len(r), 2)
expect("默认不复制备注", n, None)

print("[2 复制热身组]")
r, _ = apply_options({"copy_warmup_sets": True, "copy_weights_reps": True, "copy_note": False}, entries, "备注")
expect("开启热身组保留 3 组", len(r), 3)

print("[3 不复制重量次数]")
r, _ = apply_options({"copy_warmup_sets": False, "copy_weights_reps": False, "copy_note": False}, entries, "备注")
expect("重量清零", [e["weight"] for e in r], [0, 0])
expect("次数清零", [e["reps"] for e in r], [0, 0])

print("[4 复制备注]")
r, n = apply_options({"copy_warmup_sets": False, "copy_weights_reps": True, "copy_note": True}, entries, "备注")
expect("复制备注", n, "备注")

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
