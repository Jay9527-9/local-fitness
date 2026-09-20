#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 28 值语义推演（选择计划）。

把 `PlanPickLogic` 的筛选 / 排序 / 重复检测照搬成 Python。
用法：
    python Tools/probe_page28_semantics.py
"""


def filter_by_name(plans, query):
    trimmed = query.strip()
    if not trimmed:
        return plans
    return [p for p in plans if trimmed.lower() in p["name"].lower()]


def sort_plans(plans, order):
    if order == "recentlyUsed":
        return sorted(plans, key=lambda p: (p.get("lastUsedAt") or 0), reverse=True)
    if order == "recentlyCreated":
        return sorted(plans, key=lambda p: p["createdAt"], reverse=True)
    if order == "name":
        return sorted(plans, key=lambda p: p["name"].lower())
    return plans


def plan_contains(plan, exercise_id):
    return any(e["exerciseID"] == exercise_id for e in plan["exercises"])


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


P1 = {"name": "推拉腿", "createdAt": 100, "lastUsedAt": 300, "exercises": [{"exerciseID": "e1"}]}
P2 = {"name": "上肢", "createdAt": 200, "lastUsedAt": None, "exercises": [{"exerciseID": "e2"}]}
P3 = {"name": "核心", "createdAt": 150, "lastUsedAt": 100, "exercises": []}
PLANS = [P1, P2, P3]

print("[1 搜索]")
expect("空查询不过滤", len(filter_by_name(PLANS, "  ")), 3)
expect("按名称匹配", [p["name"] for p in filter_by_name(PLANS, "推")], ["推拉腿"])

print("[2 排序]")
expect("最近使用优先，未使用在后", [p["name"] for p in sort_plans(PLANS, "recentlyUsed")], ["推拉腿", "核心", "上肢"])
expect("最近创建", [p["name"] for p in sort_plans(PLANS, "recentlyCreated")], ["上肢", "核心", "推拉腿"])
expect("名称", [p["name"] for p in sort_plans(PLANS, "name")], ["上肢", "推拉腿", "核心"])

print("[3 重复检测]")
expect("包含 e1", plan_contains(P1, "e1"), True)
expect("不含 e3", plan_contains(P1, "e3"), False)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
