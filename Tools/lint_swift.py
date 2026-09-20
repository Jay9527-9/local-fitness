#!/usr/bin/env python3
"""
lint_swift.py — 在 Windows 上没有 Swift 编译器时，用静态手段捕捉最常犯的结构性错误。

覆盖三类问题：
  1. 括号 / 花括号 / 方括号不平衡（漏写或多写一个右括号，会连带报出十几个假错）
  2. 字符串与注释被正确剥离后再计数，避免注释里的括号干扰
  3. 引用了不存在的类型名（拼写错误、忘了定义、或定义在别的文件却没进 project.yml）

退出码 0 表示通过。
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

# 这些类型来自系统框架，不参与「自定义类型是否已定义」的检查
SYSTEM_TYPES = {
    "Any", "AnyObject", "AnyView", "Array", "Bool", "Bundle", "Calendar", "Character",
    "CodingKey", "CodingKeys", "Color", "Comparable", "ContentView", "CGFloat", "CGPoint",
    "CGRect", "CGSize", "Context", "Data", "Date", "DateComponents", "Decoder", "Dictionary",
    "Double", "EditMode", "Encodable", "Encoder", "Equatable", "Error", "FileManager",
    "Float", "Font", "ForEach", "GeometryProxy", "GeometryReader", "GraphicsContext",
    "Group", "Hashable", "HStack", "Identifiable", "Image", "IndexSet", "Int", "JSONDecoder",
    "GridItem", "GridItem.Size", "Publishers", "Autoconnect", "Timer", "UserDefaults",
    "UNUserNotificationCenter", "UNMutableNotificationContent", "UNTimeIntervalNotificationTrigger",
    "UNNotificationRequest", "UNNotificationSettings", "UNAuthorizationStatus",
    "UIApplication", "NotificationCenter",
    "JSONEncoder", "LazyHStack", "LazyVGrid", "LazyVStack", "LinearGradient", "List",
    "LocalizedError", "Locale", "NavigationPath", "NavigationStack", "Never", "ObservableObject",
    "Optional", "Path", "Picker", "ProgressView", "Published", "Rectangle", "RunLoop",
    "ScrollView", "Section", "Set", "Spacer", "State", "StateObject", "String", "StrokeStyle",
    "ScrollViewProxy", "ScrollViewReader", "Namespace",
    "Text", "TextEditor", "TextField", "TimeInterval", "Toggle", "ToolbarItem", "UIActivityViewController",
    "UIImage", "UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator", "UIViewControllerRepresentable",
    "SystemSoundID", "UIAccessibility",
    "UIKeyboardType", "UIKeyboardAppearance", "UIReturnKeyType", "UITextContentType",
    "UIView", "URL", "VStack", "View", "ViewBuilder", "Void", "ZStack", "Button", "ButtonStyle",
    "Capsule", "Circle", "RoundedRectangle", "UnevenRoundedRectangle", "Divider", "Spacer",
    "Animation", "Transition", "AsyncImage", "LinearGradient", "AngularGradient",
    "Binding", "Environment", "EnvironmentObject", "FocusState", "Gesture", "DragGesture",
    "LongPressGesture", "TapGesture", "TileStyle", "MainActor", "ObservableObject",
    "Print", "Result", "Sequence", "Collection", "RandomAccessCollection", "RawRepresentable",
    "Mirror", "Thread", "OperationQueue", "DispatchQueue", "Task", "Timer", "NotificationCenter",
    "NSObject", "NSString", "NSAttributedString", "Locale", "StringProtocol", "Range",
    "ClosedRange", "PartialRangeFrom", "PartialRangeThrough", "StrideThrough", "StrideTo",
    "Zip2Sequence", "ReversedCollection", "Just", "Empty", "Publishers", "CurrentValueSubject",
    "PassthroughSubject", "AnyPublisher", "AnyCancellable", "Cancellable", "Subscriber",
    "PreviewProvider", "UIApplication", "UIScreen", "UIWindowScene", "UIColor",
    "UIViewController", "UINavigationController", "UIGestureRecognizer", "UIViewRepresentable",
    "Shape", "InsettableShape", "InsetShape", "Path", "Canvas", "TimelineView", "Grid",
    "GridRow", "Menu", "Link", "Label", "SecureField", "Stepper", "Slider", "Progress",
    "Form", "NavigationLink", "NavigationView", "TabView", "PageTabViewStyle",
    "PhotosPicker", "PhotosPickerItem", "PHPickerFilter", "DatePicker", "UIGraphicsImageRenderer",
    # 页面 19 的 fileExporter 保存到文件：FileDocument 一族
    "FileDocument", "FileWrapper", "UTType", "ReadConfiguration", "WriteConfiguration",
    # 系统框架类型与常见泛型占位符，不做「是否已定义」判断
    "App", "Scene", "Configuration", "Content", "T", "U", "V", "W", "E", "S", "K", "P", "R",
    # Value：StatsCache<Value> 的泛型参数。泛型形参不是被声明的类型，
    # 不进 declared 表，但把它塞进白名单比让 lint 每次都报 3 条噪声更省事。
    "Value", "Item", "Element",
    # Option：页面 13 的 ProfileSegmentedRow<Option> 泛型形参，同上。
    "Option",
    "UUID", "UInt8", "UInt16", "UInt32", "UInt64", "Int8", "Int16", "Int32", "Int64",
    "Decodable", "CaseIterable", "RawRepresentable", "Sendable", "CharacterSet",
    "EmptyView",
    "Codable", "CustomStringConvertible", "Error", "LocalizedError", "Comparable",
    "EdgeInsets", "Alignment", "HorizontalAlignment", "VerticalAlignment", "Axis",
    "NumberFormatter", "DateFormatter", "ISO8601DateFormatter", "Predicate", "KeyPath", "WritableKeyPath",
    # 页面 11 引入：动态字体档位。ContentSizeCategory 是 SwiftUI 的公开类型，
    # 由 @Environment(\.sizeCategory) 提供，和 Color / Font 一样属于系统侧。
    "ContentSizeCategory",
    # 页面 51 引入：权限管理读取系统授权状态。
    # UNAuthorizationStatus / PHAuthorizationStatus 来自 UserNotifications 与
    # Photos 两个系统框架（都已 import），不是本项目定义的类型。
    "UNAuthorizationStatus",
    "PHAuthorizationStatus",
    "PHPhotoLibrary",
    "ScenePhase",
}

# 允许的括号配对。Swift 里 `[` 既做数组也做捕获列表，`(` 也用于元组，所以只检查平衡。
PAIRS = {")": "(", "]": "[", "}": "{"}


def strip_comments_and_literals(text: str) -> str:
    """把字符串字面量与注释替换成等长空白，保证行列号与括号计数不受内容干扰。

    注意顺序：必须先处理字符串，再处理注释。
    否则 `"https://x.com"` 里的 `//` 会被当成行注释起点，吃掉后面的引号，
    导致字符串状态机一路跑到文件尾，之后所有括号都被误判为「在字符串里」。
    """
    out = []
    i = 0
    n = len(text)
    # 0=代码 1=双引号字符串 2=行注释 3=块注释
    state = 0

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if state == 0:
            if ch == '"':
                # 三引号字符串
                if text[i:i + 3] == '"""':
                    state = 1
                    out.append("   ")
                    i += 3
                    continue
                state = 1
                out.append(" ")
                i += 1
                continue
            if ch == "/" and nxt == "/":
                state = 2
                out.append("  ")
                i += 2
                continue
            if ch == "/" and nxt == "*":
                state = 3
                out.append("  ")
                i += 2
                continue
            out.append(ch)
            i += 1
            continue

        if state == 1:
            if ch == "\\":
                # 转义序列，跳过两个字符
                out.append("  ")
                i += 2
                continue
            if text[i:i + 3] == '"""':
                out.append("   ")
                i += 3
                state = 0
                continue
            if ch == '"':
                out.append(" ")
                i += 1
                state = 0
                continue
            if ch == "\n":
                # 单行字符串里的裸换行说明引号没闭合，交给引号计数环节报错
                out.append("\n")
                i += 1
                state = 0
                continue
            out.append(" ")
            i += 1
            continue

        if state == 2:
            if ch == "\n":
                out.append("\n")
                i += 1
                state = 0
                continue
            out.append(" ")
            i += 1
            continue

        if state == 3:
            if ch == "*" and nxt == "/":
                out.append("  ")
                i += 2
                state = 0
                continue
            out.append("\n" if ch == "\n" else " ")
            i += 1
            continue

    return "".join(out)


