#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 33/34 值语义推演（休息日：备注 300 字 + 自然日归一化）。"""

import datetime


def normalized_note(raw, limit=300):
    return raw.strip()[:limit]


def start_of_day(dt):
    return datetime.datetime(dt.year, dt.month, dt.day)


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 备注规范化]")
expect("去首尾空白", normalized_note("  主动恢复  "), "主动恢复")
expect("300 字截断", len(normalized_note("字" * 500)), 300)
expect("空字符串", normalized_note("   "), "")

print("[2 自然日归一化]")
dt = datetime.datetime(2026, 9, 19, 23, 59, 59)
expect("归一化到零点", start_of_day(dt), datetime.datetime(2026, 9, 19))
dt2 = datetime.datetime(2026, 9, 20, 0, 0, 1)
expect("跨日区分", start_of_day(dt) != start_of_day(dt2), True)

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
