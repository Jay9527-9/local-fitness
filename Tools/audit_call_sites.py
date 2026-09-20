#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第 5 层门禁：**调用点与声明的参数个数/标签一致性**。

为什么需要这一层
----------------
前四层（preflight / lint_swift / audit_pageNN / probe_pageNN）都是**单文件内**的
文本与值语义检查。2026-09-20 第一次真编译（GitHub Actions macOS runner）暴露出
14 个编译错误，其中 **5 个是纯调用点问题**：

    TrainingHomeView.swift:623   missing arguments for 'onResumeSession', 'onOpenRecovery'
    ImportBackupView.swift:339   extra arguments at positions #1, #2, #3
    OnboardingView.swift:147     cannot convert '[BodyWeightUnit]' to 'BodyWeightUnit.Type'
    PlanListView.swift:259       argument 'titleVisibility' must precede 'presenting'
    FavoriteExercisesView.swift  viewModel. 前缀挂到了 View 自己的计算属性上

它们的共同点是：**声明在一个文件里，调用在另一个文件里**。单文件检查看不见，
括号平衡也看不见（`Foo(a: 1, b: 2)` 的括号完全平衡）。

本脚本做三件事
--------------
1. 扫出所有「多行 struct/class 声明」的参数列表，建立 类型名 → (必填参数, 全部参数)
2. 扫出所有 `TypeName(` 调用点，统计实参标签，与声明比对
3. 对 **View 结构体** 额外检查：调用点用的 `viewModel.xxx` 里的 xxx，
   是否真的定义在 view model 上（而不是错挂在了 View 上）

这一层只做**保守告警**，不认识泛型推断、默认参数展开、尾随闭包语法糖。
凡是「参数个数对不上但可能是默认参数」的，降级为 warning 而不是 fail ——
宁可漏报也不要误报，误报会让人开始忽略门禁。

用法：
    python3 Tools/audit_call_sites.py
退出码 0 = 通过（可含 warning），1 = 有 error。
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "FitnessApp"

# 保守告警：可能是问题，但静态分析无法确定，不阻断门禁。
# 误报会让门禁被无视，所以宁可漏报。
WARNINGS: list[str] = []

# ---------------------------------------------------------------- 工具

def swift_files() -> list[Path]:
    return sorted(SRC.rglob("*.swift"))


def strip_comments(text: str) -> str:
    """去掉 // 行注释与 /* */ 块注释，避免在注释里误匹配调用点。"""
    out = []
    i = 0
    n = len(text)
    in_line = False
    in_block = 0
    in_str = False
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            i += 1
            continue
        if in_block:
            if c == "/" and nxt == "*":
                in_block += 1
                i += 2
                continue
            if c == "*" and nxt == "/":
                in_block -= 1
                i += 2
                continue
            if c == "\n":
                out.append(c)
            i += 1
            continue
        if in_str:
            out.append(c)
            if c == "\\":
                if i + 1 < n:
                    out.append(text[i + 1])
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block = 1
            i += 2
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


# 类型声明前的修饰：`@MainActor` / `public` / `final` / `private` 任意顺序出现。
# 早先写成 `(?:public\s+|private\s+|internal\s+|final\s+)*` 会漏掉
# `@MainActor\nfinal class Foo` 这种属性包装器开头的声明 —— 整个类型不会被登记，
# 于是所有 `viewModel.xxx` 都被误判成「成员不存在」。
ATTR = r"(?:@\w+(?:\([^)]*\))?\s+|\b(?:public|private|fileprivate|internal|open|final)\b\s+)*"

