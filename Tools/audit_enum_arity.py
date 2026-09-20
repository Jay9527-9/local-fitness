#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第 7 层门禁：枚举关联值**个数**匹配审计。

## 为什么需要这一层

实测踩雷（CI run 35497818607）：

    RootView.swift:1358:10: error: type of expression is ambiguous
                            without a type annotation
            .navigationBarHidden(true)

编译器把错误指在 `homeRoot` 的**链尾修饰符**上，但根因在十几行之上：

    case .inProgress(let sessionID, _, _)      // 只写了 3 个占位
    // 而枚举声明是 5 个关联值：
    //   case inProgress(sessionID: UUID, name: String,
    //                   completedSets: Int, totalSets: Int,
    //                   elapsedSeconds: Int)

**少写 `_` 不报「参数个数不对」** —— 因为匹配不上时 Swift 不会说
「这个 case 有 5 个值你给了 3 个」，而是整段 `switch` 的类型推理失败，
最终以 ambiguous 报在**离现场很远**的地方。

这类错误前六层门禁全都看不见：
  - L1 括号平衡   ✓ 括号是配平的
  - L2 类型存在   ✓ `_` 不是类型，没什么可查
  - L5 调用点     ✓ 这不是**函数实参**，是**模式绑定**，标签表管不到
  - L6 规模       ✓ `homeRoot` 只有 1602 字符，远低于阈值

## 判据

1. 收集全仓 `enum` 的每个 `case` 及其**关联值个数**（能处理多行声明）。
2. 找到所有模式匹配位置：`case .name(...)`、`if case .name(...)`、
   `guard case .name(...)`。
3. 逐个比对个数。不等即报红。

## 同名 case 的归属消解（这一条决定了门禁有没有用）

`sessionDraft` / `planDetail` 这类**路由** case 在 4 个 `XxxRoute` 枚举里
各有一份，模式里只写 `.sessionDraft(id)` 看不出是哪一个。首版一律跳过，
结果 73 个匹配点里有 41 个被跳过 —— 门禁成了摆设。

正确的做法是**按「候选归属是否一致」判**：
  - 候选枚举们对该 case 的关联值个数**都相同** → 个数是确定的，
    照常比对（路由 case 全是 1 个，天然满足）。
  - 个数**不一致** → 确实分不清，跳过并计数。
这样 41 个跳过降为个位数，同时不引入误报。

## 已知的保守处理（宁可漏报不误报）

- 只比**个数**，不比类型。`case .x(let a, let b)` 对上
  `case x(Int, String)` 算过 —— 类型错交给 L2/L5。
- 模式里写 `case let .x(a, b)` 或带 `where` 子句的都取括号内那一段。
- `case .x, let y = 1` 这种「模式 + 新绑定」混写的，只取 `.x` 那一段。
- 模式里出现 `let .x(...)` 之外的可变写法（如整段 `case .x = value`）不计。

用法：
    python Tools/audit_enum_arity.py            # 全仓扫描
    python Tools/audit_enum_arity.py --list     # 列出所有枚举 case 与个数
