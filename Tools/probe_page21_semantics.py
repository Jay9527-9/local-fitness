#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 21 值语义推演（导入冲突处理）。

把 `ImportConflict.swift` 的纯函数逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「冲突数量 / 影响摘要 / 策略映射」边界算错的手段。

用法：
    python Tools/probe_page21_semantics.py
"""


# =====================================================================
# 照搬 ImportConflict.swift 的纯逻辑
# =====================================================================

STRATEGIES = {
    "mergeKeepLocal": {"mode": "merge", "policy": "keepLocal"},
    "mergeKeepBackup": {"mode": "merge", "policy": "keepBackup"},
    "replaceAll": {"mode": "replace", "policy": "keepBackup"},
}


def category_impact(existing_ids, incoming_ids):
    existing = set(existing_ids)
    added = conflicts = 0
    for i in incoming_ids:
        if i in existing:
            conflicts += 1
        else:
            added += 1
    return {"added": added, "conflicts": conflicts}


def impact(sessions, plans, exercises, measurements, backup):
    return {
        "sessions": category_impact(sessions, backup["sessions"]),
        "plans": category_impact(plans, backup["plans"]),
        "measurements": category_impact(measurements, backup["measurements"]),
        "exercises": category_impact(exercises, backup["exercises"]),
    }


def totals(imp):
    added = sum(imp[k]["added"] for k in imp)
    conflicts = sum(imp[k]["conflicts"] for k in imp)
    return added, conflicts


def summary_text(imp, mode, policy):
    added, conflicts = totals(imp)
    if mode == "merge":
        if added == 0 and conflicts == 0:
            return "备份与本机数据一致，没有需要变更的条目。"
        parts = []
        if added > 0:
            parts.append("新增 %d 条" % added)
        if conflicts > 0:
            label = "以本机为准" if policy == "keepLocal" else "以备份为准"
            parts.append("%d 个冲突按「%s」处理" % (conflicts, label))
        return "将" + "，".join(parts) + "。"
    # replace
    total = added + conflicts
    if total == 0:
        return "覆盖后本机数据将被清空。"
    return "将删除本机数据，导入备份中的 %d 条数据。" % total


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 冲突数量]")
backup = {"sessions": ["s1", "s2", "s3"], "plans": ["p1"], "measurements": ["m1"], "exercises": ["e1", "e2"]}
imp = impact(["s1", "s9"], ["p1"], ["e1"], ["m9"], backup)
expect("会话：s1 冲突、s2/s3 新增", imp["sessions"], {"added": 2, "conflicts": 1})
expect("计划：p1 冲突", imp["plans"], {"added": 0, "conflicts": 1})
expect("身体数据：m1 新增", imp["measurements"], {"added": 1, "conflicts": 0})
expect("动作：e1 冲突、e2 新增", imp["exercises"], {"added": 1, "conflicts": 1})

print("[2 影响摘要]")
expect("合并保留本机", summary_text(imp, "merge", "keepLocal"), "将新增 4 条，3 个冲突按「以本机为准」处理。")
expect("合并优先备份", summary_text(imp, "merge", "keepBackup"), "将新增 4 条，3 个冲突按「以备份为准」处理。")
expect("覆盖全部", summary_text(imp, "replace", "keepBackup"), "将删除本机数据，导入备份中的 7 条数据。")
expect("空影响", summary_text({k: {"added": 0, "conflicts": 0} for k in imp}, "merge", "keepLocal"), "备份与本机数据一致，没有需要变更的条目。")
expect("空覆盖", summary_text({k: {"added": 0, "conflicts": 0} for k in imp}, "replace", "keepBackup"), "覆盖后本机数据将被清空。")

print("[3 策略映射]")
expect("策略1 映射", STRATEGIES["mergeKeepLocal"], {"mode": "merge", "policy": "keepLocal"})
expect("策略2 映射", STRATEGIES["mergeKeepBackup"], {"mode": "merge", "policy": "keepBackup"})
expect("策略3 映射（覆盖）", STRATEGIES["replaceAll"], {"mode": "replace", "policy": "keepBackup"})

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