# 匹配一行里的「属性式参数声明」：`var name: Type` / `let name: Type`
#
# 类型部分不能用 `[^=,)]+?` 这种「排除右括号」的字符类：闭包类型的参数
# 长成 `var onStartTraining: (TodayTrainingState) -> Void`，括号是类型的一部分。
# 早先这么写导致**所有闭包型回调参数都被漏掉** —— 而那恰好就是
# `TrainingHomeView` 的 `onResumeSession` / `onOpenRecovery` 被编译期报
# 「missing arguments」的原因：门禁根本没登记它们，自然也不会提醒调用点补上。
# 改成「非贪婪吃到第一个作为值分隔符的 `=`」，右括号允许出现。
PROP_PARAM = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"          # 属性包装器
    r"(?:var|let)\s+(\w+)\s*:\s*(.+?)"          # 名字与类型
    r"(?:\s*=\s*(.+))?$"                        # 可选的默认值
)

# 只写默认值、省略类型标注的成员：`var onlyFavorite = false`。
# 类型交给编译器推断，但调用点的标签是 `onlyFavorite:`，
# 不登记的话会误判成「声明里不存在的参数」。
PROP_PARAM_INFERRED = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
    r"(?:var|let)\s+(\w+)\s*=\s*(.+)$"
)


def _split_top_level(text: str) -> list[str]:
    """
    按顶层逗号切分参数列表（忽略泛型 <>、嵌套 () [] {} 里的逗号）。

    `{}` 必须一起跟踪：像
    `sessions: deduped.sorted { $0.startedAt < $1.startedAt }, addedCount: n`
    这样的实参内部带闭包，不数花括号就会在闭包里的逗号处切错，
    后面所有参数都会跟着错位。
    """
    parts: list[str] = []
    depth = 0
    angle = 0
    cur: list[str] = []
    in_str = False
    n = len(text)
    for idx, c in enumerate(text):
        if in_str:
            cur.append(c)
            if c == "\\":
                continue
            if c == '"':
                in_str = False
            continue
        if c == '"':
            in_str = True
            cur.append(c)
            continue
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "<":
            # 只把**看起来像泛型参数**的 `<` 计入 angle。
            #
            # 不能无脑计数：闭包里的小于号（`{ $0.startedAt < $1.startedAt }`）
            # 会让 angle 永远回不到 0，后面所有顶层逗号都被当成「在泛型里」，
            # 于是整个实参列表被切成一块 —— 这正是
            # `WorkoutBackupMergePlan(sessions: ..., addedCount: ...)` 只识别出
            # 第一个参数的原因。
            # 判据：`<` 后面紧跟一个大写字母或 `[`（`Array<Foo>` / `<T>`），
            # 且前面不是空格/运算符。
            nxt = text[idx + 1] if idx + 1 < n else ""
            prev = text[idx - 1] if idx >= 1 else ""
            if (nxt.isupper() or nxt == "[") and (prev.isalnum() or prev in ".:)]"):
                angle += 1
        elif c == ">":
            angle = max(0, angle - 1)
        if c == "," and depth == 0 and angle == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(c)
    if "".join(cur).strip():
        parts.append("".join(cur))
    return [p.strip() for p in parts if p.strip()]


def _balanced_body(text: str, brace: int) -> str:
    """
    从 `{` 的位置取到与之配对的 `}`，跳过字符串字面量里的花括号。

    返回值**不含**开头的 `{`，但**含**结尾的 `}` 之前的内容。
    剥掉开头那个 `{` 很重要：调用方靠「花括号深度 == 0」判断
    「这一行属于类型体的第一层」，带着 `{` 会让深度从 1 起步，
    第一层的判定永远不成立。
    """
    depth = 0
    in_str = False
    i = brace
    n = len(text)
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
        elif c == "{":
            depth += 1
            if depth == 1 and i == brace:
                brace = i + 1          # 跳过开头的 `{`
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[brace:i]
        i += 1
    return text[brace:]


