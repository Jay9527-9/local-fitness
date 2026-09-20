#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 18 值语义推演（本地数据管理）。

把 `LocalDataBackup.swift` 的纯函数逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「备份范围裁剪 / 内容判定 / 存储占用文案 /
解码校验分支」边界算错的手段。

用法：
    python Tools/probe_page18_semantics.py
"""

FORMAT_ID = "fitness-localdata-backup"
CURRENT_VERSION = 1


# =====================================================================
# 照搬 LocalDataBackup 的纯逻辑
# =====================================================================

def make_backup(sessions, plans, measurements, profile, scope):
    # 只导出已完成的训练，按开始时间升序
    finished = sorted(
        [s for s in sessions if s["finished"]],
        key=lambda s: s["started"],
    )
    return {
        "format": FORMAT_ID,
        "version": CURRENT_VERSION,
        "sessions": finished if "sessions" in scope else [],
        "plans": plans if "plans" in scope else [],
        "measurements": measurements if "measurements" in scope else [],
        "profile": profile if "profile" in scope else None,
    }


def has_content(b):
    return bool(b["sessions"] or b["plans"] or b["measurements"] or b["profile"] is not None)


def count_summary(b):
    parts = []
    if b["sessions"]:
        parts.append("训练记录 %d 条" % len(b["sessions"]))
    if b["plans"]:
        parts.append("计划 %d 个" % len(b["plans"]))
    if b["measurements"]:
        parts.append("身体数据 %d 条" % len(b["measurements"]))
    if b["profile"] is not None:
        parts.append("个人资料")
    return "，".join(parts) if parts else "无内容"


def format_bytes(n):
    if n < 1024:
        return "不足 1 KB" if n <= 0 else "%d B" % n
    kb = n / 1024.0
    if kb < 1024:
        return "%.1f KB" % kb
    mb = kb / 1024.0
    return "%.1f MB" % mb


def validate(backup, current_version=CURRENT_VERSION):
    """照搬 decode 里 JSON 解析成功后的校验分支（空文件/非 JSON 在更外层）。"""
    if backup.get("format") != FORMAT_ID:
        return ("wrongFormat", backup.get("format", ""))
    if backup.get("version", 0) > current_version:
        return ("unsupportedVersion", backup["version"])
    if not has_content(backup):
        return ("noContent", None)
    return ("ok", None)


def session(sid, started, finished=True):
    return {"id": sid, "started": started, "finished": finished}


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 备份范围裁剪]")
ss = [session("a", 1), session("b", 2), session("c", 3, finished=False)]
plans = [{"id": "p1"}]
ms = [{"id": "m1"}]
prof = {"nickname": "小健"}

b = make_backup(ss, plans, ms, prof, {"sessions", "plans", "measurements", "profile"})
expect("全选时四类都在", (len(b["sessions"]), len(b["plans"]), len(b["measurements"]), b["profile"] is not None), (2, 1, 1, True))

b = make_backup(ss, plans, ms, prof, {"sessions"})
expect("只选训练记录时其余为空", (len(b["plans"]), len(b["measurements"]), b["profile"]), (0, 0, None))
expect("进行中的草稿不导出", len(b["sessions"]), 2)

b = make_backup(ss, plans, ms, prof, set())
expect("空范围则全空", has_content(b), False)

print("[2 内容判定]")
expect("四类都空 → 无内容", has_content({"sessions": [], "plans": [], "measurements": [], "profile": None}), False)
expect("仅有一项计划 → 有内容", has_content({"sessions": [], "plans": [{"id": "p"}], "measurements": [], "profile": None}), True)
expect("仅有资料 → 有内容", has_content({"sessions": [], "plans": [], "measurements": [], "profile": {"n": "x"}}), True)

print("[3 内容摘要]")
full = make_backup(ss, plans, ms, prof, {"sessions", "plans", "measurements", "profile"})
expect("摘要含四类", count_summary(full), "训练记录 2 条，计划 1 个，身体数据 1 条，个人资料")
expect("空备份摘要为「无内容」", count_summary({"sessions": [], "plans": [], "measurements": [], "profile": None}), "无内容")

print("[4 存储占用文案]")
expect("0 → 不足 1 KB", format_bytes(0), "不足 1 KB")
expect("500 B", format_bytes(500), "500 B")
expect("1.5 KB", format_bytes(1536), "1.5 KB")
expect("2 MB", format_bytes(2 * 1024 * 1024), "2.0 MB")

print("[5 解码校验分支]")
expect("格式不对", validate({"format": "other", "version": 1, "sessions": [session("a", 1)]}), ("wrongFormat", "other"))
expect("版本过高", validate({"format": FORMAT_ID, "version": 2, "sessions": [session("a", 1)]}), ("unsupportedVersion", 2))
expect("无内容", validate({"format": FORMAT_ID, "version": 1, "sessions": [], "plans": [], "measurements": [], "profile": None}), ("noContent", None))
expect("合法备份", validate({"format": FORMAT_ID, "version": 1, "sessions": [session("a", 1)], "plans": [], "measurements": [], "profile": None}), ("ok", None))

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
