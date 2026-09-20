#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 43 值语义推演（FeedbackPolicy 判定）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


def should_play(master, sub):
    return master and sub


def should_haptic(master, sub, available):
    return master and sub and available


print("[1 声音判定]")
expect("总开+子开 → 播", should_play(True, True), True)
expect("总关 → 不播（子开）", should_play(False, True), False)
expect("总开+子关 → 不播", should_play(True, False), False)

print("[2 触感判定]")
expect("全开 → 触发", should_haptic(True, True, True), True)
expect("总关 → 不触发", should_haptic(False, True, True), False)
expect("子关 → 不触发", should_haptic(True, False, True), False)
expect("设备不支持 → 不触发", should_haptic(True, True, False), False)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