def _member_names(body: str) -> set[str]:
    """收集一段类型体里声明的属性与方法名。"""
    names: set[str] = set()
    for pm in re.finditer(
        r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
        r"(?:private\(set\)\s+|fileprivate\s+|private\s+|public\s+|internal\s+"
        r"|static\s+|final\s+|override\s+|mutating\s+)*"
        r"(?:var|let|func)\s+(\w+)",
        body, re.M,
    ):
        names.add(pm.group(1))
    for pm in re.finditer(r"@Published\s+(?:private\(set\)\s+)?var\s+(\w+)", body):
        names.add(pm.group(1))
    return names


def _extension_members(text: str, type_name: str) -> set[str]:
    """同文件里 `extension TypeName { ... }` 声明的所有成员名。"""
    names: set[str] = set()
    for em in re.finditer(r"^\s*(?:private\s+|fileprivate\s+)?extension\s+"
                          + re.escape(type_name) + r"\b[^{]*\{", text, re.M):
        brace = text.index("{", em.start())
        names |= _member_names(_balanced_body(text, brace))
    return names


def extract_declarations(text: str) -> dict[str, dict]:
    """
    提取所有 struct/class 的**存储属性**参数列表。

    返回 {TypeName: {"required": [...], "all": [...], "file": ..., "line": ...}}

    只处理「属性式」声明（SwiftUI 视图与数据模型的主流写法）。
    带自定义 `init(` 的类型单独标记，调用点比对时跳过——自定义 init
    的参数与存储属性经常不是一一对应，硬比会大量误报。
    """
    decls: dict[str, dict] = {}

    # 只登记**顶层**类型声明（缩进为 0 的行）。
    # 嵌套类型（如 `struct SessionSummaryView { private struct Metric { ... } }`）
    # 在文件里是缩进的，且它的 `Metric(...)` 调用点常在别的嵌套类型里 ——
    # 名字会撞车、参数也对不上，硬比只会产生误报。
    for m in re.finditer(r"^" + ATTR + r"(struct|class)\s+(\w+)", text, re.M):
        kind, name = m.group(1), m.group(2)
        if name in decls:
            continue
        # 从这个位置向后扫，直到遇到下一个同级的 struct/class 或文件尾
        start = m.end()
        # 找到类型体的起始 {
        brace = text.find("{", start)
        if brace == -1:
            continue
        # 截到配对的花括号，而不是「下一个顶层声明」——
        # 后者会把本类型之后定义的辅助类型算进参数列表。
        #
        # `_balanced_body` 返回的字符串**含开头的 `{`**（这样它才能独立
        # 判断配对关系）。这里要剥掉它，否则下面的深度计数从 1 起步，
        # 「第一层」的判定永远不成立，所有参数都会被漏掉。
        body = _balanced_body(text, brace)
        if body.startswith("{"):
            body = body[1:]

        has_custom_init = bool(
            re.search(r"^\s*(?:public\s+|private\s+|internal\s+)?init\s*\(", body, re.M)
        )

        # 自定义 init 常常写在同一个文件的 `extension TypeName { init(...) }` 里。
        # 只看类型体会漏掉，于是这类类型的调用点会被拿成员列表去硬比，
        # 而它的 init 参数与成员名字并不一一对应 —— 必然误报。
        for em in re.finditer(r"^\s*(?:private\s+|fileprivate\s+)?extension\s+"
                              + re.escape(name) + r"\b[^{]*\{", text, re.M):
            ebrace = text.index("{", em.start())
            ebody = _balanced_body(text, ebrace)
            if re.search(r"^\s*(?:public\s+|private\s+|internal\s+)?init\s*\(", ebody, re.M):
                has_custom_init = True
                break

        params: list[tuple[str, bool]] = []   # (name, has_default)
        types: dict[str, str] = {}            # name -> 类型文本（判闭包用）
        # 按「花括号深度」筛出**类型体第一层**的行。
        # 早先用 `stripped.count("{") - stripped.count("}")` 逐行累加，
        # 在 SwiftUI 里必错：`var body: some View {` 让 depth 变 1，
        # 之后视图树每个闭包又叠一层，而 `}` 往往与 `)` 同行（`})`），
        # 逐行净差并不能还原真实深度 —— 结果就是整个类型的参数被漏掉。
        # 这里改成扫字符：只在**顶层**（depth==0）的行首做参数匹配。
        offset = 0
        depth = 0
        in_str = False
        for raw in body.split("\n"):
            line_start_depth = depth
            # 先算出这一行结束时的深度
            i = 0
            while i < len(raw):
                c = raw[i]
                if in_str:
                    if c == "\\":
                        i += 2
                        continue
                    if c == '"':
                        in_str = False
                    i += 1
                    continue
                if c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                i += 1

            stripped = raw.strip()
            if not stripped:
                continue
            # 只看「这一行开始时处于类型体第一层」的行
            if line_start_depth != 0:
                continue
            pm = PROP_PARAM.match(raw)
            if not pm:
                # `var onlyFavorite = false` —— 省略类型标注，只给默认值。
                # 这种成员在调用点上依然可以写 `onlyFavorite:`，
                # 必须登记，否则会被判成「不存在的参数」。
                im = PROP_PARAM_INFERRED.match(raw)
                if im and not raw.rstrip().endswith("{"):
                    stripped_i = raw.strip()
                    if not stripped_i.startswith("static ") \
                            and "@Environment" not in stripped_i \
                            and "@EnvironmentObject" not in stripped_i:
                        params.append((im.group(1), True))
                        types[im.group(1)] = ""
                continue
            pname, ptype, pdefault = pm.group(1), pm.group(2), pm.group(3)
            # 跳过 computed property（后面跟着 { 的）
            if raw.rstrip().endswith("{"):
                continue
            # `var id: String { url.absoluteString }` 这类**同行就带花括号**的
            # 计算属性，上面那条 `endswith("{")` 拦不住。它不是成员参数，
            # 登记进去会让「id」被当成必填，所有调用点集体误报。
            # 判定：类型后面紧跟着 `{`（且前面没有 `=`）就是计算属性。
            if re.match(r"^[^=]*\{\s*\S", raw.rstrip()):
                continue
            # 跳过 static / @Environment 等不算调用点参数的
            if stripped.startswith("static "):
                continue
            if "@Environment" in stripped or "@EnvironmentObject" in stripped:
                continue
            # @ObservedObject / @StateObject 是必填的
            # @State / @FocusState / @Binding 通常有默认或者从环境注入，
            # 但 @State private var x = false 有默认值
            params.append((pname, pdefault is not None))
            types[pname] = ptype

        if params:
            # Optional 类型的成员在 Swift 里**可以省略**：
            # `var icon: String?` 等价于自带 `= nil`，
            # `let action: (() -> Void)?` 同理。
            # 不这样处理的话，所有「可选回调」都会被当成必填而大量误报。
            def is_optional(ptype: str) -> bool:
                t = ptype.strip()
                return t.endswith("?") or t.endswith("? ")

            decls[name] = {
                "kind": kind,
                "params": params,
                "types": types,
                "required": [
                    n for n, d in params
                    if not d and not is_optional(types.get(n, ""))
                ],
                "all": [n for n, _ in params],
                "custom_init": bool(has_custom_init),
                "line": text[:m.start()].count("\n") + 1,
            }
    return decls