"""

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ROOT = os.path.join(ROOT, "FitnessApp")


# ---- 第一步：收集枚举 case 声明 ------------------------------------------

# 枚举体：`enum Name` 后面的第一个 `{` 到配平的 `}`。
ENUM_START = re.compile(
    r"^[ \t]*(?:(?:public|internal|fileprivate|private|indirect)\s+)*"
    r"enum\s+(\w+)[^{;]*\{",
    re.M,
)

# case 声明：`case name(类型列表)` / `case name = 值` / `case a, b`
# 这里只关心带关联值的那个分支。
#
# **必须排除 `case let (a?, b?):` 这种元组解构**：首版把 `let` 当成了
# case 名，于是报出 `PlanListSorting.let` 这类幽灵条目。
# 做法是给关键字加负向前瞻 —— case 名不能是 let / var / is / as。
CASE_DECL = re.compile(
    r"(?:^|\n)[ \t]*case\s+(?!let\b|var\b|is\b|as\b)([A-Za-z_]\w*)\s*\(",
)


def extract_braces(src: str, brace_index: int) -> str:
    """从 `{` 开始取出配平的整段，正确跳过字符串与注释。"""
    depth = 0
    i = brace_index
    n = len(src)
    in_str = False
    in_line_comment = False
    in_block_comment = False
    block_depth = 0

    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""

        if in_line_comment:
            if c == "\n":
                in_line_comment = False
        elif in_block_comment:
            if c == "/" and nxt == "*":
                block_depth += 1
                i += 1
            elif c == "*" and nxt == "/":
                block_depth -= 1
                i += 1
                if block_depth == 0:
                    in_block_comment = False
        elif in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line_comment = True
                i += 1
            elif c == "/" and nxt == "*":
                in_block_comment = True
                block_depth = 1
                i += 1
            elif c == '"':
                in_str = True
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    return src[brace_index:i + 1]
        i += 1
    return src[brace_index:]


def split_top_level(inner: str) -> list:
    """按顶层逗号切分形参/模式列表。

    必须做深度跟踪：`(Int, [String: [Int, Int]])` 里的逗号
    不能算分隔符，否则个数会数错 —— 而这正是本脚本要数的东西。
    """
    parts = []
    depth = 0
    cur = []
    in_str = False
    i = 0
    n = len(inner)
    while i < n:
        c = inner[i]
        if in_str:
            cur.append(c)
            if c == "\\":
                i += 1
                if i < n:
                    cur.append(inner[i])
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
            cur.append(c)
        elif c in "([{<":
            depth += 1
            cur.append(c)
        elif c in ")]}>":
            depth -= 1
            cur.append(c)
        elif c == "," and depth == 0:
            parts.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    tail = "".join(cur).strip()
    if tail:
        parts.append(tail)
    return [p for p in parts if p]


def read_paren_group(src: str, open_index: int) -> str:
    """从 `(` 取到配平的 `)`，返回括号内的内容。"""
    depth = 0
    i = open_index
    n = len(src)
    in_str = False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return src[open_index + 1:i]
        i += 1
    return src[open_index + 1:]


def collect_enum_cases(rows):
    """返回 {(enum, case): 关联值个数} 与 {case: [enum...]} 反向索引。"""
    arity = {}
    owners = defaultdict(set)

    for path in rows:
        try:
            src = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        for em in ENUM_START.finditer(src):
            enum_name = em.group(1)
            brace = src.rindex("{", em.start(), em.end())
            body = extract_braces(src, brace)
            for cm in CASE_DECL.finditer(body):
                case_name = cm.group(1)
                paren = body.index("(", cm.start())
                inner = read_paren_group(body, paren)
                args = split_top_level(inner)
                if not args:
                    continue
                key = (enum_name, case_name)
                # 同一 case 只声明一次；重复则按先出现的记
                arity.setdefault(key, len(args))
                owners[case_name].add(enum_name)

    return arity, owners


# ---- 第二步：收集模式匹配点 ----------------------------------------------

# `case .name(` / `case let .name(` / `if case .name(` / `guard case .name(`
#
# 关键：`.` 之前必须**不是**标识符（负向后顾）。否则
#   `case .x, let foo(bar)` 里的 `let foo(` 会被当成 `.foo(`
#   —— 首版就是这么误报出 `FavoriteExercisesFilter.let` 的。
PATTERN = re.compile(
    r"(?<![A-Za-z0-9_.])(?:case\s+)(?:let\s+)?\.\s*([A-Za-z_]\w*)\s*\(",
)

# 声明处不能算模式：`case name(` 后面没有点。
# 上面的正则强制要求 `.`，所以声明天然不会命中。好。


def scan_patterns(rows):
    hits = []
    for path in rows:
        try:
            src = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        lines = src.split("\n")
        for m in PATTERN.finditer(src):
            name = m.group(1)
            paren = src.index("(", m.start())
            inner = read_paren_group(src, paren)
            args = split_top_level(inner)
            hits.append({
                "name": name,
                "count": len(args),
                "line": src[: m.start()].count("\n") + 1,
                "text": lines[src[: m.start()].count("\n")].strip(),
                "path": path,
            })
    return hits


def main() -> int:
    rows = []
    for dp, dns, fns in os.walk(SRC_ROOT):
        dns[:] = [d for d in dns if d not in (".git", "build", "DerivedData")]
        for fn in fns:
            if fn.endswith(".swift"):
                rows.append(os.path.join(dp, fn))

    if not rows:
        print("  !! 没扫到任何 .swift 文件，匹配规则或目录结构变了。")
        return 1

    arity, owners = collect_enum_cases(rows)
    hits = scan_patterns(rows)

    if "--list" in sys.argv:
        if not arity or not hits:
            print("  !! 扫描结果为空（枚举 %d 个 / 匹配点 %d 个）—— "
                  "匹配规则失效了，不是「代码很干净」。"
                  % (len(arity), len(hits)))
            return 1
        print(f"共 {len(arity)} 个带关联值的枚举 case：")
        for (enum_name, case_name), cnt in sorted(arity.items()):
            print(f"  {cnt:>2} 个  {enum_name}.{case_name}")
        print(f"\n共 {len(hits)} 个模式匹配点。")
        return 0

    print("=" * 62)
    print(" 枚举关联值个数审计（防 ambiguous 掩盖模式绑定错）")
    print("=" * 62)
    print(f"  枚举 case  {len(arity)} 个 / 模式匹配点 {len(hits)} 个")

    if not arity:
        print("\n  !! 没有扫到任何带关联值的枚举 —— 匹配规则失效了。")
        return 1
    if not hits:
        print("\n  !! 没有扫到任何模式匹配点 —— 匹配规则失效了。")
        return 1

    bad = []
    inconsistent_skipped = 0
    unknown = 0

    for h in hits:
        candidates = owners.get(h["name"], set())
        if not candidates:
            unknown += 1
            continue

        # 消解同名归属：看候选枚举们对该 case 声明的个数是否一致。
        # 一致（路由 case 全是 1 个）→ 个数是确定的，照常比对；
        # 不一致 → 从模式本身确实分不清，跳过。
        counts = {arity[(e, h["name"])] for e in candidates}
        if len(counts) > 1:
            inconsistent_skipped += 1
            continue

        expect = next(iter(counts))
        if expect != h["count"]:
            rel = os.path.relpath(h["path"], ROOT)
            owner = "/".join(sorted(candidates))
            bad.append((rel, h, owner, expect))

    print(f"  跳过：同名个数还不一致 {inconsistent_skipped} 个 / 非枚举模式 {unknown} 个")

    if not bad:
        print("\n  [ ok ] 所有模式绑定的关联值个数都对得上")
        return 0

    print(f"\n  有 {len(bad)} 处个数不匹配：\n")
    for rel, h, owner, expect in bad:
        print(f"    {rel}:{h['line']}")
        print(f"       {h['text']}")
        print(f"       {owner}.{h['name']} 声明了 {expect} 个关联值，"
              f"模式里绑了 {h['count']} 个")
    print("""
  这不是「参数个数不对」——Swift 不会这么报。
  它会以 `type of expression is ambiguous without a type annotation`
  报在**离这里很远的**某个修饰符或链尾上，因为整段 match 推不出类型。

  修法：把 `_` 的个数补/删到与声明一致。
        校验用 `python Tools/audit_enum_arity.py --list` 查声明个数。
""")
    return 1


if __name__ == "__main__":
    sys.exit(main())
