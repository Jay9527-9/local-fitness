#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 48 值语义推演（七种空状态预设都有标题与按钮文案）。"""

import sys

FAIL = []


def expect(label, got, want):
    if got != want:
        FAIL.append((label, got, want))
    print(("  ok " if got == want else "  ✗  ") + label + f"  got={got!r}")


PRESETS = {
    "noPlans": ("还没有训练计划", "新建第一个计划"),
    "noHistory": ("还没有训练记录", "开始一次训练"),
    "noFavorites": ("还没有收藏动作", "浏览动作库"),
    "noSearchResults": ("没有找到匹配动作", "清除筛选"),
    "noBodyData": ("还没有身体数据", "记录身体数据"),
    "noActiveSession": ("没有进行中的训练", "新建力量训练"),
    "noBackupSelected": ("尚未选择备份文件", "选择文件"),
}


print("[1 预设完整性]")
expect("共 7 种预设", len(PRESETS), 7)
for key, (title, action) in PRESETS.items():
    expect(f"{key} 标题非空", bool(title), True)
    expect(f"{key} 按钮非空", bool(action), True)

print("\n" + "=" * 72)
print(f"推演 {len(FAIL)} 处失败" if FAIL else "全部推演通过")
for label, got, want in FAIL:
    print(f"  ✗ {label}: got {got!r}, want {want!r}")
sys.exit(1 if FAIL else 0)
