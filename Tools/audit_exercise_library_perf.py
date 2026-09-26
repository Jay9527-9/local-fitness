#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
动作库性能与布局回归门禁（页面 02）。

由来：实机反馈动作库「加载时间长、卡顿、底栏挡住界面」，定位到三类结构性
问题并修复。这个脚本把修复后的约束固化成断言，防止后续改动把它们改回去。
它不是规格审计（那些在 audit_page16/18/25/26 里），只守三件事：

  1. 派生结果不能退回成「每次 body 求值重算」的计算属性
  2. 列表行必须直接挂在 LazyVStack 下（惰性不能被容器包掉）
  3. 缩略图 / 动画不能退回成 body 内的同步解码
  4. 底部不能叠两层 safeAreaInset

用法：
    python Tools/audit_exercise_library_perf.py
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "FitnessApp")

LIB_FILE = "Features/Exercises/ExerciseLibraryView.swift"
VM_FILE = "Features/Exercises/ExerciseLibraryViewModel.swift"
GLYPH_FILE = "Features/Exercises/MuscleGlyph.swift"
MEDIA_FILE = "Features/Exercises/ExerciseMedia.swift"
ROOT_FILE = "Features/RootView.swift"


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    out = []
    for line in text.split("\n"):
        idx = line.find("//")
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


FILES = {}
for dirpath, _, filenames in os.walk(SRC):
    for name in filenames:
        if name.endswith(".swift"):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, SRC).replace("\\", "/")
            FILES[rel] = open(full, encoding="utf-8").read()

CODE = {k: strip_comments(v) for k, v in FILES.items()}
LIB = CODE.get(LIB_FILE, "")
VM = CODE.get(VM_FILE, "")
GLYPH = CODE.get(GLYPH_FILE, "")
MEDIA = CODE.get(MEDIA_FILE, "")
ROOTV = CODE.get(ROOT_FILE, "")

ITEMS = []


def item(label, ok, extra=""):
    ITEMS.append((label, bool(ok), extra))


def has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is not None


def not_has(text, pattern, flags=0):
    return re.search(pattern, text, flags) is None


# =====================================================================
# 辅助：取某个成员定义的正文（按大括号配平）
# =====================================================================
def body_of(text, header_pattern):
    """返回 header_pattern 匹配处之后第一个配平大括号块的内容。"""
    m = re.search(header_pattern, text)
    if not m:
        return None
    start = text.find("{", m.end() - 1)
    if start < 0:
        return None
    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return None


print("== 1. 派生结果必须预计算，不能是计算属性 ==")

# 这些成员一旦退回 `var x: T { ... }`（无 = 初始化的计算属性），
# 每次 body 求值都会把 1324 条重算一遍 —— 这正是原来的卡顿主因。
PRECOMPUTED = [
    "results",
    "muscleCounts",
    "muscleCategories",
    "availableEquipments",
    "hiddenCount",
    "customCount",
    "favoriteCount",
    "hasLocalMediaInResults",
]

for name in PRECOMPUTED:
    # 必须是 @Published private(set) var name: ... = 初始值
    decl = re.search(
        r"@Published\s+private\(set\)\s+var\s+%s\s*:" % re.escape(name), VM
    )
    item("派生值 %s 现在是 @Published 预计算" % name, decl is not None)

    # 不允许再出现无初始化器的计算属性形式
    computed = re.search(
        r"(?<![\w@])var\s+%s\s*:\s*[^{=\n]+?\{" % re.escape(name), VM
    )
    item("派生值 %s 不是计算属性" % name, computed is None,
         "仍存在 `var %s: T { ... }` 计算属性" % name)

# 重算入口必须存在，且被主要变更点调用
item("存在 rebuildDerived() 统一重算入口", has(VM, r"private\s+func\s+rebuildDerived\(\)"))
item("重算有指纹去重（DerivedKey）",
     has(VM, r"struct\s+DerivedKey") and has(VM, r"guard\s+key\s*!=\s*derivedKey"))
