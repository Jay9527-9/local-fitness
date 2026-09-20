#!/usr/bin/env python3
"""
预检脚本：在 macOS 上跑 Xcode 构建之前，先用静态检查排除常见问题。

检查项：
  1. Info.plist 可被解析，且 MinimumOSVersion / 关键键正确
  2. project.yml 可被解析，部署目标与源路径正确
  3. 源码中不残留 iOS 17 专属 API
  4. `.swift` 文件未出现已知的错别字或遗留引用
  5. 资源完整性（种子 JSON 条数、媒体文件数）

用法：python3 Tools/preflight.py
退出码 0 = 通过
"""

from __future__ import annotations

import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# iOS 17 及更高版本才有的 API。目标设备 iOS 16.3.1，出现即为错误。
IOS17_ONLY = [
    "containerRelativeFrame",
    "scrollTargetLayout",
    "scrollTargetBehavior",
    "scrollPosition(",
    "scrollTransition",
    "onGeometryChange",
    "sensoryFeedback",
    "ContentUnavailableView",
    "@Observable",
    "@Bindable",
    "onChange(of:initial:",
    ".symbolEffect",
    "@Previewable",
    ".scrollIndicators(",
    "SwiftData",
    "ModelContainer",
    "ModelContext",
    "FetchDescriptor",
    "PersistentModel",
]

# iOS 16.4+ 才有的 API，同样是风险项
IOS164_ONLY = [
    ".presentationBackground(",
    # 注意：整个 scrollBounceBehavior 修饰符都是 iOS 16.4+ API，
    # 不能只拦 .basedOnSize 变体——.always 同样是 16.4+（页面 14 之前曾被
    # 一条错误注释声称「.always 是 iOS 16.0 即可用」蒙混过关）。
    ".scrollBounceBehavior(",
    ".toolbar(.hidden",
]

# 单参数 onChange 在 iOS 17 起被弃用（仍可用，仅提示）。项目统一用双参数形式以避免噪音。
IOS17_DEPRECATED = [
    (".onChange(of: ", "onChange 单参数形式在 iOS 17 起弃用，建议改为双参数 (oldValue, newValue)"),
]

MIN_IOS = (16, 0)


def fail(msg: str) -> None:
    print(f"  [FAIL] {msg}")
    global FAILED
    FAILED = True


def ok(msg: str) -> None:
    print(f"  [ ok ] {msg}")


FAILED = False


