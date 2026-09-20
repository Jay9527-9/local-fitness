#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
重构等价性核对：证明「拆方法」没有改坏任何一行。

## 为什么需要

拆巨型 `body` / 路由分派方法是**纯搬运**重构 —— 逻辑一行都不该变。
但人工 review 几百行搬运，几乎必然漏看一行。

这个脚本把「搬运」变成可验证的命题：
从 `git show <rev>:<file>` 取出**旧文本**，与新文件里**拆出去的方法体**
逐行比对，报告「少了哪几行 / 多了哪几行」。

- **少了行** → 事故，说明搬运时漏了。
- **多了行** → 未必是错，可能是顺手修的 bug（这时人工确认那些行是故意的）。

## 用法

在脚本底部 `CHECKS` 里填「旧文件中的起止锚点」与「新文件中的方法名」：

    CHECKS = [
        # (旧文件起始锚点,         旧文件结束锚点,              新文件里的方法名)
        ("case .planList:",       "case .planDetail(let planID):", "profilePlanListView"),
        ("case .favorites:",      "case .trainingPreferences:",    "profileFavoritesView"),
    ]

然后：

    python Tools/verify_refactor_equivalence.py
    python Tools/verify_refactor_equivalence.py --rev HEAD~1   # 与上一个提交比

退出码：0 = 全部等价（或只多不少）；1 = 有行丢失。
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 要核对的文件（相对仓库根）
TARGET = "FitnessApp/Features/RootView.swift"

# (旧起始锚点, 旧结束锚点, 新方法名)
CHECKS = [
    ("case .planList:",                     "case .planDetail(let planID):",  "profilePlanListView"),
    ("case .favorites:",                    "case .trainingPreferences:",     "profileFavoritesView"),
    ("case .appSettings:",                  "case .unitSettings:",            "profileAppSettingsView"),
    ("case .dataManagement:",               "case .exportBackup:",            "profileDataManagementView"),
    ("case .sessionSummary(let sessionID):", "case .favorites:",              "profileSessionSummaryView"),
    ("case .sessionDraft(let sessionID):",  "case .sessionSummary",          "profileSessionDraftView"),
]


def significant(text: str):
    """留下有意义的行：非空，且不是裸的 `{` / `}`。"""
    return [
        line.strip()
        for line in text.split("\n")
        if line.strip() and line.strip() not in ("{", "}")
    ]


def slice_between(src: str, start_anchor: str, end_anchor: str) -> str:
    i = src.find(start_anchor)
    if i < 0:
        return ""
    j = src.find(end_anchor, i + len(start_anchor))
    return src[i: j if j > 0 else len(src)]


def method_body(src: str, name: str) -> str:
    """取出 `func <name>` 或 `var <name>` 的配平方法体（含外层花括号）。"""
    start = -1
    for keyword in ("func %s", "var %s"):
        start = src.find(keyword % name)
        if start >= 0:
            break
    if start < 0:
        return ""

    depth = 0
    opened = False
    brace = src.find("{", start)
    for j in range(brace, len(src)):
        c = src[j]
        if c == "{":
            depth += 1
            opened = True
        elif c == "}":
            depth -= 1
            if opened and depth == 0:
                return src[brace: j + 1]
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rev", default=None,
                    help="旧文本取自哪个 revision。缺省时依次尝试 "
                         "$REFACTOR_BASE、HEAD~1；都没有则跳过（rc=0）。")
    ap.add_argument("--list", action="store_true",
                    help="只打印当前 CHECKS 的配置，不比对")
    args = ap.parse_args()

    if args.list:
        print("要核对的 %d 处拆分：" % len(CHECKS))
        for a, b, m in CHECKS:
            print("  %-38s → %s" % (a, m))
        return 0

    if not CHECKS:
        print("重构等价性核对：CHECKS 为空，跳过。")
        print("  （在 Tools/verify_refactor_equivalence.py 底部填入要核对的拆分）")
        return 0

    rev = args.rev or os.environ.get("REFACTOR_BASE") or "HEAD~1"

    try:
        old = subprocess.run(
            ["git", "show", "%s:%s" % (rev, TARGET)],
            cwd=ROOT, capture_output=True, check=True,
        ).stdout.decode("utf-8")
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        # 拿不到旧文本（浅克隆、没有上一个提交、文件是新增的）→ 跳过而不是报红。
        # **跳过要明说**，不能静默 —— 静默的检查等于没有检查。
        print("重构等价性核对：拿不到 %s:%s 的旧文本，跳过。"
              % (rev, TARGET))
        print("  （%s）" % (exc.__class__.__name__))
        return 0

    try:
        new = open(os.path.join(ROOT, TARGET), encoding="utf-8").read()
    except OSError as exc:
        print("!! 读不到新文件：", exc)
        return 1

    print("重构等价性核对")
    print("=" * 66)
    print("  文件   %s" % TARGET)
    print("  旧文本 %s:%s" % (rev, TARGET))
    print("  比对   %d 个拆出去的方法\n" % len(CHECKS))

    lost_any = False
    for old_start, old_end, method in CHECKS:
        old_lines = significant(slice_between(old, old_start, old_end))
        # 旧片段里 `case X:` 那一行留在 switch 里，不参与比对
        old_lines = [ln for ln in old_lines if not ln.startswith("case .")]

        body = method_body(new, method)
        if not body:
            print("  !! %-30s 新文件里找不到" % method)
            lost_any = True
            continue

        new_lines = significant(body)
        # 方法签名与文档注释是搬运时新增的，不算差异。
        # **注意不要把行内注释（`// 跨 Tab ...`）也过滤掉** ——
        # 注释也是被搬运的内容，丢了说明搬运不完整。
        # 只过滤「方法自身的声明行」与「紧贴声明的 /// 文档注释」。
        head_doc = set()
        for ln in new_lines:
            if ln.startswith(("private func", "private var", "func ", "var ",
                              "static func", "@ViewBuilder")):
                break
            if ln.startswith("///"):
                head_doc.add(ln)
        new_lines = [
            ln for ln in new_lines
            if not ln.startswith(("private func", "private var", "func ", "var ",
                                  "static func", "@ViewBuilder"))
            and ln not in head_doc
        ]

        lost = [ln for ln in old_lines if ln not in new_lines]
        added = [ln for ln in new_lines if ln not in old_lines]

        flag = "!!" if lost else "ok"
        print("  %s %-30s  旧 %2d 行 → 新 %2d 行   少 %d   多 %d"
              % (flag, method, len(old_lines), len(new_lines),
                 len(lost), len(added)))
        for ln in lost[:8]:
            print("        少了: %s" % ln)
        for ln in added[:8]:
            print("        多了: %s  ← 确认这是有意新增" % ln)
        if lost:
            lost_any = True

    print()
    if lost_any:
        print("  结论：**有行丢失**，搬运时改坏了逻辑，必须人工核对。")
        return 1

    print("  结论：拆出的方法体逐行等价（`多了` 的行请确认是有意新增的）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