item("dataVersion 参与指纹", has(VM, r"dataVersion"))
item("allExercises 变化触发版本号自增",
     has(VM, r"@Published\s+private\(set\)\s+var\s+allExercises[\s\S]{0,120}didSet"))
item("filter 变化触发重算",
     has(VM, r"@Published\s+var\s+filter[\s\S]{0,80}didSet\s*\{\s*rebuildDerived"))
item("sort 变化触发重算",
     has(VM, r"@Published\s+var\s+sort[\s\S]{0,80}didSet\s*\{\s*rebuildDerived"))
item("debouncedKeyword 变化触发重算",
     has(VM, r"debouncedKeyword[\s\S]{0,80}didSet\s*\{\s*rebuildDerived"))
item("recentExercises 变化触发重算",
     has(VM, r"recentExercises[\s\S]{0,120}didSet\s*\{\s*rebuildDerived"))

# setMuscleCategory 不能就地改 filter 字段（didSet 不触发）
item("setMuscleCategory 整体赋值而非就地改字段",
     has(VM, r"func\s+setMuscleCategory[\s\S]{0,200}var\s+next\s*=\s*filter[\s\S]{0,120}filter\s*=\s*next"))

# 视图层不能重复取结果
item("结果列表在 body 里只取一次预计算值",
     not_has(LIB, r"viewModel\.results\.contains"))
item("署名判断用预计算标志而非再算一遍",
     has(LIB, r"viewModel\.hasLocalMediaInResults"))


print("== 2. 列表行的惰性不能被容器包掉 ==")

# 外层容器必须是 ScrollView + LazyVStack
item("外层是 ScrollView + LazyVStack",
     has(LIB, r"ScrollView\(\.vertical[\s\S]{0,200}LazyVStack\("))

# loaded 分支必须把行列表作为 LazyVStack 的直接子项
loaded = body_of(LIB, r"switch\s+viewModel\.loadState\s*\{")
if loaded is None:
    item("能取到 loadState 分支", False)
else:
    item("结果行列表是 LazyVStack 直接子项",
         has(loaded, r"resultsListSection"))
    item("结果头部与行列表拆成两个子项",
         has(loaded, r"resultsHeaderSection") and has(loaded, r"resultsListSection"))

# 行列表内部不能再用普通 VStack 容器包 ForEach
list_body = body_of(LIB, r"private\s+var\s+resultsListSection")
if list_body is None:
    item("能取到 resultsListSection", False)
else:
    item("resultsListSection 内没有嵌套 VStack 容器",
         not_has(list_body, r"\bVStack\s*\("),
         "行又被包进 VStack，惰性会失效")
    item("resultsListSection 内直接 ForEach 结果",
         has(list_body, r"ForEach\(results\)"))

# 单行抽成函数，避免大闭包拖慢类型检查
item("单行抽成 row(for:) 函数", has(LIB, r"private\s+func\s+row\(for\s+item"))


print("== 3. 缩略图 / 动画不能同步解码 ==")

item("存在缩略图缓存类型",
     has(GLYPH, r"enum\s+ExerciseThumbnailCache") and has(GLYPH, r"NSCache"))

thumb_body = body_of(GLYPH, r"struct\s+ExerciseThumbnail\s*:\s*View\s*\{")
if thumb_body is None:
    item("能取到 ExerciseThumbnail", False)
else:
    # 缓存查询必须在 .task(id:) 里，不能在 body 求值路径上
    item("缩略图走 .task(id:) 异步取缓存",
         has(thumb_body, r"\.task\(id\s*:\s*item\.image\)"))
    item("缩略图 body 内不再直接 UIImage(contentsOfFile:)",
         not_has(thumb_body, r"UIImage\(contentsOfFile:"),
         "body 内同步解码会让滚动掉帧")
    item("缩略图缓存以 @State 持有",
         has(thumb_body, r"@State\s+private\s+var\s+image"))

item("缩略图缓存有容量上限",
     has(GLYPH, r"countLimit"))

anim_body = body_of(MEDIA, r"struct\s+ExerciseAnimationView\s*:\s*View\s*\{")
if anim_body is None:
    item("能取到 ExerciseAnimationView", False)