def swift_files():
    result = []
    for dirpath, dirnames, filenames in os.walk(SRC):
        dirnames[:] = [d for d in dirnames if d not in ("build", ".git")]
        for name in sorted(filenames):
            if name.endswith(".swift"):
                result.append(os.path.join(dirpath, name))
    return result


def check_balance(files):
    """逐文件检查括号平衡，报出第一个不平衡的位置。"""
    problems = []
    for path in files:
        rel = os.path.relpath(path, ROOT)
        raw = open(path, encoding="utf-8").read()
        stripped = strip_comments_and_literals(raw)
        lines = stripped.split("\n")

        stack = []
        for lineno, line in enumerate(lines, 1):
            for col, ch in enumerate(line, 1):
                if ch in "([{":
                    stack.append((ch, lineno, col))
                elif ch in ")]}":
                    if not stack:
                        problems.append(
                            f"{rel}:{lineno}:{col} 多余的 '{ch}'"
                        )
                        break
                    open_ch, _, _ = stack.pop()
                    if open_ch != PAIRS[ch]:
                        problems.append(
                            f"{rel}:{lineno}:{col} '{ch}' 与第 {stack and '?'} 处不匹配"
                        )
                        break
        if stack:
            ch, lineno, col = stack[0]
            problems.append(
                f"{rel}:{lineno}:{col} '{ch}' 没有闭合（共 {len(stack)} 个未闭合）"
            )
    return problems


