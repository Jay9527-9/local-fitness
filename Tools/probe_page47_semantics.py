#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 47 值语义推演（训练目标五选，排除自定义）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


ALL = ["muscleGain", "fatLoss", "strength", "endurance", "stayHealthy", "custom"]


def goal_options():
    return [g for g in ALL if g != "custom"]


print("[1 训练目标五选]")
got = goal_options()
expect("排除 custom", "custom" not in got, True)
expect("共 5 项", len(got), 5)
expect("顺序保持", got, ["muscleGain", "fatLoss", "strength", "endurance", "stayHealthy"])

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