else:
    item("动画走 .task(id:) 异步加载",
         has(anim_body, r"\.task\(id\s*:\s*item\.gifURL\)"))
    item("离线任务读盘解码",
         has(anim_body, r"Task\.detached"))
    item("动画 body 内不再直接 Data(contentsOf:)",
         not_has(anim_body, r"Data\(contentsOf:"),
         "body 内同步读 GIF 会阻塞主线程")

item("存在动画解码缓存",
     has(MEDIA, r"animationCache") and has(MEDIA, r"countLimit"))
item("isMediaBundled 只查一次 Bundle",
     has(MEDIA, r"mediaBundledFlag")
     and has(MEDIA, r"static\s+var\s+isMediaBundled\s*:\s*Bool\s*\{\s*mediaBundledFlag\s*\}"))

# 全仓不得再有「在视图里同步解码缩略图」的写法。
# PlanExerciseThumbnail 当初就是自己读了盘，现在改为复用 ExerciseThumbnail，
# 于是缓存逻辑只有一份。
SYNC_DECODE = []
for rel, code in CODE.items():
    for m in re.finditer(r"UIImage\(contentsOfFile:", code):
        # 白名单：缓存实现自身（ExerciseThumbnailCache）就该在这里读盘
        if "MuscleGlyph.swift" in rel and "ExerciseThumbnailCache" in code:
            head = code[:m.start()]
            if head.rfind("enum ExerciseThumbnailCache") > head.rfind("struct ExerciseThumbnail"):
                continue
        # 白名单：动作动画缓存 animationImage(for:) 是静态缓存函数，由
        # ExerciseAnimationView 的 .task(id:) 在异步上下文调用，不在任何
        # 视图的 body 求值路径上，作为缓存实现放行（与 ExerciseThumbnailCache 同理）。
        # 这里必须用 UIImage(contentsOfFile: 而非 UIImage(data:)：系统图像解码器
        # 只有「按文件路径解码」才会把 GIF 的多帧回填到 UIImage.images，
        # UIImage(data:) 在部分系统版本上只取首帧，GifImageView 就无从逐帧循环
        # —— 这正是之前「动作 GIF 不动」的根因之一。
        if "ExerciseMedia.swift" in rel:
            fn_start = code.rfind("static func animationImage", 0, m.start())
            if fn_start >= 0:
                i = code.find("{", fn_start)
                if i >= 0:
                    depth = 0
                    closed = -1
                    for j in range(i, len(code)):
                        if code[j] == "{":
                            depth += 1
                        elif code[j] == "}":
                            depth -= 1
                            if depth == 0:
                                closed = j
                                break
                    if closed >= 0 and m.start() < closed:
                        continue
        line_no = code[:m.start()].count("\n") + 1
        SYNC_DECODE.append("%s:%d" % (rel, line_no))

item("全仓无视图内同步解码缩略图",
     not SYNC_DECODE,
     "仍有同步解码：%s（应改用 ExerciseThumbnail / 缓存）" % ", ".join(SYNC_DECODE))

item("PlanExerciseThumbnail 复用 ExerciseThumbnail",
     has(CODE.get("Features/Plans/PlanDetailView.swift", ""),
         r"struct\s+PlanExerciseThumbnail[\s\S]{0,400}ExerciseThumbnail\(item:"))


print("== 4. 底部不能叠两层 safeAreaInset ==")

# RootView 用 safeAreaInset 挂 Tab 栏（这是全局骨架，保留）
item("RootView 仍用 safeAreaInset 挂 Tab 栏",
     has(ROOTV, r"safeAreaInset\(edge:\s*\.bottom[\s\S]{0,120}MainTabBar"))

# 动作库的底部 inset 必须带条件，不能无条件挂空分支
item("动作库底部 inset 带 isPicking 条件",
     has(LIB, r"safeAreaInset\(edge:\s*\.bottom[\s\S]{0,160}if\s+isPicking"))
item("pickingFooter 不再返回空分支（已去掉 @ViewBuilder）",
     not_has(LIB, r"@ViewBuilder\s+private\s+var\s+pickingFooter"))


