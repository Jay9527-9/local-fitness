#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第 6 层门禁：SwiftUI 视图体规模审计。

## 为什么需要这一层

Swift 的类型检查器对**单个表达式**的规模有硬上限。超了以后它不是报
"表达式太长"，而是：

    error: failed to produce diagnostic for expression; please submit a bug report

**只指出 `var body` 所在的那一行**，不给具体原因、不给中间诊断。
在没有编译器的机器上，这类错误前五层门禁全都看不见：
括号是平衡的、类型都存在、调用点参数齐全、值语义也对 —— 全都合法，
编译器只是"算不动了"。

本项目实测：`RootView.swift` 的四个 Tab 各自一个巨型 body，
`TrainingTab.body` 达 10997 字符 / 66 层大括号，第一次真编译就被它挡住。

## 判据

对每个 `var body: some View { ... }` 及其它**返回 `some View` 的属性**
（`var xxx: some View`）测量两个指标：

  - `chars`  —— 表达式字符数
  - `braces` —— 其中的花括号层数（≈ 闭包 / 容器的嵌套深度）

任一超过阈值即报红。阈值取得比实测踩雷点低一档，留出余量。

## 说明

这是**启发式**检查，不是精确的类型检查。它的价值在于：
把"编译器会放弃的那一小撮文件"提前圈出来。误报（把还能编译的大 body
标红）代价很小 —— 拆一下本来也是好的；漏报才是事故。

用法：
    python Tools/audit_body_size.py            # 全仓扫描
    python Tools/audit_body_size.py --list     # 只列出最大的 N 个，不判红
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC_ROOT = os.path.join(ROOT, "FitnessApp")

# ---- 阈值 ----------------------------------------------------------------
# 第一次实测踩雷：RootView 的 TrainingTab.body = 10997 字符 / 66 层。
# 第二次实测踩雷：profileDestination(for:) = 7038 字符（@ViewBuilder 方法，
#   19 个 case 的巨型 switch）—— 当时阈值正好是 7000，**擦边漏过**，
#   结果 CI 报 `RootView.swift:1281 type of expression is ambiguous`。
# 教训：阈值要离踩雷点足够远，不要「刚好卡住」。
MAX_CHARS = 6000
MAX_BRACES = 40

# ---- 匹配 ----------------------------------------------------------------
# 同时覆盖**两类**返回 `some View` 的成员 —— 第二类是后来才补的：
# 1) 属性：
#      var body: some View {
#      @ViewBuilder var content: some View {
#      private var navHost: some View {
# 2) 方法（**容易漏**）：
#      @ViewBuilder private func xxxDestination(for:) -> some View {
#      private func planDetailView(planID: UUID) -> some View {
#    路由分派方法属于第 2 类。它们内部是一个巨大的 switch，
#    每个 case 的类型推理会累积到**整个方法**上，
#    最大的那几个正是踩雷点。
SOME_VIEW = re.compile(
    r"^[ \t]*(?:@\w+(?:\([^)]*\))?\s+)*"          # 属性包装器（@ViewBuilder 等）
    r"(?:(?:private|fileprivate|internal|public|open|final|static)\s+)*"
    r"(?:var\s+(\w+)\s*:\s*some\s+View"
    r"|func\s+(\w+)\s*(?:<[^>]*>)?\s*\([^)]*\)\s*->\s*some\s+View)"
    r"\s*\{",
    re.M,
)


def extract_body(src: str, brace_index: int) -> str:
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
                i += 1                      # 跳过转义字符
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

    # 没配平：交给括号平衡检查去报，这里返回剩余全部
    return src[brace_index:]


def strip_comments(seg: str) -> str:
    """去掉注释，避免注释里的说明文字撑大计数。"""
    seg = re.sub(r"/\*.*?\*/", "", seg, flags=re.S)
    seg = re.sub(r"//[^\n]*", "", seg)
    return seg


