#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 29 值语义推演（进行中训练选择）。

把 `sortedSessions` 的「当前训练优先、其余按开始时间倒序」照搬成 Python。
用法：
    python Tools/probe_page29_semantics.py
"""


def sort_sessions(sessions, current_id):
    def key(s):
        rank = 0 if s["id"] == current_id else 1
        return (rank, -s["started"])
    return sorted(sessions, key=key)


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


SESSIONS = [
    {"id": "a", "started": 100},
    {"id": "b", "started": 300},
    {"id": "c", "started": 200},
]

print("[1 当前训练优先]")
expect("当前 c 排第一", [s["id"] for s in sort_sessions(SESSIONS, "c")], ["c", "b", "a"])
expect("无当前按开始时间倒序", [s["id"] for s in sort_sessions(SESSIONS, None)], ["b", "c", "a"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