print("== 5. 反规格 ==")

item("不含 iOS 16.4+ 专属 API",
     not_has(LIB + VM + GLYPH + MEDIA,
             r"@Observable|@Bindable|sensoryFeedback|ContentUnavailableView"
             r"|\.presentationBackground|scrollBounceBehavior|containerRelativeFrame"))


print("== 6. Tab 切换不重建动作库状态机（2026-09-21 实机复检新增） ==")

# 由来：L8 落地后实机仍反馈「点击动作板块会卡住、加载慢」。根因在四类之外：
# TabTransitionContainer 用 .id(tab) 切换，ExercisesTab 连同它的
# StateObject VM 每次切 Tab 都被整体重建，1324 条的加载 + 筛选 + 排序
# 每次都从头跑一遍，并且先闪一帧骨架屏。修复：VM 提升到 RootView 常驻，
# ExercisesTab 以 ObservedObject 接收；load() 已有数据时静默刷新。

item("RootView 常驻持有动作库 VM",
     has(ROOTV, r"@StateObject\s+private\s+var\s+exercisesViewModel\s*:\s*ExerciseLibraryViewModel"))
item("ExercisesTab 以 ObservedObject 接收常驻 VM",
     has(ROOTV, r"@ObservedObject\s+var\s+viewModel\s*:\s*ExerciseLibraryViewModel"))
item("ExercisesTab 不再自建 StateObject VM",
     not_has(ROOTV,
             r"@StateObject\s+private\s+var\s+viewModel\b"
             r"|_viewModel\s*=\s*StateObject"),
     "VM 又回到了 Tab 内部，切 Tab 会整棵重建")
item("ExercisesTab 构造参数含 viewModel",
     has(ROOTV, r"ExercisesTab\([\s\S]{0,200}viewModel:\s*exercisesViewModel"))

item("load() 已有数据时不再打回 loading（静默刷新）",
     has(VM, r"func\s+load\(\)\s+async[\s\S]{0,240}if\s+allExercises\.isEmpty\s*\{\s*loadState\s*=\s*\.loading"),
     "每次切 Tab 都会闪骨架屏")

item("清除全部数据后刷新常驻动作库 VM",
     has(ROOTV, r"exercisesViewModel\.reloadAfterExternalChange\(\)"),
     "清空数据后动作页会显示清空前的旧列表")

# 仓储层：切 Tab 与挑选弹层每次都调 fetchExercises / fetchRecentExercises，
# 排序与建索引必须缓存复用，而不是每次全量重算。
REP = CODE.get("Data/JSONFitnessRepository.swift", "")
item("仓储层有排序缓存",
     has(REP, r"sortedExercisesCache"))
item("exercises 变化即失效缓存（didSet）",
     has(REP, r"private\s+var\s+exercises\s*:\s*\[ExerciseLibraryItem\]\s*=\s*\[\]\s*\{\s*didSet"))
item("fetchExercises 走排序缓存",
     has(REP, r"func\s+fetchExercises\(includeHidden[\s\S]{0,240}sortedExercisesByName\(\)"))
item("仓储层有 id 索引缓存",
     has(REP, r"exercisesByIDCache"))
item("fetchRecentExercises 复用 id 索引",
     has(REP, r"func\s+fetchRecentExercises[\s\S]{0,240}exercisesByID\(\)"))

# 底栏：栏体上沿必须有渐隐过渡，滚动内容不再被生硬切掉
item("MainTabBar 上沿有渐隐过渡",
     has(ROOTV, r"MainTabBar[\s\S]{0,2000}LinearGradient"),
     "底栏又会硬切滚过的内容")


# =====================================================================
print("\n" + "=" * 72)
gaps = [x for x in ITEMS if not x[1]]
print(f"回归项 {len(ITEMS)} 条，未通过 {len(gaps)} 条")
for label, _, extra in gaps:
    print(f"  ✗ {label}{('  → ' + extra) if extra else ''}")
sys.exit(1 if gaps else 0)