def collect_declared_types(files):
    """收集所有自定义类型名：struct / class / enum / protocol / typealias / actor。"""
    declared = set()
    pattern = re.compile(
        r"^\s*(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
        r"(?:final\s+)?(?:struct|class|enum|protocol|actor|typealias)\s+([A-Z]\w*)",
        re.M,
    )
    for path in files:
        text = strip_comments_and_literals(open(path, encoding="utf-8").read())
        for match in pattern.finditer(text):
            declared.add(match.group(1))
    return declared


def check_undefined_types(files, declared):
    """找出被当作类型使用、但既不是自定义类型也不是系统类型的标识符。

    只检查明显的位置：类型标注、泛型参数、构造调用、以及 `-> T` 返回类型，
    避免把变量名、函数名误判成类型。
    """
    known = declared | SYSTEM_TYPES
    problems = []

    # `let x: Foo` / `var x: Foo` / `func f() -> Foo` / `Foo(` 构造 / `<Foo>`
    patterns = [
        (re.compile(r":\s*([A-Z]\w*)\b"), "类型标注"),
        (re.compile(r"->\s*([A-Z]\w*)\b"), "返回类型"),
        (re.compile(r"\[\s*([A-Z]\w*)\s*\]"), "数组元素类型"),
        (re.compile(r"<\s*([A-Z]\w*)\s*[,>]"), "泛型参数"),
    ]

    for path in files:
        rel = os.path.relpath(path, ROOT)
        text = strip_comments_and_literals(open(path, encoding="utf-8").read())
        for pattern, kind in patterns:
            for match in pattern.finditer(text):
                name = match.group(1)
                if name in known:
                    continue
                # 允许 `Foo.Bar` 形式的枚举嵌套访问与 `Self`
                i = match.start(1) + len(name)
                if i < len(text) and text[i] == ".":
                    continue
                lineno = text[:match.start(1)].count("\n") + 1
                problems.append(f"{rel}:{lineno} 未知{kind} '{name}'")

    # 去重，同一个名字多处出现只报一次
    seen = set()
    unique = []
    for item in problems:
        key = item.split(" ", 1)[1]
        if key in seen:
            continue
        seen.add(key)
        unique.append(item)
    return unique


def check_duplicate_declarations(files):
    """同一个类型名在**顶层**被定义两次会编译失败。

    Swift 允许把类型嵌套在别的类型里，所以 `PlanDetailViewModel.LoadState` 与
    `HistoryViewModel.LoadState` 可以共存。这里用缩进判断是否顶层声明：
    顶层声明没有前导缩进，嵌套声明一定有。
    """
    index = {}
    pattern = re.compile(
        r"^(?:public\s+|private\s+|internal\s+|fileprivate\s+)?"
        r"(?:final\s+)?(?:struct|class|enum|protocol|actor)\s+([A-Z]\w*)",
        re.M,
    )
    for path in files:
        rel = os.path.relpath(path, ROOT)
        text = strip_comments_and_literals(open(path, encoding="utf-8").read())
        for match in pattern.finditer(text):
            index.setdefault(match.group(1), []).append(rel)

    problems = []
    for name, locations in index.items():
        if len(locations) > 1 and name != "CodingKeys":
            # CodingKeys 在每个类型里都会定义一次，属正常
            problems.append(f"类型 '{name}' 在多个文件重复定义：{', '.join(locations)}")
    return problems


def main():
    files = swift_files()
    if not files:
        print("没有找到 .swift 文件")
        return 1

    print(f"Swift 静态检查（{len(files)} 个文件）")
    print("=" * 46)

    failed = False

    balance = check_balance(files)
    if balance:
        failed = True
        print("== 括号平衡 ==")
        for item in balance:
            print(f"  [fail] {item}")
    else:
        print("== 括号平衡 ==\n  [ ok ] 全部文件括号闭合正确")

    declared = collect_declared_types(files)
    print(f"== 类型定义 ==\n  [ ok ] 共 {len(declared)} 个自定义类型")

    undefined = check_undefined_types(files, declared)
    if undefined:
        print(f"== 未知类型引用（{len(undefined)} 处）==")
        for item in undefined[:40]:
            print(f"  [warn] {item}")
        if len(undefined) > 40:
            print(f"  ... 还有 {len(undefined) - 40} 处")
    else:
        print("== 未知类型引用 ==\n  [ ok ] 未发现未知类型")

    duplicates = check_duplicate_declarations(files)
    if duplicates:
        failed = True
        print("== 重复定义 ==")
        for item in duplicates:
            print(f"  [fail] {item}")
    else:
        print("== 重复定义 ==\n  [ ok ] 无重复类型定义")

    print("=" * 46)
    if failed:
        print("检查未通过。")
        return 1
    print("检查通过。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