def scan_file(path: str):
    try:
        src = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return []
    out = []
    for m in SOME_VIEW.finditer(src):
        brace = src.rindex("{", m.start(), m.end())
        seg = extract_body(src, brace)
        code = strip_comments(seg)
        out.append({
            # 第 1 组是属性名，第 2 组是方法名
            "name": m.group(1) or m.group(2),
            "token": m.end(),
            "line": src[:brace].count("\n") + 1,
            "chars": len(code),
            "braces": code.count("{"),
            "path": path,
        })
    # 去重：同一个 `{` 只保留一处。属性与方法两组正则不太可能同时命中同一段，
    # 但 `-> some View {` 后面紧跟换行再 `{` 的排版会命中两次 —— 取更长的那个。
    dedup = {}
    for r in out:
        key = (r["path"], r["line"])
        if key not in dedup or r["chars"] > dedup[key]["chars"]:
            dedup[key] = r
    return list(dedup.values())


def collect():
    rows = []
    for dp, dns, fns in os.walk(SRC_ROOT):
        dns[:] = [d for d in dns if d not in (".git", "build", "DerivedData")]
        for fn in fns:
            if fn.endswith(".swift"):
                rows += scan_file(os.path.join(dp, fn))
    return rows


def main() -> int:
    listing_only = "--list" in sys.argv
    rows = collect()

    if not rows:
        print("  !! 没有扫到任何 some View 属性 —— 说明匹配规则失效了，")
        print("     不是「代码很干净」。请检查 SOME_VIEW 正则。")
        return 1

    big = [r for r in rows if r["chars"] > MAX_CHARS or r["braces"] > MAX_BRACES]

    if listing_only:
        print(f"共 {len(rows)} 个 some View 属性，最大的 15 个：")
        for r in sorted(rows, key=lambda r: -r["chars"])[:15]:
            rel = os.path.relpath(r["path"], ROOT)
            flag = "  <== 超阈值" if r in big else ""
            print(f"  {r['chars']:>6} 字符 / {r['braces']:>3} 层  "
                  f"{r['name']}  行 {r['line']}  {rel}{flag}")
        return 0

    print("=" * 62)
    print(" SwiftUI 视图体规模审计（防类型检查器放弃）")
    print(f" 阈值：{MAX_CHARS} 字符 / {MAX_BRACES} 层大括号")
    print("=" * 62)
    print(f"  扫描 {len(rows)} 个 some View 属性")

    # 不管过不过，都列出最大的几个，便于观察趋势
    print("\n  最大的 5 个：")
    for r in sorted(rows, key=lambda r: -r["chars"])[:5]:
        rel = os.path.relpath(r["path"], ROOT)
        mark = "!!" if r in big else "  "
        print(f"   {mark} {r['chars']:>6} 字符 / {r['braces']:>3} 层  "
              f"{r['name']}  行 {r['line']}  {rel}")

    if not big:
        print("\n  [ ok ] 无视图体超过阈值")
        return 0

    print(f"\n  有 {len(big)} 个视图体超过阈值：\n")
    for r in sorted(big, key=lambda r: -r["chars"]):
        rel = os.path.relpath(r["path"], ROOT)
        why = []
        if r["chars"] > MAX_CHARS:
            why.append(f"字符 {r['chars']} > {MAX_CHARS}")
        if r["braces"] > MAX_BRACES:
            why.append(f"层数 {r['braces']} > {MAX_BRACES}")
        print(f"    {rel}:{r['line']}  {r['name']}")
        print(f"       {', '.join(why)}")
    print("""
  修法（按这个顺序，不要试图"精简"内容）：
    1. 把 `body` 拆成几个 `private var xxx: some View`，
       每个只负责一层：导航宿主 / 路由分派 / 弹出层。
    2. 路由 switch 单独成方法：`private func xxxDestination(for:) -> some View`。
       一个 case 一个页面，一个页面一个构造调用。
    3. 单个 case 里若还有 3 个以上闭包 + 嵌套 sheet，再拆一层。
    4. 不要用 `AnyView` 去"压"类型 —— 那是运行时开销，不解决检查规模。

  注意：这类错误在**没有编译器的机器上前五层门禁全都看不见**
  （括号平衡、类型存在、调用点齐全、值语义都对），
  只有真编译会以 `failed to produce diagnostic for expression` 报出来。
""")
    return 1


if __name__ == "__main__":
    sys.exit(main())
