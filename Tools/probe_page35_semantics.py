#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 35/36 值语义推演（历史列表分组 + 当天操作菜单决策）。"""


def group_by_day(sessions):
    groups = {}
    for s in sessions:
        key = s["date"]
        groups.setdefault(key, []).append(s)
    # 日期倒序
    return [groups[k] for k in sorted(groups.keys(), reverse=True)]


def day_menu_items(has_sessions, has_rest_day):
    items = []
    if has_sessions or has_rest_day:
        items.append("查看当天记录")
    items.append("新建力量训练")
    items.append("新建有氧训练")
    if has_rest_day:
        items.append("编辑休息日备注")
    else:
        items.append("添加休息日")
    items.append("导入个人计划到当天")
    return items


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 按日分组]")
sessions = [
    {"id": "a", "date": "2026-09-19"},
    {"id": "b", "date": "2026-09-20"},
    {"id": "c", "date": "2026-09-19"},
]
groups = group_by_day(sessions)
expect("倒序分组（最新日在前）", [g[0]["date"] for g in groups], ["2026-09-20", "2026-09-19"])
expect("同日归组", len(groups[1]), 2)

print("[2 当天菜单决策]")
expect("无记录", day_menu_items(False, False), ["新建力量训练", "新建有氧训练", "添加休息日", "导入个人计划到当天"])
expect("有休息日", day_menu_items(False, True), ["查看当天记录", "新建力量训练", "新建有氧训练", "编辑休息日备注", "导入个人计划到当天"])
expect("有训练无休息日", day_menu_items(True, False), ["查看当天记录", "新建力量训练", "新建有氧训练", "添加休息日", "导入个人计划到当天"])

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
