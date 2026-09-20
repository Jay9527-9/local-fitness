#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 39 值语义推演（计划动作替换：推荐替换）。"""

GROUP_OF = {"胸大肌": "胸", "背阔肌": "背", "三角肌": "肩", "肱二头肌": "手臂"}


def recommend(current, items):
    cur_group = GROUP_OF.get(current["primary"], current["primary"])
    cur_eq = current["equipment"]
    scored = []
    for item in items:
        if item["id"] == current["id"] or item.get("hidden"):
            continue
        s = 0
        if GROUP_OF.get(item["primary"], item["primary"]) == cur_group:
            s += 3
        if item["equipment"] == cur_eq:
            s += 2
        if item["primary"] == current["primary"]:
            s += 1
        if s > 0:
            scored.append((s, item))
    scored.sort(key=lambda x: (-x[0], x[1]["name"].lower()))
    return [it for _, it in scored[:5]]


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


current = {"id": "a", "primary": "胸大肌", "equipment": "杠铃"}
items = [
    {"id": "a", "primary": "胸大肌", "equipment": "杠铃", "name": "self"},
    {"id": "b", "primary": "胸大肌", "equipment": "杠铃", "name": "上斜卧推"},
    {"id": "c", "primary": "胸大肌", "equipment": "哑铃", "name": "哑铃卧推"},
    {"id": "d", "primary": "背阔肌", "equipment": "绳索", "name": "高位下拉"},
    {"id": "e", "primary": "三角肌", "equipment": "哑铃", "name": "侧平举"},
]

print("[1 推荐替换]")
r = recommend(current, items)
expect("排除自身", [x["id"] for x in r if x["id"] == "a"], [])
expect("同肌群+同器械优先", r[0]["id"], "b")
expect("无关联不推荐", "e" in [x["id"] for x in r], False)
expect("最多 5 个", len(r) <= 5, True)

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