# ---------------------------------------------------------------- 调用点提取

def extract_call_args(text: str, type_name: str) -> list[tuple[int, list[str]]]:
    """
    找出所有 `TypeName(` 调用，返回 [(行号, [标签, ...]), ...]。

    只看带标签的实参（`name: value`）；位置实参记为 ""。

    尾随闭包会被补一个特殊标签 `"<trailing>"`：Swift 的
    `CardContainer(padding: 8) { ... }` 里那个闭包填的是 `content:` 参数，
    不补的话所有用尾随闭包的调用点都会被误判成「缺少必填参数 content」。
    """
    results: list[tuple[int, list[str]]] = []
    pattern = re.compile(r"(?<![\w.])" + re.escape(type_name) + r"\s*\(")
    for m in pattern.finditer(text):
        # 前面若紧跟 `struct ` / `class ` / `-> ` 说明是声明不是调用
        before = text[max(0, m.start() - 40):m.start()]
        if re.search(r"(struct|class|enum|extension|protocol)\s+$", before):
            continue
        if before.rstrip().endswith("->"):
            continue
        # `self.init(...)` / `super.init(...)` 是委托初始化器：
        # 它们的实参对应的是**另一个** init 的签名，不是成员变量列表，
        # 拿成员列表去比必然误报。
        if re.search(r"\b(self|super)\.\s*$", before):
            continue
        open_paren = m.end() - 1
        # 配对括号
        depth = 0
        i = open_paren
        in_str = False
        while i < len(text):
            c = text[i]
            if in_str:
                if c == "\\":
                    i += 2
                    continue
                if c == '"':
                    in_str = False
                i += 1
                continue
            if c == '"':
                in_str = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        if depth != 0:
            continue
        inner = text[open_paren + 1:i]
        line_no = text[:m.start()].count("\n") + 1

        labels: list[str] = []
        for part in _split_top_level(inner):
            # 取形如 `label:` 的开头
            lm = re.match(r"^(\w+)\s*:", part)
            if lm:
                labels.append(lm.group(1))
            else:
                labels.append("")   # 位置参数
        # 空调用 `Foo()` 标签列表就是 []
        if not inner.strip():
            labels = []

        # 尾随闭包：紧跟右括号的 `{`。
        # `CardContainer(padding: 8) { ... }` 的闭包填的是 `content:`，
        # 补一个占位标签交给上层「填第一个未赋值参数」。
        j = i + 1
        while j < len(text) and text[j] in " \t":
            j += 1
        if j < len(text) and text[j] == "{":
            labels.append("<trailing>")

        results.append((line_no, labels))
    return results


