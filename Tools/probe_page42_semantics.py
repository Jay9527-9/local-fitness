#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 42 值语义推演（DistanceUnit 换算）。"""

import sys

FAIL = []


def expect(label, got, want):
    ok = abs(got - want) < 1e-9 if isinstance(got, float) else got == want
    if not ok:
        FAIL.append((label, got, want))
    print(("  ok " if ok else "  ✗  ") + label + f"  got={got!r}")


METERS_PER_MILE = 1609.344


def km(v):
    return v / 1000


def mi(v):
    return v / METERS_PER_MILE


print("[1 距离换算]")
expect("公里 5000m=5km", km(5000), 5.0)
expect("英里 1609.344m=1mi", mi(1609.344), 1.0)
expect("英里 5000m≈3.1mi", round(mi(5000), 2), 3.11)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