def swift_files() -> list[str]:
    out = []
    for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, "FitnessApp")):
        for name in filenames:
            if name.endswith(".swift"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


def strip_comments_and_literals(text: str) -> str:
    """去掉 Swift 注释与字符串内容，保留其余代码。

    顺序很关键：**必须先剥字符串，再剥注释**。

    原因是代码里存在 `"© Gym visual — https://gymvisual.com/"` 这类字面量。
    如果先按 `//` 剥注释，`https://` 会被误认成行注释起点，
    连带把该字符串的收尾引号一起吃掉 —— 引号总数从偶数变奇数，
    后面的状态机就会永久停在「字符串内」，导致文件后半段所有 func 全部"消失"，
    表现为仓储协议一致性检查大面积误报缺失方法。

    状态机本身很朴素：
      - 在字符串外遇到 `"` 进入字符串，把内容丢弃
      - 在字符串内遇到 `\\` 跳过两字符（转义对），遇到 `"` 退出
      - 字符串外的 `//...` 与 `/*...*/` 视为注释丢弃
    """
    result: list[str] = []
    in_string = False
    in_line_comment = False
    in_block_comment = False
    i = 0
    n = len(text)

    while i < n:
        ch = text[i]
        nxt = text[i + 1] if i + 1 < n else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                result.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
                continue
            i += 1
            continue

        if in_string:
            if ch == "\\" and nxt:
                i += 2
                continue
            if ch == '"':
                in_string = False
                i += 1
                continue
            i += 1
            continue

        # 字符串外
        if ch == '"':
            in_string = True
            result.append('""')
            i += 1
            continue
        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue
        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue
        result.append(ch)
        i += 1

    return "".join(result)


def check_info_plist() -> None:
    print("== Info.plist ==")
    path = os.path.join(ROOT, "FitnessApp", "Info.plist")
    if not os.path.exists(path):
        fail("Info.plist 不存在")
        return

    raw = open(path, "rb").read()
    if b"&lt;" in raw or b"&gt;" in raw or b"&amp;" in raw:
        fail("Info.plist 含 HTML 实体（&lt; / &gt; / &amp;），不是合法 XML")
        return

    try:
        data = plistlib.loads(raw)
    except Exception as exc:  # noqa: BLE001
        fail(f"Info.plist 解析失败：{exc}")
        return

    minimum = data.get("MinimumOSVersion", "")
    if minimum != "16.0":
        fail(f"MinimumOSVersion = {minimum!r}，应为 '16.0'")
    else:
        ok("MinimumOSVersion = 16.0")

    for key, expected in [
        ("CFBundleDisplayName", "训练"),
        ("UIUserInterfaceStyle", "Dark"),
        ("UIDeviceFamily", [1]),
        ("UIRequiredDeviceCapabilities", ["arm64"]),
    ]:
        actual = data.get(key)
        if actual != expected:
            fail(f"{key} = {actual!r}，应为 {expected!r}")
        else:
            ok(f"{key} 正确")

    # 不应出现任何联网相关的声明
    for key in data:
        if key in {"NSAppTransportSecurity", "UIBackgroundModes"}:
            fail(f"检测到联网 / 后台相关键：{key}")
    ok(f"无联网权限声明（共 {len(data)} 个键）")


def check_project_yml() -> None:
    print("== project.yml ==")
    path = os.path.join(ROOT, "project.yml")
    if not os.path.exists(path):
        fail("project.yml 不存在")
        return
    try:
        import yaml  # noqa: PLC0415
    except ImportError:
        print("  [skip] 未安装 pyyaml，跳过（pip install pyyaml）")
        return

    doc = yaml.safe_load(open(path, encoding="utf-8"))
    target = doc["targets"]["FitnessApp"]

    for label, value in [
        ("options.deploymentTarget.iOS", doc["options"]["deploymentTarget"]["iOS"]),
        ("settings.base.IPHONEOS_DEPLOYMENT_TARGET", doc["settings"]["base"]["IPHONEOS_DEPLOYMENT_TARGET"]),
        ("targets.FitnessApp.deploymentTarget", target["deploymentTarget"]),
    ]:
        if str(value) != "16.0":
            fail(f"{label} = {value!r}，应为 '16.0'")
        else:
            ok(f"{label} = 16.0")

    # 签名必须关闭，TrollStore 需要未签名 IPA
    for key in ["CODE_SIGNING_REQUIRED", "CODE_SIGNING_ALLOWED"]:
        for scope, node in [("base", doc["settings"]["base"]), ("target", target["settings"]["base"])]:
            if str(node.get(key)) != "NO":
                fail(f"{scope}.{key} 应为 'NO'，实际 {node.get(key)!r}")
            else:
                ok(f"{scope}.{key} = NO")

    # 媒体必须以 folder reference 打进去，否则子目录被压平
    folder_src = [s for s in target["sources"] if s.get("path") == "Resources/ExerciseMedia"]
    if not folder_src:
        fail("sources 中缺少 Resources/ExerciseMedia")
    elif folder_src[0].get("type") != "folder":
        fail("Resources/ExerciseMedia 必须声明 type: folder，否则 images/ 与 videos/ 会被打平")
    else:
        ok("Resources/ExerciseMedia 声明为 folder reference")


def check_sources() -> None:
    print("== 源码 iOS 版本兼容性 ==")
    files = swift_files()
    if not files:
        fail("未找到任何 .swift 文件")
        return
    ok(f"共 {len(files)} 个 .swift 文件")

    def code_only(text: str) -> str:
        # 一次性剥掉注释与字符串字面量，避免注释里的 API 名被误报
        return strip_comments_and_literals(text)

    bad17: list[str] = []
    bad164: list[str] = []

    for path in files:
        rel = os.path.relpath(path, ROOT)
        code = code_only(open(path, encoding="utf-8").read())
        for token in IOS17_ONLY:
            if token in code:
                bad17.append(f"{rel}: {token}")
        for token in IOS164_ONLY:
            if token in code:
                bad164.append(f"{rel}: {token}")

    if bad17:
        for item in bad17:
            fail(f"iOS 17 专属 API 残留 → {item}")
    else:
        ok("无 iOS 17 专属 API")

    if bad164:
        for item in bad164:
            fail(f"iOS 16.4+ 专属 API 残留 → {item}")
    else:
        ok("无 iOS 16.4+ 专属 API")


def check_typos() -> None:
    print("== 已知错别字 / 遗留引用 ==")
    patterns = {
        r"\.di\b": "疑似误写（应为 .id）",
        r"DesignShot": "疑似误写（应为 DesignTokens）",
        r"proficient\":": "疑似误写（应为 proficiency）",
        r"SwiftDataFitnessRepository": "SwiftData 实现已删除，仍被引用",
        r"\bPlanEntity\b|\bSessionEntity\b|\bExerciseEntity\b|\bBodyMeasurementEntity\b":
            "SwiftData 实体已删除，仍被引用",
    }

    # 同一份 API / 类型只应出现在一个文件里，重复定义会编译失败
    declarations = {
        r"struct\s+ExerciseThumbnail\b": "ExerciseThumbnail",
        r"struct\s+MuscleGlyph\b": "MuscleGlyph",
        r"final class\s+ExerciseLibraryViewModel\b": "ExerciseLibraryViewModel",
        r"final class\s+ExerciseDetailViewModel\b": "ExerciseDetailViewModel",
        r"struct\s+FlowChips\b": "FlowChips",
        r"struct\s+PrimaryButton\b": "PrimaryButton",
        r"struct\s+SecondaryButton\b": "SecondaryButton",
        r"struct\s+CardContainer\b": "CardContainer",
        r"struct\s+SectionHeader\b": "SectionHeader",
        r"struct\s+ProgressBar\b": "ProgressBar",
        r"struct\s+MetaLabel\b": "MetaLabel",
        r"struct\s+EmptyStateView\b": "EmptyStateView",
        r"struct\s+SkeletonBlock\b": "SkeletonBlock",
        r"struct\s+StepperBlock\b": "StepperBlock",
        r"struct\s+ExercisePrescription\b": "ExercisePrescription",
        r"struct\s+ExerciseMuscleRef\b": "ExerciseMuscleRef",
        r"struct\s+AddToWorkoutSheet\b": "AddToWorkoutSheet",
        r"struct\s+ExercisePrescriptionSheet\b": "ExercisePrescriptionSheet",
        r"struct\s+NewPlanNameSheet\b": "NewPlanNameSheet",
        r"struct\s+MediaAttributionLabel\b": "MediaAttributionLabel",
        r"struct\s+ExerciseAnimationView\b": "ExerciseAnimationView",
        # 计划详情与编辑（页面 04）
        r"struct\s+PlanDetailView\b": "PlanDetailView",
        r"final class\s+PlanDetailViewModel\b": "PlanDetailViewModel",
        r"struct\s+PlanExerciseConfigView\b": "PlanExerciseConfigView",
        r"struct\s+PlanExerciseThumbnail\b": "PlanExerciseThumbnail",
        r"struct\s+PlanDetailSkeleton\b": "PlanDetailSkeleton",
        r"struct\s+PlanDetailPreviewHost\b": "PlanDetailPreviewHost",
        r"struct\s+ExerciseDraft\b": "ExerciseDraft",
        r"struct\s+ToastLabel\b": "ToastLabel",
        r"struct\s+ShareSheet\b": "ShareSheet",
        r"struct\s+ExportedFile\b": "ExportedFile",
        r"enum\s+ProgressionRule\b": "ProgressionRule",
        r"enum\s+WeekdayLabel\b": "WeekdayLabel",
        r"enum\s+PlanBackupWriter\b": "PlanBackupWriter",
        r"enum\s+Haptics\b": "Haptics",
        # 通用底部抽屉
        r"struct\s+BottomDrawer\b": "BottomDrawer",
        r"struct\s+DrawerActionRow\b": "DrawerActionRow",
        # 训练 Tab 的导航层
        r"enum\s+TrainingRoute\b": "TrainingRoute",
        r"struct\s+ExercisePickerContext\b": "ExercisePickerContext",
        # 训练执行页（页面 05）与训练总结页
        r"struct\s+WorkoutSessionView\b": "WorkoutSessionView",
        r"final class\s+WorkoutSessionViewModel\b": "WorkoutSessionViewModel",
        r"struct\s+SetRowView\b": "SetRowView",
        r"struct\s+SessionHeaderClock\b": "SessionHeaderClock",
        r"struct\s+FadingNumberText\b": "FadingNumberText",
        r"struct\s+CardQuickAction\b": "CardQuickAction",
        r"struct\s+ExerciseCardView\b": "ExerciseCardView",
        r"struct\s+RestTimerPanel\b": "RestTimerPanel",
        r"struct\s+FinishSummaryContent\b": "FinishSummaryContent",        r"struct\s+NoteEditorContent\b": "NoteEditorContent",
        r"struct\s+ExerciseInfoDrawerContent\b": "ExerciseInfoDrawerContent",
        r"struct\s+ToastBanner\b": "ToastBanner",
        r"struct\s+SessionSkeleton\b": "SessionSkeleton",
        r"struct\s+WorkoutSessionPreviewHost\b": "WorkoutSessionPreviewHost",
        r"struct\s+SessionSummaryView\b": "SessionSummaryView",
        r"struct\s+SessionSummaryPreviewHost\b": "SessionSummaryPreviewHost",
        # 组间休息倒计时（页面 06）
        r"struct\s+RestCountdownPanel\b": "RestCountdownPanel",
        r"struct\s+RestDefaultPickerSheet\b": "RestDefaultPickerSheet",
        r"struct\s+RestTimerRecord\b": "RestTimerRecord",
        r"enum\s+RestNotification\b": "RestNotification",
        r"struct\s+RestFinishedBanner\b": "RestFinishedBanner",
    }

    # 已废弃 API 的调用点，属「能用但不该再用」，单独提示
    deprecated = {
        # 注意：不要建议改用 .toolbar(.hidden, for:)，那是 iOS 16.4+ API，
        # 在 16.3.1 真机上会直接编译不过。这里保留废弃 API 才是正确选择。
        r"\.navigationBarHidden\(":
            "navigationBarHidden 已废弃，但它是 iOS 16.0 起可用的写法，"
            "在 16.3.1 上必须用它，不要换成 iOS 16.4+ 的 .toolbar(.hidden, for:)",
    }

    hits = 0
    files = swift_files()
    decl_index: dict[str, list[str]] = {}
    dep_hits: list[str] = []

    for path in files:
        rel = os.path.relpath(path, ROOT)
        text = open(path, encoding="utf-8").read()
        for pattern, why in patterns.items():
            for match in re.finditer(pattern, text):
                line = text[: match.start()].count("\n") + 1
                fail(f"{rel}:{line} {why} → {match.group(0)!r}")
                hits += 1
        for pattern, why in deprecated.items():
            for match in re.finditer(pattern, text):
                line = text[: match.start()].count("\n") + 1
                dep_hits.append(f"{rel}:{line} {match.group(0)} — {why}")
        for pattern, name in declarations.items():
            if re.search(pattern, text):
                decl_index.setdefault(name, []).append(rel)

    for name, where in decl_index.items():
        if len(where) > 1:
            fail(f"{name} 在多个文件中定义，会重复声明：{', '.join(where)}")
            hits += 1

    if hits == 0:
        ok("未发现错别字、遗留引用或重复声明")

    for item in dep_hits:
        print(f"  [warn] 废弃 API → {item}")


def check_repository_conformance() -> None:
    """协议里声明的方法，两个实现都必须在。

    Swift 编译器会兜住这个，但 Windows 上没有编译器，这条静态检查是唯一防线。
    """
    print("== 仓储协议一致性 ==")
    proto_path = os.path.join(ROOT, "FitnessApp", "Data", "FitnessRepository.swift")
    if not os.path.exists(proto_path):
        fail("缺少 FitnessRepository.swift")
        return

    text = open(proto_path, encoding="utf-8").read()
    # 只取 protocol 主体，不含 extension 里的默认实现
    body_match = re.search(r"protocol\s+FitnessRepository\s*\{(.*?)\n\}", text, re.S)
    if not body_match:
        fail("无法定位 FitnessRepository 协议主体")
        return
    body = re.sub(r"//[^\n]*", "", body_match.group(1))

    # 方法签名：func 名字(label1:label2:
    required = set()
    for match in re.finditer(r"func\s+(\w+)\s*\(([^)]*)\)", body):
        name = match.group(1)
        params = match.group(2)
        # 取出每个参数的外部标签
        labels = []
        for part in params.split(","):
            part = part.strip()
            if not part or part.startswith("_"):
                continue
            label = part.split(":")[0].strip().split()[0]
            if label and label != "_":
                labels.append(label)
        required.add(f"{name}({':'.join(labels)})")

    ok(f"协议声明 {len(required)} 个方法")

    for impl in ["JSONFitnessRepository.swift", "PreviewFitnessRepository.swift"]:
        path = os.path.join(ROOT, "FitnessApp", "Data", impl)
        if not os.path.exists(path):
            fail(f"缺少实现文件 {impl}")
            continue
        impl_text = strip_comments_and_literals(
            open(path, encoding="utf-8").read()
        )
        # 去掉 @discardableResult 等属性行，避免打断 func 匹配。
        # 注意用 [ \t] 而不是 \s：\s 会匹配换行，把整段代码吃掉。
        impl_text = re.sub(r"^[ \t]*@\w+[ \t]*$", "", impl_text, flags=re.M)

        missing = []
        for signature in sorted(required):
            name = signature.split("(")[0]
            if not re.search(rf"\bfunc\s+{name}\s*\(", impl_text):
                missing.append(name)

        if missing:
            fail(f"{impl} 缺少协议方法：{', '.join(missing)}")
        else:
            ok(f"{impl} 覆盖全部协议方法")


def check_resources() -> None:
    print("== 资源 ==")
    seed = os.path.join(ROOT, "Resources", "exerciseLibrary.seed.json")
    if not os.path.exists(seed):
        fail("缺少 Resources/exerciseLibrary.seed.json")
    else:
        try:
            data = json.load(open(seed, encoding="utf-8"))
            ok(f"种子数据 {len(data)} 条，{os.path.getsize(seed) / 1024 / 1024:.1f} MB")
        except Exception as exc:  # noqa: BLE001
            fail(f"种子数据解析失败：{exc}")

    media = os.path.join(ROOT, "Resources", "ExerciseMedia")
    if not os.path.isdir(media):
        fail("缺少 Resources/ExerciseMedia")
        return
    for sub in ("images", "videos"):
        folder = os.path.join(media, sub)
        if not os.path.isdir(folder):
            fail(f"缺少子目录 {sub}/")
            continue
        count = len(os.listdir(folder))
        size = sum(
            os.path.getsize(os.path.join(folder, n)) for n in os.listdir(folder)
        ) / 1024 / 1024
        ok(f"{sub}/ {count} 个文件，{size:.1f} MB")


def main() -> int:
    print("FitnessApp 预检（目标 iOS 16.0 / 实机 16.3.1）")
    print("=" * 46)
    check_info_plist()
    check_project_yml()
    check_sources()
    check_typos()
    check_repository_conformance()
    check_resources()
    print("=" * 46)
    if FAILED:
        print("预检未通过，先修掉上面的 FAIL 再构建。")
        return 1
    print("预检通过。可以运行 ./Tools/build_ipa.sh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
