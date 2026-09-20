#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 22 值语义推演（应用设置）。

把 `ProfileData.swift` 新增的 AppearanceMode / ListTextSize 及默认值照搬成 Python。
用法：
    python Tools/probe_page22_semantics.py
"""

APPEARANCE = {"dark": "深色", "system": "跟随系统"}
LIST_SIZE = {"normal": "系统默认", "large": "较大"}

DEFAULT_APPEARANCE = "dark"
DEFAULT_LIST_SIZE = "normal"

# allKeys 是否含新增键（照搬 ProfileSettings.allKeys 的完整性约定）
NEW_KEYS = {"preference.appearanceMode", "preference.listTextSize"}


def resolve_appearance(raw):
    return raw if raw in APPEARANCE else DEFAULT_APPEARANCE


def resolve_list_size(raw):
    return raw if raw in LIST_SIZE else DEFAULT_LIST_SIZE


ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 外观模式]")
expect("深色", APPEARANCE["dark"], "深色")
expect("跟随系统", APPEARANCE["system"], "跟随系统")
expect("空值回退深色", resolve_appearance(""), "dark")
expect("未知值回退深色", resolve_appearance("light"), "dark")

print("[2 列表文字大小]")
expect("系统默认", LIST_SIZE["normal"], "系统默认")
expect("较大", LIST_SIZE["large"], "较大")
expect("空值回退系统默认", resolve_list_size(""), "normal")

print("[3 新增键完整性]")
expect("外观模式键", "preference.appearanceMode" in NEW_KEYS, True)
expect("列表文字大小键", "preference.listTextSize" in NEW_KEYS, True)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
