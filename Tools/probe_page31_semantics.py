#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 31 值语义推演（有氧训练执行：目标解析 / 圆环进度 / 配速）。"""


def parse_goal(note):
    if not note:
        return None
    for kind, prefix in [("duration", "目标时长："), ("distance", "目标距离："), ("calories", "目标热量：")]:
        if prefix in note:
            rest = note.split(prefix, 1)[1]
            digits = ""
            for ch in rest:
                if ch.isdigit() or ch == ".":
                    digits += ch
                else:
                    break
            v = float(digits) if digits else 0
            if v > 0:
                return (kind, v)
    return None


def ring_progress(goal_kind, goal_value, elapsed_seconds, distance_meters, kilocalories):
    if goal_kind == "free" or goal_value <= 0:
        return None
    if goal_kind == "duration":
        return min(1, elapsed_seconds / (goal_value * 60))
    if goal_kind == "distance":
        return min(1, distance_meters / (goal_value * 1000))
    if goal_kind == "calories":
        return min(1, kilocalories / goal_value)
    return None


def pace(from_distance_meters, elapsed_seconds):
    if from_distance_meters <= 0 or elapsed_seconds <= 0:
        return None
    return elapsed_seconds / (from_distance_meters / 1000)


def pace_text(seconds_per_km):
    if not seconds_per_km or seconds_per_km <= 0:
        return None
    m = int(seconds_per_km) // 60
    s = int(seconds_per_km) % 60
    return f"{m}′{s:02d}″/公里"


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 目标解析]")
expect("时长目标", parse_goal("目标时长：30分钟\n轻松跑"), ("duration", 30.0))
expect("距离目标", parse_goal("目标距离：5公里"), ("distance", 5.0))
expect("热量目标", parse_goal("目标热量：300千卡"), ("calories", 300.0))
expect("无目标", parse_goal("轻松跑"), None)
expect("空备注", parse_goal(None), None)

print("[2 圆环进度]")
expect("自由训练无进度", ring_progress("free", 0, 100, 0, 0), None)
expect("时长 30 分钟跑 15 分钟 = 0.5", ring_progress("duration", 30, 900, 0, 0), 0.5)
expect("距离 5 公里跑 2.5 公里 = 0.5", ring_progress("distance", 5, 0, 2500, 0), 0.5)
expect("热量 300 消耗 300 = 1", ring_progress("calories", 300, 0, 0, 300), 1.0)

print("[3 配速]")
expect("5 公里 25 分钟 = 300 秒/公里", pace(5000, 1500), 300.0)
expect("无距离 → nil", pace(0, 1500), None)
expect("配速文案", pace_text(330), "5′30″/公里")

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
