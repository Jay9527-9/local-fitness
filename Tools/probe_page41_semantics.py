#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 41 值语义推演（RestRange 夹取）。"""

import sys

FAIL = []


def expect(label, got, want):
    ok = got == want
    if not ok:
        FAIL.append((label, got, want))
    print(("  ok " if ok else "  ✗  ") + label + f"  got={got!r}")


def clamp(s):
    return min(max(15, s), 600)


def is_valid(s):
    return 15 <= s <= 600


def parse(text, fallback):
    try:
        return clamp(int(text.strip()))
    except (ValueError, AttributeError):
        return clamp(fallback)


print("[1 夹取]")
expect("下界夹到 15", clamp(0), 15)
expect("上界夹到 600", clamp(900), 600)
expect("界内原样", clamp(90), 90)
expect("合法判定 15", is_valid(15), True)
expect("合法判定 600", is_valid(600), True)
expect("非法判定 14", is_valid(14), False)
expect("非法判定 601", is_valid(601), False)

print("[2 自定义解析]")
expect("空串回落", parse("", 90), 90)
expect("非法回落", parse("abc", 90), 90)
expect("合法解析", parse("75", 90), 75)
expect("越界回落夹取", parse("9999", 90), 600)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
