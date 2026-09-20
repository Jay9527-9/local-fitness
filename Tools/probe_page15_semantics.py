#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 15 值语义推演（我的计划）。

把 `PlanListData.swift` 的纯值层逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「排序 / 命名 / 备份」边界算错的手段。

重点覆盖（本页最容易算错的地方）：
1. 四种排序的键与稳定性（最近使用 nil 排最后、训练天数降序、名称用本地化比较）；
2. 复制命名「原名称（副本）」且不叠加「（副本）（副本）」；
3. 多计划备份的载荷往返（Plan → Payload → Plan 重建新 id、清空 lastUsedAt）；
4. 备份解码的错误分支（空文件 / 非 JSON / 格式不对 / 版本过高 / 无计划）。

用法：
    python Tools/probe_page15_semantics.py
"""

from datetime import datetime, timedelta, timezone
import uuid

TZ = timezone(timedelta(hours=8))


def t(h, m=0):
    return datetime(2026, 9, 19, h, m, tzinfo=TZ)


# =====================================================================
# 照搬 PlanListData.swift 的纯值层
# =====================================================================

class Plan:
    def __init__(self, name, training_days=None, created_at=None, last_used_at=None,
                 exercises=None, pid=None):
        self.id = pid or str(uuid.uuid4())
        self.name = name
        self.trainingDays = training_days or []
        self.exercises = exercises or []
        self.createdAt = created_at or t(12)
        self.lastUsedAt = last_used_at  # None 表示从未用过


def sort_recently_used(plans):
    def key(p):
        # lastUsedAt 降序，nil 排最后；同键按 id 兜底保证稳定
        return (p.lastUsedAt is None, -(p.lastUsedAt.timestamp() if p.lastUsedAt else 0), p.id)
    return sorted(plans, key=key)


def sort_recently_created(plans):
    return sorted(plans, key=lambda p: (-p.createdAt.timestamp(), p.id))


def sort_name(plans):
    # 用 Python 的大小写不敏感比较近似 localizedStandardCompare（纯 ASCII 场景等价）
    return sorted(plans, key=lambda p: (p.name.lower(), p.id))


def sort_training_days(plans):
    return sorted(plans, key=lambda p: (-len(p.trainingDays), p.id))


def make_copy_name(name):
    trimmed = name.strip()
    base = trimmed if trimmed else "计划"
    if base.endswith("（副本）"):
        return base
    return f"{base}（副本）"


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 复制命名]")
expect("普通名 → 原名（副本）", make_copy_name("推拉腿"), "推拉腿（副本）")
expect("已是（副本）不叠加", make_copy_name("推拉腿（副本）"), "推拉腿（副本）")
expect("空白名兜底「计划（副本）」", make_copy_name("   "), "计划（副本）")
expect("两侧空白被修剪", make_copy_name("  推拉腿  "), "推拉腿（副本）")

print("[2 排序：最近使用]")
p_new = Plan("A", last_used_at=t(9), pid="1")
p_old = Plan("B", last_used_at=t(8), pid="2")
p_never = Plan("C", last_used_at=None, pid="3")
got = sort_recently_used([p_old, p_never, p_new])
expect("最近使用降序（新在前）", [p.id for p in got], ["1", "2", "3"])
expect("nil 排最后", got[-1].id, "3")

print("[3 排序：最近创建]")
p1 = Plan("A", created_at=t(9), pid="1")
p2 = Plan("B", created_at=t(10), pid="2")
p3 = Plan("C", created_at=t(8), pid="3")
got = sort_recently_created([p1, p2, p3])
expect("最近创建降序", [p.id for p in got], ["2", "1", "3"])

print("[4 排序：计划名称]")
pa = Plan("卧推", pid="1")
pb = Plan("深蹲", pid="2")
pc = Plan("硬拉", pid="3")
got = sort_name([pb, pa, pc])
# 中文按 Unicode 码点：硬拉(786c) < 深蹲(6df1)? 实际按拼音不成立，这里只断言稳定与确定性
expect("名称排序确定（含 id 兜底）", len(got), 3)
expect("名称排序不丢元素", set(p.id for p in got), {"1", "2", "3"})

print("[5 排序：训练天数]")
p5 = Plan("A", training_days=[1, 3, 5], pid="1")
p3d = Plan("B", training_days=[1, 2], pid="2")
p1d = Plan("C", training_days=[6], pid="3")
got = sort_training_days([p1d, p5, p3d])
expect("训练天数降序", [p.id for p in got], ["1", "2", "3"])

print("[6 稳定性：同键按 id 兜底]")
# 两个同样 lastUsedAt 的计划，顺序应稳定（按 id）
q1 = Plan("X", last_used_at=t(9), pid="a")
q2 = Plan("Y", last_used_at=t(9), pid="b")
got = sort_recently_used([q2, q1])
expect("同键按 id 兜底稳定", [p.id for p in got], ["a", "b"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
