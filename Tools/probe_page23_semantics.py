#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 23/24 值语义推演（自定义动作表单）。

把 `CustomExerciseForm.swift` 的纯函数照搬成 Python。
用法：
    python Tools/probe_page23_semantics.py
"""


def normalized_name(raw):
    trimmed = raw.strip()
    if not trimmed:
        return None
    return trimmed[:50]


def has_duplicate(raw, existing_names, excluding=None):
    n = normalized_name(raw)
    if n is None:
        return False
    return any(name != (excluding or "") and name.strip().lower() == n.lower()
               for name in existing_names)


def normalized_steps(raw):
    return [s.strip() for s in raw if s.strip()]


def plans_referencing(exercise_id, plans):
    return [p for p in plans if any(e["exerciseID"] == exercise_id for e in p["exercises"])]


def removing_references(exercise_id, plans):
    out = []
    for p in plans:
        copy = {"name": p["name"], "exercises": [e for e in p["exercises"] if e["exerciseID"] != exercise_id]}
        out.append(copy)
    return out


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 名称规范化]")
expect("空名 → nil", normalized_name("   "), None)
expect("去空白", normalized_name("  卧推  "), "卧推")
expect("50 字截断", len(normalized_name("字" * 60)), 50)

print("[2 重名检测]")
expect("重名（忽略大小写）", has_duplicate(" 卧推 ", ["卧推", "深蹲"]), True)
expect("不重名", has_duplicate("硬拉", ["卧推", "深蹲"]), False)
expect("编辑时排除自身", has_duplicate("卧推", ["卧推"], excluding="卧推"), False)

print("[3 分步规范化]")
expect("去空步骤", normalized_steps(["第一步 ", "  ", "第二步"]), ["第一步", "第二步"])
expect("全空 → 空数组", normalized_steps(["", "  "]), [])

print("[4 计划引用]")
plans = [
    {"name": "推拉腿", "exercises": [{"exerciseID": "e1"}, {"exerciseID": "e2"}]},
    {"name": "上肢", "exercises": [{"exerciseID": "e3"}]},
]
expect("引用 e1 的计划", [p["name"] for p in plans_referencing("e1", plans)], ["推拉腿"])
expect("无引用 → 空", plans_referencing("e9", plans), [])
removed = removing_references("e1", plans)
expect("移除后推拉腿只剩 e2", [e["exerciseID"] for e in removed[0]["exercises"]], ["e2"])
expect("其它计划不变", [e["exerciseID"] for e in removed[1]["exercises"]], ["e3"])

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
