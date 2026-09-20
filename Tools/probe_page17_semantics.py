#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 17 值语义推演（个人资料编辑）。

把 `ProfileData.swift` 的 `ProfileValidation` 逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「字段规范化 / 长度限制」边界算错的手段。

重点覆盖（本页最容易算错的地方）：
1. 昵称去前后空格 + 上限 20 字符截断 + 空串归一为 nil；
2. 个人说明去前后空格 + 上限 200 字符截断 + 空串归一为 nil；
3. 训练目标枚举六个 case 与中文文案一一对应。

用法：
    python Tools/probe_page17_semantics.py
"""

# =====================================================================
# 照搬 ProfileValidation
# =====================================================================

NICKNAME_MAX = 20
BIO_MAX = 200


def normalized_nickname(raw):
    trimmed = raw.strip()
    if not trimmed:
        return None
    return trimmed[:NICKNAME_MAX]


def normalized_bio(raw):
    trimmed = raw.strip()
    if not trimmed:
        return None
    return trimmed[:BIO_MAX]


TRAINING_GOALS = {
    "muscleGain": "增肌",
    "fatLoss": "减脂",
    "strength": "力量",
    "endurance": "体能",
    "stayHealthy": "保持健康",
    "custom": "自定义",
}

# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 昵称规范化]")
expect("去前后空格", normalized_nickname("  小健  "), "小健")
expect("正常昵称原样", normalized_nickname("小健"), "小健")
expect("空串 → nil", normalized_nickname(""), None)
expect("全空白 → nil", normalized_nickname("   \t "), None)
expect("超长截断到 20", normalized_nickname("a" * 25), "a" * 20)
expect("恰好 20 不截断", normalized_nickname("测" * 20), "测" * 20)
expect("21 个中文字符截到 20", normalized_nickname("测" * 21), "测" * 20)

print("[2 个人说明规范化]")
expect("去前后空格", normalized_bio("  你好  "), "你好")
expect("空串 → nil", normalized_bio(""), None)
expect("超长截断到 200", normalized_bio("x" * 250), "x" * 200)
expect("恰好 200 不截断", normalized_bio("y" * 200), "y" * 200)

print("[3 训练目标枚举]")
expect("六个 case", len(TRAINING_GOALS), 6)
expect("增肌", TRAINING_GOALS["muscleGain"], "增肌")
expect("减脂", TRAINING_GOALS["fatLoss"], "减脂")
expect("力量", TRAINING_GOALS["strength"], "力量")
expect("体能", TRAINING_GOALS["endurance"], "体能")
expect("保持健康", TRAINING_GOALS["stayHealthy"], "保持健康")
expect("自定义", TRAINING_GOALS["custom"], "自定义")
expect("文案互不重复", len(set(TRAINING_GOALS.values())), 6)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
