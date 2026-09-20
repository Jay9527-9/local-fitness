#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 50 值语义推演（RecoveryCategory 友好文案 + 操作集合）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


CATEGORIES = {
    "sessions": "训练记录文件无法读取",
    "plans": "训练计划文件无法读取",
    "measurements": "身体数据文件无法读取",
    "preferences": "偏好设置无法读取",
}

ACTIONS = ["重试读取", "导出诊断副本", "从备份恢复", "跳过并继续", "重置受影响数据"]


print("[1 友好位置说明]")
expect("四个类别", len(CATEGORIES), 4)
for key, title in CATEGORIES.items():
    expect(f"{key} 不含原始路径", "/Application Support" not in title and "\\" not in title, True)
    expect(f"{key} 标题非空", bool(title), True)

print("[2 操作集合]")
expect("五种操作", len(ACTIONS), 5)
expect("含重置（危险）", "重置受影响数据" in ACTIONS, True)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
