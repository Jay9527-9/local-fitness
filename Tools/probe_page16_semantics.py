#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 16 值语义推演（收藏动作）。

把 `FavoriteExercisesSort.swift` 的纯函数逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「排序 / 筛选」边界算错的手段。

重点覆盖（本页最容易算错的地方）：
1. 「最近收藏」排序：收藏时间越晚越靠前，无时间戳的老数据排最后；
2. 「主肌群」排序：同肌群聚在一起，肌群内按名称；
3. 「最近使用」排序：越近越靠前，没使用过的排最后；
4. 肌群筛选按「分类命中 或 主肌群映射命中」判断（glutes 归在背下也能按「臀」筛到）；
5. 关键词筛选命中名称 / 别名 / 器械 / 肌群即保留，否则剔除。

用法：
    python Tools/probe_page16_semantics.py
"""

from datetime import datetime, timedelta, timezone
from functools import cmp_to_key

TZ = timezone(timedelta(hours=8))
MAX = 10 ** 9  # 对应 Swift 的 Int.max


def t(h, m=0):
    return datetime(2026, 9, 19, h, m, tzinfo=TZ)


class Item:
    def __init__(self, id_, name, category_zh="", primary_muscle="", target="",
                 equipment="", equipment_zh="", aliases=None, favorited_at=None):
        self.id = id_
        self.name = name
        self.categoryZh = category_zh
        self.primaryMuscleText = primary_muscle
        self.target = target
        self.equipment = equipment
        self.equipmentText = equipment_zh or equipment
        self.aliases = aliases or []
        self.favoritedAt = favorited_at  # None 表示无时间戳（升级前已收藏）


# =====================================================================
# 照搬 MuscleIconGroup.of 的映射（仅覆盖本页测试用到的中文肌群名）
# =====================================================================

def group_title(muscle):
    m = muscle
    if m in ("胸", "chest", "pectorals", "serratus anterior", "upper chest"):
        return "胸"
    if m in ("背", "back", "lats", "latissimus dorsi", "upper back", "lower back",
             "rhomboids", "spine", "traps", "trapezius"):
        return "背"
    if m in ("肩", "shoulders", "delts", "deltoids", "rear deltoids", "rotator cuff"):
        return "肩"
    if m in ("手臂", "前臂", "arm", "biceps", "triceps", "forearms", "brachialis",
             "wrist flexors", "wrists"):
        return "手臂"
    if m in ("核心", "core", "abs", "obliques", "hip flexors"):
        return "核心"
    if m in ("臀", "臀大肌", "glutes"):
        return "臀"
    if m in ("小腿", "calves", "soleus"):
        return "小腿"
    if m in ("腿", "leg", "quads", "quadriceps", "hamstrings", "adductors",
             "abductors", "ankles", "ankle stabilizers", "feet"):
        return "腿"
    if m in ("有氧", "cardiovascular system"):
        return "有氧"
    if m in ("颈", "neck", "levator scapulae"):
        return "颈"
    return "其他"


# =====================================================================
# 照搬 FavoriteExercisesFilter 的排序与筛选
# =====================================================================

def cmp_name(lhs, rhs):
    a = lhs.name.lower()
    b = rhs.name.lower()
    if a < b:
        return -1
    if a > b:
        return 1
    return 0


def cmp_recently_favorited(lhs, rhs):
    l, r = lhs.favoritedAt, rhs.favoritedAt
    if l is not None and r is not None:
        if l != r:
            return -1 if l > r else 1  # 越晚越靠前
        return cmp_name(lhs, rhs)
    if l is None and r is not None:
        return 1   # 无时间戳排后面
    if l is not None and r is None:
        return -1  # 有时间戳排前面
    return cmp_name(lhs, rhs)


def cmp_primary_muscle(lhs, rhs):
    lm, rm = lhs.primaryMuscleText, rhs.primaryMuscleText
    if lm != rm:
        return -1 if lm.lower() < rm.lower() else 1
    return cmp_name(lhs, rhs)


def cmp_recently_used(lhs, rhs, rank):
    l = rank.get(lhs.id, MAX)
    r = rank.get(rhs.id, MAX)
    if l != r:
        return -1 if l < r else 1
    return cmp_name(lhs, rhs)


SORTERS = {
    "name": lambda items, rank: sorted(items, key=cmp_to_key(cmp_name)),
    "primaryMuscle": lambda items, rank: sorted(items, key=cmp_to_key(cmp_primary_muscle)),
    "recentlyUsed": lambda items, rank: sorted(items, key=cmp_to_key(lambda a, b: cmp_recently_used(a, b, rank))),
    "recentlyFavorited": lambda items, rank: sorted(items, key=cmp_to_key(cmp_recently_favorited)),
}


def score(it, needle):
    total = 0
    nm = it.name.lower()
    if nm == needle or needle in nm:
        total += 1
    for a in it.aliases:
        if needle in a.lower():
            total += 1
            break
    if needle in it.primaryMuscleText.lower() or needle in it.target.lower():
        total += 1
    if needle in it.equipmentText.lower() or needle in it.equipment.lower():
        total += 1
    return total


def apply(items, keyword, muscle_category, sort, recent_rank):
    filtered = list(items)
    if muscle_category is not None:
        filtered = [it for it in filtered
                    if it.categoryZh == muscle_category
                    or group_title(it.primaryMuscleText) == muscle_category]
    needle = keyword.strip().lower()
    if needle:
        filtered = [it for it in filtered if score(it, needle) > 0]
    return SORTERS[sort](filtered, recent_rank)


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


def ids(items):
    return [x.id for x in items]


print("[1 最近收藏排序]")
a = Item("a", "Bench Press", category_zh="胸", primary_muscle="胸大肌", favorited_at=t(8))
b = Item("b", "Squat", category_zh="腿", primary_muscle="股四头肌", favorited_at=t(10))
c = Item("c", "Deadlift", category_zh="背", primary_muscle="臀大肌", favorited_at=None)  # 老数据无时间戳
expect("收藏时间越晚越靠前", ids(apply([a, b, c], "", None, "recentlyFavorited", {})), ["b", "a", "c"])
expect("无时间戳排最后", apply([a, b, c], "", None, "recentlyFavorited", {})[-1].id, "c")

print("[2 动作名称排序]")
d = Item("d", "barbell curl", category_zh="手臂", primary_muscle="肱二头肌")
e = Item("e", "Arnold press", category_zh="肩", primary_muscle="三角肌")
f = Item("f", "Cable Fly", category_zh="胸", primary_muscle="胸大肌")
expect("名称大小写不敏感升序", ids(apply([f, d, e], "", None, "name", {})), ["e", "d", "f"])

print("[3 主肌群排序]")
# 中文按 Unicode 码点比较：三角肌(三 U+4E09) < 胸大肌(胸 U+80F8)，故 i 在前；
# 同肌群（胸大肌）内按名称：Bench Press < Push Up，故 h 在 g 前。
g = Item("g", "Push Up", category_zh="胸", primary_muscle="胸大肌")
h = Item("h", "Bench Press", category_zh="胸", primary_muscle="胸大肌")
i = Item("i", "Lateral Raise", category_zh="肩", primary_muscle="三角肌")
got = apply([i, g, h], "", None, "primaryMuscle", {})
expect("主肌群排序（同肌群聚在一起，肌群内按名称）", ids(got), ["i", "h", "g"])
expect("主肌群排序不丢元素", set(ids(got)), {"g", "h", "i"})

print("[4 最近使用排序]")
rank = {"a": 0, "b": 1, "c": 2}  # 0 最新
expect("最近使用越近越靠前", ids(apply([b, a, c], "", None, "recentlyUsed", rank)), ["a", "b", "c"])
# c 不在 rank 里 → Int.max → 排最后
rank2 = {"b": 0, "a": 1}
expect("未使用过的排最后", apply([c, b, a], "", None, "recentlyUsed", rank2)[-1].id, "c")

print("[5 肌群筛选]")
glute = Item("gl", "Hip Thrust", category_zh="背", primary_muscle="臀大肌")  # glutes 归在「背」下
back = Item("bk", "Pull Up", category_zh="背", primary_muscle="背阔肌")
chest = Item("ch", "Bench Press", category_zh="胸", primary_muscle="胸大肌")
got = apply([glute, back, chest], "", "臀", "name", {})
expect("按「臀」能筛到 glutes（主肌群映射命中）", ids(got), ["gl"])
got = apply([glute, back, chest], "", "背", "name", {})
expect("按「背」筛到 categoryZh=背 的条目", set(ids(got)), {"gl", "bk"})
got = apply([glute, back, chest], "", "胸", "name", {})
expect("按「胸」筛到 categoryZh=胸 的条目", ids(got), ["ch"])

print("[6 关键词筛选]")
bench = Item("bp", "Barbell Bench Press", category_zh="胸", primary_muscle="胸大肌",
             target="pectorals", equipment="barbell", equipment_zh="杠铃",
             aliases=["卧推", "平板卧推"])
squat = Item("sq", "Back Squat", category_zh="腿", primary_muscle="股四头肌",
             target="quads", equipment="barbell", equipment_zh="杠铃",
             aliases=["深蹲"])
expect("按别名「卧推」命中", ids(apply([bench, squat], "卧推", None, "name", {})), ["bp"])
expect("按器械「杠铃」命中", set(ids(apply([bench, squat], "杠铃", None, "name", {}))), {"bp", "sq"})
expect("按英文名称命中", ids(apply([bench, squat], "bench", None, "name", {})), ["bp"])
expect("按主肌群中文命中", ids(apply([bench, squat], "股四头肌", None, "name", {})), ["sq"])
expect("无匹配返回空", apply([bench, squat], "zzz", None, "name", {}), [])

print("[7 肌群计数]")

def muscle_counts(items):
    counter = {}
    for it in items:
        counter[it.categoryZh] = counter.get(it.categoryZh, 0) + 1
    return counter

expect("按 categoryZh 计数", muscle_counts([bench, squat, chest]), {"胸": 2, "腿": 1})

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
