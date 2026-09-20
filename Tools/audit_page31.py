#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""页面 31 规格审计（有氧训练执行页）。"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

FILES = ["Features/Training/CardioSessionView.swift",
         "Features/Training/CardioSessionMath.swift",
         "Models/Models.swift"]


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


ALL = {}
for dirpath, _, fns in os.walk(SRC):
    for name in fns:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            ALL[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in ALL.items()}
VIEW = CODE.get(FILES[0], "")
MATH = CODE.get(FILES[1], "")
MODEL = CODE.get(FILES[2], "")
PAGE = VIEW + "\n" + MATH + "\n" + MODEL

ITEMS = []


def item(label, ok):
    ITEMS.append((label, bool(ok)))


def has(text, p):
    return re.search(p, text) is not None


def not_has(text, p):
    return re.search(p, text) is None


print("== 1. 顶部栏 / 计时 ==")
item("最小化 / 结束 / 训练名称", has(VIEW, r"最小化") and has(VIEW, r"\"结束\"") and has(VIEW, r"viewModel\.name"))
item("超大训练时长", has(VIEW, r"font\(\.system\(size: 64"))
item("暂停 / 继续", has(VIEW, r"togglePause") and has(VIEW, r"已暂停"))

print("== 2. 圆环进度 ==")
item("按目标显示圆环进度", has(VIEW, r"ringProgress") and has(MATH, r"CardioRingProgress"))
item("自由训练显示已进行", has(VIEW, r"case \.free"))

print("== 3. 统计卡 / 记录数据 ==")
item("距离 / 热量 / 平均配速", has(VIEW, r"距离") and has(VIEW, r"热量") and has(VIEW, r"平均配速"))
item("未填写显示 —", has(VIEW, r"—"))
item("记录数据面板", has(VIEW, r"记录数据") and has(VIEW, r"RecordDataContent"))

print("== 4. 分段 ==")
item("添加分段 + 分段列表", has(VIEW, r"添加分段") and has(VIEW, r"segments"))
item("分段编辑 / 删除", has(VIEW, r"编辑") and has(VIEW, r"删除") and has(VIEW, r"deleteSegment"))

print("== 5. 结束确认 ==")
item("结束确认抽屉（时长/距离/热量/分段数/备注）", has(VIEW, r"showFinishConfirm") and has(VIEW, r"分段") and has(VIEW, r"finish\(\)"))
item("写入 endedAt", has(VIEW, r"finishSession"))

print("== 6. 恢复 ==")
item("按 startedAt / pausedAt 恢复", has(MODEL, r"var pausedAt") and has(MODEL, r"pausedAt \?\? \.now"))

print("== 7. 反规格 ==")
item("无 GPS / 网络 / 地图 / 社交", not_has(PAGE, r"CoreLocation|CLLocation|URLSession|MapKit|MKMapView|ShareLink|分享"))


print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"规格项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _ in gaps:
    print(f"  ✗ {label}")
sys.exit(1 if gaps else 0)
