#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
页面 20 值语义推演（导入本地备份）。

把 `ImportBackup.swift` 的纯函数逐字照搬成 Python，跑断言表。
本机没有 Swift 编译器，这是抓「合并模式 / 冲突策略 / 计数 / 动作并集收藏 /
预检分支」边界算错的手段。

用法：
    python Tools/probe_page20_semantics.py
"""


# =====================================================================
# 照搬 ImportBackup.swift 的纯逻辑
# =====================================================================

def conflicts_resolved(c):
    return c["updated"] + c["skipped"]


def add_counts(a, b):
    return {
        "added": a["added"] + b["added"],
        "updated": a["updated"] + b["updated"],
        "skipped": a["skipped"] + b["skipped"],
    }


def dedupe_by_key(items, key):
    seen = set()
    out = []
    for it in items:
        k = key(it)
        if k not in seen:
            seen.add(k)
            out.append(it)
    return out


def merge(existing, incoming, key, mode, policy):
    incoming_deduped = dedupe_by_key(incoming, key)

    # 覆盖本机全部数据：本机丢弃，只保留备份（去重后）
    if mode == "replace":
        return list(incoming_deduped), {"added": len(incoming_deduped), "updated": 0, "skipped": 0}

    result = list(existing)
    existing_keys = set(key(x) for x in existing)
    counts = {"added": 0, "updated": 0, "skipped": 0}

    for item in incoming_deduped:
        k = key(item)
        if k in existing_keys:
            backup_wins = (policy == "keepBackup")
            if backup_wins:
                for i, x in enumerate(result):
                    if key(x) == k:
                        result[i] = item
                        counts["updated"] += 1
                        break
            else:
                counts["skipped"] += 1
        else:
            result.append(item)
            counts["added"] += 1
    return result, counts


def merge_sessions(existing, incoming, mode, policy):
    # sessions 按 id 去重，再按 started 升序（incoming 与最终结果都排）
    deduped = dedupe_by_key(incoming, lambda s: s["id"])
    deduped.sort(key=lambda s: s["started"])
    result, counts = merge(existing, deduped, lambda s: s["id"], mode, policy)
    result.sort(key=lambda s: s["started"])
    return result, counts


def merge_exercises(existing, incoming, mode, policy):
    customs = [e for e in incoming if e["custom"]]
    favorites = [e for e in incoming if e["favorite"] and not e["custom"]]

    deduped = dedupe_by_key(customs, lambda e: e["id"])
    deduped.sort(key=lambda e: e["id"])
    library, counts = merge(existing, deduped, lambda e: e["id"], mode, policy)

    fav_ids = set(e["id"] for e in favorites)
    for i, e in enumerate(library):
        if e["id"] in fav_ids:
            e = dict(e)
            e["favorite"] = True
            library[i] = e
    return library, counts


def has_content(b):
    return bool(
        b.get("sessions") or b.get("plans") or b.get("exercises")
        or b.get("measurements") or b.get("preferences") is not None
        or b.get("profile") is not None
    )


# =====================================================================
ok = True
count = 0


def expect(label, got, want):
    global ok, count
    count += 1
    good = (got == want)
    ok = ok and good
    print(f"  {'[ok]  ' if good else '[FAIL]'} {label}: 得 {got!r}, 期望 {want!r}")


print("[1 计数]")
c = {"added": 1, "updated": 2, "skipped": 3}
expect("冲突解决 = 更新 + 跳过", conflicts_resolved(c), 5)
c2 = add_counts({"added": 1, "updated": 0, "skipped": 2}, {"added": 3, "updated": 1, "skipped": 0})
expect("计数累加", c2, {"added": 4, "updated": 1, "skipped": 2})

print("[2 通用合并]")
# existing: a(1) b(2)；incoming: b(2->改) c(3) 及重复 b
existing = [{"id": "a", "v": 1}, {"id": "b", "v": 2}]
incoming = [{"id": "b", "v": 99}, {"id": "b", "v": 99}, {"id": "c", "v": 3}]

r, cnt = merge(existing, incoming, lambda x: x["id"], "merge", "keepLocal")
expect("merge+keepLocal：冲突跳过", cnt, {"added": 1, "updated": 0, "skipped": 1})
expect("merge+keepLocal：本机 b 保留 v=2", [x["v"] for x in r if x["id"] == "b"], [2])

r, cnt = merge(existing, incoming, lambda x: x["id"], "merge", "keepBackup")
expect("merge+keepBackup：冲突更新", cnt, {"added": 1, "updated": 1, "skipped": 0})
expect("merge+keepBackup：b 被覆盖为 99", [x["v"] for x in r if x["id"] == "b"], [99])

r, cnt = merge(existing, incoming, lambda x: x["id"], "replace", "keepLocal")
expect("replace：覆盖本机（本机 a 被丢弃）", [x["id"] for x in r], ["b", "c"])
expect("replace：全部按新增计数", cnt, {"added": 2, "updated": 0, "skipped": 0})
expect("replace：b 被覆盖为 99", [x["v"] for x in r if x["id"] == "b"], [99])

print("[3 训练记录合并]")
s_existing = [{"id": "s1", "started": 1}, {"id": "s2", "started": 2}]
s_incoming = [{"id": "s2", "started": 5}, {"id": "s3", "started": 0}, {"id": "s3", "started": 9}]
r, cnt = merge_sessions(s_existing, s_incoming, "merge", "keepBackup")
expect("会话去重（s3 只保留先出现）", len([x for x in r if x["id"] == "s3"]), 1)
expect("会话排序按 started 升序", [x["id"] for x in r], ["s3", "s1", "s2"])
expect("会话计数", cnt, {"added": 1, "updated": 1, "skipped": 0})

print("[4 动作合并 + 收藏]")
e_existing = [{"id": "e1", "custom": True, "favorite": False}]
e_incoming = [
    {"id": "e1", "custom": True, "favorite": True},   # 自建，更新并带收藏
    {"id": "e2", "custom": False, "favorite": True},  # 内置收藏
    {"id": "e3", "custom": True, "favorite": False},  # 新自建
]
r, cnt = merge_exercises(e_existing, e_incoming, "merge", "keepBackup")
expect("动作计数只算自定义", cnt, {"added": 1, "updated": 1, "skipped": 0})
fav = {x["id"]: x.get("favorite", False) for x in r}
expect("e1 更新且带收藏", fav.get("e1"), True)
expect("新自建 e3 存在", any(x["id"] == "e3" for x in r), True)
expect("内置 e2 收藏未生成条目", any(x["id"] == "e2" for x in r), False)

print("[5 内容判定]")
expect("全空无内容", has_content({"sessions": [], "plans": [], "exercises": [], "measurements": [], "preferences": None, "profile": None}), False)
expect("有偏好即有内容", has_content({"sessions": [], "plans": [], "exercises": [], "measurements": [], "preferences": {"rest": 90}, "profile": None}), True)

# =====================================================================
print("\n" + "=" * 72)
print(f"全部{'通过' if ok else '存在失败'}：{count} 项断言")
import sys
sys.exit(0 if ok else 1)