# ---------------------------------------------------------------- viewModel 成员检查

def check_viewmodel_members(files: dict[Path, str]) -> list[str]:
    """
    对每个 `struct XxxView`，若 body 里出现 `viewModel.member`，
    检查 member 是否定义在对应的 XxxViewModel 上（或它继承的类）。

    这是 FavoriteExercisesView 那个 bug 的形状：
    `muscleCounts` 实际是 View 自己的私有计算属性，却被写成 `viewModel.muscleCounts`。
    """
    problems: list[str] = []

    # 先收集所有 ViewModel 的成员名
    vm_members: dict[str, set[str]] = {}
    for path, text in files.items():
        for m in re.finditer(r"^" + ATTR + r"class\s+(\w*ViewModel\w*)\s*[:<]", text, re.M):
            name = m.group(1)
            brace = text.find("{", m.end())
            if brace == -1:
                continue
            # 类体结束的位置：扫到与开括号配对的闭括号，而不是「下一个类型声明」。
            # 用「下一个类型声明」会把同一个类后面定义的类型误算进来。
            depth = 0
            end = brace
            in_str = False
            for idx in range(brace, len(text)):
                c = text[idx]
                if in_str:
                    if c == "\\":
                        continue
                    if c == '"':
                        in_str = False
                    continue
                if c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        end = idx
                        break
            body = text[brace:end]
            members: set[str] = set()
            for pm in re.finditer(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
                                  r"(?:private\(set\)\s+|private\s+|public\s+|static\s+|final\s+)*"
                                  r"(?:var|let|func)\s+(\w+)", body, re.M):
                members.add(pm.group(1))
            # `@Published var x` / `@Published private(set) var y` 也要收
            for pm in re.finditer(r"@Published\s+(?:private\(set\)\s+)?var\s+(\w+)", body):
                members.add(pm.group(1))
            vm_members[name] = members

    # 跨文件的 `extension SomeViewModel { ... }`：
    # 大量派生属性（如「今日日期标题」「无障碍朗读串」）都写在别的文件里，
    # 不合并的话会被误判成「成员不存在」。
    for path, text in files.items():
        for em in re.finditer(r"^\s*(?:private\s+|fileprivate\s+)?extension\s+(\w+)\b",
                              text, re.M):
            name = em.group(1)
            if name not in vm_members:
                continue
            brace = text.find("{", em.end())
            if brace == -1:
                continue
            vm_members[name] |= _member_names(_balanced_body(text, brace))

    # 再检查每个 View 里的 viewModel.xxx
    for path, text in files.items():
        for m in re.finditer(r"^" + ATTR + r"struct\s+(\w+View)\b", text, re.M):
            view_name = m.group(1)
            brace = text.find("{", m.end())
            if brace == -1:
                continue
            depth = 0
            end = brace
            in_str = False
            for idx in range(brace, len(text)):
                c = text[idx]
                if in_str:
                    if c == "\\":
                        continue
                    if c == '"':
                        in_str = False
                    continue
                if c == '"':
                    in_str = True
                elif c == "{":
                    depth += 1
                elif c == "}":
                    depth -= 1
                    if depth == 0:
                        end = idx
                        break
            # 只取到第一个嵌套类型定义为止，避免把子视图的成员算进本视图。
            # 注意：`private extension XxxView` 里的成员**不算**在本体里，
            # 所以下面还要单独收集本文件内所有 extension 的成员。
            body = text[brace:end]

            # 这个 View 用的是哪个 ViewModel 类型
            vm_type = None
            tm = re.search(r"@\w+(?:Object)?\s+(?:private\s+)?var\s+viewModel\s*:\s*(\w+)", body)
            if tm:
                vm_type = tm.group(1)
            if not vm_type:
                tm2 = re.search(r"var\s+viewModel\s*:\s*(\w+)", body)
                if tm2:
                    vm_type = tm2.group(1)
            if not vm_type or vm_type not in vm_members:
                continue

            known = vm_members[vm_type]
            # View 自己定义的成员（合法路径：viewModel 成员不存在但 View 自己有）
            own: set[str] = set()
            for om in re.finditer(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*"
                                  r"(?:private\s+)?(?:var|let|func)\s+(\w+)", body, re.M):
                own.add(om.group(1))

            # 同文件里 `extension XxxView { ... }` 的成员也算本视图的。
            # 大量计算属性（如「文案拼接」「无障碍标签」）都写在 extension 里，
            # 不收集的话会被误判成「viewModel 上不存在」。
            own |= _extension_members(text, view_name)

            # 嵌套子视图（`private struct FooRow: View` 写在 body 里）的成员
            # 对本视图可见，同样要收。
            for nested in re.finditer(r"struct\s+(\w+)\s*:\s*View", body):
                own.add(nested.group(1))

            for um in re.finditer(r"viewModel\.(\w+)", body):
                member = um.group(1)
                # 「View 自己也有同名成员」时不报：这确实可能是写错了
                # 前缀（正是 FavoriteExercisesView 的 bug 形状），
                # 但 View 自己定义同名成员也可能是**故意的**转发属性，
                # 无法静态区分，降级为 warning 让人看一眼。
                if member in known:
                    continue
                line_no = text[:m.start() + um.start()].count("\n") + 1
                loc = f"{path.relative_to(ROOT)}:{line_no}"
                if member in own:
                    WARNINGS.append(
                        f"{loc}: `viewModel.{member}` —— {vm_type} 上没有，"
                        f"但 {view_name} 自己有同名成员，确认是否写错了前缀"
                    )
                else:
                    problems.append(
                        f"{loc}: `viewModel.{member}` —— "
                        f"{vm_type} 与 {view_name} 上都没有 `{member}`"
                    )
    return problems


