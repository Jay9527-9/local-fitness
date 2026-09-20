#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 49 值语义推演（ResumeDraftMath）。"""

import sys
from datetime import date

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


def age_days(start, now):
    return max(0, (now - start).days)


def age_reminder(days):
    return f"该训练已暂停 {days} 天" if days > 0 else None


print("[1 暂停天数]")
expect("当天 0 天", age_days(date(2026, 9, 20), date(2026, 9, 20)), 0)
expect("隔 7 天", age_days(date(2026, 9, 13), date(2026, 9, 20)), 7)
expect("未来日期不出现负数", age_days(date(2026, 9, 25), date(2026, 9, 20)), 0)

print("[2 提醒文案]")
expect("0 天不提醒", age_reminder(0), None)
expect("7 天提醒", age_reminder(7), "该训练已暂停 7 天")

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
