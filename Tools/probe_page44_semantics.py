#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 44 值语义推演（MotionPreference.isReduced）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


def is_reduced(pref, system):
    if pref == "followSystem":
        return system
    if pref == "alwaysReduced":
        return True
    return False


print("[1 减少动画判定]")
expect("始终减少恒真", is_reduced("alwaysReduced", False), True)
expect("正常动画恒假", is_reduced("normal", True), False)
expect("跟随系统+系统开 → 减少", is_reduced("followSystem", True), True)
expect("跟随系统+系统关 → 正常", is_reduced("followSystem", False), False)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