# ---------------------------------------------------------------- 主流程

def main() -> int:
    files = {p: strip_comments(p.read_text(encoding="utf-8")) for p in swift_files()}

    # 1) 收集声明
    decls: dict[str, dict] = {}
    decl_file: dict[str, Path] = {}
    for path, text in files.items():
        for name, info in extract_declarations(text).items():
            if name not in decls:
                decls[name] = info
                decl_file[name] = path

    errors: list[str] = []
    warnings: list[str] = WARNINGS

    # 2) 比对调用点
    for path, text in files.items():
        for name, info in decls.items():
            if info["custom_init"]:
                # 有自定义 init 的类型参数与属性常常不一致，跳过
                continue
            for line_no, labels in extract_call_args(text, name):
                if not labels:
                    continue
                named = [l for l in labels if l and l != "<trailing>"]
                trailing = labels.count("<trailing>")
                required = list(info["required"])
                allp = set(info["all"])
                given = set(named)

                # 尾随闭包填的是**最后一个函数类型参数**，不是「第一个没赋值」的。
                # Swift 的规则：`Foo(title: "x") { ... }` 里闭包对应声明中
                # 那个「类型是闭包」的参数 —— 通常排在最后。中间那些
                # `isEnabled: Bool = true` 这类带默认值的参数是会被跳过的。
                for _ in range(trailing):
                    for pname, _pdefault in reversed(info["params"]):
                        if pname in given:
                            continue
                        ptype = info["types"].get(pname, "")
                        is_closure = "->" in ptype or "()" in ptype
                        # `@ViewBuilder var content: Content` 这种泛型视图内容
                        # 也是靠尾随闭包填的，但类型文本里既没有 `->` 也没有 `()`。
                        # `Content` / `Content2` 这类泛型占位名一并认作闭包参数。
                        if not is_closure and re.fullmatch(r"Content\d*", ptype.strip()):
                            is_closure = True
                        if is_closure:
                            given.add(pname)
                            break

                # 必填参数缺失 —— 这是最可靠的信号
                missing = [p for p in required if p not in given]
                # 多出来的标签（既不是声明参数，也不是常见系统参数）
                extra = given - allp

                loc = f"{path.relative_to(ROOT)}:{line_no}"
                if missing:
                    errors.append(
                        f"{loc}: 调用 `{name}(...)` 缺少必填参数 "
                        f"{missing}（声明于 {decl_file[name].name}:{info['line']}）"
                    )
                elif extra and len(given) > len(allp):
                    errors.append(
                        f"{loc}: 调用 `{name}(...)` 有声明里不存在的参数 "
                        f"{sorted(extra)}（声明于 {decl_file[name].name}:{info['line']}）"
                    )

    # 3) viewModel 成员
    vm_problems = check_viewmodel_members(files)

    # ---------------------------------------------------------------- 输出
    print("调用点一致性审计")
    print("=" * 62)
    print(f"扫描 {len(files)} 个 .swift 文件，{len(decls)} 个类型声明")
    print()

    if errors:
        print(f"== 参数不匹配 ({len(errors)}) ==")
        for e in errors:
            print("  [ERR ] " + e)
        print()
    else:
        print("== 参数不匹配 ==")
        print("  [ ok ] 未发现调用点参数与声明不一致")
        print()

    if vm_problems:
        print(f"== viewModel 成员 ({len(vm_problems)}) ==")
        for e in vm_problems:
            print("  [ERR ] " + e)
        print()
    else:
        print("== viewModel 成员 ==")
        print("  [ ok ] 未发现挂错对象的成员访问")
        print()

    if warnings:
        print(f"== 待人工确认 ({len(warnings)}) ==")
        for w in warnings:
            print("  [warn] " + w)
        print()

    print("=" * 62)
    if errors or vm_problems:
        print(f"审计未通过：{len(errors) + len(vm_problems)} 个 error")
        return 1
    print("审计通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
