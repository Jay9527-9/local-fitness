#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 40 值语义推演（递增规则：校验 + 示例预览）。"""


def validation_error(cfg):
    if not cfg["enabled"]:
        return None
    if cfg["weight_inc"] < 0.5 or cfg["weight_inc"] > 20:
        return "重量增幅需在 0.5–20 kg 之间。"
    if cfg["reps_inc"] < 1 or cfg["reps_inc"] > 10:
        return "次数增幅需在 1–10 次之间。"
    if cfg["deload_enabled"]:
        if cfg["deload_interval"] < 1:
            return "降载间隔需至少为 1 次训练。"
        if cfg["deload_percent"] <= 0 or cfg["deload_percent"] > 100:
            return "降载百分比需在 0–100 之间。"
    return None


def previews(cfg, base_weight):
    next_w = base_weight + cfg["weight_inc"]
    hit = f"若本次完成 3×10，下次建议 {next_w} kg"
    if cfg["missed"] == "deload":
        reduced = base_weight * (1 - cfg["deload_percent"] / 100)
        miss = f"若未完成目标，下次建议降至 {reduced} kg"
    else:
        miss = f"若未完成目标，下次维持 {base_weight} kg"
    return hit, miss


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 校验]")
base = {"enabled": True, "weight_inc": 2.5, "reps_inc": 2, "deload_enabled": False, "deload_interval": 4, "deload_percent": 10}
expect("合法配置通过", validation_error(base), None)
expect("关闭时跳过校验", validation_error(dict(base, enabled=False, weight_inc=99)), None)
expect("重量增幅超界", validation_error(dict(base, weight_inc=0.1)) is not None, True)
expect("次数增幅超界", validation_error(dict(base, reps_inc=99)) is not None, True)
expect("降载间隔非法", validation_error(dict(base, deload_enabled=True, deload_interval=0)) is not None, True)

print("[2 示例预览]")
hit, miss = previews(dict(base, weight_inc=2.5, missed="keep", deload_percent=10), 40)
expect("达标建议 42.5 kg", hit, "若本次完成 3×10，下次建议 42.5 kg")
expect("未达标维持", miss, "若未完成目标，下次维持 40 kg")
hit, miss = previews(dict(base, weight_inc=2.5, missed="deload", deload_percent=10), 40)
expect("降载建议 36.0 kg", miss, "若未完成目标，下次建议降至 36.0 kg")

print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
