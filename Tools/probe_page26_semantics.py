#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 26 值语义推演（动作库排序）。

把 `ExerciseSearch.sorted` 的排序逻辑照搬成 Python。
用法：
    python Tools/probe_page26_semantics.py
"""

from functools import cmp_to_key

# 动作：id / name / difficulty(order) / favorited_at
DIFF_ORDER = {"beginner": 0, "intermediate": 1, "advanced": 2}


def name_key(a, b):
    # 简化的 case-insensitive 比较
    la, lb = a["name"].lower(), b["name"].lower()
    return -1 if la < lb else (1 if la > lb else 0)


def sorted_by(items, order, recent_rank=None):
    recent_rank = recent_rank or {}
    if order == "defaultOrder":
        return list(items)
    if order == "name":
        return sorted(items, key=cmp_to_key(name_key))
    if order == "difficulty":
        def cmp_diff(a, b):
            if DIFF_ORDER[a["difficulty"]] != DIFF_ORDER[b["difficulty"]]:
                return -1 if DIFF_ORDER[a["difficulty"]] < DIFF_ORDER[b["difficulty"]] else 1
            return name_key(a, b)
        return sorted(items, key=cmp_to_key(cmp_diff))
    if order == "recentlyUsed":
        def cmp_recent(a, b):
            la = recent_rank.get(a["id"], 10 ** 9)
            lb = recent_rank.get(b["id"], 10 ** 9)
            if la != lb:
                return -1 if la < lb else 1
            return name_key(a, b)
        return sorted(items, key=cmp_to_key(cmp_recent))
    if order == "recentlyFavorited":
        def cmp_fav(a, b):
            fa = a["favorited_at"] or 0
            fb = b["favorited_at"] or 0
            if fa != fb:
                return -1 if fa > fb else 1  # 最近收藏在前
            return name_key(a, b)
        return sorted(items, key=cmp_to_key(cmp_fav))
    return list(items)


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


def ids(items):
    return [x["id"] for x in items]


A = {"id": "a", "name": "Bench Press", "difficulty": "advanced", "favorited_at": 300}
B = {"id": "b", "name": "pull up", "difficulty": "beginner", "favorited_at": None}
C = {"id": "c", "name": "Lateral Raise", "difficulty": "intermediate", "favorited_at": 500}

print("[1 默认推荐保持内置顺序]")
expect("默认顺序不重排", ids(sorted_by([C, A, B], "defaultOrder")), ["c", "a", "b"])

print("[2 名称 A-Z]")
expect("名称排序", ids(sorted_by([C, A, B], "name")), ["a", "c", "b"])

print("[3 难度]")
expect("难度入门到高级", ids(sorted_by([A, C, B], "difficulty")), ["b", "c", "a"])

print("[4 最近使用]")
rank = {"c": 0, "a": 1}
expect("最近使用在前，未使用在后", ids(sorted_by([B, A, C], "recentlyUsed", rank)), ["c", "a", "b"])

print("[5 最近收藏]")
expect("最近收藏在前，未收藏在后", ids(sorted_by([A, B, C], "recentlyFavorited")), ["c", "a", "b"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
