#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 30 值语义推演（新建有氧训练）。

把 `CardioSetupValidation` 的校验与备注拼接照搬成 Python。
用法：
    python Tools/probe_page30_semantics.py
"""


def normalized_name(raw):
    return raw.strip()[:50]


def validation_error(name, goal_kind, goal_value):
    if not normalized_name(name):
        return "请填写训练名称。"
    if goal_kind != "free":
        if goal_value is None or goal_value <= 0:
            return "请填写目标数值。"
    return None


def goal_summary(goal_kind, goal_value):
    if goal_kind == "free" or goal_value is None or goal_value <= 0:
        return None
    unit = {"duration": "分钟", "distance": "公里", "calories": "千卡"}[goal_kind]
    title = {"duration": "目标时长", "distance": "目标距离", "calories": "目标热量"}[goal_kind]
    value = str(int(goal_value)) if goal_value == int(goal_value) else f"{goal_value:.1f}"
    return f"{title}：{value}{unit}"


def composed_note(goal_kind, goal_value, note):
    parts = []
    s = goal_summary(goal_kind, goal_value)
    if s:
        parts.append(s)
    t = (note or "").strip()
    if t:
        parts.append(t)
    return "\n".join(parts) if parts else None


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 校验]")
expect("空名报错", validation_error("   ", "free", None), "请填写训练名称。")
expect("自由训练不要求目标值", validation_error("晨跑", "free", None), None)
expect("目标时长缺值报错", validation_error("晨跑", "duration", None) is not None, True)

print("[2 目标摘要]")
expect("自由训练无摘要", goal_summary("free", None), None)
expect("时长摘要", goal_summary("duration", 30), "目标时长：30分钟")
expect("距离摘要", goal_summary("distance", 5), "目标距离：5公里")

print("[3 备注拼接]")
expect("摘要 + 备注", composed_note("duration", 30, "轻松跑"), "目标时长：30分钟\n轻松跑")
expect("只有备注", composed_note("free", None, "轻松跑"), "轻松跑")
expect("都为空 → nil", composed_note("free", None, "  "), None)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
