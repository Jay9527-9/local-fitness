#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 25 值语义推演（动作库高级筛选）。

把 `ExerciseSearch.matches` 的筛选逻辑照搬成 Python。
用法：
    python Tools/probe_page25_semantics.py
"""

# 动作：is_hidden / is_custom / is_favorite / category_zh / primary_group / equipment / difficulty
# group_of：把主肌群中文名归到肌群大类（这里简化为 category_zh 或显式传入的 group）

GROUP_OF = {
    "胸大肌": "胸", "背阔肌": "背", "三角肌": "肩", "肱二头肌": "手臂",
    "腹肌": "核心", "股四头肌": "腿", "臀大肌": "臀", "腓肠肌": "小腿",
}


def group_of(primary):
    return GROUP_OF.get(primary, primary)


def matches(item, filt):
    if item["is_hidden"] and not filt["include_hidden"]:
        return False
    src = filt["source"]
    if src == "builtin" and item["is_custom"]:
        return False
    if src == "custom" and not item["is_custom"]:
        return False
    if filt["only_favorite"] and not item["is_favorite"]:
        return False
    if filt["muscle_category"] is not None:
        cat = filt["muscle_category"]
        if not (item["category_zh"] == cat or group_of(item["primary_muscle"]) == cat):
            return False
    if filt["muscle_groups"]:
        g = group_of(item["primary_muscle"])
        if not (item["category_zh"] in filt["muscle_groups"] or g in filt["muscle_groups"]):
            return False
    if filt["equipments"] and item["equipment"] not in filt["equipments"]:
        return False
    if filt["difficulty"] is not None and item["difficulty"] != filt["difficulty"]:
        return False
    return True


EMPTY = {
    "muscle_category": None, "muscle_groups": set(), "equipments": set(),
    "difficulty": None, "source": "all", "only_favorite": False, "include_hidden": False,
}

ITEMS = [
    {"id": "a", "is_hidden": False, "is_custom": False, "is_favorite": True,
     "category_zh": "胸", "primary_muscle": "胸大肌", "equipment": "杠铃", "difficulty": "advanced"},
    {"id": "b", "is_hidden": False, "is_custom": True, "is_favorite": False,
     "category_zh": "背", "primary_muscle": "背阔肌", "equipment": "自重", "difficulty": "beginner"},
    {"id": "c", "is_hidden": True, "is_custom": False, "is_favorite": False,
     "category_zh": "肩", "primary_muscle": "三角肌", "equipment": "哑铃", "difficulty": "intermediate"},
]

ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


def ids(result):
    return [x["id"] for x in result]


print("[1 空筛选不过滤]")
expect("空筛选全命中（不含隐藏）", ids([i for i in ITEMS if matches(i, EMPTY)]), ["a", "b"])

print("[2 来源筛选]")
f = dict(EMPTY, source="custom")
expect("来源=自定义", ids([i for i in ITEMS if matches(i, f)]), ["b"])
f = dict(EMPTY, source="builtin")
expect("来源=内置导入", ids([i for i in ITEMS if matches(i, f)]), ["a"])

print("[3 肌群多选]")
f = dict(EMPTY, muscle_groups={"胸", "背"})
expect("肌群多选 胸+背", ids([i for i in ITEMS if matches(i, f)]), ["a", "b"])

print("[4 器械多选]")
f = dict(EMPTY, equipments={"杠铃"})
expect("器械=杠铃", ids([i for i in ITEMS if matches(i, f)]), ["a"])

print("[5 难度单选]")
f = dict(EMPTY, difficulty="advanced")
expect("难度=高级", ids([i for i in ITEMS if matches(i, f)]), ["a"])

print("[6 隐藏 / 收藏]")
f = dict(EMPTY, include_hidden=True)
expect("包含隐藏", ids([i for i in ITEMS if matches(i, f)]), ["a", "b", "c"])
f = dict(EMPTY, only_favorite=True)
expect("仅收藏", ids([i for i in ITEMS if matches(i, f)]), ["a"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
