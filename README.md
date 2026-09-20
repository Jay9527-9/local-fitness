# 本地健身 App · 训练首页 + 动作库 + 动作详情 + 计划详情 + 训练执行 + 组间休息 + 训练总结 + 历史日历 + 历史训练详情 + 训练统计 + 动作历史趋势 + 身体数据 + 我的 + 训练偏好 + 我的计划 + 权限管理 + 权限管理

离线优先的中文健身记录 App。TrollStore 侧载使用。已实现页面 01（训练首页）、页面 02（动作库）、页面 03（动作详情）、页面 04（计划详情与编辑）、页面 05（训练执行页）、页面 06（组间休息倒计时）、页面 07（完成训练与训练总结）、页面 08（历史训练日历）、页面 09（历史训练详情）、页面 10（训练统计）、页面 11（动作历史趋势）、页面 12（身体数据）、页面 13（我的）、页面 14（训练偏好）、页面 15（我的计划）。

- 深色炭黑底 + 白色文字 + 单一荧光绿强调色
- 无登录、无网络、无社交（好友 / 动态 / 关注 / 分享 / 云端账号 全部不实现）
- 数据全部本地持久化：`plans` / `workoutSessions` / `exerciseLibrary` / `bodyMeasurements`

---

## 零、统一要求（全项目逐页遵守）

> 这是本项目所有页面必须遵守的硬性约束。任一页面违反即为缺陷，须在交付前修复。
> 本段是权威来源，各页面的展开设计见 §六 各小节与 §十四 门禁。

- **目标系统**：iOS 16.0+，实机 iOS 16.3.1；**不使用 SwiftData**。
- **技术栈**：SwiftUI + `NavigationStack` + `ObservableObject`；本地 `FileManager` + `Codable` JSON 持久化。
- **API 兼容**：不得使用 iOS 16.4+/17 API。点名禁止：`scrollBounceBehavior`（**整个修饰符都算**，`.always` 与 `.basedOnSize` 一样）、`presentationBackground`、`containerRelativeFrame`、`scrollTargetBehavior`、`.toolbar(.hidden, for:)`。
- **数据**：离线优先、无登录、无网络依赖、无云同步；写入用原子替换（`.atomic`），关键操作可回滚。
- **视觉**：深炭黑背景 + 深灰卡片 + 荧光绿强调色（`#C6FF3E`，项目自选，非取自 IPA）；180–260ms 轻量动效；支持动态字体与 VoiceOver。
- **内容边界**：不实现好友、社区、动态、公开计划、排行榜、分享等任何社交功能。
- **版权边界**：不复用原 IPA 的 Logo / 图标 / 插画 / GIF / 私有动作 ID / 专有文案 / 视觉资产；媒体仅用确认可用的本地资源，否则代码绘制占位。动作库媒体署名 `© Gym visual — https://gymvisual.com/` 必须保留（动作库列表页 / 动作详情页 / 我的页三处）。
- **操作安全**：删除、覆盖导入、清空数据等危险操作必须二次确认；历史训练不因删除计划而消失。
- **TrollStore 交付**：后续需 macOS/Xcode 编译为未加密 IPA；安装与最终兼容性待提供安装包后检查。

---

## 一、目标平台

| 项 | 值 |
|---|---|
| 最低版本 | **iOS 16.0** |
| 实机验证目标 | **iOS 16.3.1**（TrollStore 完全支持） |
| 语言 | Swift 5.7+ |
| UI | SwiftUI |
| 持久化 | 本地 JSON 文件（Application Support/FitnessData/*.json） |
| 网络依赖 | 无 |
| 第三方依赖 | 无 |
| 签名 | 不签名（TrollStore 设备端 perma-sign） |
| 架构 | arm64 only |

### 为什么不用 SwiftData

你原话写「iOS 15+ + SwiftData」。这两个条件无法同时成立 —— **SwiftData 要求 iOS 17+**。
目标设备是 **iOS 16.3.1**，因此持久化层改用自己实现的 `JSONFitnessRepository`：
`FileManager` + `JSONEncoder/Decoder`，四个集合各写一个 JSON 文件到 Application Support。

界面层零改动 —— 这正是把界面依赖收敛到 `FitnessRepository` 协议的价值。

### iOS 16 兼容性处理

| 原实现（iOS 17+） | 现实现（iOS 16.0 可用） |
|---|---|
| `SwiftData` + `@Model` + `ModelContainer` | `JSONFitnessRepository`（FileManager + JSON） |
| `.containerRelativeFrame(.horizontal)` | `GeometryReader` 量宽 → 夹到 200…260 |
| `.scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)` | 移除，交给系统默认贴靠 |
| `.scrollBounceBehavior`（16.4+，**整个修饰符**，`.always` 与 `.basedOnSize` 都算） | 直接删除，不留替代（只是「内容不足一屏也回弹」的锦上添花） |
| `.presentationBackground(_:)`（16.4+） | 移除，抽屉自身 `.background` 负责底色 |
| `.toolbar(.hidden, for: .navigationBar)`（16.4+） | `.navigationBarHidden(true)`（16.0+，虽已废弃但在 16.3.1 上必须用它） |
| `Swift Charts`（本可用于图表） | 手绘 `Shape` + `GeometryReader`，理由见 6.4.5 与 6.5.6（页面 11 又多了一条：两图都要「点数据点看详情」，手绘时每个点就是一个 `Button`，不需要在 `.chartOverlay` 里反算几何） |
| `Schema` / `FetchDescriptor` / `#Predicate` | 全部删除 |

保留可用的 iOS 16.0 API：`.safeAreaInset(edge:)`、`.task`、`.refreshable`、`.sheet(item:)`、
`.presentationDetents`、`.alert(_:isPresented:presenting:)`、`LazyVStack` / `LazyHStack`、`NavigationStack`、
`.fileImporter`、`confirmationDialog`、`.onChange(of:)`（单参形式）、`.task(id:)`。

依赖扫描结果：`FitnessApp/` 下已无任何 iOS 17 专属 API 调用（仅注释中保留说明文字）。

---

## 二、如何产出可安装的 IPA

**重要前提**：iOS 二进制必须在 **macOS + Xcode** 上编译。Windows 上不存在 iOS 工具链，无法本地出包。

本仓库提供两条路径，任选其一。

### 路径 A：GitHub Actions（无需 Mac，推荐）

```
1. 把整个 FitnessApp 目录推到你的 GitHub 仓库
2. 仓库页面 → Actions → 左侧选 "Build unsigned IPA" → Run workflow
3. 等约 10 分钟
4. 从该次运行的 Artifacts 下载 FitnessApp-unsigned-ipa
5. 传到 iPhone，用 TrollStore 打开安装
```

工作流文件：`.github/workflows/build-ipa.yml`
- runner：`macos-14`
- 自动安装 `xcodegen` 与 `ldid`
- **构建前依次跑完整门禁链**：媒体完整性 → `preflight.py` → `lint_swift.py` →
  全部 `audit_page*.py` 与 `probe_page*_semantics.py`，任何一项不通过即中止，不会产出坏包
- 产出未签名 IPA 并上传为 Artifact

**本地仓库已经初始化好了**（分支 `main`，2841 个文件，含 131 MB 媒体）。
只剩「建远程仓库 + push」这一步，在本机 `FitnessApp` 目录下执行：

```bash
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

> 首次 push 约 131 MB（媒体占绝大部分）。若不想把媒体提交进仓库，
> 取消 `.gitignore` 里 `Resources/ExerciseMedia/{images,videos}/` 两行的注释，
> 工作流的 "Prepare media assets" 步骤会自动下载补齐（要求总量 < 2648 时才触发）。
> `.gitattributes` 已把这些文件标为 `binary`，不会被行尾转换损坏。

### 路径 B：本机 Mac

```bash
cd FitnessApp
chmod +x Tools/*.sh
./Tools/build_ipa.sh Release
# 产物：FitnessApp-unsigned.ipa
```

`build_ipa.sh` 会先依次跑 `Tools/preflight.py`、`Tools/lint_swift.py`、
以及全部按页留档的审计与推演脚本，任何一项不通过就中止，不会产出坏包。
预检可以单独跑：

```bash
pip3 install pyyaml
python3 Tools/preflight.py
```

覆盖：Info.plist 可解析且最低版本正确、`project.yml` 部署目标与签名设置、
源码中 iOS 17 / 16.4 专属 API 残留、已知错别字、重复声明、**仓储协议与两个实现的方法覆盖一致性**、
种子数据与媒体完整性。废弃 API（如 `navigationBarHidden`）以 `[warn]` 提示但不阻断。

### 安装到设备（iOS 16.3.1）

1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 局域网 HTTP 服务）
2. 用 TrollStore 打开该 IPA
3. 点 Install

**TrollStore 版本要求**：iOS 16.3.1 处于 TrollStore 2 的完整支持区间
（**iOS 15.6 – 16.5 全设备支持**），无需降级系统也无需其他前置条件。

| 系统版本 | TrollStore 支持情况 |
|---|---|
| 15.6 – 16.5 | 全设备支持（含 16.3.1） |
| 16.5.1 – 16.6.1 | 仅 A8 – A11 |
| 17.0 | 仅 A12+ |

> TrollStore 采用 CoreTrust 漏洞做 perma-sign，**要求 IPA 未签名**。
> 本工程的 `build_ipa.sh` 会移除 `_CodeSignature` 并用 `ldid` 做伪签名，符合要求。
> 设备端安装时由 TrollStore 重新签名并永久生效，不依赖电脑、不依赖证书有效期。

---

## 三、工程结构与文件清单

```
FitnessApp/
├── project.yml                          XcodeGen 工程声明
├── .gitignore
├── .github/workflows/build-ipa.yml      GitHub Actions 云端编译
├── README.md
├── Tools/
│   ├── download_media.py                下载动作图片与 GIF
│   ├── verify_resources.py              打包前资源完整性校验
│   ├── preflight.py                     构建前预检（iOS 版本门禁 / plist / 工程声明 / 资源）
│   ├── lint_swift.py                    Swift 结构检查（括号平衡 / 重复定义 / 未知类型）
│   ├── audit_page07.py                  页面 07 规格审计（54 项）
│   ├── probe_page07_semantics.py        页面 07 值语义推演（47 条断言）
│   ├── audit_page08.py                  页面 08 规格审计（97 项）
│   ├── probe_page08_semantics.py        页面 08 值语义推演（91 条断言）
│   ├── audit_page09.py                  页面 09 规格审计（154 项）
│   ├── probe_page09_semantics.py        页面 09 值语义推演（133 条断言）
│   ├── audit_page10.py                  页面 10 规格审计（214 项）
│   ├── probe_page10_semantics.py        页面 10 值语义推演（238 条断言）
│   ├── audit_page11.py                  页面 11 规格审计（157 项）
│   ├── probe_page11_semantics.py        页面 11 值语义推演（258 条断言）
│   ├── audit_page12.py                  页面 12 规格审计（117 项）
│   ├── probe_page12_semantics.py        页面 12 值语义推演（54 条断言）
│   ├── audit_page13.py                  页面 13 规格审计（75 项）
│   ├── probe_page13_semantics.py        页面 13 值语义推演（23 条断言）
│   ├── audit_page14.py                  页面 14 规格审计（60 项）
│   ├── probe_page14_semantics.py        页面 14 值语义推演（45 条断言）
│   ├── audit_page15.py                  页面 15 规格审计（57 项）
│   ├── probe_page15_semantics.py        页面 15 值语义推演（11 条断言）
│   ├── make_project.sh                  生成 Xcode 工程
│   ├── package_resources.sh             素材校验入口
│   ├── build_ipa.sh                     一键编译打包 IPA（内含预检）
│   └── entitlements.plist               ldid 伪签名用
├── FitnessApp/                          源码目录
│   ├── FitnessAppApp.swift              App 入口，装配 JSONFitnessRepository
│   ├── Info.plist                       Bundle 声明（最低 iOS 16.0、深色锁定、仅竖屏、无网络权限）
│   ├── DesignSystem/
│   │   ├── DesignTokens.swift           色彩 / 圆角 / 间距 / 排版 / 动效 / 尺寸
│   │   ├── PressableButtonStyle.swift   按压 0.97 + 180ms 弹性回弹
│   │   └── Resources.swift              资源常量 + 中文格式化工具
│   ├── Models/
│   │   ├── Models.swift                 领域模型 + 今日训练状态枚举
│   │   └── ExerciseTaxonomy.swift       动作库词表：肌群中文名 / 检索别名 / 图标分组
│   ├── Data/
│   │   ├── FitnessRepository.swift          数据层协议（50 个方法）
│   │   ├── JSONFitnessRepository.swift      协议的生产实现（iOS 16 可用）
│   │   └── PreviewFitnessRepository.swift   预览 / 测试用内存桩
│   └── Features/
│       ├── Components.swift             主按钮 / 次级按钮 / 卡片 / 进度条 / 骨架屏 / 空状态
│       ├── BottomDrawer.swift           通用底部抽屉容器 + DrawerActionRow + Haptics
│       ├── RootView.swift               四栏 Tab 骨架 + 220ms 横向淡入 + 训练/历史两个导航栈
│       ├── Training/
│       │   ├── TrainingHomeView.swift        页面 01：训练首页
│       │   ├── TrainingHomeViewModel.swift   首页状态机
│       │   ├── WorkoutSessionView.swift      页面 05：训练执行页
│       │   ├── WorkoutSessionViewModel.swift 执行页状态机（草稿落盘 / 休息计时 / 组表）
│       │   ├── WorkoutSessionComponents.swift 组表行 / 卡片 / 抽屉内容 / 休息结束横幅 / 骨架
│       │   ├── RestCountdownPanel.swift      页面 06：组间休息倒计时面板 + 默认休息选择器
│       │   ├── RestNotification.swift        休息结束的本地通知（可选，默认关闭）
│       │   ├── SessionSummaryView.swift      页面 07：训练总结（统计卡 / 动作完成情况 / 笔记）
│       │   └── SessionSummaryComponents.swift 总结页组件：代码绘制勾选 / 递增数字 / 动作行 / 笔记卡
│       ├── Plans/
│       │   ├── PlanDetailView.swift          页面 04：计划详情（概览 / 训练日 / 动作列表 / 排序）
│       │   ├── PlanDetailViewModel.swift     计划详情状态机 + ExerciseDraft + PlanBackupWriter
│       │   └── PlanExerciseConfigView.swift  计划内动作配置（组数 / 次数 / 休息 / 备注 / 递增）
│       ├── Exercises/
│       │   ├── ExerciseLibraryView.swift     页面 02：动作库（搜索 + 筛选 + 列表）
│       │   ├── ExerciseLibraryViewModel.swift 动作库状态机（检索防抖 / 筛选 / 排序）
│       │   ├── ExerciseSearch.swift          检索与筛选的纯函数（加权打分）
│       │   ├── ExerciseFilterSheet.swift     高级筛选弹窗（器械 / 负重 / 难度 / 标记）
│       │   ├── ExerciseDetailView.swift      页面 03：动作详情（媒体 / 要点 / 肌群 / 加入训练）
│       │   ├── ExerciseDetailViewModel.swift 详情状态机（收藏 / 隐藏 / 复制 / 加入计划）
│       │   ├── AddToWorkoutSheet.swift       加入训练目标选择 + 参数设置 + 新建计划命名
│       │   ├── CustomExerciseEditor.swift    新建 / 编辑自定义动作
│       │   ├── MuscleGlyph.swift             代码绘制肌群图标 + 缩略图（占位图）
│       │   └── ExerciseMedia.swift           媒体路径解析 + 动画视图
│       ├── History/
│       │   ├── HistoryView.swift             页面 08：历史（月历 + 当日时间线 + 列表 + 统计入口）
│       │   ├── HistoryCalendar.swift         日历数学与自然日归并（纯值类型，可移植验证）
│       │   ├── HistoryCalendarComponents.swift 月历 / 日期格 / 标记点 / 训练卡
│       │   ├── HistorySessionDetail.swift    页面 09 值层：动作记录 / 只读契约 / 复制草稿（零 SwiftUI）
│       │   ├── HistorySessionDetailComponents.swift 页面 09 组件：摘要卡 / 动作卡 / 组行 / 输入抽屉 / 删除确认
│       │   ├── HistorySessionDetailView.swift 页面 09：历史训练详情（加载状态机 + 四个抽屉 + toast）
│       │   ├── WorkoutStatistics.swift        页面 10 值层：时间范围 / 五类聚合 / 缓存 / 动作趋势（零 SwiftUI）
│       │   ├── WorkoutBackup.swift            页面 10 值层：备份编解码 / 三条合并策略 / 清除范围（零 SwiftUI）
│       │   ├── WorkoutStatisticsComponents.swift 页面 10 图表：四类卡 + 手绘柱状 / 折线 / 进度条 + 两个抽屉内容
│       │   ├── WorkoutStatisticsView.swift    页面 10：训练统计（范围切换 + 三图一表 + 骨架）
│       │   ├── WorkoutDataManagementView.swift 页面 10：数据管理（导出 / 导入 / 清除）
│       │   ├── ExerciseTrendDetail.swift        页面 11 值层：时间范围 / 单位 / 1RM / 聚合（零 SwiftUI）
│       │   ├── ExerciseTrendDetailComponents.swift 页面 11 图表：折线 / 柱状 / 单位切换 / 降级列表 / 建议抽屉
│       │   └── ExerciseTrendDetailView.swift   页面 11：动作历史趋势（范围菜单 + 三卡 + 开始训练）
│       └── Profile/
│           ├── ProfileView.swift             我的（页面 13 主体：概览卡 + 三组菜单 + 应用设置 + 版本信息）
│           ├── ProfileData.swift             页面 13/14 值层：设置键 / 默认值 / 天数计算 / 摘要文案 / 倒计时样式（零 SwiftUI）
│           ├── ProfileSubpages.swift         页面 13 子页 + 页面 14：个人资料编辑 / 动作收藏 / 训练偏好
│           ├── PlanListView.swift            页面 15：我的计划（搜索 / 排序 / 三点菜单 / 多选 / 导入导出）
│           ├── PlanListData.swift            页面 15 值层：排序 / 复制命名 / 多计划备份编解码（零 SwiftUI）
│           ├── BodyData.swift                页面 12 值层：指标 / 单位 / 校验 / 聚合 / 摘要（零 SwiftUI）
│           ├── BodyDataComponents.swift      页面 12 组件：摘要卡 / 折线图 / 记录卡 / 录入面板 / 删除确认
│           ├── BodyDataView.swift            页面 12：身体数据（趋势 / 记录分段 + 录入 / 覆盖 / 删除）
│           ├── PermissionData.swift          页面 51 值层：权限种类 / 四态 / 状态映射 / 清单（零 SwiftUI）
│           ├── PermissionCenter.swift        页面 51：系统权限读取（只读，不含任何申请调用）
│           └── PermissionSettingsView.swift   页面 51：权限管理（四项状态 + 前往系统设置 + 兜底说明）
└── Resources/                           打包进 Bundle 的资源
    ├── exerciseLibrary.seed.json        动作库种子数据（1324 条，1.4 MB）
    └── ExerciseMedia/                   动作媒体（2648 个文件，131 MB）
        ├── images/                      1324 张 JPG，8.5 MB
        └── videos/                      1324 个 GIF，122.8 MB
```

---

## 四、资源准备

动作媒体需先下载到本地才能打进 IPA：

```bash
python3 Tools/download_media.py      # 下载 2648 个文件，约 5 分钟
python3 Tools/verify_resources.py    # 校验完整性，退出码 0 才算通过
```

`build_ipa.sh` 会自动调用校验，缺失时中断打包并列出缺失清单。

媒体体积预期：**约 130 MB**
- `images/` 1324 张 JPG，约 9 MB
- `videos/` 1324 个 GIF，约 126 MB

---

## 五、页面 01 布局对照

| 区域 | 实现位置 | 说明 |
|---|---|---|
| 顶部安全区导航栏 | `navigationBar` | 左「训练」大标题，右「日历/计划」+「更多」线框图标，各 44pt 触控区 |
| 今日训练卡 | `TodayTrainingCard` | 日期 + 星期 + 状态；三态：加载骨架 / 无计划空状态 / 已安排或进行中 |
| 快捷入口 | `quickActions` | 两个等宽按钮「新建力量训练」「新建有氧训练」 |
| 我的计划 | `myPlansSection` | 横向滚动卡片，名称 / 训练天数 / 上次使用 / 动作数 / 三点菜单 |
| 最近训练 | `recentSessionsSection` | 按日期倒序，名称 / 时长 / 组数 / 容量 或 距离 |
| 底部 Tab | `MainTabBar` | 四栏，当前项荧光绿高亮，`safeAreaInset(.bottom)` 固定 |

### 今日训练卡的四种状态

| 状态 | 触发条件 | 主按钮 |
|---|---|---|
| `loading` | 正在读取本地数据 | 不可点击 |
| `empty` | 无计划且无进行中训练 | 「开始一次训练」 |
| `scheduled` | 今日命中训练日，或有可用计划 | 「开始训练」 |
| `inProgress` | 存在 `endedAt == nil` 的记录 | 「继续训练」+ 进度条 |

优先级：**进行中 > 今日计划 > 空**。

---

## 五之二、页面 02 动作库

### 布局对照

| 区域 | 实现位置 | 说明 |
|---|---|---|
| 顶部安全区导航栏 | `navigationBar` | 左「动作」大标题，右 34pt 荧光绿圆形「+」，外包 44pt 触控区 |
| 搜索框 | `searchField` | 左侧放大镜，占位「搜索动作名称或器械」，右侧清除按钮 + 高级筛选按钮 |
| 肌群 Chip 行 | `muscleChips` | 横向滚动：全部 / 胸 / 背 / 肩 / 手臂 / 核心 / 腿 / 臀 / 小腿 / 有氧 / 收藏，各自带条数 |
| 最近使用 | `recentSection` | `@ViewBuilder` 条件渲染，无历史时整块不占位 |
| 结果列表 | `resultsSection` | `LazyVStack`，行数统计 + 行 + 署名 |
| 底部 Tab | `MainTabBar` | 复用页面 01 骨架，「动作」高亮 |

### 动作行结构

```
┌──────────────────────────────────────────────────┐
│ ┌──────┐  杠铃平板卧推                       ›   │
│ │ 52×52│  胸大肌 · 杠铃 · 进阶                    │
│ └──────┘                                          │
└──────────────────────────────────────────────────┘
```

- 左：52×52。有本地媒体时用 JPG 缩略图；无媒体时用 `MuscleGlyph` 代码绘制
- 中：动作名（最多两行）+ 主肌群 · 器械 · 难度
- 右：`chevron.right`
- 长按：`.contextMenu`，顺序为 添加到训练 / 收藏 / 编辑 / 隐藏或删除

### 列表状态机

| 状态 | 触发条件 | 呈现 |
|---|---|---|
| `loading` | 首次读取动作库 | 8 行骨架屏 |
| `loaded` + 有结果 | 正常 | 列表 |
| `loaded` + 无结果 | 关键字或筛选过滤为空 | 「没有找到匹配动作」+「新建自定义动作」 |
| `loaded` + 库为空 | 种子导入失败或全被隐藏 | 区分提示：库为空 / 全被筛掉 |

`emptyMessage` 会区分三种成因，不会一律显示「没有找到」造成误导。

### 中文检索怎么做的

数据源只有英文（`barbell bench press`），但用户要搜「卧推」。**没有使用任何第三方 App 的名称映射**，
而是在 `Models/ExerciseTaxonomy.swift` 里自建了三张词表：

| 表 | 作用 | 规模 |
|---|---|---|
| `MuscleName.targetToChinese` | `target` 英文 → 主肌群中文名 | 19 条（覆盖数据集全部 target 值） |
| `MuscleName.groupToChinese` | `muscleGroup` / `secondaryMuscles` → 中文肌群名 | 40 条（覆盖数据集全部肌群标识） |
| `ExerciseAliases.rules` | 英文名称关键词 → 中文口语别名 | 约 100 条规则 |

导入种子数据时执行一次 `ExerciseAliases.enrich(_:)`，把中文别名与主肌群写进 `aliases` / `primaryMuscle`
并落盘，之后检索全是本地字符串比较，零网络。

### 加权检索打分

`ExerciseSearch.score(_:needle:)` 按命中位置给分，分数高者靠前：

| 命中位置 | 分值 |
|---|---|
| 名称完全相等 | 1000 |
| 名称前缀 | 600 |
| 别名完全相等 | 500 |
| 名称包含 | 400 |
| 别名包含 | 300 |
| 主肌群 | 200 |
| 器械 | 150 |
| 次级肌群 | 120 |
| 收藏加权 | +60 |
| 自定义加权 | +40 |

排序可切换：相关度 / 名称 / 难度 / 最近使用。

### 搜索防抖 150ms

```swift
searchCancellable = $searchText
    .removeDuplicates()
    .debounce(for: .seconds(Self.searchDebounce), scheduler: RunLoop.main)
    .sink { [weak self] text in self?.debouncedKeyword = text }
```

用 Combine 在 ViewModel 内完成，不改动输入框内容，光标不跳。`isDebouncePending` 暴露给 UI
用于显示轻微的活动指示。

### 高级筛选

`ExerciseFilterSheet`，工具栏左「重置」右「完成」。

| 分组 | 内容 |
|---|---|
| 器械 | `FlowChips` 自适应网格，选项从当前库反推，不硬编码 |
| 负重性质 | 自重 / 负重 / 器械 |
| 难度 | 入门 / 进阶 / 高级 |
| 标记 | 仅看自定义动作 / 仅看收藏 / 包含已隐藏（带条数副标题） |

入口按钮带角标，显示当前生效的高级筛选条数（`ExerciseFilter.advancedCount`）。
肌群 Chip 不算高级筛选，单独占一行常驻。

### 隐藏而非删除

官方导入的动作**不可删除**，只能收藏或隐藏：

| 来源 | 收藏 | 隐藏 | 编辑 | 删除 |
|---|---|---|---|---|
| 导入（`isCustom == false`） | ✅ | ✅ | ❌ | ❌ |
| 自定义（`isCustom == true`） | ✅ | ✅ | ✅ | ✅（二次确认） |

`JSONFitnessRepository.deleteExercise(id:)` 对非自定义条目抛 `StorageError.notDeletable`，
不只是在 UI 上藏起按钮 —— 数据层也拦住。

隐藏条目默认不出现在列表与最近使用中，需要高级筛选里勾「包含已隐藏」才能看到。

### 最近使用为什么用 `@ViewBuilder` 条件渲染

你要求「没有历史时不渲染该区，避免空白」。实现上整个 section 是一个 `@ViewBuilder` 分支，
`recentExercises.isEmpty` 时直接返回空视图，**不占任何垂直空间**，而不是渲染一个空容器再加 `if`。
上限 6 个，超出由 `recentLimit` 截断。

### 新建自定义动作

`CustomExerciseEditor` 用 `Form`，分四段：

1. 基本信息：名称、别名、实时 `MuscleGlyph` 预览
2. 肌群：肌群分组 `Picker`（中文）、主肌群、协同肌群
3. 器械与难度：器械 `Picker`、难度 `Picker`、根据器械推导的负重性质（只读）
4. 内容：动作说明、分步说明

保存时把肌群分组映射回英文 `target`，别名按 `、,，/` 切分，分步说明按换行切分，
`id` 生成 `"custom-\(UUID().uuidString)"` 保证不与导入数据冲突。

### 媒体没有授权时怎么办

你要求「媒体资源必须来自已确认可使用的数据源；若未授权则只显示代码生成的占位图」。
实现是 `MuscleGlyph` —— 纯 `Canvas` + `GraphicsContext` 绘制的几何图形，零第三方美术素材。

| 位置 | 有本地媒体 | 无本地媒体 |
|---|---|---|
| 列表缩略图 | JPG 缩略图 | `MuscleGlyph` |
| 详情页主视觉 | 播放 GIF | 180pt 大号 `MuscleGlyph` + 说明文字 |

`MuscleIconGroup` 把肌群归成 11 个形体组（胸 / 背 / 肩 / 手臂 / 核心 / 腿 / 臀 / 小腿 / 有氧 / 颈 / 其他），
每组画不同几何形状，所以列表在不看文字时也能一眼区分部位。

### 无障碍

- 搜索框：`accessibilityLabel("搜索动作名称或器械")`
- 肌群 Chip：`accessibilityLabel("按胸筛选")` 形式，含条数
- 动作行：`accessibilityLabel` 拼出「动作名，主肌群，器械，难度」，附 `.isButton`
- 长按菜单项：中文 `Label` 文本本身就是可读标签
- 动作名 `.lineLimit(2)`，配合动态字体放大不会截断成单字

---

## 五之三、页面 03 动作详情

### 布局对照

| 区域 | 实现位置 | 说明 |
|---|---|---|
| 导航栏 | `toolbar` | 左返回（系统）、中标题「动作详情」、右收藏星标 + 更多菜单 |
| 媒体区 | `mediaCard` | 16:9 圆角卡片；右下角「演示」标签 |
| 名称与标签 | `titleBlock` | 大标题 + 别名副标题 + 主肌群／器械／难度／自定义标签 |
| 动作要点 | `stepsSection` | 编号圆点 + 中文分步说明 |
| 涉及肌群 | `muscleSection` | 主肌群置顶高亮，协同肌群普通标签，点击跳动作库筛选 |
| 底部主操作 | `safeAreaInset(.bottom)` | 固定「添加到训练」 |

### 收藏按钮

| 状态 | 图标 | 颜色 |
|---|---|---|
| 未收藏 | `star` | `textTertiary`（灰描边） |
| 已收藏 | `star.fill` | `accent`（荧光绿实心） |

按下走 `PressableButtonStyle`（0.97 缩放 + 180ms 弹性回弹），松开即写本地数据。

写入策略是**乐观更新 + 失败回滚**：先翻转本地 `item.isFavorite` 让星标立刻响应，
再调 `repository.toggleFavorite(exerciseID:)`；抛错就把本地值翻回去并弹提示。
这样星标不会因为一次磁盘写入而出现可见延迟。

### 媒体区的三种情形

| 情形 | 呈现 |
|---|---|
| 有本地媒体且已随包分发 | `ExerciseAnimationView(aspectRatio: 16/9)` 循环演示，可点按暂停 |
| 无媒体（自定义动作） | `MuscleGlyph` + 「自定义动作，使用代码绘制的肌群示意图」 |
| 无媒体（导入动作未打包） | `MuscleGlyph` + 「本包未分发该动作的媒体，使用代码绘制的肌群示意图」 |

**任何情况下都不加载外部网络图片。** 「演示」标签固定在卡片右下角，半透明黑底。

### 涉及肌群与「点击跳筛选」

主肌群用低透明度荧光绿底 + `target` 图标，协同肌群用深灰底。
点击任一标签调 `onOpenMuscle(muscle)`，由 `ExercisesTab` 处理：

```swift
onOpenMuscle: { muscle in
    viewModel.applyMuscleFilterFromDetail(muscle)
    path = NavigationPath()   // 回到动作库根页
}
```

`applyMuscleFilterFromDetail` 的顺序很关键 —— **先清搜索关键词，再设肌群，并重置高级筛选**：

```swift
func applyMuscleFilterFromDetail(_ muscle: String) {
    clearSearch()
    var next = ExerciseFilter.none
    next.muscleCategory = muscle
    next.includeHidden = filter.includeHidden
    filter = next
    sort = .relevance
}
```

若不清关键词，会落进「关键词 ∩ 肌群」的交集，用户很可能看到空列表，
误以为肌群筛选坏了。同理，旧的器械／难度条件若叠加进来也会造成空结果，
所以一并重置。

### 底部「添加到训练」的三条路径

点击底部按钮弹出 `AddToWorkoutSheet`：

| 项 | 显示条件 | 后续 |
|---|---|---|
| 添加到正在进行的训练 | 仅存在 `endedAt == nil` 的训练 | 直接追加一组，附「已加入」提示 |
| 添加到已有计划 | 存在计划时可选（无计划则禁用） | 展开计划列表 → 选中 → 弹参数设置面板 |
| 新建力量训练并添加 | 总是显示 | 弹命名面板 → 建计划 → 加入动作 |

有进行中训练时，它被排在第一项并用荧光绿高亮 —— 这是最高频的路径。

### 参数设置面板

选中计划后弹 `ExercisePrescriptionSheet`，字段与你要求的一致：

| 字段 | 控件 | 范围 |
|---|---|---|
| 组数 | `StepperBlock` | 1…20，步长 1 |
| 次数范围 | 区间开关 + 两个 `StepperBlock` | 1…50，步长 1 |
| 休息秒数 | `StepperBlock` | 15…600，步长 15 |
| 是否热身组 | `Toggle` | — |

默认值由动作推导，不是写死的：

```swift
static func `default`(for item: ExerciseLibraryItem) -> ExercisePrescription {
    switch item.loadKind {
    case .bodyweight:  sets 3, reps 12…20, rest 60
    case .machine:     sets 3, reps 10…15, rest 75
    case .weighted:    sets 4, reps 8…12,  rest 90
    }
    if item.difficulty == .advanced { rest += 30 }   // 高难度动作多休息
}
```

次数用区间时上限自动不低于下限（`onChange` 联动）；关掉区间则上限跟随下限。
面板底部给出「这组参数大约需要 X 分钟」，按每组 40 秒动作时间加休息累加，
并在文案里注明这是估算值。

### 右上角更多菜单

| 菜单项 | 导入动作 | 自定义动作 |
|---|---|---|
| 编辑动作 | 不显示 | ✅ 打开 `CustomExerciseEditor` |
| 复制为自定义动作 | ✅ | ✅ |
| 隐藏动作 / 取消隐藏 | ✅ | ✅（二次确认） |

**「复制为自定义动作」**是给导入动作开的一扇门：既然它不可编辑，就产出一个可编辑的副本。
新条目 `id` 为 `custom-<UUID>`，名称加「（副本）」后缀（已是副本则不叠加），
`isCustom = true`，收藏与隐藏状态不继承。复制完直接打开编辑器。

### 隐藏必须二次确认

`viewModel.requestHide()` 只置 `isConfirmingHide = true`，由 `.alert` 承接：

```
隐藏这个动作？
隐藏后它不会出现在动作库列表和最近使用里。
可以在动作库右上角的高级筛选里勾选「包含已隐藏」找回。
```

确认后才调 `toggleHidden`。文案明确告知**如何找回**，避免用户以为数据被删了。

### 空数据容错

| 缺失项 | 表现 |
|---|---|
| 无步骤说明 | 「暂未提供动作说明」 |
| 无肌群信息 | 「暂未提供肌群信息」 |
| 无媒体 | 代码绘制占位图 + 说明文字 |
| 无任何计划与进行中训练 | 底部按钮下方提示「还没有训练记录或计划。可以先新建一个力量训练。」 |

**「添加到训练」在任何情况下都保持可用** —— 即使没计划没记录，第三条路径
「新建力量训练并添加」也能走通。

### 无障碍

- 收藏按钮：`accessibilityLabel` 在「收藏」/「取消收藏」间切换，已收藏时加 `.isSelected`
- 更多菜单：`accessibilityLabel("更多操作")`
- 步骤行：`accessibilityElement(children: .ignore)` + `accessibilityLabel("第 N 步，<内容>")`，
  避免读屏把编号和正文拆成两个元素
- 肌群标签：区分「主训练肌群 X，点击筛选」与「协同肌群 X，点击筛选」
- 占位媒体：`accessibilityLabel("<动作名> 暂无演示动画，显示肌群示意图")`
- `StepperBlock` 用 `.accessibilityAdjustableAction`，读屏可直接上滑／下滑增减；
  中间数值不是纯数字时（如「1 分 30 秒」）通过 `accessibilityValue` 给出可读文案

---

## 五之四、页面 04 计划详情与编辑

### 布局对照

| 区域 | 实现 |
| --- | --- |
| 导航栏 | 返回 ／ 计划名（可点击重命名）／ 更多菜单 |
| 概览卡 | 计划名 + 四项指标（每周训练、动作总数、预计时长、上次训练）+ 全宽「开始训练」 |
| 训练日 | 周一至周日圆形按钮，已选荧光绿；「编辑训练日」进多选 |
| 动作列表 | 序号、缩略图、动作名、`组数 × 次数`、休息、热身标记、拖拽把手 |
| 底部 | 「添加动作」，空计划时是「添加第一个动作」 |

### 为什么整页是一个 `List`

`onMove` 的拖拽排序只有当 `List` **自己**是滚动容器时才稳定工作。把 `List` 塞进
`ScrollView` 就必须给它写死高度，行高一变就会截断或留白，拖到屏幕边缘也滚不动。

所以概览卡、训练日、动作行都是 `List` 的行，用 `.listRowInsets` 控制留白，
视觉上仍是卡片式分区，但滚动与排序共用一个容器。

### 排序模式的进入方式

iOS 16 的 `List` 排序要在 `EditMode.active` 下才显示系统拖拽控件。
这里把卡片右侧把手做成入口：

- 常规模式：点把手 → 进入排序模式，底部按钮换成「完成排序」
- 排序模式：把手换成 ✓，点它或底部按钮退出

进入排序模式后，卡片的 `onTapGesture` 与 `onLongPressGesture` 全部短路，
避免拖动过程中误触发出配置页或长按菜单。

### 只改计划内的配置，不动动作库

`PlanExercise` 才是这一页的编辑对象。动作库的 `ExerciseLibraryItem` 是只读来源，
页面里任何操作都不会写回它。这一点在两个地方显式说明：

- 配置页底部的提示条：「这里的修改只作用于本计划内的这个条目」
- 备注区的说明：「只在当前计划内生效，不会改动动作库里这个动作的说明」

配置页新增了两个字段：

```swift
var note: String?                    // 计划内备注
var progression: ProgressionRule     // 不设置 / 加重量 / 加次数 / 加组数
```

`PlanExercise` 提供了容错 `init(from:)`：老版本 `plans.json` 没有这两个字段，
升级后仍能正常解码，缺省值是 `nil` 与 `.none`。

### 移除动作的二次确认

长按 → 从计划移除 → 底部抽屉二次确认，文案明确说明作用范围：

> 只会移除这个计划里的动作配置。动作库中的动作，以及已经完成的历史训练记录都不会被删除。

### 删除计划不删历史

`delete(planID:)` 只摘掉 `plans.json` 里的这一条，`sessions.json` 完全不动。
二次确认弹窗里也写明了这一点。

### 「开始训练」置灰

`canStartTraining` 在动作数为 0 时为 false，按钮走 `PrimaryButton(isEnabled: false)`，
视觉降为 40% 不透明度并禁用点击。**不做**「点进去再提示」——
那样会先创建出一个空训练草稿，反而污染训练历史。

### 训练日选择器只读

概览卡下方的训练日圆形按钮**不可点击**，只做展示。
修改必须走「编辑训练日」。

原因：七个圈排在一行，误触概率高，而改训练日会直接影响首页「今日已安排」的判断，
不该在浏览页面时被随手改掉。这也是把编辑拆成独立抽屉的原因。

### 中文星期的两种写法

训练日存的是 `Int`（1 = 周一 … 7 = 周日），展示需要两种粒度：

- `WeekdayLabel.symbol(_:)` → `一`，圆形按钮里的单字
- `WeekdayLabel.short(_:)` → `周一`，用于「周一、周三、周五」这类列举

统一放在 `WeekdayLabel` 里，避免各处各写一套 switch。
`normalize(calendarWeekday:)` 负责把 `Calendar` 的 1 = 周日换算成 1 = 周一。

### 导出本地备份

`PlanBackupWriter` 把计划连同所引用动作的名称序列化成 JSON，写到临时目录，
再用 `UIActivityViewController` 弹出系统分享面板。

只导出与这个计划有关的内容，不含账号、训练历史等其他数据。
文件里带了 `format` 与 `version` 字段，便于将来做导入兼容。

### 从动作库挑动作的完整链路

「添加动作」和「替换动作」都进入动作库的**挑选模式**：

1. 底部 `sheet` 展示 `ExerciseLibraryView(pickerTitle:)`
2. 挑选模式下：大标题换成提示文案、隐藏「新增自定义动作」按钮、
   右侧图标从 chevron 换成勾选圈、底部加一条「轻点任意动作即可选中」
3. 点行即选中 → 关闭 sheet → 写入计划（追加到末尾 / 覆盖原条目）
4. 上层 `planRefreshToken` 自增，计划详情页 `onChange` 重新读数据

第 4 步不能省：`sheet` 关闭后计划详情页不会重走 `onAppear`，
只用 `onAppear` 刷新的方案会看到过期列表。

### 替换动作保留配置

`replacePlanExercise(_:inPlan:withExerciseID:)` 只换 `exerciseID`，
`sets` / `repsLow` / `repsHigh` / `restSeconds` / `isWarmup` / `note` / `progression` 全部保留。
用户换动作时不需要重填一遍参数。

### 无障碍

- 动作卡：单个可访问元素，标签形如「第 3 个动作，杠铃卧推，4 组 × 6-8 次，休息 2 分，备注：…，递增规则：加重量」
- 拖拽把手单独可聚焦，否则 VoiceOver 用户无法进入排序模式
- 训练日圆点：`accessibilityValue` 给出「训练日 / 休息日」
- 编辑抽屉里的圆点：`accessibilityValue` 给出「已选择 / 未选择」+ `.isSelected` trait
- 概览四项指标合并成一个元素，读作「动作总数：6 个动作」，而不是标题和数值分开读

---


| # | 修正项 | 落实情况 |
|---|---|---|
| 1 | `PlanCard` 嵌套 Button 点击冲突 | 已改为 `ZStack` 内两个并列 `Button`：卡片主体负责打开，右上角三点负责菜单，互不嵌套 |
| 2 | `ClosedRange<Int>` 拆分 | 已改为 `repsLow` / `repsHigh`，保留 `repsText` 输出 `"8-12"` / `"10"` |
| 3 | 抽屉用计划对象驱动 | 已改为 `.sheet(item: $drawerPlan)`，`showPlanDrawer` 已删除（0 处引用） |
| 4 | 按压动画不用 `DragGesture` | 已改为 `PressableButtonStyle`，由 `configuration.isPressed` 驱动（`DragGesture` 0 处） |
| 5 | `MainTab.icon` 显式 `return` | 已改为 `symbolName` / `selectedSymbolName`，每个分支显式 `return` |
| 6 | Tab 栏用 `safeAreaInset` | 已在 `RootView` 使用 `.safeAreaInset(edge: .bottom)`，未手写底部 padding |
| 7 | 计划卡宽度自适应 | 因 iOS 17 限制，`.containerRelativeFrame` 用不了；改为 `GeometryReader` 量滚动容器宽度后取约 65%，夹在 200…260 |
| 8 | 数据层协议 | 已定义 `FitnessRepository`（29 方法）；所有 ViewModel 均通过构造器注入该协议 |

### 关于强调色

`#C6FF3E` 是本项目自选的独立强调色，**并非**从原 App 提取的色值。代码注释中已注明。

---

## 五之五、页面 05 训练执行页

App 的核心页面：从计划详情点「开始训练」进入，也从未结束训练卡点回来。

### 布局对照

| 规格 | 实现 |
|---|---|
| 顶部固定栏：左最小化 / 中名称 + 时长 / 右结束 | `safeAreaInset(edge: .top)` + `topBar`；`chevron.down` / `SessionHeaderClock` / 「结束」 |
| 计时器持续运行 | `SessionHeaderClock` 自持 1 秒 `Timer`，时长恒为 `now − startedAt` |
| 最小化后保留进行中，返回可恢复 | `minimize()` 只停秒表；草稿早已落盘；`didBecomeActive` → `resumeFromMinimize()` |
| 概览：已完成动作数 / 组数 / 总容量 | `strengthMetrics` 三项，`completedExerciseCount` / `completedSetCount` / `totalVolume` |
| 有氧改显示时长 / 距离 / 消耗 | `cardioMetrics` 三项，`kind == .cardio` 时替换 |
| 数字变化 180ms 淡入 | `FadingNumberText`，`.task(id: value)` 自驱 opacity 0→1 |
| 主区纵向 `LazyVStack` | `ScrollView { LazyVStack { overviewCard; ForEach(viewModel.cards) } }` |
| 动作卡：名称 / 目标肌群 / 上次记录 / 组表 / 更多 | `ExerciseCardView` 的 `header` + `tableHeader` + `setList` + `moreButton` |
| 表列：组号 / 重量 / 次数 / 完成状态 | `setIndexColumn` / `weightControl` / `repsControl` / `checkbox` 四列 |
| 重量与次数可直接点击编辑 | `valueButton` → `valueEditor`：真 `TextField` + `decimalPad` / `numberPad` + 加减步进 |
| 圆形勾选：灰描边 → 荧光绿实心 | `checkbox`，`checkboxIdle` 描边 → `accent` 实心 + `DS.Motion.check` |
| 热身组低对比灰标签、不计容量 | `warmupBadge`「热身」；`SetEntry.volume` 中 `isWarmup ? 0 : …` |
| 正式组显示主强调色进度 | `ProgressBar(value: viewModel.progress)` |
| 卡底三按钮 | `CardQuickAction`：新增一组 / 休息计时 / 动作说明 |
| 新增一组复制上一组数值 | `duplicatedTarget(at:)` + `insertSetEntry` 取该动作最后一组为模板 |
| 动作说明打开只读抽屉 | `ExerciseInfoDrawerContent` + `BottomDrawer` |
| 完成一组自动触发休息倒计时 | `toggleCompletion` → `startRest(card:seconds: card.restSeconds)` |
| 休息面板底部上滑 | `RestTimerPanel` + `.transition(.move(edge: .bottom))` |
| 剩余秒数 / 暂停继续 / ±15 秒 / 跳过 | `remainingSeconds` / `toggleRestPause()` / `adjustRest(by:)` / `skipRest()` |
| 结束播放本地提示音 + 触感 | `AudioServicesPlaySystemSound(1057)` + `Haptics.success()` |
| 前台显示，不依赖推送 | 无任何 `UNUserNotificationCenter` 调用 |
| 更多：编辑配置 / 替换 / 备注 / 删除 | `DrawerActionRow` ×4；删除走 `pendingDeleteCard` 二次确认 |
| 替换保留已完成组 | `guard !entry.isCompleted else { continue }` |
| 底部固定「完成训练」 | `safeAreaInset(edge: .bottom)` + `PrimaryButton(title: "完成训练")` |
| 完成确认抽屉 | `FinishSummaryContent`：时长 / 组数 / 总容量 + 备注 `TextEditor` |
| 确认后写 `endedAt`、停表、进总结页 | `finishSession(sessionID:endedAt:note:)` → `SessionSummaryView` |
| 草稿实时原子保存 | 每处改动都走 `mutateSession` → 整份 `sessions.json` `.atomic` 重写 |
| 终止或最小化后能恢复 | 首页 `.inProgress` 分支直接 `path.append(.sessionDraft(sessionID))` |

### 双态 `SetEntry`：一张表同时承载「计划」与「已完成」

执行页最大的建模问题是：组表既要有**未完成的目标行**（让用户看到 4 组 × 8-12 次），
又要有**已完成的记录行**。常见做法是拆成 `plannedSets` + `draftSets` 两个数组，
但那样排序、插入、删除、替换动作都需要在两套结构之间同步。

这里改用**单数组双态**：`SetEntry.completedAt == nil` 表示未完成，非 nil 表示已完成。

```swift
var isCompleted: Bool { completedAt != nil }
/// 未完成组直接读 weight 字段（草稿展开时已用历史最高重量预填）
var displayWeight: Double { weight }
var displayReps: Int { isCompleted ? reps : targetRepsLow }
```

带来的三个直接好处：

1. **排序与分组只作用于一个数组**，`entriesByExercise` 天然保序；
2. **「替换动作保留已完成组」不需要额外簿记** —— 只把 `!isCompleted` 的条目改 `exerciseID`，已完成条目原地不动；
3. **「新增一组复制上一组」就是读数组最后一个元素**，无需回查计划。

**解码容错是这里的重点**：`completedAt` 是后加字段，旧版 `sessions.json` 里没有。
若按常规 `decodeIfPresent` 解成 `nil`，**所有历史记录都会被当成「未完成组」**，
容量、组数统计会瞬间归零。所以缺字段时补一个 `Date(timeIntervalSince1970: 0)`：

```swift
if container.contains(.completedAt) {
    completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
} else {
    completedAt = Date(timeIntervalSince1970: 0)   // 老数据都是已完成的
}
```

### 草稿从计划展开：`WorkoutSession.draft(from:)`

进入执行页不能是一张全空的表。`draft(from:)` 把计划里的每个 `PlanExercise`
按 `sets` 数量展开成对应条数的未完成组，并带上 `planEntryID`（替换动作用）、
`targetRepsLow/High`（表里显示 8-12）、`isWarmup`：

```swift
static func draft(from plan: Plan, startedAt: Date = .now) -> WorkoutSession {
    var entries: [SetEntry] = []
    for item in plan.exercises {
        for offset in 1...max(1, item.sets) {
            entries.append(SetEntry(
                exerciseID: item.exerciseID, planEntryID: item.id, index: offset,
                weight: 0, reps: item.repsLow,
                targetRepsLow: item.repsLow, targetRepsHigh: item.repsHigh,
                isWarmup: item.isWarmup, completedAt: nil))
        }
    }
    ...
}
```

紧接着 `seedPrescribedWeights(in:)` 用**该动作最近 30 次训练里的最高重量**预填未完成组的重量。
不填的话整张表全是 0（自重），用户每组都要手输；填上之后表格立刻像一份可用的训练日志。
`PlanDetailViewModel.makeSessionDraft()` 与 `TrainingTab.startDraft(forPlanID:)` 两处入口都调它。

### 每处改动都原子落盘

规格要求「每次完成组、修改重量次数、增删组、修改备注后都原子写入」。实现方式是
仓储里的一个私有助手，所有改动收敛到同一条路径：

```swift
private func mutateSession(_ sessionID: UUID,
                           _ body: (inout WorkoutSession) -> Bool) throws -> WorkoutSession? {
    try loadIfNeeded()
    guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return nil }
    var session = sessions[index]
    guard body(&session) else { return session }   // 闭包返回 false：无变化，不落盘
    sessions[index] = session
    try write(sessions, to: sessionsURL)           // 整份 .atomic 重写
    return session
}
```

`updateSetEntry` / `markSetCompleted` / `insertSetEntry` / `removeSetEntry` /
`replaceExerciseInSession` / `updateSessionNote` / `finishSession` 七个方法全部走它。
**没有批量、没有延迟合并**：宁可多写几次盘，也不能出现「App 被系统杀掉后丢最后几组」。

`insertSetEntry` 把新组插在该动作**最后一组之后**而不是数组末尾，
否则 `entriesByExercise` 分组时会插入到别的动作后面。`removeSetEntry` 在同一动作只剩一组时拒绝，
避免动作卡消失（也避免误删最后一个入口）。

### 性能：每秒的时钟绝不能放在 ViewModel 里

一个 300 组的训练里，如果秒数放在 `@Published var tick` 上，**每一秒都会让整屏动作卡重建一次**，
滚动时肉眼可见地掉帧。所以：

- 秒表进 `SessionHeaderClock`，它自己持有 `Timer`，只有这一小块 `Text` 重绘；
- ViewModel **完全没有** `tick` 属性，`handleTick()` 在没有休息倒计时时直接返回：
  ```swift
  private func handleTick() {
      guard restTimer?.isPresented == true else { return }
      advanceRestTimer()
  }
  ```
- 时长恒按 `now − startedAt` 计算而非累加，所以最小化、切后台、甚至被终止后重开都不会少算。

同理，`load()` 做成了有守卫的入口：

```swift
func load() {
    guard case .loaded = state else { return loadFull() }
    refreshSession()      // 只是同步一次，不闪骨架屏、不丢滚动位置
    startTicking()
}
```

### 替换动作后为什么会出现两张卡

替换的语义是「**后续组换成新动作，已完成的组保留**」。写库时只改未完成条目：

```swift
guard entry.exerciseID == fromExerciseID else { continue }
guard !entry.isCompleted else { continue }        // 已完成的组原地不动
session.entries[index].exerciseID = toExerciseID
```

于是按 `exerciseID` 分组后**同一个位置会出现两张卡**：老的（已完成 N 组）+ 新的（剩余组）。
这是刻意保留的诚实模型 —— 已完成的重量确实属于原来那个动作，
如果把它改写成新动作，会污染该动作的力量进步曲线和历史记录。

替换是在动作选择器里写库的，ViewModel 看不到操作本身，
所以用 `willReplaceExercise()` 打标记 + `refreshSession()` 对比前后动作集合补一句提示：
「已替换为「X」，已完成的组记录保留」。

`refreshSession()` **故意不按新组数重新展开草稿**：已经开工的训练，组数由用户用「新增一组」自己加，
不会被计划改动偷偷改写已经完成或正在进行的组。

### 休息倒计时

- 完成一组自动开始，时长取该动作的 `PlanExercise.restSeconds`（默认 90）；
- 手动「休息计时」按钮走同一条路径；
- `adjustRest(by:)` 把剩余夹在 `5 … max(total, 120) * 2`，加时间时同步抬高 `totalSeconds`，进度环不会出负进度；
- 归零后播 `AudioServicesPlaySystemSound(1057)`（系统音，不引入任何第三方音频文件）+ `Haptics.success()`，
  面板停留 1.2 秒展示 `00:00` 再自动收起；
- 撤销完成会把属于这组的休息一起停掉，避免继续空转。

### 小屏与大屏

- 组表三列用固定宽度令牌（`setIndexColumn` 40 / `setValueField` 62 / `setCheckbox` 30），
  中间用 `Spacer(minLength: 0)` 吸收剩余空间，因此 iPhone SE 到 iPad 都不会挤变形；
- 所有数值文本带 `minimumScaleFactor`，超大动态字体下缩排而不截断；
- 抽屉高度写死的是**内容高度**而非屏高，小屏上由 `BottomDrawer` 自身滚动兜底。

### 无障碍

- 概览区整体一个 `accessibilityLabel`：`accessibilityOverview`
  →「已完成 3 个动作，8 组，总训练容量 1020 公斤」，有氧换成时长 / 距离 / 消耗；
- 组行 `entry.accessibilityText`：「第 1 组，80 kg，8 次，已完成」；
- 重量 / 次数控件带 `accessibilityHint("双击编辑…")`，编辑态 `TextField` 有独立 label 与 value；
- 复选框用 `.isSelected` 特征而非纯颜色表达状态；
- 装饰性的热身强调条、分割线、进度环全部 `accessibilityHidden(true)`。

### 依然保留 `.navigationBarHidden(true)`

`preflight.py` 会为它报 4 条 deprecated 警告，这几条是**故意保留**的：
替代写法 `.toolbar(.hidden, for: .navigationBar)` 是 **iOS 16.4+**，
在目标设备 iOS 16.3.1 上不生效。预检的警告文案已改写说明这一点。

---

## 五之六、页面 06 组间休息倒计时

底部上滑面板，24pt 顶部圆角、深灰底、35% 黑色遮罩，开合沿用 `DS.Motion.drawer`（260ms ease-out）。
**没有复用 `BottomDrawer`**：通用抽屉的「把手 + 标题行」承载不了关闭按钮与超大倒计时这套排版，
硬套会把一个已被多个页面依赖的组件改脏。面板复用它的视觉常量，但不复用结构。

### 布局对照

| 规格 | 实现 |
| --- | --- |
| 面板从底部上滑 | `WorkoutSessionView.restDrawer` 内 `.transition(.move(edge: .bottom))` |
| 深灰背景 | `UnevenRoundedRectangle` 填充 `DS.Palette.surfaceElevated` |
| 24pt 顶部圆角 | `DS.Size.restPanelRadius = 24` |
| 黑色半透明遮罩 | `DS.Scrim.color`（35% 黑） |
| 260ms ease-out | `DS.Motion.drawer` |
| 顶部：动作名 + 「组间休息」 | `RestCountdownPanel.header` |
| 右侧关闭按钮 | `closeButton`，44pt 触控区 |
| 关闭只收起、不停止倒计时 | `dismissRestPanel()` 仅置 `isPresented = false` |
| 再次进入可继续显示剩余时间 | `restoreRestTimerIfNeeded()` 在 `load()` / `loadFull()` 里调用 |
| 超大等宽数字 `01:30` | `DS.Size.restCountdownFont = 64` + `.monospaced` + `FormatterKit.stopwatch(seconds:)` |
| 数字每秒刷新 | 面板自带 `Timer.publish(every: 1)`，经 `refreshRestClock()` 回灌求值时刻 |
| 最后 10 秒荧光绿 | `isFinalCountdown` → `DS.Palette.accent` |
| 最后 3 秒轻微缩放 | `isFinalPulse` → `scaleEffect(1.06)` + `repeatForever(autoreverses: true)` |
| 圆环从完整减至 0 | `Circle().trim(from: 0, to: 1 - timer.progress)` |
| 圆环底色低对比灰 | `Color.white.opacity(0.10)`，线宽 `restRingStroke = 8` |
| 进度色荧光绿 | `DS.Palette.accent`，`lineCap: .round` |
| 暂停停止动画并显示「已暂停」 | `.animation(timer.isPaused ? nil : .linear…)` + 环心 `Text("已暂停")` |
| 第一行 −15 / +15 / +30 秒 | `adjustRow`，三个等宽按钮 |
| 按下 0.97 缩放反馈 | 全部走 `PressableButtonStyle()` |
| 第二行「暂停」/「继续」 | `controlRow` 主控按钮，文案随 `isPaused` 切换 |
| 旁边「跳过休息」 | 文字按钮，`skipRest()` |
| 跳过后停表、关面板、焦点回下一组 | `skipRest(reason: .skipped)` 清内存 + 清盘 + 撤通知 |
| 「设为默认休息时间」入口 | `defaultRestEntry`，无计划条目时置灰 |
| 30/45/60/90/120/180 或自定义 | `RestDefaultPickerSheet.presets` + `customText` 输入 |
| 只改计划动作的 `restSeconds` | `setDefaultRest(seconds:)` → `repository.updatePlanExercise(_:inPlan:)` |
| 不回写动作库本体 | 只调 `updatePlanExercise`，不碰 `save(exercise:)` |
| 结束播放包内短提示音 | `AudioServicesPlaySystemSound(1057)`（系统音，随 iOS 自带） |
| 轻量触感 | `Haptics.success()` |
| 显示「休息结束，开始下一组」 | `RestFinishedBanner` 压在页面顶部 |
| 后台只申请本地通知权限后才发通知 | `RestNotification.enable(_:)`，**默认关闭，由用户主动开** |
| 拒绝权限不影响倒计时 | 所有通知调用都是「尽力而为」，倒计时不读任何回调结果 |
| 保存四个字段 | `RestTimerRecord` 的 `startedAt` / `durationSeconds` / `isPaused` / `remainingSeconds` |
| 后台 / 最小化 / 重启后重算剩余 | `remainingSeconds(at:) = durationSeconds - (now - startedAt)` |
| 完成或跳过清除休息状态 | `clearRestTimer()` 删掉 `restTimer.json` |
| 无网络 / 推送 / 社交 / 云同步 | 只有 `UserNotifications`（本地），无任何网络 API |

### 计时为什么不用「每秒递减」

页面 05 原先的 `RestTimer` 是一个内存里的整数，每秒 `-1`。它有一个致命缺陷：
**没有 `startedAt`，所以无法恢复**。App 被切到后台、被系统回收、或用户主动杀掉之后，
那个整数就随进程消失了，剩余时间无从重建。

页面 06 改成「只存起点、剩余现算」：

```swift
// 运行中按墙钟推导，暂停时读冻结值
func remainingSeconds(at now: Date) -> Int {
    if isPaused { return max(0, remainingSeconds) }
    let elapsed = Int(now.timeIntervalSince(startedAt))
    return max(0, durationSeconds - max(0, elapsed))
}
```

由此，三种场景自动都成立，不需要任何补算逻辑：

| 场景 | 行为 |
| --- | --- |
| 切后台 30 秒再回来 | 下一次求值就是对的，`handleTick()` 用的是墙上时间 |
| 在后台期间走完 | `resumeFromMinimize()` 里先手动 `handleTick()` 一次，补上提示音与横幅 |
| App 被终止后重启 | `restoreRestTimerIfNeeded()` 从 `restTimer.json` 读回，按 `startedAt` 现算 |

因此 `handleTick()` 不再做减法，只更新 `now` 一个字段；这也是它不会触发已完成组重绘的原因。

### 加减时间必须同时重设 `durationSeconds`

这是实现时踩到的一个真 bug，值得单独记录。

最初的写法是「剩余值设为目标值，把 `startedAt` 挪到现在」：

```swift
// 错误写法
copy.remainingSeconds = next
copy.startedAt = now
```

因为剩余值是**推导**出来的（`durationSeconds - elapsed`），只挪 `startedAt` 而不动总时长，
下一次求值立刻变回 `durationSeconds`——用户刚点完 `+30 秒`，数字又跳回原值。
正确做法是把 `durationSeconds` 一起设成目标剩余，语义等价于「从现在起重新倒数 N 秒」：

```swift
copy.durationSeconds = next
copy.remainingSeconds = next
copy.startedAt = now
```

### 加时间的上限必须锚定原始时长

`adjusting(by:)` 的夹取上限一开始写成 `max(durationSeconds, 120) * 2`。
由于 `durationSeconds` 会被自己抬高，连续点 `+30 秒` 就变成「自己抬高自己的上限」：
90 → 120 → … → 690，一路没有天花板。

修法是单独存一个 `originalDurationSeconds`，只在构造时赋值，`resumed` / `adjusting` 都不改它：

```swift
let ceiling = max(originalDurationSeconds, 120) * 2   // 90 秒的休息 → 上限 240
let next = min(max(5, current + delta), ceiling)
```

`originalDurationSeconds` 用 `decodeIfPresent(...) ?? durationSeconds` 容错，
旧文件读出来语义上等价于「没加过时间」。

### 关闭与跳过是两回事

| 操作 | 面板 | 倒计时 | 持久化 | 通知 |
| --- | --- | --- | --- | --- |
| 关闭（右上角 ×） | 收起 | **继续走** | 保留 | 保留 |
| 跳过休息 | 收起 | 停止 | 清除 | 撤销 |
| 走完归零 | 停留 1.4s 后自动收起 | 已结束 | 清除 | 系统已发出 |

规格里「关闭仅收起面板，不停止倒计时」这一条很容易被写成「关闭 = 取消」，
所以 `dismissRestPanel()` 里刻意**不**碰 `restTimer = nil`，也**不**清盘。

### 遮罩不响应点击关闭

面板的遮罩上挂了空 `onTapGesture {}`。原因是训练中手指常在屏幕上，
点遮罩就收起面板会频繁误触，而收起后面板要以 260ms 动画重开。
规格只要求「右侧关闭按钮」，所以关闭入口就只保留那一个。

### 本地通知是纯可选项

- **默认关闭**，开关在「我的 → 偏好 → 休息结束提醒」，由用户主动打开；
- 权限申请只在用户拨动开关时发生，不在 App 启动或第一次训练时弹窗；
- 权限被拒绝时开关自动退回关闭，并提示去系统设置打开，**倒计时完全不受影响**；
- 暂停 / 继续 / 加减时间都会 `rescheduleRestNotification()`，
  先把旧的通知撤掉再按新的剩余时间重排，避免在错误的时间提醒；
- 跳过、归零、结束训练都会 `cancelPending()`。

### 小屏与大屏

- 倒计时用 `minimumScaleFactor(0.5)`，`restRing = 176pt` 在 iPhone SE 上仍有余量；
- 三个调整按钮等宽平分，`1:2:3` 的宽度差在窄屏上依然可辨；
- 数值选择器用 3 列 `LazyVGrid`，六档位正好两行；
- 面板总高不依赖固定值，靠内容自然撑开，避免小屏被裁。

### 无障碍

- 面板整体是 `accessibilityElement(children: .contain)`，标签「组间休息」，值形如
  「组间休息，1 分 30 秒」；暂停时读作「已暂停，剩余 1 分 30 秒」；
- 剩余时间用 `spokenTime` 转成「M 分 S 秒」，不让 VoiceOver 去读 `01:30`；
- 关闭按钮的 hint 明确说明「倒计时会继续」；
- 跳过按钮的 hint 说明「停止计时并关闭面板，回到下一组」；
- 自由训练时「设为默认休息时间」的 hint 说明原因，而不是静默失效。

### 设计令牌的补充

`DS.Size` 新增 `restPanelRadius(24)`、`restRing(176)`、`restRingStroke(8)`、
`restCountdownFont(64)`、`restAdjustButtonHeight(48)`；
`DS.Motion` 新增 `restPulse`（0.35s ease-in-out）与 `restPulseRepeat`（0.45s 往复）。

## 六、页面 07 完成训练与训练总结

触发：训练执行页底部「完成训练」。整条链路分两步 —— 先确认，再总结。

### 6.1 第一步：底部确认抽屉

`BottomDrawer` 高 460，标题「完成本次训练？」，副标题「确认后写入本地记录」。

内容区是一个 `ScrollView`，动作数多或有氧指标多时可滚动：

| 区域 | 力量训练 | 有氧训练 |
|---|---|---|
| 名称块 | 训练名 + 「力量训练」 | 训练名 + 「有氧训练」 |
| 指标 1 | 总时长 · 完成动作 | 总时长 · 距离 |
| 指标 2 | 完成组数 · 训练总容量 | 消耗估算 · 完成动作 |
| 备注 | 多行 `TextEditor`，`minHeight: 74` | 同左 |

三个操作固定在底部（`.safeAreaInset(edge: .bottom)`，不随内容滚动）：

```
[  完成训练  ]          ← 荧光绿主按钮
[ 取消 ] [ 继续训练 ]    ← 两个描边次级按钮
```

**只有「完成训练」会写盘。** 取消与继续训练共用同一条退出路径：

```swift
/// 取消与继续训练共用同一条退出路径：只收起抽屉，不改动训练草稿。
private func dismissFinishDrawer() {
    viewModel.isFinishDrawerPresented = false
}
```

抽屉里那段备注文本绑定的是 `viewModel.finishNote`，这是 ViewModel 上的
暂存字段、不是 `WorkoutSession.note`。所以中途取消，草稿里的备注原样不动；
只有点「完成训练」时才随 `finishSession(sessionID:endedAt:note:)` 一起落盘。

### 6.2 幂等在仓储层，不在 View

```swift
try mutateSession(sessionID) { session in
    if session.endedAt == nil {
        // 结束时间不能早于开始时间，避免时钟回拨导致负时长
        session.endedAt = max(endedAt, session.startedAt)
    }
    ...
}
```

`endedAt == nil` 这个守卫让重复调用天然幂等：第二次进来时 `endedAt` 已非空，
时间戳不被覆盖，也就不会多出一条历史记录。放在仓储层而不是按钮的 `isEnabled` 上，
是因为连点、手势穿透、VoiceOver 双击这三种路径都可能绕过 UI 层的防抖。

时钟回拨用 `max(endedAt, startedAt)` 兜住，负时长不会出现。

### 6.3 第二步：全屏训练总结页

只读页面，不持有 ViewModel，构造时读一次 `fetchSession(id:)`。

**顶部**：`SummaryCheckGlyph` + 「训练完成」+ 大标题训练名 + `日期 · 总时长`。

图标是纯代码绘制的 `Shape`，没有任何图片或第三方插画：

```swift
private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        // 按 0…1 归一化坐标，随 frame 等比缩放
        path.move(to: CGPoint(x: rect.minX + w * 0.04, y: rect.minY + h * 0.54))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.36, y: rect.minY + h * 0.86))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.14))
    }
}
```

外圈 `Circle().stroke`，内部这个勾，共用同一线宽，视觉上像一支笔一次画完。

**统计卡片**（横向三张）：

| 训练类型 | 卡 1 | 卡 2 | 卡 3 |
|---|---|---|---|
| 力量 | 训练时长 | 总组数 | 总容量 |
| 有氧 | 训练时长 | 距离 | 平均配速 + 消耗估算 |

为什么卡数不是固定的：力量训练的核心量是「容量」，有氧训练没有容量概念，
硬塞一个 0 会让用户以为数据丢了。所以按 `session.kind` 分两套。

### 6.4 递增动画：500ms，且能被减少动态效果绕过

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

guard !reduceMotion else {
    displayed = target   // 直接显示最终值，不产生任何中间帧
    return
}

displayed = 0
let steps = 24
let stepDuration = 0.5 / Double(steps)
for step in 1...steps {
    let eased = 1 - pow(1 - progress, 3)   // easeOut：前段快，尾部收敛
    displayed = target * eased
    try? await Task.sleep(nanoseconds: UInt64(stepDuration * 1_000_000_000))
    if Task.isCancelled { return }
}
```

三个实现选择：

1. **用 `.task(id:)` 自己驱动，不用 `.animation`。** 在 `ScrollView` 里隐式动画
   对文本内容插值不可靠 —— 这一点在页面 05 已经踩过，当时的 `FadingNumberText`
   就是同一个原因。`.task(id: value)` 在值变化时自动取消上一次、重启新一次，
   连点或数据刷新不会出现两段动画叠加。
2. **`Task.isCancelled` 必查。** 用户中途返回上一页时，任务被取消但循环还在跑，
   不检查会继续往一个已经消失的视图写状态。
3. **平均配速不做递增。** 配速是比值，从 0 递增会依次显示 `0'00"`、`12'30"`……
   这类无意义读数。`CountUpNumberText.literalText` 非空时直接显示文本、跳过动画。

### 6.5 动作完成情况：默认收起

每个动作一张卡，标题行显示 `动作名` + `N/M 组` + `容量 XX kg`，
点击展开逐组记录。

**默认全部收起**，不是展开。一次上肢训练常有 6–8 个动作、每个 4 组，
全展开就是三十多行，用户要滑很久才能看到笔记。收起后一屏能看完全部动作。

展开状态是 `Set< String >`（动作 id 集合）而不是 `[Bool]` 数组：
数组下标和 `ForEach` 的 id 会在数据重排后错位，集合按 id 记则不会。

**单动作容量**取的是「已完成、且非热身组」的求和 —— 这和 `SetEntry.volume`
的口径一致（`isWarmup ? 0 : weight * reps`）。热身组不计容量是健身领域的惯例。

「实际重量 × 次数」取的是**容量最大**的那一组，不是重量最大的那一组。
`80 kg × 8 = 640` 优于 `85 kg × 6 = 510`，这才是这次训练的代表组。

### 6.6 训练笔记：空态与就地编辑

有备注 → 显示文本 + `SectionHeader` 右侧「编辑」。
无备注 → 「未记录训练笔记」+「添加笔记」胶囊按钮。

两者都不跳页，原地把卡片换成 `TextEditor` + 取消/保存。
保存走 `repository.updateSessionNote(sessionID:note:)`，
再同步刷新本地 `session?.note` —— 为了一个字段重新走一次完整 `fetchSession`
不划算，且会让整页重新渲染一次。

焦点延时 0.15s 再给，避免键盘弹出动画和卡片切换动画互相打断：

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
    isFocused = true
}
```

### 6.7 底部两个按钮的跳转含义

| 按钮 | 行为 |
|---|---|
| 主：「返回训练首页」 | 清空训练 Tab 的 `NavigationPath`，并刷新首页「最近训练」 |
| 次：「查看历史记录」 | 切到历史 Tab，并推入本次训练的详情页 |

「刷新最近训练」这件事不能只靠 `onAppear`：训练 Tab 一直在栈底，
从总结页返回时它**不会**重新走 `onAppear`。所以用 `reloadToken` 驱动
一个 `.id(homeReloadID)` 强制重建首页视图：

```swift
.onChange(of: reloadToken) { _ in
    // 训练结束后首页已在栈底、不会重新走 onAppear，
    // 用 id 强制重建最内层视图
    homeReloadID = UUID()
}
```

「查看历史记录」要走三步：清空训练栈 → `selection = .history` → 把 session id
交给 `HistoryTab`。第三步必须**等记录真的读得到**再推详情：

```swift
let hasRecord = (try? repository.fetchSession(id: target)) != nil
guard hasRecord else {
    // 记录确实不存在：留在列表页，仅消费掉定位请求
    onConsumeHighlight()
    return
}
pushDetail(target)
```

历史栏可能在本次训练写入**之前**就已挂载完毕。此时过早入栈，
总结页会读到空记录、渲染空状态。先探测再推，就绕开了这个时序问题。

历史列表里那一条同时加荧光绿描边高亮，供用户从详情返回后确认是哪一次。

### 6.8 无障碍

| 元素 | 处理 |
|---|---|
| 「训练完成」 | `.accessibilityAddTraits(.isHeader)`，VoiceOver 可按标题跳转 |
| 勾选图形 | `.accessibilityHidden(true)`，纯装饰 |
| 三张统计卡 | 外层 `.accessibilityElement(children: .ignore)`，合并成一句完整语句：「训练时长 45 分钟，完成 18 组，总容量 4200 千克」 |
| 抽屉指标区 | 同样合并，且把训练名读在最前 |
| 动作行 | 标签为「动作名，完成 3 组，共 4 组，该动作容量 640 千克」，值为「已展开」/「已收起」，提示「轻点两下展开每组记录」 |
| 每组的勾 | 合并进行标签，不单独朗读 |

统计卡如果逐张朗读，用户会听到「训练时长」「45」「秒」三段孤立念白；
合并成一句才是有意义的信息。

### 6.9 新增的设计令牌与格式化

```swift
// DS.Motion
static let countUp = Animation.easeOut(duration: 0.5)
static let disclosure = Animation.easeInOut(duration: 0.22)

// DS.Size
static let summaryCheckGlyph: CGFloat = 40      // 勾形边长
static let summaryCheckRing: CGFloat = 76       // 外圈直径
static let summaryCheckStroke: CGFloat = 7      // 线宽
static let summaryMetricFont: CGFloat = 24      // 卡片数字字号
static let summaryRowHeight: CGFloat = 44       // 动作行最小高度
```

```swift
// FormatterKit
static func plainNumber(_ value: Double) -> String   // 卡片用纯数字，不带单位
static func pace(seconds: Int, meters: Double) -> String   // 5'30"
```

`pace` 在距离不足 100 米、时长非正、或配速≥99 分钟时返回 `—`。
前两个是防除零，第三个是防格式溢出 —— 否则会显示成 `150'00"` 这种读不出来的东西。

---

## 六之二、页面 08 历史训练日历

对齐规格：底部 Tab「历史」的完整页面。日历、当日时间线、列表、统计入口四部分。

### 6.2.1 布局对照

| 规格要求 | 实现位置 |
|---|---|
| 大标题「历史」+ 右侧新增按钮 | `HistoryView.navigationBar` |
| 新增菜单四项 | `addMenuContent`（`BottomDrawer`） |
| 上个月 / 当前月份 / 下个月 | `MonthSwitcher` |
| 周一至周日月历，今天细描边，选中日荧光绿圆 | `MonthGridView` + `DayCell` |
| 标记点：力量绿 / 有氧蓝绿 / 休息日灰 | `DayMarkerDots.color(for:)` |
| 点击日期 → 当日时间线 | `DayTimelineSection` |
| 空态「当天没有训练记录」+「新增训练」 | `DayTimelineSection.emptyState` |
| 分段切换「日历 / 列表 / 统计」 | `HistoryView.segmentPicker` |
| 长按日期 3 项菜单 | `dayMenuContent` |
| 长按卡片 3 项菜单 | `HistorySessionCard.contextMenu` |
| 删除二次确认 | `.alert("删除这条训练记录？")` |

### 6.2.2 日历数学抽成纯值类型，是为了能被验证

`Features/History/HistoryCalendar.swift` 里没有任何 SwiftUI 类型。原因是这里最容易错、也最难在真机上肉眼看出错：月初偏移、跨年、闰年、月末对齐、本地时区切天。

抽成纯值类型后，整个文件可以逐行移植到 Python 跑断言表（`Tools/probe_page08_semantics.py`，91 项）。本页实际靠它抓到 2 个真 bug，详见 6.2.5。

### 6.2.3 网格固定 6 行 42 格，不按月份自适应

5 行还是 6 行取决于当月的月初偏移与天数。若自适应，翻月时日历高度会跳，而当日时间线紧跟在日历下方，高度一跳整页内容都会位移。固定 42 格让日历高度恒定，翻月时只有格内内容在变。

超出当月天数的尾部格子填 `nil` 留白，而不是补下个月的日期：补下月会让用户以为那些格子属于当前月，点进去才发现是别的月。

### 6.2.4 休息日为什么是独立模型

规格要求在日历上标出休息日，但数据层本来没有这个概念。两个选择：

| 方案 | 后果 |
|---|---|
| 给 `WorkoutSession.Kind` 加第三个分支 `.rest` | 协议零改动，但休息日会混进 `fetchRecentSessions`，于是「最近训练」「总容量」「总里程」「已完成训练数」每个聚合点都要额外过滤，漏一处就是错的 |
| 新增独立 `RestDay` 模型 + `restDays.json` | 协议 44 → 47 个方法，两处实现同步；但休息日与训练记录的聚合彻底隔离，语义干净 |

选了后者。`save(restDay:)` 内部会先按自然日剔除同一天的旧记录，所以同一天重复标记只会更新，不会堆出多条灰点。

### 6.2.5 探针抓到的两个真 bug

**bug 1：跨月选择把月份降级成了「1 号」。**

`select(_:)` 原本在选中日期落在别的月份时，用 `HistoryCalendar.month(byAdding: 0, to: date)` 把 `visibleMonth` 设成该月 1 号。而 `visibleMonth` 在初始化、切月等其他路径上存的一直是「某天的 00:00」。于是这个字段在两种形态之间漂移，而 `MonthGridView` 的 `.animation(value: month)` 正是比较这个 `Date`。

修法是统一用 `startOfDay(date)`，并且把月份修正挪到 `selectedDate = date` **之前**——反过来的话，会先按旧月份渲染一帧错的日历。

**bug 2：补记历史训练时，时长被算成 9 天。**

从月历点 9 月 10 日新建训练，原本把 `startedAt` 设成那天的 00:00。用户 9 月 19 日才点完成，而 `durationSeconds = endedAt - startedAt`，锚点落在零点等于把整段等待都算进修时——卡片上显示「216 小时」。

修法是 `HistoryViewModel.timeOfDay(from:onDayOf:)`：保留点下按钮那一刻的时 / 分 / 秒，只把年月日换成选中那天。这样记录归属正确的那一天，时长又不会失真。另外拼接结果若晚于此刻（选中未来日期时会发生）会退回该日零点，保证 `startedAt <= now` 恒成立。

### 6.2.6 「复制为新训练」为什么要清掉完成时间

复制一条已结束的记录时，原样复制会让历史里凭空多出一条「已完成」的训练，而用户本意是拿它当模板再练一次。所以副本一定是未结束状态：`endedAt` 置空、`startedAt` 设为此刻、每组记录的 `completedAt` 清空（重量与次数保留，作为待完成的目标组）。

### 6.2.7 有氧标记色是本项目第二个语义色

规格要求同一天的力量与有氧用不同颜色并列显示，单靠荧光绿的深浅在炭黑底上分不出来。所以新增了 `DS.Palette.cardio = #3ED8C6`。

它的作用域被严格限制为「区分训练类型」（日历标记点、类型标签）。主按钮、选中态等一切强调语境仍然只用荧光绿 `#C6FF3E`。

### 6.2.8 统计分段只做入口

规格写的是「统计进入下一页的训练数据汇总」，即汇总页本身属于下一页。所以这里只落一个入口卡片，点击 push 到统计页，不留空白页。

**页面 10 交付后更新**：这里当时 push 的是占位页 `HistoryStatsPlaceholderView`；页面 10 落地后占位页已删除，改为 push 真正的 `WorkoutStatisticsView`。历史页只负责摆入口这条分层没有变，因此页面 08 的这一节除了目标页名之外无需改动。入口卡片文案也随页面 10 从「查看总容量趋势、训练频率与各肌群分布。」改成「按时间范围查看训练频率、容量趋势、常练动作与部位分布。」——旧文案会让用户以为没有时间范围切换。

### 6.2.9 无障碍

- 日历每个日期格的标签是「9月19日 星期六，2 次训练，已选中」这种拼装句，含日期 + 训练数 + 选中态三项，符合规格要求
- 选中态同时挂 `.isSelected` 特征，VoiceOver 会读成「已选中」
- 图例合并为一个元素朗读，说明三种颜色的含义
- 长按有 `accessibilityHint` 提示可用操作
- 全部文案使用语义化字体，随动态字体缩放

### 6.2.10 新增的设计令牌

| 令牌 | 值 | 用途 |
|---|---|---|
| `Palette.cardio` | `#3ED8C6` | 有氧标识色 |
| `Palette.restMarker` | `white 0.42` | 休息日标记灰 |
| `Size.calendarCellHeight` | 46 | 日期格最小高度 |
| `Size.calendarSelectionCircle` | 36 | 选中荧光绿圆直径 |
| `Size.calendarTodayRing` | 42 | 今天描边圆直径 |
| `Size.calendarTodayStroke` | 1.5 | 今天描边线宽 |
| `Size.calendarMarkerDot` | 5 | 标记点直径 |
| `Size.calendarMarkerMaxDots` | 3 | 单格最多显示几个点 |
| `Size.calendarMarkerRowHeight` | 8 | 标记行固定高度 |

今天描边圆（42）与选中圆（36）故意不同直径，留出约 3pt 可见描边宽度，这样「今天」和「已选中」可以同时成立。

---

## 六之三、页面 09 历史训练详情

对齐规格：在历史日历或训练列表中点击某一条已完成训练进入。查看 + 有限编辑，**不包含分享、社交、公开链接、点赞、评论**。

### 6.3.1 布局对照

| 规格要求 | 实现位置 |
|---|---|
| 顶部：左返回 / 中「训练详情」/ 右三点 | `HistoryDetailTopBar`（`safeAreaInset(edge: .top)`） |
| 摘要卡：名称、完成日期与开始时间、类型、总时长 | `HistoryDetailSummaryCard` 上半部 |
| 力量统计格：总组数 / 总容量；有氧：距离 / 平均配速 / 时长 | `HistorySessionSummary.build(session:dateText:startTimeText:)` |
| 「动作记录」列表，按完成时动作顺序 | `HistoryRecordOrder.detailDefault` → `HistorySessionDetailIndex.records(for:library:)` |
| 动作卡：名称 / 主肌群 / 完成组数 / 该动作总容量 | `HistoryExerciseRecordCard` 头部 |
| 点击展开：重量、次数、热身标记、完成时间、单组备注 | `HistorySetRow` + `HistorySetDisplay` |
| 已完成为只读 | `HistoryEditPolicy.allowedFields(session:)` |
| 更多菜单四项 | `moreMenuContent`（`BottomDrawer`，高度 372） |
| 编辑标题 / 备注用底部输入抽屉 | `HistoryTextInputDrawer`（250 / 336） |
| 复制为新训练草稿 → 跳执行页 | `HistorySessionDuplicator.makeDraft(from:startedAt:nameSuffix:)` |
| 删除二次确认，明示「只删除本机这条记录」 | `HistoryDeleteConfirmContent`（364） |
| 动作已隐藏 / 已删除时降级不崩 | `HistoryExerciseAvailability` |
| 底部训练笔记，空态「未记录训练笔记」 | `HistoryNoteCard` |
| 操作完成短暂 toast | `HistoryToast` |

### 6.3.2 只读契约写成一个可探测的类型，而不是「我们没写编辑按钮」

规格的硬约束是「不允许在历史详情直接修改完成组数据」。最容易滑过去的实现方式是：界面里确实没放编辑入口，于是看起来合规。但这条约束会随时间腐化——下一轮加个「修正一下重量」的按钮，就破了。

所以把它提升成一个显式函数：

```swift
enum HistoryEditPolicy {
    enum Field: String { case title, note, setData }
    static func allowedFields(session: WorkoutSession) -> Set<Field>
    static func allowsSetDataEditing(session: WorkoutSession) -> Bool
    static let redoHint = "要重新练一次，请用「复制为新训练草稿」。"
}
```

已完成训练的白名单是 `[.title, .note]`，**`setData` 永远不在里面**。探针 §08 除了断言这个结果，还额外加了一条回归断言：白名单里绝不允许出现 `setData`。这样将来谁想开这个口子，门禁会先红。

同一个 `redoHint` 也被渲染在详情页的只读提示里，保证「不允许改」和「那我要重练怎么办」这两个信息始终成对出现，用户不会撞到一堵没有出口的墙。

### 6.3.3 动作名的三级兜底，以及它为什么不可能为空

历史记录里存的是动作 id，动作库却可能变。显示名按这个顺序取：

| 顺序 | 来源 | 命中场景 |
|---|---|---|
| 1 | `item.displayName` | 动作库里的中文别名（正常情况） |
| 2 | `item.name` | 没设中文别名 |
| 3 | 记录里存的 id 本身 | 动作库查不到这条 id |
| 4 | `"未知动作"` | id 是空串这种退化输入 |

前三级都在 `HistorySessionDetailIndex.displayName(for:item:)`。**第 3 级是关键**：即使动作被删，也仍然把 id 显示出来，而不是显示成空白——空白会让整张卡看起来像渲染失败。探针 §03 断言了「任何输入组合都不会产出空字符串」。

### 6.3.4 1970 哨兵值：为什么过滤阈值不能直接用 1970

`SetEntry.completedAt` 是双态的：`nil` 表示「待完成的目标组」，非 `nil` 表示「已完成」。老版本解码器缺这个字段时会给默认值 `Date(timeIntervalSince1970: 0)`，也就是 1970 年——一条「看起来已经完成了」的组。

于是页面上会出现「完成于 08:00」旁边跟着「完成于 1970-01-01」这种荒谬文案。本页的办法是设一个**参考系纪元**做地板：

```swift
static let referenceFloor = Date(timeIntervalSinceReferenceDate: 0)  // 2001-01-01
```

用 Cocoa 纪元（2001）而不是 Unix 纪元（1970）当阈值，是为了顺带滤掉另一种坏数据：**设备时钟被改到 2000 年**时写进去的时间戳。它比 1970 大得多，但显然也不是真实的训练时间。任何 `completedAt <= referenceFloor` 都当作「未完成」处理，不显示完成时间。

探针 §01 覆盖了 5 种输入：1970 精确值、2000 年坏时钟、恰好等于阈值、阈值 +1 秒（正向对照，必须显示）、以及 `nil`。

### 6.3.5 动作库必须用 `includeHidden: true` 取

`FitnessRepository.fetchExercises(includeHidden:)` 默认是 `false`。历史详情如果按默认取，被用户隐藏的动作会查不到，于是被判成 `.missing`，页面显示「该动作已不可用」——但事实上它只是被隐藏了，数据一个字都没丢。

所以 `apply(_:)` 里显式传 `includeHidden: true`，并在代码里留了注释说明这个区别：

| 状态 | 含义 | 提示文案 |
|---|---|---|
| `.available` | 动作库里有，可点进详情 | 无 |
| `.hidden` | 被用户隐藏（可逆的用户选择） | 「该动作已隐藏，仍可查看这一天的完成记录。」 |
| `.missing` | 库里真的没有这条 id | 「该动作已不可用，仅保留历史记录中的名称与数据。」 |

`canShowMedia` 对 `.hidden` 仍为 `true`（媒体文件还在 Bundle 里），只有 `.missing` 才关闭。

### 6.3.6 摘要卡故意不做递增动画

页面 07 的训练总结有 500ms 递增动画，本页**没有**，而且这是刻意的，代码里也写了注释说明原因：

- 页面 07 是「你刚刚练完了」，递增是在为成绩做庆祝，动画本身是反馈的一部分
- 页面 09 是「翻看一条旧记录」，数字是既成事实，再递增一边等于把旧数据表演成新成绩

`contentTransition` 是 iOS 17+，本项目本来也要手搓递增，所以「不做」比「做」还省事——但省事不是理由，判断依据是场景语义。

### 6.3.7 复制为新训练草稿：复制什么、不复制什么

`HistorySessionDuplicator.makeDraft(from:startedAt:nameSuffix:)` 的契约：

| 项 | 处理 | 原因 |
|---|---|---|
| 动作顺序 | 复制 | 规格明确要求 |
| 目标组数 / 次数 / 重量 | 复制（整条 `SetEntry` 拷贝） | 规格明确要求「最近实际重量/次数」当模板 |
| `completedAt` | **清空为 `nil`** | 不复制完成状态 |
| `id`（每条组） | **重新生成 `UUID()`** | 否则副本与原记录的组 id 撞车 |
| `endedAt` | `nil` | 副本是未完成 |
| `startedAt` | 传入的此刻 | 不能沿用旧时间 |
| `note` | `nil` | 不复制旧备注（规格明确） |
| `distanceMeters` / `consumedKilocalories` | `nil` | 有氧的量是旧成绩，不能预填成新目标 |
| `planID` | `nil` | 副本是「自由训练」，不挂回原计划，避免污染计划的完成统计 |
| 训练名 | 追加后缀，且不叠加 | `draftName(from:suffix:)` 里查 `hasSuffix(marker)`，已带「副本」就不再追加 |

实现用的是整条 `var copy = entry` 再改两个字段，不是逐字段重写。这样将来 `SetEntry` 加字段，副本会自动跟上。探针 §09 用 13 条断言覆盖上表，并加了两条回归守卫 `not_has("copy.weight =")` / `not_has("copy.reps =")`——防止有人「顺手优化」成逐字段赋值时漏掉某个字段。

### 6.3.8 删除后日历标记怎么刷新：`historyReloadToken`

`NavigationStack` 弹栈**不会触发**下层页面的 `onAppear`。删除一条记录后 pop 回历史页，`HistoryView` 不会重新加载，那条记录的绿色标记点会继续留在日历上。

修法是在 `RootView.HistoryTab` 里放一个 `@State private var historyReloadToken = UUID()`，把 `HistoryView` 挂上 `.id(historyReloadToken)`，并在三处 bump 它：详情页 `onBack`、`onOpenDraft` 回跳、以及 `sessionDraft` 的 `onFinished` / `onMinimize`。`HistoryView` 同时新增了 `onDataChanged` 回调（它的语义是「通知外层重建本页」，不是「重新加载数据」本身）。

顺带一提，返回用的是 `popOne()` 而不是 `path = NavigationPath()`：整体清空会把用户已经滚到的位置和列表状态一起丢掉，而详情页是从列表推上来的，只需要退一层。

### 6.3.9 训练首页的「点历史卡进详情」也接上了

`TrainingTab` 原来有一个 `onOpenSession` 空桩。本页补上了 `TrainingRoute.historyDetail(UUID)` 与对应 `navigationDestination` 分支，复用同一个 `HistorySessionDetailView`。

没有复用 `HistoryRoute.sessionDetail` 是因为两个 Tab 各自持有独立的 `NavigationPath`，跨 Tab 复用同一个枚举会把两套栈耦在一起；代价只是多了一个 case。

这里踩过一次坑：第一版在 `.historyDetail` 分支里写了 `sessionSummaryReloadToken = UUID()`，但那个状态声明在**父级** `RootView` 上，不在 `TrainingTab` 里——直接是编译错误。改成用 `TrainingTab` 自己的 `homeReloadID`，语义也更对：它重建的是内层首页的 ViewModel，不该动父级的 Tab 选中状态。

### 6.3.10 无障碍

- 摘要卡整体合并为一个元素，`accessibilityLabel` 由 `HistorySessionSummary.accessibilityLabel` 拼装，一次读完名称 / 日期 / 时长 / 各项统计
- 动作卡展开态由 `HistoryExerciseRecord.accessibilityLabel` 提供，含可用性说明
- 不可用动作额外挂 `exclamationmark.triangle`，`accessibilityText` 为「该动作已隐藏」/「该动作已不可用」
- 组行标签含「第 N 组」「热身」标记、重量次数、达成情况、完成时间
- 顶部栏两个按钮分别标注「返回」「更多操作」，并给「更多操作」加了 `accessibilityHint`
- 笔记区 `.textSelection(.enabled)`，方便用户复制自己的旧笔记
- 全部文案使用语义化字体，随动态字体缩放

### 6.3.11 新增的设计令牌

| 令牌 | 值 | 用途 |
|---|---|---|
| `Size.detailMetricFont` | 21 | 摘要卡统计格数值字号 |
| `Size.detailSetRowHeight` | 34 | 组行最小高度 |

---

## 六之四、页面 10 训练统计

入口：历史页的分段控件第三格「统计」。整页由 **5 个新文件**承载，全部数据来自本机历史记录，不含好友对比、排行榜、云同步或分享。

### 6.4.1 布局对照

| 区块 | 内容 |
|---|---|
| 导航栏 | 左返回 / 中「训练统计」/ 右时间范围按钮（显示当前范围简称） |
| 摘要区 | 四张紧凑统计卡：训练次数、总训练时长、总完成组数、总训练容量；含可计时，追加总距离 |
| 图卡 1 | 训练频率：柱状图，横轴日期、纵轴次数；力量与有氧分色；选中柱为荧光绿 |
| 图卡 2 | 训练容量趋势：平滑折线（≥8 点时叠加柱）；可按全部 / 肌群 / 单个动作筛选 |
| 图卡 3 | 常练动作：按完成组数降序前 5，显示名称 / 组数 / 累计容量，可点进动作趋势子页 |
| 图卡 4 | 训练部位分布：横向进度条，按主肌群列出肌群名 / 组数 / 百分比 / 代表色 |
| 页尾 | 数据管理入口卡片 |

### 6.4.2 时间范围：终点取「明天 00:00」，不是「今天 23:59:59」

六种范围（近 7 天 / 近 30 天 / 本月 / 近 3 个月 / 今年 / 自定义）统一归一成**半开区间** `[start, end)`。

两个边界各踩过一次：

- **起点**：近 7 天写成 `-7` 天会得到 8 个自然日，柱状图上凭空多一根柱子。正确是 `-6`。
- **终点**：用「今天 23:59:59」会把 `23:59:59.5` 这种带小数秒的记录漏在外面（训练记录的 `completedAt` 是 `Date`，带亚秒精度）。终点取**明天 00:00**，与 `Date` 的精度天然对齐。

`calendar.startOfDay` 全程替代「减 86400 秒」，避开夏令时的坑（中国不实行夏令时，但代码不该依赖这个前提）。

自定义范围有三条兜底：没给起点 → 退到近 30 天；终点早于起点 → 交换；终点正好落在某天 00:00 → 加一天。

### 6.4.3 「—」和「0」是两件事

`StatsMetric.value` 的类型是 `String?`，不是 `String`。这一条是规格里「无法计算的指标显示『—』，不显示误导性的 0」的直接落地：

| 场景 | 显示 | 理由 |
|---|---|---|
| 期间一次力量训练都没有 | 总训练容量 = **—** | 算不出来 |
| 有力量训练但都是自重（容量 0） | 总训练容量 = **0** | 算出来就是 0 |
| 期间没有有氧记录 | 总距离卡片**不出现** | 不是 0，是这一项无关 |
| 期间没有任何训练 | 总训练时长 = **—** | 同上 |

「—」和「0」在 `accessibilityText` 里也分开：前者读作「无数据」，后者读作「零公斤」。

### 6.4.4 三张图对「空数据」的处理**故意不一致**

这是本项目里唯一一处三张图行为相反的地方，且三处都是规格要求：

| 图 | 空桶 / 空点 | 规格依据 |
|---|---|---|
| 训练频率 | **补** 空桶（该日 0 次也占一格） | 横轴必须是连续日期轴；不补的话柱子位置会随训练日跳变，「哪天没练」反而看不出来 |
| 训练容量趋势 | **不补**（`guard volume > 0`） | 「无容量数据时显示空状态，而非绘制零值折线」——补 0 就正好画成了被禁止的零值折线 |
| 动作历史趋势 | **补** 空月（12 个月恒为 12 个点） | 「三月没练」本身就是答案的一部分，缺一个月会让横轴断裂、误读成连续训练 |

三处行为差异都在代码注释里写了理由，避免后来者「统一」掉其中两个。

### 6.4.5 手绘图表，不用 Swift Charts

项目全程未引入 Swift Charts，页面 10 是这条决定收益最大的一页。三个理由：

1. **深色令牌体系下，Charts 的坐标轴 / 配色 / 选中态定制成本高于手绘**。本项目的荧光绿强调色 + 深炭黑底是一套自定 palette，Charts 需要大量覆盖才接近。
2. **手绘的每根柱子都是独立视图，天然带自己的 VoiceOver 标签与点击目标**。Charts 的 `.chartOverlay` 命中测试在这一页要处理「点哪个柱」，反而更绕。
3. **规格要求「横向空间不足时可横向滚动或降级为列表」**，同一份数据要能渲染成两种形态。手绘时这两条渲染路径共用同一个 `StatsFrequencyBucket` 数组，Charts 里做不到这么干净。

折线用二次贝塞尔（`VolumeLineShape`），**不用三次样条**——三次样条会在数据点之间过冲，把「某天容量 0」画成一个个小凸起，视觉上像练过。单点数据专门做了守卫（`guard points.count > 1 else { return size.width / 2 }`），否则 `x` 轴步长为 0 会算出 NaN。

### 6.4.6 缓存的键是时间戳，不是枚举

`StatsCache<Value>` 是**单条目**缓存，不是 LRU（本页最多同时存在 6 份派生数据，LRU 的簿记成本大于收益）。

缓存键 `StatsCacheKey` 由**起止时间戳**拼成，而不是 `StatsRangeKind` 枚举。原因：自定义范围的起止日期可以被用户连续改两次，两次都是 `.custom`，用枚举做键会让第二次改动命中第一次的缓存。用时间戳则天然失效。

数据变化后由 `WorkoutStatisticsViewModel.invalidateCaches()` 显式作废，并由 `onDataChanged` 回调（数据管理页改过记录后）触发重算。

### 6.4.7 汇总口径：「完成组数」含热身，「容量」不含

同一份记录上并存两个组数口径，各自出现在不同的卡片里：

| 口径 | 属性 | 用途 |
|---|---|---|
| 含热身 | `completedSetCount` | 摘要卡「总完成组数」——回答「做了多少」 |
| 不含热身 | `totalSets` | 常练动作、部位分布、容量趋势——回答「练了多少有效量」 |

容量口径只有一个：`SetEntry.volume` 对热身组恒返回 0（页面 05 定下的契约，页面 07 / 09 / 10 与趋势层全部遵守）。所以热身组会被算进「组数」但永远不会进「容量」，这是刻意的——热身是做了，但不算训练量。

### 6.4.8 排序的稳定性

- **常练动作**：三级排序（组数降序 → 容量降序 → id 升序）。第三级专门兜住「组数与容量都相同」的两个动作，否则 `sorted` 的顺序不确定，列表会在两次刷新之间自己换位。
- **容量筛选器**：先 `.all`，再按**固定枚举顺序**列肌群（不按词频排序，避免常用肌群一直换位），最后按「次数降序 → id 升序」取前几个动作。
- **部位分布**：输出顺序固定为枚举顺序，**不按组数排序**。规格要求的是「每行显示肌群名、组数、百分比与代表色」，横条本身已经表达了大小，再排序会让行序随数据跳动。

### 6.4.9 肌群代表色刻意避开强调色

`MuscleDistributionPalette` 是固定 11 色的查表（胸 `0xE8776B` … 其它 `0x8A8A8F`），**每一色都与荧光绿拉开距离**。理由是强调绿在本页有专属语义（选中柱、强调数值），如果某个肌群也用绿，用户会误以为那一行被选中了。

审计脚本里专门留了一条断言：所有部位代表的色值都不得等于 `0xC6FF3E`。

### 6.4.10 数据管理：导出、导入、清除

数据管理页（`WorkoutDataManagementView`）三个能力：

- **导出 JSON**：`WorkoutBackup.encode` 产出的文件用 `UIActivityViewController` 分享。这是「离线无分享」原则的唯一例外——分享的是**用户自己的备份文件**，不是训练成绩，也不经过任何服务端。
- **导入**：`.fileImporter` 限定 `.json`。解码顺序是**先全部校验完再写盘**，所以解码失败时本机数据一个字节都没动过。三种合并策略：保留本机 / 覆盖同名 / 全部替换，默认为**保留本机**（三个里破坏性最小，用户没明说时不该替他丢数据）。
- **清除全部训练记录**：`confirmationDialog` 二次确认，文案明确「不会删除动作库或 App 设置」。清除范围是 `[.sessions, .restDays, .restTimer]`，`clearWorkoutRecords()` 的实现里有一行注释逐个列出**没碰**的东西：`plans / exercises / measurements / recentExercises / isExerciseSeeded`。

### 6.4.11 动作历史趋势子页（页面 11 已替换为真页面）

页面 10 交付时这里是从「常练动作」点进来的占位子页（`ExerciseTrendView`，恒为 12 个月）。
页面 11 把它换成了真正的趋势页（`ExerciseTrendDetailView`），占位页连同它的 `#Preview`
一并删除；这一节保留，是因为它记录了「为什么当初占位页不做范围选择器」：

- 占位页的问题：从统计页某个范围里点进来，用户问的是「这个动作我练得怎么样」，
  按月看最近 12 个月比看 7 天更有信息量；再给一个范围选择器会让
  「我现在看的是哪个范围」变成一件需要动脑子的事。
- 页面 11 的修正：规格要求四档范围（近 30 天 / 近 3 个月 / 近一年 / 全部记录），
  所以范围选择器**必须**有。修正后的做法是把默认档定在「近 3 个月」而不是「近 30 天」——
  周训 2 次的用户用 30 天只有 8 个点，看不出走势；周训 5 次的用户在 3 个月里
  有 60 个点又太密。3 个月对两种频率都还读得出来。

真页面的设计与取舍见下一节（六之五）。

### 6.4.12 无障碍

每张图配一句文字摘要，例如「近 30 天完成 12 次训练，共 18 小时」：`StatsSummary.accessibilitySummary(rangeTitle:)`、`StatsFrequencyBuilder.accessibilitySummary`、`StatsVolumeBuilder.accessibilitySummary`、`MuscleDistributionRow.accessibilityLabel`、`ExerciseTrendSummary.accessibilityText`。摘要句在**没有数据时也成立**（「近 30 天没有训练记录」），不留空标签。

选中柱带 `.isSelected` trait；手动条形在窄屏退化为列表时仍是同一组数据，VoiceOver 读到的内容不变。

### 6.4.13 新增的设计令牌与格式化

| 令牌 | 用途 |
|---|---|
| `Palette.statsStrengthBar` / `statsSelectedBar` | 力量柱 / 选中柱 |
| `Palette.statsGrid` | 图表网格线 |
| `Palette.statsVolumeLine` / `statsVolumeFill` | 容量折线 / 填充 |
| `Size.statsMetricFont` / `statsMetricCardHeight` | 摘要卡字号 / 高度 |
| `Size.statsFrequencyChartHeight` / `statsVolumeChartHeight` | 两图高度 |
| `Size.statsBarMaxWidth` / `statsBarMinWidth` / `statsAxisWidth` | 柱宽与轴宽 |
| `Size.statsMuscleBarHeight` | 部位横条高度 |
| `Size.statsMinVisibleBuckets` / `statsAxisLabelMaxCount` | 粒度降级阈值 / 轴标签上限 |

`FormatterKit` 新增 `monthDaySlash(_:)`（`M/d`）与 `dateRangeSlash(_:_:)`，用于时间范围按钮的简称。

---

## 六之五、页面 11 动作历史趋势

入口两处：统计页「常练动作」点某个动作（`HistoryRoute.exerciseTrend`），
或动作详情页右上角菜单的「历史记录」（`ExerciseRoute.exerciseTrend`）。

### 6.5.1 布局对照

```
┌──────────────────────────────────┐
│ ‹   杠铃卧推           近 3 个月 ⌄ │  ← 顶部栏：返回 / 动作名 / 范围菜单
├──────────────────────────────────┤
│ 累计数据            8/19 – 9/19  │
│ ┌────────────┬────────────┐      │
│ │ 累计训练次数│ 累计完成组数│      │
│ │ 12 次      │ 24 组      │      │
│ ├────────────┼────────────┤      │
│ │ 最高单组重量│ 估算 1RM   │      │
│ │ 82 kg ★   │ 98.4 kg    │      │
│ │            │ 按 6 次组估算│     │
│ ├────────────┴────────────┘      │
│ │ 最近训练  9月17日              │
│ └────────────────────────────────┘
│ 最高重量趋势  仅统计正式组        │
│  ···╭╮···╭─╮·····              │  ← 折线，点一下出详情条
│  9/1    9/8    9/15             │
├──────────────────────────────────┤
│ 单次训练容量趋势  重量 × 次数     │
│                    [ kg | lb ]   │  ← 单位切换
│  ▁▃▅▂▆█▄▂▅▇                     │
├──────────────────────────────────┤
│ 最近记录  按时间倒序       10 次  │
│  9/17  第 12 次训练   82 kg × 6  │
│        2 组 · 1030 kg            │
├──────────────────────────────────┤
│ [      开始练这个动作      ]      │
└──────────────────────────────────┘
```

### 6.5.2 时间范围：与统计页**不是同一套**

统计页问「这段时间我练了多少」，所以要「本月」「今年」这种日历区间；
趋势页问「这个动作我练得怎么样」，日历区间在这里没有意义——「本月」在一个月
刚开始时会给出近乎空白的图。所以 `TrendRangeKind` 只有四档：
近 30 天 / 近 3 个月 / 近一年 / 全部记录。

口径细节（都由 `probe_page11_semantics.py` 锁死）：

| 档位 | 起点 | 为什么这么算 |
|---|---|---|
| 近 30 天 | 今天往前 **29** 天 00:00 | 30 个自然日 = 今天 + 往前 29 天。写成 `-30` 会得到 31 天 |
| 近 3 个月 | 当月 1 号往前 **2 个日历月** | 用户说「3 个月」时想的是 4 月 → 2 月，不是「往前 2160 小时」。4 月 30 日往回 90 天是 1 月 30 日，按日历月才是 2 月 1 日 |
| 近一年 | 当月 1 号往前 11 个日历月 | 同上 |
| 全部记录 | Cocoa 纪元（2001-01-01） | 之前不可能有记录。不用 `distantPast`：它序列化出来的值会让调试日志完全不可读 |

终点统一取**明天 00:00**（半开区间 `[start, end)`），与页面 10 同一个理由：
写成「今天 23:59:59」会漏掉 `23:59:59.5` 这种带亚秒精度的记录。

### 6.5.3 两处「—」：算不出来不等于 0

延续 6.4.3 的约定，顶部摘要里三个可能算不出来的字段都是 Optional：

- **最高单组重量**：自重动作整段都是 0，显示「0 kg」会让人以为自己举过 0 公斤，所以是 `nil` → 「—」。
- **估算 1RM**：没有任何落在 Epley 可靠区间的组时为 `nil` → 「—」。
- **最近训练**：没有任何记录时为 `nil` → 「—」。

### 6.5.4 1RM 用 Epley，但有一条 12 次的天花板

`1RM = w × (1 + reps / 30)`。选它而不是 Brzycki / Lombardi，是因为它在 1–10 次
区间里误差最小，而那正是力量训练记录里最常见的次数区间。

超过 12 次后公式会显著高估：一组 20 次 60 kg 会被算成 `60 × (1 + 20/30) = 100 kg`，
而实际做不了 100 kg。所以 `epley(weight:reps:)` 在 `reps > 12` 时返回 **nil 而不是 0**——
nil 表示「不参与最高值评选」，0 会污染最大值比较（0 永远赢不了，但会让
「有没有 1RM」的判断变得含糊）。UI 因此只在能算时才补一句「按 N 次组估算」。

### 6.5.5 三张图共用同一条时间轴

`validSets(sessions:exerciseID:range:)` 一次筛出全部有效组（已完成训练 + 已完成组 + 非热身），
按日期升序排好，再分别喂给 `weightPoints` / `volumePoints` / `recentRecords`。
排序只在这一处做：三个视图各排一次迟早会不一致。

由此得到一个可以拿来当断言用的不变式：**`weightPoints` 为空 ⟺ 本范围内没有任何有效组**
⟺ 页面走空状态。所以三张卡内部都不再写空分支——走到那里时数据必定非空，
写一份走不到的分支只会让人以为要维护它。

### 6.5.6 折线图：按训练日聚合，不补空日

与页面 10 的容量趋势（按月、补空月）相反，这里**按训练聚合**：
用户问的是「我这个动作的重量有没有涨」，按月平均会把「月初 60、月末 80」抹成「这个月 70」。
同样地，没练的日子不补 0——补 0 会画出一条跌到零的折线，用户会以为自己退步了。

折线用二次贝塞尔连接（控制点取两点中点），与页面 10 同一选择：三次样条会在峰值处
过冲，把「这次没练到」画成一个凸起。单点时不画线（两点才定义一条线，强行画会除零）。

圆点直径只有 7pt，手指点不中，所以每个点给一个**贯穿整列的透明点击区**；
`TrendWeightLineShape.x(at:)` 的列宽算法必须与 `dotsRow` 完全一致
（`rect.width / count` 的列中心布局，不是首末贴边的轴布局），
否则折线端点会和圆点对不上。

### 6.5.7 单位切换只改展示值

`TrendWeightUnit` 里**一个 `mutating` 方法都没有**，全部是纯函数：
`displayValue(fromKilograms:)` 只产出展示用的 Double，舍入留给格式化。
（先舍入再换算会把误差累积进图表。）

切换单位的 ViewModel 方法只有一行 `unit = newUnit`：

- **不重新读盘**——走一遍仓储会把刚刚算好的选中态一起冲掉；
- **不重算聚合**——原始值没变，算出来的还是同一组点；
- **不写回任何记录**——规格明确要求「仅转换展示值，不修改原始记录」。

容量柱只表达相对高度，所以单位切换在柱子上是看不出变化的。为此图上补了一行
**峰值读数**（`unit.volumeText(fromKilograms:)`），切换后这个数字会变，
否则用户会以为开关没生效。

### 6.5.8 「最佳组」比重量，不比容量

`recentRecords` 里的最佳组定义是：先比重量，同重量再比次数。
不按容量比——`80×3(240)` 不该盖过 `70×10(700)`，用户点进详情页想看的是
「这次最重举了多少」，而不是「哪组做的功最多」。

### 6.5.9 「开始练这个动作」的建议来自最近一次，且**不自动加重**

建议取自**最近一次有效记录**，不是全期最高：建议的意义是「接着上次练」，
拿历史最高去建议会让新手一上来就加满重量。

- 重量：沿用上次最高组，**不做渐进超负荷**。App 替用户加重量出了伤没人负责。
- 次数：上限 = 上次最高次数；下限 = 上限的 8 折向上取整，并尽量不低于 5
  （低于 5 次就接近力量举而非增肌区间）。上限本身低于 5 时下限被压回与上限相等——
  「5-4」这种倒挂区间比窄区间难看得多。
- 组数：上次该动作的组数，但不低于 3。
- 休息：沿用项目默认的 90 秒。

建议**始终按全部历史计算，不受当前查看范围影响**：「接着上次练」这件事
跟「我当前在看近 30 天」没有关系。

抽屉里明确写出这些数字来自哪里（`suggestion.sourceText`）——用户有权知道
这是照抄上次还是 App 替他编的默认值。确认后落盘一份 `kind: .strength` 的草稿，
训练名直接取动作名（执行页顶部写着别的名字会让人怀疑走错了页），
然后把草稿 id 交给执行页。

### 6.5.10 空状态只有一个，按钮始终在

没有任何记录时整页只给一句「还没有这个动作的训练记录」，而不是四张卡各空一次——
三句「还没有…」叠在一起，读起来像页面坏了。

「开始练这个动作」按钮在卡片之外、与空状态并列：**空状态下也保留**。
用户没有历史记录时，最需要的恰恰是「现在就去练一次」。

### 6.5.11 动作被删除后仍能看到趋势

动作名三级兜底：库里的当前名 → 上游传来的快照名 → 动作 id → 「未知动作」。
任何输入都不产出空字符串——空白标题看起来像渲染失败。
所以动作被隐藏或从库里移除后，已有趋势仍按 id 与快照名展示。

### 6.5.12 无障碍

- 两张图各配一句 VoiceOver 摘要（`weightTrendSummary` / `volumeTrendSummary`），
  内容包含范围、次数、最高值，以及**首末点的涨跌**（持平 / 提高 N 公斤 / 下降 N 公斤）。
  单点时不提涨跌（没有可比对象）。空数据时摘要也说得通：「近 30 天内没有这个动作的训练记录。」
- 图上的形状本身全部 `.accessibilityHidden(true)`：VoiceOver 读的是外层拼好的整句，
  逐个形状朗读只会得到一串碎片。
- 动态字体达到**无障碍档位**时，两张图自动降级为数据列表
  （`TrendAccessibilityScale.shouldUseList` 判据取 `category.isAccessibilityCategory`，
  而不是某个具体档位——系统把它设为 true 的那一刻，就是「文字已经大到图表装不下」的时刻）。
  降级列表与图共用同一组数据点，所以切换档位不会丢选中状态。

### 6.5.13 新增的设计令牌

| 令牌 | 用途 |
|---|---|
| `Palette.trendWeightLine` / `trendWeightFill` | 最高重量折线 / 填充。用强调绿本身：这一页的主角就是重量，没有别的元素需要跟它抢 |
| `Palette.trendVolumeBar` | 容量柱 |
| `Palette.trendSelected` / `trendDot` / `trendUnitSelected` | 选中态 / 未选中圆点 / 单位切换选中底 |
| `Size.trendWeightChartHeight` / `trendVolumeChartHeight` | 两图高度（168 / 140） |
| `Size.trendDotDiameter` / `trendSelectedDotDiameter` | 圆点直径（7 / 11） |
| `Size.trendBarMaxWidth` / `trendBarMinWidth` | 柱宽上限 20 / 最小高度 4 |
| `Size.trendMetricFont` / `trendMetricRowHeight` | 摘要格字号 / 行高 |
| `Size.trendUnitToggleHeight` / `trendRecordRowHeight` | 切换器高 / 记录行高 |
| `Size.trendChartVerticalPadding` | 图表上下内边距（父视图与圆点共用同一个值，避免两处各算一次导致漂移） |

---

## 六之六、页面 12 身体数据

### 6.6.1 布局对照

```
┌───────────────────────────────────┐
│ ←  身体数据                    ＋ │  导航栏：返回 / 标题 / 新增
├───────────────────────────────────┤
│  最近一次            9月19日      │
│  ┌──────────────┬──────────────┐ │  摘要卡：最近一次记录
│  │ 体重 74.2 kg │ 体脂率 16.4% │ │   体重 / 体脂率 / 日期
│  └──────────────┴──────────────┘ │   较上次 −0.6 kg / 较上次 −0.4%
│  重量 kg|lb    围度 cm|in        │  单位切换（kg/lb + cm/in）
├───────────────────────────────────┤
│        趋势          记录         │  分段控件
├───────────────────────────────────┤
│ [体重][体脂][胸][腰][臀][大腿][臂] │  指标 Chip（横向滚动）
│  ╭───────────────────────────╮   │  折线图（纵轴自动范围 + 留边距）
│  ╰───────────────────────────╯   │
│  最新值  变化值  最低值  最高值    │  指标统计四格
├───────────────────────────────────┤  （记录分段）
│ ┌───────────────────────────┐    │
│ │ 9月19日 星期六            │    │  记录卡（日期倒序）
│ │ 体重 74.2  体脂 16.4       │    │   左滑 / 长按删除（二次确认）
│ └───────────────────────────┘    │
└───────────────────────────────────┘
```

### 6.6.2 七个指标集中在一个枚举里

体重用重量单位、体脂率用百分比、胸/腰/臀/大腿/上臂五项围度用长度单位——
三类量的换算口径不同。`BodyMetric` 用一个枚举集中处理 `rawValue(of:)`、
`isWeight` / `isPercent` / `isLength`、`unitShort` 与 `displayValue`，
避免在图表、记录卡、摘要卡、录入面板四处重复 `switch`。

### 6.6.3 单位换算只影响展示，内部统一存 kg 与 cm

与页面 11 的 `TrendWeightUnit` 同一条契约：`BodyWeightUnit`（kg/lb）与
`BodyLengthUnit`（cm/in）**连一个 `mutating` 方法都没有**，全部是纯函数
`displayValue(fromKilograms:)` / `displayValue(fromCentimeters:)`。
落盘与聚合全程 kg / cm，切换单位只改 `Text`。推演脚本有断言守住这个单向性
（`lb 不等于原值`、`in 不等于原值`）。

单位偏好存 `UserDefaults`（`preference.bodyWeightUnit` / `preference.bodyLengthUnit`），
纯本地设置，不落 JSON。

### 6.6.4 「未记录」不等于「0」

`BodyMeasurement` 的每个数值字段都是 `Double?`。摘要卡、统计格在字段为 nil 时
显示「未记录」/「—」，而不是 0——0 公斤体重是医学上不成立的读数。
这是页面 10 的 `StatsMetric.value: String?` 同一套语义，落到身体数据上就是：
「这条记录没填体重」和「体重是 0」必须分得清。

### 6.6.5 变化值 = 最近一条 − 上一条有该字段的记录

摘要卡底部的「较上次 −0.6 kg」：取**最近一条有体重**的记录，减去**上一条有体重**的记录。
最近一条记录自己没体重时，变化值为 nil（没有可比较的基准），整行不显示。
体脂率同理。推演脚本覆盖了这条边界（`最新记录无体重时变化为 None`）。

### 6.6.6 纵轴自动设范围 + 留边距

`BodyTrendChart` 的纵轴下界取 `minValue − 10% 跨度`、上界取 `maxValue × 1.1`，
并上下各留 12pt 内边距，避免曲线贴边。全相等时上下界收敛，此时给一个最小跨度
避免除零。横轴为日期，点只在「有该指标的记录」上出现——**不补空日**，
身体数据不是每天必测，补 0 会把「没测」画成「值降到 0」。

### 6.6.7 不足两条记录的空状态

选中指标不足两条记录时，趋势图换成 `EmptyStateView("记录更多数据后可查看趋势")`，
而不是画一条孤立无意义的折线。统计四格同样只在有数据时出现。

### 6.6.8 同日唯一键，覆盖需二次确认

`BodyMeasurement` 的 `save` 在**仓储层**保证一个自然日只留一条（与 `RestDay` 同款
`calendar.isDate(_:inSameDayAs:)` 去重）。UI 层在编辑器保存时先 `conflict(on:)` 查冲突：
同一天已有记录（且不是正在编辑的那条）时，弹出「覆盖当天记录 / 取消」确认，
确认后仓储的去重逻辑原子覆盖。编辑保留原 id，所以「覆盖」和「改这条」是同一语义。

### 6.6.9 校验：至少一个值 + 范围

录入面板七个数值字段全部可选，但 `hasAnyValue` 为 false（一个都没填）时拒绝保存。
范围校验：体重 20–400 kg、体脂率 1–70%、围度 20–300 cm（规格只给了前两个例子，
围度取覆盖成年人全部体型的 20–300）。越界或非数字在保存时统一拦截并提示。

### 6.6.10 记录列表用 List 而非 LazyVStack

只有 `List` 才支持 `swipeActions`（左滑删除）。记录分段是 `List` 里的一段
`ForEach`，每个记录卡带 `.swipeActions` 与 `.contextMenu`（长按删除），
两者都只打开删除确认抽屉、不直接删。一个容易踩的坑：**List 只展平自己
ViewBuilder 产出的顶层 TupleView**，把趋势/记录内容包在一个 `@ViewBuilder var`
里再引用，会让多行塌成一整行——所以这部分必须直接内联进 List 的 `if/else`。

### 6.6.11 无障碍与降级

- 摘要卡、趋势图整体给一句话 VoiceOver 摘要（`trendSummary` 拼出最新/变化/最低/最高）。
- 图形（折线 / 网格 / 圆点）一律 `.accessibilityHidden(true)`，读的是整句摘要。
- 数据点有独立无障碍标签（日期 + 数值）。
- 动态字体到 `isAccessibilityCategory` 时折线图降级为 `BodyMetricPointList`，
  与图共用同一组 `BodyMetricPoint`，切换档位不丢数据。

### 6.6.12 新增的设计令牌

| 令牌 | 用途 |
|---|---|
| `Palette.bodyChartLine` / `bodyChartFill` | 折线 / 填充（强调绿本身） |
| `Palette.bodyChartDot` / `bodyChartSelected` | 未选中 / 选中数据点 |
| `Size.bodyChartHeight` / `bodyChartVerticalPadding` | 图高 180 / 上下内边距 12 |
| `Size.bodyDotDiameter` / `bodySelectedDotDiameter` | 圆点直径 7 / 11 |
| `Size.bodyChipHeight` / `bodyMetricFont` | 指标 Chip 高 32 / 摘要字号 20 |
| `Size.bodyRecordRowHeight` | 记录卡最小行高 54 |

---

## 六之七、页面 13 我的

### 6.7.1 布局对照

```
┌───────────────────────────────────┐
│  我的                            │  大标题
├───────────────────────────────────┤
│  [首字母头像] 小健        已使用 60 天  › │  个人概览卡（可点 → 个人资料编辑）
├───────────────────────────────────┤
│  74.2 kg     12 次     18 小时    │  数据摘要（最近体重 / 累计训练 / 累计时长）
├───────────────────────────────────┤
│  训练与身体                        │
│  🏋 身体数据        体重/体脂/围度  › │
│  📋 我的计划        已保存的计划    › │
│  ⭐ 动作收藏        收藏的动作      › │
│  🎚 训练偏好        休息与自动开始  › │
├───────────────────────────────────┤
│  数据                              │
│  💾 本地数据管理    导出/导入/清除  › │
│  ⬇ 导入备份        从 JSON 恢复    › │
│  ⬆ 导出备份        生成 JSON 文件  › │
├───────────────────────────────────┤
│  应用设置                          │
│  重量单位        [kg|lb]           │
│  长度单位        [cm|in]           │
│  默认休息时间     1 分 30 秒       › │
│  声音            [开关]            │
│  触感            [开关]            │
│  深色外观        [开关]            │
│  减少动态效果    [开关]            │
├───────────────────────────────────┤
│  本地健身                          │
│  本地数据库 v1 · 动作库 v1.0       │
│  © Gym visual — …                 │
└───────────────────────────────────┘
```

### 6.7.2 个人资料是独立模型 `UserProfile`

昵称 + 开始使用日期单独存 `profile.json`（单个对象，不是数组）——它是「这台设备上的
一个用户」，与训练 / 身体数据 / 动作库这些集合数据天然分开。协议新增 `fetchProfile()` /
`save(profile:)` 两个方法（50 → **52**），仓储三层同步落地。首次进入「我的」时若还没有
资料，就创建一份、`startedAt` 记作今天。

「已使用 N 天」是纯函数 `ProfileMath.daysSince`：按自然日算（昨天 = 1 天、今天 = 0 天），
`max(0, …)` 兜底时钟回拨不为负。推演脚本覆盖了这条边界。

### 6.7.3 单位是全 App 的一处真相

重量单位 / 长度单位写 `preference.bodyWeightUnit` / `preference.bodyLengthUnit`，
**与页面 12 身体数据共用同一把键**（`ProfileSettings` 与 `BodyDataViewModel` 读同一处）。
所以「我的 → 应用设置」里改单位，身体数据页的展示跟着变，不会出现两把键各说各话。

### 6.7.4 声音 / 触感是真正生效的开关

规格只要求「提供独立开关」，但一个改了没效果的开关比没有更糟。两个开关都接了真实行为：

- 触感 → `Haptics` 每个方法 `guard ProfileSettings.hapticsEnabled else { return }`。
- 声音 → `RestAlertSound.play()` `guard ProfileSettings.soundEnabled else { return }`。

「休息结束提醒」（本地通知）从旧「我的」页迁到「训练偏好」子页，与声音 / 触感区分开：
一个是后台通知、一个是前台音效 / 振动，三者是独立的能力。

### 6.7.5 数据组复用页面 10

「本地数据管理」直接路由到页面 10 的 `WorkoutDataManagementView`（导出 / 导入 / 清除）。
「导出备份」「导入备份」是快捷动作：在 `ProfileTab` 里复用同一个
`WorkoutDataManagementViewModel` 直接导出 / 导入，导入走页面 10 的合并策略抽屉
（保留本机 / 覆盖同名 / 全部替换，破坏性一条二次确认）。

### 6.7.6 底部版本信息与署名

底部显示 App 自己的名字「本地健身」（不是原 App 名）、本地数据库版本 v1
（与 `WorkoutBackup.currentVersion` 同口径）、动作库版本 v1.0，以及
`MediaAttributionLabel()`（`© Gym visual — https://gymvisual.com/`）。
不出现原 App 名、第三方品牌或引流入口——审计把这些写成反规格断言。

### 6.7.7 设置全部本地持久化

所有开关、单位、默认休息时间都写 `UserDefaults`（见 `ProfileSettings` 的键与默认值）。
开关即时写入；切换单位只改展示值、不回写任何记录。深色外观是「固定深色」的开关
（本应用深色锁定），减少动态效果是独立的用户偏好键。

### 6.7.8 无障碍

概览卡、数据摘要、菜单行、开关行都有明确的 VoiceOver 标签；数据摘要合并成一句完整语句。
列表用语义化字体，动态字体增大时自动增高，不硬编码行高。

---

## 六之八、页面 14 训练偏好

入口：我的 → 训练偏好。纯本地个人设置中心，不含云同步、账号同步或社交偏好。

### 6.8.1 布局对照

```
┌───────────────────────────────────┐
│  ‹  训练偏好                       │
├───────────────────────────────────┤
│  训练记录                          │
│  默认组间休息时间      1 分 30 秒 ›│  → 秒数选择抽屉（30/45/60/90/120/180 + 自定义）
│  自动复制上次记录        [开关]    │
│  完成一组后自动开始休息  [开关]    │
│  显示训练容量            [开关]    │
├───────────────────────────────────┤
│  计时器                            │
│  倒计时提示音            [开关]    │
│  触感反馈                [开关]    │
│  倒计时最后 10 秒提醒    [开关]    │
│  倒计时数字样式        普通 ›     │  → 单选抽屉（普通 / 大号）
│  休息结束通知            [开关]    │  （页面 06 遗留功能，保留开关）
├───────────────────────────────────┤
│  训练流程                          │
│  完成当前动作后自动定位下一动作 [开关] │
│  新增组时复制上一组数值         [开关] │
│  默认显示热身组                 [开关] │
│  最小化训练后保留计时器         [开关] │
├───────────────────────────────────┤
│  ↺  恢复默认训练偏好               │  → 危险操作，先列清单再二次确认
└───────────────────────────────────┘
```

### 6.8.2 「自动复制上次记录」复用页面 13 的 `prefillWeights` 键

规格措辞是「自动复制上次记录」，页面 13 的占位页叫它「重量预填建议」。两者是**同一个概念**
——「建议最近一次有效重量 / 次数」——只是名字不同。**同一概念不落两把键**，所以页面 14 直接
沿用 `prefillWeights`，只是把 UI 文案改成「自动复制上次记录」。开关接进了两处草稿入口的
`seedPrescribedWeights`（`PlanDetailViewModel` 与 `RootView.startDraft`），关闭后新建训练
不再预填历史重量。

### 6.8.3 每个开关都真正生效（不是摆设）

延续页面 13「改了没效果的开关比没有更糟」的原则，页面 14 的开关全部接进运行态：

| 开关 | 关闭后的行为 |
|---|---|
| 显示训练容量 | 执行页概览不显示「总训练容量」，但 `totalVolume` 照常由仓储计算，历史统计不受影响 |
| 完成一组后自动开始休息 | 勾选完成一组后不自动弹休息倒计时 |
| 自动复制上次记录 | 新建训练草稿不预填历史最高重量 |
| 倒计时最后 10 秒提醒 | 倒计时数字最后 10 秒不再转荧光绿 |
| 倒计时数字样式 | 大号用 84pt，普通用 64pt（`DS.Size.restCountdownFontLarge`） |
| 自动定位下一动作 | 完成一张动作卡后不滚动到下一张 |
| 新增组时复制上一组数值 | 新组重量从 0 起填，只保留计划目标次数 |
| 默认显示热身组 | 热身组行从组表隐藏（仍在会话模型里，统计照常算） |
| 最小化训练后保留计时器 | 最小化时连休息倒计时也停掉（草稿仍保留） |

其中「自动定位下一动作」走 `ScrollViewReader`：完成整卡后把 `advanceTargetID` 置成下一张
未完成卡的 id，页面层 `.onChange(of:)` 消费后 `scrollTo` 并清空。

### 6.8.4 恢复默认是「先清单、再二次确认」

「恢复默认训练偏好」先弹一个抽屉列出 12 项将被重置的内容与默认值，用户点「恢复默认」才真正
写回。`restoreTrainingDefaults()` **只重置训练偏好这一组**——不碰单位、深色外观、减少动态
效果（应用设置那组），更不碰训练计划 / 历史 / 动作库 / 身体数据（都在仓储，不在 UserDefaults）。
推演脚本断言了这条边界（恢复函数体里出现 `weightUnit` / `plans` 等都算失败）。

### 6.8.5 「休息结束通知」是保留的页面 06 遗留功能

页面 14 规格的计时器组只列了四项，但「休息结束本地通知」（`RestNotification`，页面 06 引入）
是已经接线的真实功能，删掉会把它变成永远无法关闭。因此作为计时器组的第五项保留，与
「倒计时提示音」（前台音效）区分开：一个是后台通知、一个是前台音效。

### 6.8.6 值层与无障碍

新增 `CountdownNumberStyle`（普通 / 大号，纯值枚举）与 `TrainingPreferenceResetItem`
（恢复默认清单项）。开关行的 `accessibilityValue` 统一朗读「已开启 / 已关闭」
（在 `ProfileToggleRow` 上加的，页面 13 的开关一并受益）。倒计时数字样式单选抽屉带
`.isSelected` 特征；恢复默认按钮有「只重置训练偏好」的无障碍提示。

---

## 六之九、页面 15 我的计划

入口：我的 → 我的计划。纯本地计划管理，不展示官方计划、公开计划、好友计划或社区内容。

### 6.9.1 布局对照

```
┌───────────────────────────────────┐
│  ‹  我的计划                   ＋  │  ＋ = 菜单（新建力量计划 / 导入本地计划备份）
├───────────────────────────────────┤
│  🔍 按名称筛选                     │  实时搜索
│  排序  [最近使用][最近创建][名称][训练天数] │  排序 Chip
├───────────────────────────────────┤
│  ┌─────────────────────────────┐ │
│  │ 推拉腿                ⋯     │ │  名称 / 每周天数 / 动作数 / 预计时长 / 上次训练
│  │ 每周 3 天                  │ │
│  │ 6 个动作 · 预计 45 分钟     │ │
│  │ 上次训练 9月18日            │ │
│  └─────────────────────────────┘ │
│  …                                │
└───────────────────────────────────┘
```

### 6.9.2 「自动复制」之外的四个排序是纯函数

`PlanListSorting.sort(_:by:)` 是零 SwiftUI 的纯函数，四种排序：
- **最近使用**：`lastUsedAt` 降序，从未用过的（nil）排最后；
- **最近创建**：`createdAt` 降序；
- **计划名称**：`localizedStandardCompare` 升序；
- **训练天数**：`trainingDays.count` 降序。

全部带 **id 兜底**保证稳定排序——同键值顺序不跳变。推演脚本覆盖了 nil 排最后、
降序、稳定兜底这些边界。

### 6.9.3 复制命名统一为「原名称（副本）」

页面 15 规格要求「原名称（副本）」，但页面 04 时期 `duplicate(planID:)` 生成的是
「名字 2」。本轮把命名统一成 `PlanCopyName.makeCopyName(for:)`（纯函数），
**两处仓储实现同步改**，并防「（副本）（副本）」叠加。页面 04 的复制计划、首页的
复制计划、页面 15 的复制计划现在走同一个命名。

### 6.9.4 多计划备份（批量导出 + 导入）

页面 04 的 `PlanBackupWriter` 只导单个计划；页面 15 多选模式需要批量导出，于是新增
`PlanBackup`（`fitness-plans-backup`，version 1，`plans` 数组）。`PlanBackupCodec` 负责：
- 编码 / 解码，错误分支与 `WorkoutBackupCoder` 同款（空文件 → 非 JSON → 格式 → 版本 → 无计划）；
- 载荷往返：`PlanBackupPayload.toPlan()` 重建**全新 id** 的计划，`lastUsedAt` 清空，
  动作条目 `id` 也重新生成——导入的计划不继承源计划的训练历史，也不共享条目引用。

### 6.9.5 批量删除进仓储协议（52 → 53）

多选批量删除需要一个原子落盘的方法，新增 `deletePlans(ids:)`：只动 `plans.json`，
不碰 `sessions.json`，历史训练不受影响。协议 + JSON 实现 + 内存桩三处同步。

### 6.9.6 从「我的计划」进入计划详情与训练执行页

页面 15 补齐了 ProfileTab 的下游路由：`planDetail` / `exerciseConfig` /
`sessionDraft` / `sessionSummary` 四个新 case，加上动作选择器 sheet（`ExercisePicker`，
追加 / 替换计划条目 / 替换训练中动作三种上下文），以及「开始训练」的草稿展开 + 历史重量预填
（与 TrainingTab 的 `startDraft` 同逻辑，受页面 14「自动复制上次记录」开关控制）。

**本轮顺带修了一个页面 07 遗留的跨作用域错误**：`TrainingTab` 是独立 struct，却在其
`sessionSummaryView` 里直接访问了 `RootView` 的 `selection` / `pendingHistorySessionID` /
`sessionSummaryReloadToken`——这在 Swift 里根本无法编译，只因 Windows 无编译器而一直潜伏。
修复方式：给 `TrainingTab` / `ProfileTab` 各加 `onOpenHistory: (UUID) -> Void` 回调，
由 RootView 完成「切 Tab + 定位本次训练」。这是页面 15 接入 ProfileTab 训练总结页时发现的，
一并改正。

### 6.9.7 无障碍

卡片有合并的 VoiceOver 标签（名称 + 天数 + 动作数 + 预计时长 + 上次训练 + 选中态）；
排序 Chip 带 `.isSelected`；批量删除 / 批量导出按钮有明确标签；列表用语义化字体。

---

### 6.10 页面 51 权限管理

**入口**：应用设置 → 隐私 → 「权限管理」。首次触发相册 / 本地通知功能时，系统弹窗仍是唯一的申请时机。

#### 布局对照

| 区块 | 内容 |
|---|---|
| 顶部说明卡 | 一句话交代「本 App 只用两项系统权限」，并列出**不申请**的清单 |
| 权限列表 | 两项：本地通知、相册访问。每项显示图标 + 名称 + 用途说明 + 状态徽章 |
| 状态徽章 | 未授权（灰）/ 已授权（荧光绿）/ 已拒绝（琥珀）/ 受限制（冷灰） |
| 前往系统设置 | 仅当状态为「已拒绝」或「受限制」时出现，点击跳 `UIApplication.openSettingsURLString` |
| 「不开权限会怎样」 | 逐项给出降级说明：没有通知仍可用前台倒计时；没有相册权限仍可用代码绘制头像 |
| 页脚 | 隐私声明：只反映本机系统权限状态，不上传、不追踪、无第三方登录 |

#### 6.10.1 页面只反映状态，绝不申请

`PermissionCenter` 里**没有任何 `requestAuthorization` 调用**，只有两个读取：

```swift
UNUserNotificationCenter.current().getNotificationSettings { ... }  // 只读
PHPhotoLibrary.authorizationStatus()                               // 只读
```

审计把这条写成反规格断言：`PermissionCenter.swift` 与 `PermissionSettingsView.swift` 两个文件里
`requestAuthorization` 的出现次数必须为 **0**。申请权限是「使用该功能的那一刻」的事，
不是「打开权限页」的事——权限页主动弹窗会让用户以为「进了这页就得授权」。

#### 6.10.2 四态是四态，不要合并

| 内部值 | 显示 | 是否引导去系统设置 | 说明 |
|---|---|---|---|
| `notDetermined` | 未授权 | ❌ | 从没问过。此时引导去系统设置是错的——应该等用户用功能时再弹 |
| `authorized` | 已授权 | ❌ | 已授权无需引导 |
| `denied` | 已拒绝 | ✅ | 系统弹窗不会再出现，只能去设置里改 |
| `restricted` | 受限制 | ✅ | 家长控制 / MDM 限制，用户自己也改不了，但设置里能看到原因 |

「要不要显示前往系统设置的按钮」这条规则被抽成 `PermissionStatus.needsSystemSettingsLink`，
写成**显式 switch**而不是 `status != .authorized`。两者只在 `notDetermined` 上分歧，
而这正是最容易写错的那一格——推演脚本为这条专门写了双向断言
（`SHOWS_LINK == {denied, restricted}` 且反向守卫「未授权态绝不引导去系统设置」）。

#### 6.10.3 两个映射器的输入是原始枚举，不是我自己造的字符串

`PermissionStatusMapper` 接收的是系统枚举的 `rawValue` 字符串，不是中文名也不是枚举 case。
之所以绕一层字符串，是为了让值层保持**零 UIKit / 零 UserNotifications / 零 Photos import** ——
这样才能在 Windows 上用 Python 照搬推演（第 4 层门禁的既有做法）。

映射规则：
- 通知：`provisional` / `ephemeral` → **已授权**（它们都是「能送达」的状态，只是送达方式不同）；
  未知取值 → **未授权**（兜底到最保守的一档，而不是当作已授权）
- 相册：`limited` → **已授权**（受限选择也是能用）；`restricted` **原样保留**（它和 denied 的
  处置方式相同但成因不同，合并会让页脚解释不了「为什么用户自己也改不了」）

**通知侧永远不会产出 `restricted`** —— 这是 Apple 的 `UNAuthorizationStatus` 里本就没有的取值。
推演脚本对通知映射器的全部合法输入做了全量断言，确认输出永不为 `restricted`，
并且额外断言「相册映射器是 `restricted` 的唯一来源」。

#### 6.10.4 探针抓到的一个真缺陷：硬编码的「两项」

`PermissionCatalog.availabilitySummary(_:)` 是拼汇总文案的纯函数，签名接受**任意长度的清单**，
但第一版实现把数字写死成了「两项」：

```swift
// 错的：接受任意清单，却说「两项」
if grantedCount == entries.count { return "两项权限均已授权。" }

// 对的：跟着清单长度走
if grantedCount == entries.count { return "\(total) 项权限均已授权。" }
```

当前调用方传的确实是两项，所以**页面上看不出任何异常**——这是个潜伏缺陷：将来加第三项权限
（比如相机）时文案会说「两项」而列表里有三条。第 4 层推演用一条单项清单把它逼了出来。

修完的断言不再硬编码句子，改成**关系断言**：
`availabilitySummary(n 项全授权).hasPrefix("\(n) 项")`，n 取 1 / 2 / 3 / 5。
这是页面 10 那条教训的再次应用 —— 硬编码的期望值下次还会错，关系不会。

#### 6.10.5 拒绝权限不影响核心功能，这句话在代码里有落点

规格要求「拒绝权限不影响核心功能」，所以每一档状态对应的**降级说明**是值层的一部分
（`PermissionKind.fallbackNote`），而不是视图里的临时文案：

| 权限 | 拒绝后的降级 |
|---|---|
| 本地通知 | 休息结束无后台提醒，但**前台倒计时、声音、触感全部照常** |
| 相册访问 | 无法设置自定义头像，但**代码绘制的首字母头像照常显示** |

推演脚本为这条写了一个 16 组合的矩阵断言：「无论如何组合四项状态，清单长度恒为 2」——
界面不会因为权限全被拒绝就少显示一行。

#### 6.10.6 回到前台要重读

用户在页面里点了「前往系统设置」，改完权限回来，页面必须反映新状态。用
`.onChange(of: scenePhase)` 在 `.active` 时重读，而不是 `onAppear` ——
从设置 App 切回来时 `onAppear` 不会再触发（与本项目其它页面「刷新不能只靠 onAppear」
是同一个坑）。

#### 6.10.7 相册权限其实不需要预授权

`PhotosPicker`（iOS 16 引入）走的是**带内授权**：用户选中哪几张，App 就只拿到哪几张，
连相册权限都不必先要。所以本页的相册条目是**如实反映**当前状态，
而不是「不用就不能选图」的门槛。这一点写进了 `PermissionKind.photoLibrary.purpose` 的文案：
「仅用于设置本地头像」，暗示不授权也有别的路。

#### 6.10.8 `Info.plist` 只加了一个键

新增 `NSPhotoLibraryUsageDescription`。全项目**不存在**定位、通讯录、蓝牙、麦克风、
健康数据、网络（`NSAppTransportSecurity` 之外）的任何权限键——这一条被 preflight 与审计
双重断言守着。加一个用不到的权限键，会在 App Store 审核（以及用户看隐私报告）时变成
需要解释的东西，本项目不需要。

#### 6.10.9 无障碍

每行一个合并的 VoiceOver 标签：「本地通知，用于后台休息结束提醒，当前状态：已拒绝」；
状态徽章不单独发音（信息已在行标签里）；「前往系统设置」按钮有明确的
`.accessibilityHint`（「将打开系统设置，需手动开启」）。

---

## 七、IPA 静态取证结果

对 `训记.ipa` 仅做静态结构分析，用于还原信息架构，**未复制任何素材、图标或专有资源**。

| 发现 | 内容 |
|---|---|
| 应用类型 | React Native（存在 `main.jsbundle`），bundle 名 `trainnote` |
| 主导航 | 本地化确认 `Training=训练`、`Movement=动作`、`History=历史`、`Me=我的` |
| 首页文案 | `TodayTrain=今日训练`、`OfficialPlan=官方计划`、`PersonalPlan=个人模版`、`NewTraining=新建训练`、`NewCardio=新建有氧`、`TrainVolume=容量`、`addoneset=新增一组` |
| 需去除的社交项 | `Friends=朋友`、`ShareXunji=分享训记`、`shareapp_friend`、`template_share`、`hist_gen_share`，设置项 `friends_hide`「关闭后，首页右上角朋友按钮不再显示」 |
| 官方计划数据 | `assets/src/universalplan_json/` 下 **168 份**计划 JSON |
| 动作素材 | 自带 `movegif` / `back` / `chest` 等分类 GIF |

**关键结论**：计划 JSON 中动作以私有 `key` 引用（如 `benchpress`、`15551201-Dumbbell-Squat_Thighs_withicon`），离开原 App 无法解析；GIF 属原 App 素材。因此官方计划与动作素材均不可复用，动作库改为独立数据源导入。

---

## 八、动作库数据源与许可

数据来源：[hasaneyldrm/exercises-dataset](https://github.com/hasaneyldrm/exercises-dataset)

| 项 | 内容 |
|---|---|
| 条数 | 1324 |
| 中文说明 | `instructions.zh` 与 `instruction_steps.zh`，**中文缺失 0 条** |
| 分类分布 | 手臂 292 / 腿 227 / 背 203 / 核心 169 / 胸 163 / 肩 143 / 小腿 59 / 前臂 37 / 有氧 29 / 颈 2 |
| 器械分布 | 自重 325 / 哑铃 294 / 绳索 167 / 杠铃 154 / 固定器械 81 / 弹力带 54 / 史密斯 48 / 壶铃 41 |

### 许可（务必知悉）

- 数据集**结构与说明文本**：MIT License
- 运动**媒体**（`images/` JPG 与 `videos/` GIF）：版权归 **© Gym visual** — https://gymvisual.com/ ，经许可以 180×180 分发
  - 必须保留署名：`© Gym visual — https://gymvisual.com/`
  - 复用媒体前需自行取得 Gym visual 授权
  - 上游仓库不主张对运动内容或媒体的所有权

代码中已内置常量 `AppResources.exerciseMediaAttribution`，在动作库列表页、动作详情页、我的页均有渲染。

### 关于 TrollStore 自用场景

TrollStore 侧载**绕过 App Store 审核**，因此上述媒体授权不会成为安装阻塞项 —— 这属于你与 Gym visual 之间的许可关系，无人审核。

但请注意：**署名要求与授权范围在法理上依然存在**，绕过审核不等于绕过版权。当前实现已保留署名，属合理做法。若将来要公开分发或上架，仍需另行取得授权。

---

## 九、编译与运行（手动路径）

若不用 Actions，在本机 Mac 上手动操作：

1. Xcode → File → New → Project → iOS → App
   - Product Name: `FitnessApp`
   - Interface: **SwiftUI**
   - Storage: **None**
   - Minimum Deployments: **iOS 16.0**
2. 删除模板生成的 `ContentView.swift` 与 `FitnessAppApp.swift`
3. 把 `FitnessApp/` 下所有目录拖入工程，勾选 **Create groups** 与 **Copy items if needed**
4. 确认 `exerciseLibrary.seed.json` 已加入 **Target Membership**
5. 把 `Resources/ExerciseMedia` 拖入工程，**选择 Create folder references**（蓝色文件夹，必须，否则子目录会被打平）
6. 项目设置 → Info → 添加 `UIUserInterfaceStyle` = `Dark`
7. 项目设置 → Build Settings → `iOS Deployment Target` = **16.0**，`Swift Language Version` = **5.7**

> 更省事的做法：直接用 `Tools/make_project.sh` 走 XcodeGen，`project.yml` 里已把 `ExerciseMedia` 声明为 `type: folder`。

---

## 十、已完成 / 待接入

**已完成**

- 训练首页全部内容与三态逻辑
- 四栏 Tab 骨架 + 220ms 横向淡入
- **动作库（页面 02 完整实现）**：
  - 1324 条本地动作，零网络检索
  - 150ms 防抖搜索，覆盖名称 / 别名 / 主肌群 / 器械 / 次级肌群
  - 10 个肌群 Chip + 高级筛选弹窗（器械 / 负重 / 难度 / 收藏 / 自定义 / 隐藏）
  - 4 种排序：相关度 / 名称 / 难度 / 最近使用
  - 长按菜单：添加到训练 / 收藏 / 编辑 / 隐藏或删除
  - 二次确认删除；导入动作仅可收藏或隐藏，数据层同步拦截
  - `MuscleGlyph` 代码绘制分肌群占位图
  - 新建 / 编辑自定义动作表单
  - 最近使用横向区（上限 6，无历史时不占位）
- **动作详情（页面 03 完整实现）**：
  - 16:9 媒体卡，本地 GIF 循环播放或代码绘制占位图，右下角「演示」标签
  - 收藏星标（荧光绿实心 / 灰描边，乐观更新 + 失败回滚）
  - 动作要点编号列表；空说明时显示「暂未提供动作说明」
  - 涉及肌群卡片，主肌群高亮，点击跳动作库并自动应用该肌群筛选
  - 底部固定「添加到训练」：进行中训练 / 已有计划 / 新建力量训练
  - 参数设置面板：组数、次数范围、休息秒数、热身组，默认值由动作类型推导
  - 更多菜单：编辑（仅自定义）、复制为自定义动作、隐藏或取消隐藏（二次确认）
- **计划详情与编辑（页面 04 完整实现）**：
  - 计划名可点击重命名，单行输入，保存即写入本地 `Plan`
  - 概览卡四项指标：每周训练天数、动作总数、预计时长、上次训练日期
  - 全宽「开始训练」创建 `WorkoutSession` 草稿；无动作时置灰
  - 训练日横向选择器（周一至周日，圆形按钮，荧光绿高亮）+ 独立的多选编辑抽屉
  - 动作列表：序号、缩略图 / 代码绘制肌群图标、名称、`组数 × 次数`、休息、热身标记
  - 拖拽排序（`onMove`）落位即持久化；长按菜单支持上移 / 下移 / 复制配置 / 替换 / 移除
  - 移除动作二次确认，文案说明不影响动作库与历史训练
  - 动作配置页：组数、次数范围（可切固定次数）、休息、热身、**备注**、**递增规则**
  - 仅修改计划内的 `PlanExercise`，动作库条目只读
  - 添加 / 替换动作走动作库挑选模式，带 `planId` 上下文
  - 更多菜单：复制计划 / 导出本地备份（JSON + 系统分享）/ 删除计划（二次确认，不删历史）
  - 空状态「这个计划还没有动作」+「添加第一个动作」
  - 通用 `BottomDrawer` 抽屉容器（24pt 圆角、35% 遮罩、260ms ease-out、下拉关闭）
- **训练执行页（页面 05 完整实现，App 核心页）**：
  - 顶部固定栏：最小化 / 训练名 + 自驱动秒表 / 结束
  - 秒表放在独立子视图里自持 `Timer`，ViewModel 里**没有** `tick`，不会每秒重建整屏动作卡
  - 概览区：已完成动作 / 已完成组 / 总容量；有氧自动换成时长 / 距离 / 消耗；数字变化 180ms 淡入
  - `LazyVStack` 动作卡：名称、目标肌群、上次记录摘要、组表、更多
  - 组表四列（组号 / 重量 / 次数 / 完成），重量次数可点击进编辑态，真 `TextField` + 数字键盘 + 加减步进
  - 圆形勾选灰描边 → 荧光绿实心，`DS.Motion.check` 弹性动画
  - 热身组低对比灰标签、不计入容量；正式组显示荧光绿进度
  - 卡底三按钮：新增一组（复制上一组数值）/ 休息计时 / 动作说明（只读抽屉）
  - 完成一组自动触发组间休息：底部上滑面板、剩余秒数、暂停继续、±15/+30 秒、跳过
  - 倒计时结束播系统音 `1057` + `Haptics.success()`，纯前台实现，不依赖推送
  - 更多菜单：编辑动作配置 / 替换动作（保留已完成组）/ 添加备注 / 删除动作（二次确认）
  - 底部固定「完成训练」→ 完成确认抽屉 → 写 `endedAt` → 训练总结页
  - **草稿实时原子落盘**：每次完成组、改重量次数、增删组、改备注都整份重写 `sessions.json`
  - 终止或最小化后重启，从未结束训练卡直接恢复进度
- **组间休息倒计时（页面 06 完整实现）**：
  - 底部上滑面板，24pt 顶部圆角、深灰底、35% 黑色遮罩、260ms ease-out
  - 顶部动作名 + 「组间休息」，右上角关闭按钮；**关闭只收起，倒计时继续走**
  - 中央 64pt 等宽数字 `01:30`；最后 10 秒转荧光绿，最后 3 秒 1.06 缩放呼吸提示
  - 圆环进度从完整减至 0，底环低对比灰、进度荧光绿；暂停停动画并显示「已暂停」
  - 第一行 `−15 秒` / `+15 秒` / `+30 秒`，走 `PressableButtonStyle` 的 0.97 缩放反馈
  - 第二行「暂停 / 继续」主控 + 「跳过休息」；跳过后停表、关面板、清除状态、撤通知
  - 「设为默认休息时间」数值选择器（30 / 45 / 60 / 90 / 120 / 180 或自定义），
    只写当前计划动作的 `restSeconds`，不回写动作库本体
  - **状态可恢复**：`RestTimerRecord` 落盘 `restTimer.json`（`startedAt` / `durationSeconds` /
    `isPaused` / `remainingSeconds`），剩余值按墙钟现算，切后台 / 被最小化 / 重启后依然正确
  - 结束播 `1057` 系统音 + `Haptics.success()` + 顶部「休息结束，开始下一组」横幅
  - 本地通知为**可选项**，默认关闭，开关在「我的 → 偏好」；拒绝权限完全不影响倒计时
- **完成训练与训练总结（页面 07 完整实现）**：
  - 完成确认抽屉，标题「完成本次训练？」，展示训练名 + 总时长 / 完成动作数 / 完成组数 /
    训练总容量；有氧训练换成距离 + 消耗估算
  - 三个操作：`完成训练`（主）/ `取消` / `继续训练`；后两者只收起抽屉，**不触碰训练草稿**
  - 多行「训练备注」输入框，只有点「完成训练」才随记录一起落盘
  - **完成幂等**：`finishSession` 以 `endedAt == nil` 为守卫，重复点击不覆盖时间、不产生第二条记录
  - 时钟回拨用 `max(endedAt, startedAt)` 兜底，不会出现负时长
  - 全屏总结页，顶部**代码绘制**的勾选图形（`CheckmarkShape`，无图片 / 无第三方插画）
  - 统计卡横向三张，数值 **500ms 从 0 递增**（easeOut，24 帧）；
    开启「减少动态效果」时直接显示最终值，不产生中间帧
  - 有氧补充「平均配速」（`5'30"`），配速是比值故不做递增动画
  - 「动作完成情况」按动作列出完成组数 / 实际重量 × 次数 / 单动作容量，**默认收起**，
    点击展开逐组记录与热身标记
  - 「训练笔记」空态显示「未记录训练笔记」+「添加笔记」，有备注时右上角「编辑」，
    原地编辑，保存即 `updateSessionNote`
  - 底部主按钮「返回训练首页」并刷新最近训练；次按钮「查看历史记录」跨 Tab 定位到本次详情
  - VoiceOver：标题为页面标题、统计卡合并成一句完整语句、动作行朗读展开 / 收起状态
- **历史训练日历（页面 08 完整实现）**：
  - 月历：周一至周日，今天细描边 + 选中日荧光绿圆，可同时成立
  - 上月 / 当前月份 / 下月切换；点标题一键回到本月
  - 标记点：力量荧光绿 / 有氧蓝绿 / 休息日灰，同一天多条并列（超 3 个折叠）
  - 当日时间线：按开始时间升序，卡片显示名称 / 类型 / 时长 / 组数 / 容量，有氧显示距离
  - 空态「当天没有训练记录」+「新增训练」，不留大块空白
  - 分段切换「日历 / 列表 / 统计」，日历为默认；列表按月份倒序 + 累计统计
  - 新增菜单四项：新建力量训练 / 新建有氧训练 / 添加休息日 / 导入本地计划
  - 长按日期 3 项菜单；长按训练卡 3 项菜单（编辑标题 / 复制为新训练 / 删除）
  - 删除二次确认，只删当前本地记录
  - 休息日独立建模（`RestDay` + `restDays.json`），同一天只保留一条
  - 日期格 VoiceOver 朗读「日期 + 训练数量 + 选中状态」
- **历史训练详情（页面 09 完整实现）**：
  - 顶部栏：返回 / 「训练详情」/ 更多三点；从历史日历或训练首页的最近训练卡均可进入
  - 摘要卡：训练名称、类型标签、完成日期 · 开始时间、总时长；力量显示总组数 / 总容量 / 动作数，
    有氧显示总组数 / 距离 / 平均配速 / 消耗估算
  - **不做递增动画**（页面 07 才做），旧记录不做表演性动效
  - 「动作记录」按**训练完成时的动作顺序**排列，顺序常量收在 `HistoryRecordOrder.detailDefault`
  - 动作卡：名称 / 主肌群 / 完成组数 / 该动作总容量；点击展开逐组显示重量次数、热身标记、完成时间、单组备注
  - 热身组不计入容量（沿用页面 05 契约）；只有目标没有完成的组显示「未完成 · 目标 N-M 次」
  - **只读契约提升为可探测类型** `HistoryEditPolicy`：已完成的白名单恒为 `[.title, .note]`，
    `setData` 永不入列，探针带回归断言
  - 更多菜单四项：编辑标题 / 编辑备注 / 复制为新训练草稿 / 删除本次记录，均走底部抽屉
  - 标题与备注编辑：单行 `TextField` / 多行 `TextEditor`(+`@FocusState` 延迟聚焦)，
    **标题空值不可保存**，备注可清空；保存即 `rename` / `updateSessionNote`
  - 「复制为新训练草稿」：复制动作顺序与目标组数 / 重量 / 次数，清空完成状态，重生成每组 id，
    不复制备注 / 距离 / 消耗 / `planID`；训练名后缀不叠加；创建后直接跳训练执行页
  - 删除二次确认，文案明示「只删除本机这一条训练记录，无法恢复」，
    返回历史页后通过 `historyReloadToken` 强制重建，日历标记与统计同步刷新
  - **动作不可用不崩页**：三级名称兜底（中文别名 → 原名 → id → 「未知动作」），
    区分「已隐藏」（可逆，仍给媒体与详情入口）与「已不可用」（仅保留历史数据）
  - 底部训练笔记卡，空态「未记录训练笔记」；笔记区可选中复制
  - 每组完成时间过滤 1970 哨兵值与坏时钟（阈值取 Cocoa 纪元 2001，不是 1970）
  - 所有写入仅经 `FitnessRepository`，每步操作给一句 toast 反馈
  - 不包含分享、社交、公开链接、点赞、评论
- **训练统计（页面 10 完整实现）**：
  - 顶部栏：返回 / 「训练统计」/ 时间范围按钮；范围六选一（近 7 天 / 近 30 天 / 本月 /
    近 3 个月 / 今年 / 自定义），选择后立即重算本地聚合
  - 范围归一成半开区间 `[start, end)`，**终点取明天 00:00**，不漏 `23:59:59.5` 这类带小数秒的记录
  - 摘要区四张紧凑卡：训练次数 / 总训练时长 / 总完成组数 / 总训练容量；含可计时追加总距离
  - **「—」与「0」分开**：算不出来显示「—」，算出来是 0 才显示 0（`StatsMetric.value: String?`）
  - 「训练频率」柱状图：横轴连续日期（**补空桶**）、纵轴次数；力量与有氧分色，
    当前选中柱为荧光绿；点击柱子读出该日次数与时长
  - 「训练容量趋势」：平滑折线（≥8 点时叠加柱），二次贝塞尔而非三次样条；
    可按全部 / 肌群 / 单个动作筛选；**无数据时显示空状态，不画零值折线**
  - 「常练动作」：按完成组数降序前 5，显示名称 / 组数 / 累计容量；三级稳定排序
    （组数 → 容量 → id），点击进入动作历史趋势子页
  - 「训练部位分布」：按主肌群统计完成组数，**横向进度条而非饼图**，
    每行含肌群名 / 组数 / 百分比 / 代表色；11 色固定查表且全部避开强调绿
  - 「数据管理」页：导出 JSON 备份（系统分享面板）/ 导入备份（`.fileImporter` 限 `.json`，
    **先校验完再写盘**）/ 清除全部训练记录（二次确认，文案明示不动动作库与设置）
  - 导入三条合并策略：保留本机（默认，破坏性最小）/ 覆盖同名 / 全部替换；按 id 去重保留先出现的那条
  - 全部聚合走纯本地函数（`WorkoutStatistics.swift` 零 SwiftUI 引入），
    `StatsCache<Value>` 单条目缓存，**缓存键由起止时间戳拼成**，
    自定义范围被改动时天然失效；数据变化后由 `onDataChanged` 触发重算
  - 手绘图表（未引入 Swift Charts），每根柱子是独立视图，各自带 VoiceOver 标签与点击目标；
    窄屏时降级为列表，与图表共用同一份数据
  - 图表配文字摘要，如「近 30 天完成 12 次训练，共 18 小时」；无数据时摘要同样成立
  - 不包含好友对比、排行榜、云同步；导出分享的是**用户自己的备份文件**，不经过服务端
- **动作历史趋势（页面 11 完整实现）**：
  - 两个入口：统计页「常练动作」点某个动作；动作详情页右上角菜单「历史记录」
  - 顶部栏：返回 / 动作名 / 时间范围菜单；范围四档（近 30 天 / 近 3 个月 / 近一年 / 全部记录），
    **与统计页的六档不是同一套**（日历区间对「这个动作练得怎么样」没有意义）
  - 摘要卡五格两列：累计训练次数 / 累计完成组数 / 最高单组重量 / 估算 1RM / 最近训练日期；
    算不出来的字段显示「—」，不显示 0
  - 「最高重量趋势」折线图：按**训练日**聚合（不按月、不补空日），仅正式组，
    点数据点出详情条（日期 / 重量 × 次数 / 训练名）
  - 「单次训练容量趋势」柱状图：`重量 × 次数` 按次汇总，带峰值读数，可切 kg / lb
  - 单位切换**只改展示值**：不重新读盘、不重算聚合、不回写记录（`TrendWeightUnit` 里没有 `mutating`）
  - 「最近记录」10 条倒序：日期 / 训练名 / 最佳组 / 总组数 / 容量；整行可点进历史训练详情
  - 1RM 用 Epley 公式，但 **超过 12 次的组不参与估算**（否则 20 次 60 kg 会被算成 100 kg）
  - 「开始练这个动作」：按**最近一次**记录预填（不自动加重），确认后建草稿进执行页；空状态时按钮仍在
  - 空状态只有一句「还没有这个动作的训练记录」，不是四张卡各空一次
  - 动作名三级兜底（库名 → 快照名 → id → 「未知动作」），动作被删除后趋势仍可看
  - 动态字体达到无障碍档位时两张图自动降级为数据列表，与图共用同一组数据点
  - 全部聚合在 `ExerciseTrendDetail.swift`（零 SwiftUI 引入），可被 Python 逐字推演
- **身体数据（页面 12 完整实现）**：
  - 入口：我的页「身体数据」卡片（整卡可点），从 `ProfileTab` 的独立 `NavigationStack` 推入
  - 顶部栏：返回 / 「身体数据」/ 新增（+）；新增打开底部录入面板
  - 摘要卡：最近一次记录的体重 / 体脂率 / 日期；缺失字段显示「未记录」而非 0；
    底部显示与上一条有效记录的变化值（「较上次 −0.6 kg」）
  - 单位切换 kg / lb 与 cm / in，**只转显示值**，内部统一存 kg 与 cm（`BodyWeightUnit` / `BodyLengthUnit` 里没有 `mutating`）
  - 分段控件「趋势 / 记录」，趋势默认；趋势页七个指标 Chip（体重 / 体脂率 / 胸围 / 腰围 / 臀围 / 大腿围 / 上臂围）
  - 折线图：横轴日期、纵轴按当前指标自动设范围 + 留上下边距；点数据点出详情；
    不足两条记录显示「记录更多数据后可查看趋势」空状态
  - 图表下四格：最新值 / 变化值 / 最低值 / 最高值
  - 记录页按日期倒序的测量卡片；点击编辑，左滑 / 长按删除（二次确认）
  - 录入面板：日期 + 七个数值字段 + 备注，全部可选，**至少一个有效值才能保存**；
    范围校验体重 20–400 kg、体脂率 1–70%、围度 20–300 cm
  - **本地自然日为唯一键**：仓储层按天去重，同一天已有记录时询问「覆盖当天记录 / 取消」
  - 全部聚合在 `BodyData.swift`（零 SwiftUI 引入），可被 Python 逐字推演
- **我的（页面 13 完整实现）**：
  - 大标题「我的」+ 个人概览卡（代码绘制首字母头像 / 昵称 / 已使用天数），点击进个人资料编辑
  - 没昵称显示「设置昵称」；个人资料独立存 `profile.json`（`UserProfile`，协议 +2 方法）
  - 数据摘要一行：最近体重 / 累计训练次数 / 累计训练时长，无记录显示「—」不伪造
  - 三组菜单：训练与身体（身体数据 / 我的计划 / 动作收藏 / 训练偏好）、数据（本地数据管理 / 导入备份 / 导出备份）、应用设置（重量单位 / 长度单位 / 默认休息时间 / 声音 / 触感 / 深色外观 / 减少动态效果）
  - 菜单项带 SF Symbol + 标题 + 摘要 + chevron；子页 / 抽屉进入
  - 数据组复用页面 10 的 `WorkoutDataManagementView` + `WorkoutBackup`（导出 / 导入 / 合并策略）
  - 声音 / 触感是**真正生效**的独立开关（`Haptics` 与 `RestAlertSound` 各带 guard）；单位与页面 12 共用一把键
  - 底部显示 App 名「本地健身」、数据库版本 v1、动作库版本 v1.0、媒体署名；不出现原 App 名 / 第三方品牌
  - 全部设置写 UserDefaults（`ProfileSettings` 集中键与默认值），开关即时写入
  - 全部菜单 / 摘要给 VoiceOver 标签，语义化字体随动态字体增高
- **训练偏好（页面 14 完整实现）**：
  - 入口：我的 → 训练偏好；三组（训练记录 / 计时器 / 训练流程）+ 底部「恢复默认」危险操作
  - 训练记录组：默认组间休息时间（30/45/60/90/120/180 + 自定义抽屉）、自动复制上次记录、完成一组后自动开始休息、显示训练容量
  - 计时器组：倒计时提示音 / 触感反馈 / 倒计时最后 10 秒提醒 / 倒计时数字样式（普通 / 大号单选抽屉）+ 保留的「休息结束通知」
  - 训练流程组：完成当前动作后自动定位下一动作 / 新增组时复制上一组数值 / 默认显示热身组 / 最小化训练后保留计时器
  - **每个开关真正生效**：显示容量 → 概览隐藏总容量但统计照算；自动休息 → 完成组不自动开倒计时；自动复制 → 草稿不预填历史重量；最后 10 秒提醒 → 不再转荧光绿；数字样式 → 64/84pt；自动定位 → 完成整卡滚动到下一张；复制上一组 → 新组重量从 0 起填；隐藏热身组 → 组表隐藏热身行；最小化保留计时器 → 关闭后最小化停掉休息倒计时
  - 「自动复制上次记录」复用页面 13 的 `prefillWeights` 键（同一概念不落两把键），只是改 UI 文案
  - 恢复默认：先列 12 项将被重置的清单，二次确认后才写回；只重置训练偏好，不碰单位 / 深色 / 减动效，更不碰训练数据
  - 开关 `accessibilityValue` 统一朗读「已开启 / 已关闭」；单选抽屉带 `.isSelected`；危险操作有无障碍提示
  - 新增纯值枚举 `CountdownNumberStyle` 与 `TrainingPreferenceResetItem`，可被 Python 逐字推演
- **我的计划（页面 15 完整实现）**：
  - 入口：我的 → 我的计划；纯本地计划管理，不展示官方计划 / 公开计划 / 好友计划 / 社区内容
  - 顶部栏：返回 / 「我的计划」/ ＋ 菜单（新建力量计划、导入本地计划备份）
  - 搜索框按名称实时筛选；排序四选一（最近使用 / 最近创建 / 计划名称 / 训练天数），带 id 兜底的稳定排序
  - 计划卡片：名称 / 每周训练天数 / 动作数量 / 预计时长 / 上次训练日期；`LazyVStack` 承载长列表
  - 点击卡片 → 计划详情与编辑；三点菜单（开始训练 / 编辑 / 复制计划 / 删除计划）
  - 复制计划自动命名「原名称（副本）」，防「（副本）（副本）」叠加，与页面 04 / 首页复制走同一个纯函数
  - 删除二次确认，只删计划不删历史训练；长按进入多选，批量删除（二次确认）+ 批量导出本地备份
  - 空状态「还没有训练计划」+「新建第一个计划」；无搜索「没有匹配的计划」
  - 批量删除进仓储协议（52 → **53** 方法 `deletePlans(ids:)`）；多计划备份 `PlanBackup`（`fitness-plans-backup`）支持批量导出与导入
  - 从「我的计划」下钻计划详情 / 动作配置 / 训练执行页 / 训练总结，动作选择器三种上下文齐备
  - 顺带修复页面 07 遗留的跨作用域错误（`TrainingTab` 访问 RootView 成员 → 改为 `onOpenHistory` 回调）
  - 卡片 VoiceOver 标签 + 排序 Chip `.isSelected` + 批量按钮无障碍标签；语义化字体随动态字体增高
- **权限管理（页面 51 完整实现）**：
  - 入口：应用设置 → 隐私 → 权限管理；只在首次触发相册 / 本地通知功能时才弹系统请求
  - 只展示两项实际用到的权限：本地通知（后台休息结束提醒）、相册访问（仅设置本地头像）
  - 四态完整区分：未授权 / 已授权 / 已拒绝 / 受限制，且每态都有独立的处置方式
  - 「前往系统设置」**只在已拒绝或受限制时出现** —— 未授权态引导去设置是错的（`needsSystemSettingsLink` 显式 switch）
  - 拒绝权限不影响核心功能：「不开权限会怎样」逐项给出降级说明（前台倒计时照常、代码绘制头像照常）
  - **页面只读不申请**：`PermissionCenter` 里 `requestAuthorization` 出现次数为 **0**，反规格断言守着
  - 回到前台经 `scenePhase` 重读（从设置 App 切回来 `onAppear` 不触发）
  - 不申请定位 / 通讯录 / 蓝牙 / 麦克风 / 健康数据 / 网络；不上传权限信息、无第三方登录、无隐私追踪
  - `Info.plist` 仅新增 `NSPhotoLibraryUsageDescription` 一个键
- `FitnessRepository` 协议（**53 方法**）+ JSONFile 实现 + 内存桩
- **iOS 16.0 兼容**（实机目标 iOS 16.3.1），全部 iOS 17 专属 API 已替换
- 按压反馈、骨架屏、空状态、进度条、抽屉、删除二次确认
- 动态字体（全量语义化字体）、无障碍标签、小屏大屏自适应
- 动作媒体全量打包（2648 个文件）

**待接入（回调已预留）**

| 回调 | 目标页面 | 现状 |
|---|---|---|
| `onStartTraining` | 训练执行页 | ✅ 已接入：计划详情「开始训练」建草稿后直接进入 |
| 未结束训练卡 | 训练执行页 | ✅ 已接入：`.inProgress` 分支直接回到 `sessionDraft(sessionID)` |
| `onNewStrength` | 力量训练编辑页 | 已能建草稿并进入执行页，尚未做独立的「自由训练编辑」前置页 |
| `onNewCardio` | 有氧训练编辑页 | 未接入 |
| `onOpenSession`（历史列表 / 日历卡片） | 历史详情 | ✅ 已接入：推入 `HistorySessionDetailView` |
| `onOpenSession`（训练首页最近训练） | 历史详情 | ✅ 已接入：`TrainingRoute.historyDetail(UUID)`，与历史 Tab 各自独立入栈 |
| `onOpenCalendar` | 日历 / 计划 | 未接入 |
| `onOpenMore` | 更多设置 | 未接入 |
| `onAddToWorkout` | 从动作加入训练（页面 02 长按菜单第 1 项） | 未接入 |
| 计划详情 | **页面 04** | ✅ 已接入 |
| 训练执行页 | **页面 05** | ✅ 已接入 |
| 训练总结页 | **页面 07** | ✅ 已接入：完成抽屉三个操作 + 总结页 + 跨 Tab 定位历史详情 |
| 组间休息倒计时 | **页面 06** | ✅ 已接入：完成一组自动弹出 + 卡片「休息计时」手动开启 |
| 历史训练日历 | **页面 08** | ✅ 已接入：月历 + 当日时间线 + 列表 + 统计入口 + 新增/长按菜单 |
| 历史训练详情 | **页面 09** | ✅ 已接入：历史 Tab 推入 + 训练首页最近训练卡推入，含四个抽屉与 toast |
| 训练统计 | **页面 10** | ✅ 已接入：历史页「统计」分段进入，含四张卡 + 三图一表 + 数据管理 |
| 动作历史趋势 | **页面 11** | ✅ 已接入：两处入口（统计页常练动作、动作详情页「历史记录」），下钻历史训练详情与训练执行页均在同一条栈内 |
| 身体数据 | **页面 12** | ✅ 已接入：我的页「身体数据」卡片 → `ProfileRoute.bodyData`；保存 / 删除后经 `profileReloadToken` 刷新我的页摘要 |
| 我的 | **页面 13** | ✅ 已接入：`ProfileTab` 独立 `NavigationStack`，六个子路由（个人资料 / 我的计划 / 动作收藏 / 训练偏好 / 数据管理）+ 直接导出 / 导入 |
| 训练偏好 | **页面 14** | ✅ 已接入：`ProfileRoute.trainingPreferences` → `TrainingPreferencesView`；三组 12 项设置全部接进训练执行页 / 组间休息面板 / 草稿预填 |
| 我的计划 | **页面 15** | ✅ 已接入：`ProfileRoute.planList` → `PlanListView`；下钻计划详情 / 动作配置 / 训练执行页 / 训练总结，含动作选择器与批量删除 / 导出 / 导入 |
| 「导入本地计划」 | 计划选择流程 | 仅占位提示：需先在「训练」页选计划再开始，未做从历史页直接选计划的流程 |

**菜单 03-A「添加到训练」尚未实现**：页面 03 的底部按钮目前走的是系统 `sheet`，
还没有换成 `BottomDrawer`，也还缺「新建个人计划并添加」这一项。
`BottomDrawer` 与 `DrawerActionRow` 已经就位，可以直接复用来改造。
另外 `ExercisePrescription.default(for:)` 目前仍由 `loadKind` 推导，
尚未改成规格要求的固定 3 / 8 / 12 / 90 / 关。

---

## 十一、已知风险

| 风险 | 说明 |
|---|---|
| IPA 体积大 | 含 126 MB GIF，成品 IPA 预计 130 MB 左右。若嫌大，可删 `Resources/ExerciseMedia/videos` 并改 `ExerciseAnimationView` 走占位分支 |
| GIF 内存占用 | 动作库列表用 JPG 缩略图，不进 GIF；仅详情页加载单张 GIF，内存可控 |
| 首启导入耗时 | 首次启动要解析 1.4 MB 种子 JSON 并写一次 `exercises.json`；之后走缓存，不再重复导入 |
| 单文件写入 | 五个集合各为一个 JSON 文件，训练记录上千条后 `sessions.json` 会变大。若到瓶颈，改按年月分片即可，协议不变 |
| 数据无加密 | 明文 JSON 存在 Application Support。属本地自用场景，未加 SQLCipher 之类保护 |
| 动作库全量常驻内存 | 1324 条动作一次性读进内存做检索。单条约 2 KB，合计约 2.6 MB，可接受；到万条级别需改为分页或建索引 |
| 别名表需人工维护 | `ExerciseAliases.rules` 是我方维护的词表，新增动作若命名不含既有规则关键词，就不会有中文别名，只能靠英文名搜到 |
| 历史记录读取上限 500 条 | `HistoryViewModel.load()` 一次取 500 条训练记录，日历与列表都基于这一份数据。按每周 4 练、两年内不会触顶；超过后更早的记录不会显示。到瓶颈时改按年月分片查询即可，协议不变 |
| 有氧训练的独立编辑页未做 | 从历史页「新建有氧训练」会建一条 `kind == .cardio` 的草稿并进入训练执行页，但距离 / 配速的专门编辑界面尚未实现 |
| 补记训练的时间语义 | 补记过去的日期时，`startedAt` 取「点按时刻 + 选中日期的年月日」，因此补记一条昨天的训练、今天才点完成，时长仍会把这段跨度算进去。这是既有 `durationSeconds` 定义的必然结果；若要精确补记，需要给 `WorkoutSession` 增加独立的「实际训练时段」字段 |
| `onChange(of:)` 单参形式 | `CustomExerciseEditor` 与 `ExercisePrescriptionSheet` 用的是 iOS 16 单参重载，iOS 17 起废弃但**仍可用**。预检会以 `[warn]` 提示，不阻断构建 |
| 详情页持有动作副本 | `ExerciseDetailViewModel` 在初始化时拷入 `item`，不是每次从仓储重读。这是有意的 —— 避免详情页在用户操作途中被外部改动覆盖。代价是若其它页改了同一条动作，详情页要重建才会同步 |
| `.navigationBarHidden` 已废弃 | `ExercisesTab` 用它隐藏动作库系统导航栏，iOS 16 正常，iOS 17 起废弃。预检会提示；提升最低版本时改为 `.toolbar(.hidden, for: .navigationBar)` |
| 休息通知的权限只申请一次 | iOS 不允许重复弹窗。用户第一次拒绝后，再拨开关只会提示去系统设置，不会二次弹窗。这是系统行为，不是实现缺陷 |
| 休息计时依赖系统时钟 | 剩余值由 `Date()` 墙钟推导。用户手动改系统时间会让倒计时跳变。相比「切后台就丢」，这个取舍是划算的 |
| 页面 06 之后可断言项变化 | 页面 05 的审计脚本曾断言「源码不含 `UNUserNotificationCenter`」。页面 06 引入了**本地**通知，该断言已放宽为「不含推送服务（APNs / 远端通知）」。仅本地 `UserNotifications` 不算违规 |
| 历史定位依赖记录已落盘 | 「查看历史记录」先 `fetchSession` 探测、再推详情。若记录确实不存在（例如写盘失败），停留在历史列表并消费掉定位请求，不弹错误提示。这是有意为之：查不到就不该把用户带进空页面 |
| 跨 Tab 定位用了 `.id()` 重建 | 训练 Tab 在栈底、返回时不走 `onAppear`，因此用 `reloadToken` + `.id()` 强制重建首页。代价是首页所有 `@State`（含滚动位置）会被重置。首页本身是短列表，可接受；若将来首页状态变重，应改为只刷新数据源 |
| 「查看历史记录」会直接推入详情 | 规格要求「跳转历史页并定位到本次训练详情」，因此实现为直接入栈详情页，列表高亮仅作为返回后的锚点。若期望的是「只定位列表不推详情」，改 `HistoryTab.handleHighlight` 里的 `pushDetail(target)` 即可 |
| 历史详情不提供组数据编辑 | 规格明令禁止（避免统计失真），由 `HistoryEditPolicy.allowedFields` 强制。用户要重练只能走「复制为新训练草稿」，这条路径会丢掉旧备注与有氧量，是有意为之 —— 那属于旧成绩，不是新目标 |
| 详情页删除后靠 `.id()` 重建历史页 | `NavigationStack` 弹栈不触发 `onAppear`，所以用 `historyReloadToken` + `.id()` 强制重建。代价是历史页所有 `@State`（含日历滚动位置、选中日期）会重置。若将来历史页状态变重，应改为细粒度刷新而不是重建 |
| 隐藏动作在历史里的媒体入口仍在 | `canShowMedia` 对 `.hidden` 返回 `true`（媒体文件仍在 Bundle）。若后续希望隐藏动作在历史里也完全不露出媒体，改这个属性的返回值即可，无需动视图层 |
| 单组备注在历史详情只读 | 规格只允许编辑训练标题与备注，单组备注属于组数据，同样不可改。它随「复制为新训练草稿」一起被复制，因为那属于目标组配置 |
| 统计页最多取 500 条训练记录 | `WorkoutStatisticsViewModel.sessionFetchLimit = 500`，与历史页同一上限。按每周 4 练、两年内不会触顶；超过后更早的记录不进统计。到瓶颈时改按年月分片查询即可，聚合函数签名不变 |
| 统计的日期轴依赖设备时区 | 范围与分桶都用 `Calendar.current`。用户改时区后，同一批记录会落到不同的自然日里。「近 7 天」的分界也会随之平移。自用场景下未做固定时区，若需要可把 `Calendar` 换成固定 `TimeZone(identifier: "Asia/Shanghai")` 的实例 |
| 容量筛选器不缓存动作名 | 每次重算筛选器都要 `fetchExercises(includeHidden: true)` 里查名字。动作库 1324 条在内存里，成本可接受；若将来动作库改成分页，这里要补一个 `[String: String]` 名字缓存 |
| 备份文件无版本迁移代码 | `WorkoutBackup.currentVersion = 1`，解码时版本不符会明确报错（`unsupportedVersion`）而不是尽力解析。目前只有 v1，等真有 v2 时才需要写迁移分支 |
| 导出分享与「离线无社交」的边界 | 导出用 `UIActivityViewController`，是本项目唯一使用分享面板的地方。分享对象是**用户自己刚生成的 JSON 备份文件**，不涉及成绩、排行或任何服务端。审计脚本把这条边界写成了断言：分享 API 不得出现在统计页本体，只允许在数据管理页出现一次 |
| 清除操作的回调是「整页重建」 | 清除后 `RootView.historyReloadToken` 变化，历史页与统计页靠 `.id()` 重建。代价是页面 `@State`（含选中的时间范围、滚动位置）会重置。统计页重建后会回到默认的「近 30 天」 |
| 趋势页同样受 500 条读取上限约束 | `ExerciseTrendDetailBuilder.sessionFetchLimit = 500`，与历史页、统计页同一上限。超过后更早的训练不进趋势；「全部记录」这一档因此是「本机最近 500 条里的全部」，不是字面意义的全部 |
| 趋势页的日期轴依赖设备时区 | 与统计页同一个取舍：范围用 `Calendar.current`。改时区后「近 3 个月」的分界会平移 |
| 1RM 是估算值 | Epley 公式在 1–10 次区间误差最小，但仍是估算。超过 12 次的组直接不参与（返回 nil）而不是给一个高估值，代价是高次数训练者的「估算 1RM」会显示「—」 |
| 趋势页的建议不自动加重 | 「开始练这个动作」的建议重量沿用上次最高组，不做渐进超负荷。想要自动加重的用户需要自己在执行页改 |
| 动作栏与历史栏各有一套趋势路由 | `ExerciseRoute.exerciseTrend` 与 `HistoryRoute.exerciseTrend` 同名不同型：`navigationDestination` 只认注册在自己这条栈上的类型，混用会找不到注册者。代价是新增下钻目标时要**两边都注册**（本次补了 `historyDetail` / `sessionDraft` 两条） |
| 容量图未做点击交互 | 规格只要求折线图「点击数据点看详情」，柱状图只要求单位切换。所以柱子不是 `Button`，也就没有选中态；单位切换的可见效果落在峰值读数上 |
| 身体数据同样受 500 条读取上限约束 | `BodyDataBuilder.fetchLimit = 500`，与历史 / 统计 / 趋势页同一上限。超过后更早的测量记录不进趋势与记录列表 |
| 身体数据的日期轴依赖设备时区 | 趋势点按记录日期排序、同日唯一键用 `Calendar.current`。改时区后「同一天」的判定与横轴排布会平移。自用场景未做固定时区 |
| 围度输入范围是自定常量 | 规格只给了体重 20–400、体脂率 1–70 两个例子，围度的 20–300 cm 是项目自选的范围。若用户有超出范围的特殊体型，会触发校验提示 |
| 身体数据页用 List 承载趋势与记录 | 记录分段需要 `.swipeActions`（左滑删除），而它只在 `List` 里可用。代价是趋势图 / 摘要卡都要以 List 行承载，且不能把多行内容包进 `@ViewBuilder var` 再引用（List 不展平嵌套 TupleView） |
| 页面 13 已统一单位键 | 页面 12 时期「身体数据」与「我的」各持一把重量单位键的问题，在页面 13 交付时解决：两边都指向 `preference.bodyWeightUnit` / `preference.bodyLengthUnit`，改一处全 App 生效 |
| 「我的计划」「动作收藏」是只读列表 | 这两个子页只展示数据、不深链进计划编辑 / 动作详情，新建与编辑仍在「训练」「动作」Tab。这是页面 13 的有意收窄——把完整的计划编辑器 / 动作详情再复制一份到 Profile 栈，收益远小于维护成本 |
| 深色外观是固定深色的开关 | 本应用深色锁定，`深色外观` 开关只持久化偏好，不改配色（浅色模式需要整套浅色令牌，不在本页范围）。界面文案已注明「界面固定为深色模式」 |
| 「减少动态效果」「默认休息时间」目前只持久化 | 减少动态效果与默认休息时间写进 UserDefaults 并即时生效，但尚未接线到所有动画 / 新建动作的默认值（`ExerciseDraft.restSeconds` 仍是硬编码 90，页面 14 没动它）。接线是后续页面的增量工作，键名已固定，不破坏兼容 |
| 个人资料的「开始使用」是首次进入「我的」时刻 | `startedAt` 在第一次读到空资料时记为当天，不是严格意义上的「安装时刻」。若要求精确到安装日，改在 App 入口首次启动时写入即可 |
| 「隐藏热身组」只隐藏行、不改模型 | 页面 14「默认显示热身组」关闭时，热身组行从组表隐藏，但热身组仍留在会话模型里、仍计入组数统计（`completedSetCount` 含热身组）。若希望隐藏时连统计也排除热身组，需改 `SetEntry.volume` / 聚合的契约，是数据层改动而非视图层 |
| 训练偏好设置即时生效，但已打开的页面不刷新 | 开关写 UserDefaults 即时生效，但训练执行页 / 休息面板是在渲染时读 `ProfileSettings` 的值。已在执行页里的训练不会因用户中途去改偏好而实时重绘（例如已在倒计时中改「最后 10 秒提醒」不会立刻变色），下一次进入时生效。这是「偏好读一次、不订阅变化」的有意取舍 |
| 「自动复制上次记录」与页面 13 键合并的语义代价 | 页面 13 占位页把该键叫「重量预填建议」，页面 14 规格改叫「自动复制上次记录」，两者共用 `prefillWeights` 键。代价是旧文案下的用户若按「预填建议」的理解关闭了它，页面 14 会显示成「自动复制上次记录 = 关」。语义上等价，无数据风险 |
| 复制计划命名从「名字 2」改为「（副本）」 | 页面 04 时期的 `duplicate(planID:)` 生成「名字 2」，页面 15 规格要求「原名称（副本）」，本轮统一改成后者。代价是**老用户之前复制出的计划名仍是「名字 2」**，不会被追溯改名；只有新复制动作走新命名。纯展示层差异，无数据风险 |
| 计划导入不校验动作是否存在 | 导入计划备份时只校验文件格式 / 版本，不逐条核对 `exerciseID` 是否仍在动作库里。动作被删后，导入的计划详情页会走三级名称兜底（与页面 09 同一套），不会崩页 |
| 多计划备份只有 v1 | `PlanBackup.currentVersion = 1`，与 `WorkoutBackup` 同口径：版本不符明确报错而非尽力解析。将来格式变化时再加迁移分支 |
| 页面 15 是「我的计划」从只读升级为完整管理页 | 页面 13 时期「我的计划」是只读列表（新建 / 编辑在训练 Tab），页面 15 把它升级为完整管理页（可进入计划详情 / 开始训练 / 复制 / 删除 / 批量操作）。README 里页面 13 那条「只读列表」的风险描述已过时，以页面 15 为准 |

---

## 十二、视觉还原的边界

静态 IPA 分析能可靠还原**导航结构**与**功能分区**。以下无法从静态包严谨还原，需运行截图或录屏：

- 精确间距与卡片内边距
- 实际字体族与字重
- 动画时长与缓动曲线
- 深色模式下各层级的真实灰阶

当前配色与尺寸是本项目的独立设计决策，不是对原 App 的复刻。

---

## 十三、数据存储位置与备份

`JSONFitnessRepository` 把数据写在 App 沙盒的：

```
<AppSandbox>/Library/Application Support/FitnessData/
├── plans.json              训练计划
├── sessions.json           训练记录
├── exercises.json          动作库（首启从种子导入，1324 条）
├── recentExercises.json    最近使用的动作（上限 30 条）
├── measurements.json       身体数据
├── restDays.json           休息日标记（页面 08 新增，一天最多一条）
└── restTimer.json          组间休息状态（全局一条；结束或跳过后整个文件被删除）
```
- 用 Application Support 而非 Caches：**Caches 会被系统在空间紧张时清理**，用户数据不能放那里
- 全部写入走 `Data.write(options: .atomic)`，中途崩溃不会留下截断文件
- 日期统一 `ISO8601` 编码，便于直接读改 JSON
- Info.plist 已开 `UIFileSharingEnabled` 与 `LSSupportsOpeningDocumentsInPlace`，可从「文件」App 直接访问沙盒 Documents

### 页面 10 的备份边界：导出范围 == 清除范围

导出 JSON 备份时**只导训练记录**（`sessions.json` 里 `endedAt != nil` 的那些），
清除时也只清训练记录。两侧范围刻意保持一致，因为这两个操作是一对：
用户「先备份、再清除」之后，理论上应该能通过「导入」把状态还原回来。
若导出多带了设置、而清除又不动设置，这个闭环就不成立。具体清掉与保留什么：

| 清除范围（`WorkoutDataPolicy.clearedScopes`） | 保留不动 |
|---|---|
| `sessions` 训练记录 | `plans` 训练计划 |
| `restDays` 休息日标记 | `exercises` 动作库与自定义动作 |
| `restTimer` 进行中的组间休息 | `measurements` 身体数据 |
| | `recentExercises` 最近使用 |
| | `isExerciseSeeded` 种子导入标记 |

`WorkoutDataPolicy.preservedItems` 是一份 5 项清单，二次确认的文案直接由 `confirmMessage`
拼出来，保证「说了不清什么」和「实际不清什么」出自同一处常量，不会各自漂移。

**改字段时的注意**：旧 JSON 缺字段会按 `Codable` 规则报错。`ExerciseLibraryItem` 已用自定义
`init(from:)` 对每个字段做 `try?` + `??` 兜底，并在缺字段时由 `target` / `equipment` 推导出
`primaryMuscle` / `difficulty`，因此**旧版 `exercises.json` 升级后仍可解码**。
其它模型改字段时请照此处理，或在 `Models.swift` 里给默认值。

**种子重导入不会覆盖用户数据**：`seedExerciseLibraryIfNeeded()` 会先取出已存在的导入条目 id 集合，
只追加新增条目，**已存在条目的收藏 / 隐藏状态原样保留**，不会被重置。

**`restDays.json` 为什么与 `sessions.json` 分开**：休息日本质上不是「一次训练」。
若给它加一个 `WorkoutSession.Kind` 分支，休息日就会出现在 `fetchRecentSessions()` 的结果里，
于是「最近训练」「总容量」「总里程」「已完成训练数」每个聚合点都得额外过滤，
漏掉任何一处都会显示错误数字。独立成文件后，两边的聚合彻底不相干，
也各自拥有独立的演化空间（`RestDay` 目前只有 `id` / `date` / `note` 三个字段）。
`RestDay.init(from:)` 同样对每个字段做了 `decodeIfPresent ?? 默认值` 兜底。

**`restTimer.json` 为什么是单个对象而不是数组**：全局同时只可能存在一次组间休息，
在数组里翻找既没必要、也容易留下多条陈旧记录。它是**临时状态**而非用户数据，
所以 `clearRestTimer()` 与 `deleteAllData()` 都直接删除文件，而不是写入空值。

**页面 09 没有新增任何存储文件**：历史训练详情的全部读写都落在既有的 `sessions.json` 上，
用的也是既有的 47 个协议方法（`fetchSession` / `fetchExercises(includeHidden:)` /
`save(session:)` / `updateSessionNote` / `delete(sessionID:)`）。
「复制为新训练草稿」写的是新增一条 `WorkoutSession`，不是新集合。
故本页的改动不涉及 `FitnessRepository` 协议，也不涉及文件迁移。

**休息状态损坏不影响使用**：`readSingle()` 对解码失败返回 `nil`（而不是抛错），
退化成「当前没有休息」，不会因为一条临时状态把整页读崩。
`RestTimerRecord.init(from:)` 也对每个字段做了 `decodeIfPresent ?? 默认值` 兜底。

---

## 十四、四层门禁

这台机器**没有 Swift 编译器**（Windows），改完代码无法 `swift build` 验证。
所以每个页面都过四层静态门禁，缺一不可：

| 层 | 脚本 | 页面 07 结果 | 页面 08 结果 | 页面 09 结果 | 页面 10 结果 | 页面 11 结果 | 页面 12 结果 | 页面 13 结果 | 页面 14 结果 | 页面 15 结果 | 页面 51 结果 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 预检 | `Tools/preflight.py` | 36 个 `.swift`；协议 44 方法 | 38 个 `.swift`；无 iOS 17 / 16.4+ API；**协议 47 方法**双实现全覆盖；6 条 `.navigationBarHidden` 警告，均为刻意保留 | **41 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 47 方法**双实现全覆盖；**7 条** `.navigationBarHidden` 警告，均为刻意保留 | **46 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 50 方法**双实现全覆盖；**10 条** `.navigationBarHidden` 警告，均为刻意保留 | **49 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 50 方法**双实现全覆盖；**9 条** `.navigationBarHidden` 警告，均为刻意保留 | **52 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 50 方法**双实现全覆盖；**11 条** `.navigationBarHidden` 警告，均为刻意保留 | **54 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 52 方法**双实现全覆盖；**15 条** `.navigationBarHidden` 警告，均为刻意保留 | **54 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 52 方法**双实现全覆盖；**15 条** `.navigationBarHidden` 警告，均为刻意保留 | **56 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 53 方法**双实现全覆盖；**16 条** `.navigationBarHidden` 警告，均为刻意保留 | **94 个 `.swift`**；无 iOS 17 / 16.4+ API；**协议 65 方法**双实现全覆盖；**34 条** `.navigationBarHidden` 警告，均为刻意保留 |
| 2 结构 | `Tools/lint_swift.py` | 148 个自定义类型 | **164 个自定义类型**；括号平衡；无未知类型；无重复定义 | **186 个自定义类型**；括号平衡；无未知类型；无重复定义 | **238 个自定义类型**；括号平衡；无未知类型；无重复定义 | **268 个自定义类型**；括号平衡；无未知类型；无重复定义 | **299 个自定义类型**；括号平衡；无未知类型；无重复定义 | **310 个自定义类型**；括号平衡；无未知类型；无重复定义 | **314 个自定义类型**；括号平衡；无未知类型；无重复定义 | **327 个自定义类型**；括号平衡；无未知类型；无重复定义 | **458 个自定义类型**；括号平衡；无未知类型；无重复定义 |
| 3 规格审计 | `Tools/audit_page07.py` … `audit_page15.py` | 54 项，0 缺口 | **97 项，0 缺口** | **154 项，0 缺口** | **214 项，0 缺口** | **157 项，0 缺口** | **117 项，0 缺口** | **75 项，0 缺口** | **60 项，0 缺口** | **57 项，0 缺口** | **72 项，0 缺口** |
| 4 值语义推演 | `Tools/probe_page07_semantics.py` … `probe_page15_semantics.py` | 47 条断言全通过 | **91 条断言全通过** | **133 条断言全通过** | **238 条断言全通过** | **258 条断言全通过** | **54 条断言全通过** | **23 条断言全通过** | **45 条断言全通过** | **11 条断言全通过** | **92 条断言全通过** |

页面 11 的预检里 `.navigationBarHidden` 警告从 10 条降到 **9 条**：新增了趋势页一处，
同时删掉了页面 10 时期遗留在数据管理页里的旧趋势占位页一处，净减一。
这个数字本身就是「占位页已真的删除」的一个旁证。

页面 09 另做了回归验证：`audit_page08.py` 与 `probe_page08_semantics.py` 在页面 09 全部改动落地后重跑，
仍是 **97/97** 与 **91/91**，未因新增路由与刷新机制破坏页面 08。

页面 10 的回归验证跑得更远——因为页面 10 删掉了一个页面 08 时期的占位页、并改写了历史页的分段入口，
这两处正是最容易踩到时序相关断言的地方：

| 回归项 | 结果 | 说明 |
|---|---|---|
| `audit_page07.py` | **54/54** | 有一条断言失效，见下 |
| `audit_page08.py` | **97/97** | 有一条断言失效，见下 |
| `audit_page09.py` | **154/154** | 直接通过 |
| `probe_page07 / 08 / 09` | **47 / 91 / 133** | 全部直接通过 |

两条失效的断言都**不是代码缺陷，是断言过期**，已按新实现改写而不是删掉：

1. `audit_page08.py` 的「统计进入下一页（独立路由）」原本断言源码里存在
   `HistoryStatsPlaceholderView`——那是页面 10 之前的占位页。页面 10 交付后占位页被删除，
   断言改为「装配的是 `WorkoutStatisticsView`，且占位页确已不存在」。
2. `audit_page07.py` 的「历史页定位到本次训练」原本断言 `scrollToHighlight`。实现后来
   从「拿到 id 再主动滚过去」演化为「把 id 作为 `highlightSessionID` 一路传下去，
   由列表项自己决定高亮」，断言随之改成按现在的实现判。

这两条留在审计脚本里，是因为它们各自记录了一次**真实的设计演化**。删掉很容易，
但下次有人想改回旧写法时，就没有东西提醒他为什么当初改了。

另有第 5 层**跨文件接线校验**（脚本内联在会话里跑，未落盘为文件）：本机没有编译器时，
「改了构造函数签名但漏了某个调用点」是最常见的隐藏错误。校验方式是对全部 `.swift`
做正则扫描，逐一确认新签名的每个必填参数在所有调用点都出现。页面 08 改动
`HistoryView` 的构造签名后，这一层确认了 `RootView.swift` 的调用点已补齐
`onOpenDraft` / `onOpenStats`。

页面 09 这一层确认：`HistorySessionDetailView(` 的 2 个调用点（`RootView.swift:198` 与 `:511`）、
`HistorySessionDetailViewModel(` 的 2 个调用点参数齐备；`WorkoutSessionView(` 的 3 个调用点
未受影响（防回归）；21 个新增符号全部有定义；页面 09 引用的 34 个 `DS.*` 令牌全部存在；
用到的两个 `FormatterKit` 函数均存在。另外这一层顺带查出 `HistoryRecordOrder` 一度是死代码
（`defs=1`、无引用），于是把它接进 `HistorySessionDetailViewModel` 当作「动作顺序」的约定载体，
而不是留在那里当装饰。

页面 10 这一层扫了 21 个新增类型：`WorkoutStatisticsView` / `WorkoutDataManagementView` /
`ExerciseTrendView` 及其视图模型各有 1 个外部调用点（都在 `RootView.swift`，即页面 10 的三个路由分支），
`StatsChartCard` 有 6 个（四张图卡 + 摘要区与空态各复用一次），`CompactChartEmptyState` 有 2 个，
其余组件（`FrequencyBar` / `VolumeLineShape` / `VolumeFillShape` / `StatsDataManagementCard` /
`DataManagementSkeleton`）是文件内私有或仅在定义文件内使用，**0 个外部调用点属预期**。
21 个符号全部有定义，无缺口。

页面 11 这一层扫了 27 个新增符号，全部 `defs == 1`（无重复定义、无漏定义），
并把全仓库用到的 `DS.*` 令牌做了一次全量解析：**93 个令牌，0 未解析**。
两个入口的调用点也逐一核对过：`ExerciseTrendDetailView(` 有 2 个
（历史栏路由分支、动作栏路由分支）、`ExerciseTrendDetailViewModel(` 同样 2 个，
四个回调（`onBack` / `onOpenSessionDetail` / `onStartTraining` / 动作栏的 `onOpenHistory`）
在每个调用点都齐备。

页面 11 的回归范围比页面 10 更宽——它动了动作详情页的构造签名：

| 回归项 | 结果 | 说明 |
|---|---|---|
| `audit_page07.py` | **54/54** | 直接通过 |
| `audit_page08.py` | **97/97** | 直接通过 |
| `audit_page09.py` | **154/154** | 直接通过 |
| `audit_page10.py` | **214/214** | 有两条断言失效，见下 |
| `probe_page07 / 08 / 09 / 10` | **47 / 91 / 133 / 238** | 全部直接通过 |

失效的两条都在 `audit_page10.py`，都是因为页面 11 把趋势子页换成了真页面：

1. 「趋势子页路由已注册」原本断言 `ExerciseTrendView(`——那是页面 10 时期的占位页。
   现在断言改成「装配的是 `ExerciseTrendDetailView(`，且占位页确已不存在」。
2. 「动作趋势页从路由取动作名与肌群」原本还要 `fallbackMuscle: exerciseMuscle(for:)`。
   真页面的标题只显示动作名，不画肌群图标，`exerciseMuscle(for:)` 随占位页一起删除，
   断言里那一路改成查 `return exerciseID` 这条兜底。

两次都是同一个教训的复现：**删掉一个符号之前，先 grep 一遍 `Tools/*.py`**，
审计脚本会记住它，删了代码还得回头改断言。这条已经写进 `ios16-static-gate` 技能。

页面 12 这一层扫了 27 个新增符号（`BodyDataViewModel` / `BodyDataView` / `BodyMetric` /
`BodyDataBuilder` / `BodyWeightUnit` / `BodyLengthUnit` / 一串图表组件 / `ProfileTab` /
`ProfileRoute` 等），全部 `defs == 1`；页面 12 引用的 11 个 `body*` 设计令牌全部解析到。
回归范围与页面 11 相同——页面 12 动了「我的」页的构造签名与 `BodyMeasurement` 模型：

| 回归项 | 结果 |
|---|---|
| `audit_page07.py` … `audit_page11.py` | **54 / 97 / 154 / 214 / 157**，全部直接通过 |
| `probe_page07 … 11` | **47 / 91 / 133 / 238 / 258**，全部直接通过 |

页面 12 的回归**没有一条断言过期**——它删掉的是「我的」页内联的最近 5 条身体数据
列表（换成整卡入口），没有删任何被别页断言过的符号。`.navigationBarHidden` 从 9 条
升到 **11 条**（新增身体数据页 1 处 + `ProfileTab` 1 处），均为刻意保留。

页面 13 这一层扫了 15 个新增符号（`UserProfile` / `ProfileSettings` / `ProfileMath` /
`ProfileSummaryText` / `ProfileViewModel` / `ProfileMenuRow` / `ProfileToggleRow` /
`ProfileSegmentedRow` / `ProfileRestPickerContent` / `ProfileEditView` / `PlanListView` /
`FavoriteExercisesView` / `TrainingPreferencesView` / `ProfileRoute` / `ProfileTab`），
全部 `defs == 1`；`ProfileRoute` 六个 case 全部在路由里注册。
页面 13 重写了「我的」页，动了 `audit_page12.py` 的一条断言（「我的页身体数据卡是整卡
Button」→ 现在身体数据入口是菜单行 `ProfileMenuRow`，断言改为「入口仍接 onOpenBodyData」），
其余全部历史脚本直接通过：

| 回归项 | 结果 |
|---|---|
| `audit_page07.py` … `audit_page12.py` | **54 / 97 / 154 / 214 / 157 / 117**，除 page12 一条按新实现改写外全部直接通过 |
| `probe_page07 … 12` | **47 / 91 / 133 / 238 / 258 / 54**，全部直接通过 |

`.navigationBarHidden` 从 11 条升到 **15 条**（新增 4 个子页各 1 处），均为刻意保留。
协议方法从 50 增至 **52**（`fetchProfile` / `save(profile:)`），三处仓储同步落地。

页面 14 这一层扫了 4 个新增符号（`CountdownNumberStyle` / `TrainingPreferenceResetItem` /
`CountdownStylePickerContent` / `ResetTrainingDefaultsContent`），全部 `defs == 1`；
`ProfileSettings` 新增 7 个键（`showVolume` / `lastTenSecondsReminder` / `countdownStyle` /
`autoAdvanceExercise` / `copyPreviousSet` / `showWarmupSets` / `keepTimerOnMinimize`）各出现
恰好 3 次（声明 + getter + setter）；`restCountdownFontLarge` 令牌解析到。
页面 14 只改 `TrainingPreferencesView` 的体量（把页面 13 的两开关占位页扩成三组 12 项），
没有删任何被别页断言过的符号——`ProfileRoute.trainingPreferences`、`struct TrainingPreferencesView`
这两个页面 13 断言的符号都原样保留。历史脚本全部直接通过：

| 回归项 | 结果 |
|---|---|
| `audit_page07.py` … `audit_page13.py` | **54 / 97 / 154 / 214 / 157 / 117 / 75**，全部直接通过 |
| `probe_page07 … 13` | **47 / 91 / 133 / 238 / 258 / 54 / 23**，全部直接通过 |

`.swift` 文件数保持 **54**（页面 14 没有新增文件——值层加在 `ProfileData.swift`、视图加在
`ProfileSubpages.swift`，正好印证「训练偏好是『我的』的子页」而非独立 Tab）。自定义类型
310 → **314**（+4：两个纯值类型 + 两个抽屉组件）。

页面 15 这一层扫了 14 个新增符号（`PlanListView` / `PlanListViewModel` / `PlanCardContent` /
`PlanListAccessibility` / `PlanListSkeleton` / `PlanSortOrder` / `PlanListSorting` /
`PlanCopyName` / `PlanBackup` / `PlanBackupPayload` / `PlanBackupExercise` / `PlanBackupError` /
`PlanBackupCodec` / `NewPlanNameContent`），全部 `defs == 1`；`ProfileRoute` 新增 4 个 case
（`planDetail` / `exerciseConfig` / `sessionDraft` / `sessionSummary`）全部在路由注册；
`TrainingTab` / `ProfileTab` 的 `onOpenHistory` 回调调用点各 1 个。
页面 15 把 `PlanListView` 从 `ProfileSubpages.swift` 迁到独立文件，动了 `audit_page13.py`
的一条断言（「我的计划菜单项」里的 `in_subpages(struct PlanListView)` → `has(ALL_CODE, …)`，
因为文件迁移后它不再在 subpages 作用域内）。**另修了一个页面 07 遗留的跨作用域错误**：

| 回归项 | 结果 |
|---|---|
| `audit_page07.py` … `audit_page13.py` | **54 / 97 / 154 / 214 / 157 / 117 / 75**，除 page13 一条按新实现改写外全部直接通过 |
| `probe_page07 … 13` | **47 / 91 / 133 / 238 / 258 / 54 / 23**，全部直接通过 |

`.swift` 文件数 54 → **56**（新增 `PlanListView.swift` + `PlanListData.swift`）。自定义类型
314 → **327**（+13：14 个新符号，`PlanListView` 旧占位从 ProfileSubpages 移除净减 1）。
`.navigationBarHidden` 15 → **16**（新增 PlanListView 1 处）。协议方法 52 → **53**
（`deletePlans(ids:)`），三处仓储同步落地。

**页面 07 遗留的跨作用域错误**（本轮修复，不是新引入）：`TrainingTab` 是独立 struct，
却在其 `sessionSummaryView` 里直接访问 `RootView` 的 `selection` / `pendingHistorySessionID` /
`sessionSummaryReloadToken`——Swift 不允许子 struct 访问父级成员，这在真机打包时必然编译失败，
只因本机无 Swift 编译器、`lint_swift.py` 只查「未知类型」不查「未定义成员」，才一直潜伏。
页面 15 给 `TrainingTab` / `ProfileTab` 各加 `onOpenHistory: (UUID) -> Void` 回调，
由 RootView 完成跨 Tab 跳转，彻底消除这处隐患。这印证了门禁的边界：**四层门禁能查
类型 / 括号 / 协议 / 值语义，但查不了跨作用域引用——这类错误只能靠人工审代码发现**。

### 第 4 层为什么必要

把纯值逻辑转写进 Python 跑断言表。**前两个页面的真实缺陷都是被这一层抓出来的、
另外三层全部放行**：

- 页面 06 BUG 1：`adjusting(by:)` 没有同时重设 `durationSeconds`，点 `+30 秒` 后
  下一次求值会回弹到原值
- 页面 06 BUG 2：加时上限用了**已被改动**的 `durationSeconds`，导致 90 → 690 自我抬高

页面 07 这一层覆盖：递增动画的分帧与「减少动态效果」分支、平均配速的边界与除零、
单动作容量与代表组选取、备注空白归一化、`finishSession` 的幂等与时钟回拨。

页面 08 这一层又抓到 **2 个真 bug**，其余三层同样全部放行：

- 页面 08 BUG 1：跨月选择日期时，`visibleMonth` 被 `month(byAdding: 0)` 降级成该月 1 号，
  与别处写入的「某天 00:00」形态漂移（详见 6.2.5）
- 页面 08 BUG 2：补记历史训练时 `startedAt` 落在零点，`durationSeconds` 把整段等待
  算进修时，卡片显示「216 小时」（详见 6.2.5）

页面 08 覆盖范围：2024–2027 共 48 个月的月初偏移与网格不变量、闰年（含 2000 / 2100）、
跨年、月份加减不越界、本地时区自然日归并、UTC 切天陷阱、休息日归并、
标记点顺序与超限折叠、列表分组、以及上述两个 bug 的防回归断言。

页面 09 这一层覆盖 14 组共 133 条断言：完成时间哨兵值（1970 / 坏时钟 / 边界 / 正向对照）、
单组文案（热身零容量 / 达成 / 自重）、名称三级兜底（含「任何输入都不产出空串」）、
隐藏与删除的降级差异、动作顺序与容量排序（含并列稳定性）、组序号排序、
单动作组数与容量（含纯热身）、只读白名单（含 `setData` 缺席的回归断言）、
复制草稿的 13 条契约（含不复制项的守卫）、两种训练类型的摘要指标、
未完成训练兜底、空数据与多组边界、重复 id、总计。

这一层**没有抓到新 bug**，但抓到 1 条我自己的算错（详见下节）。页面 09 的正确性
主要靠「断言写得足够细」而不是「事后修出来」，因为本页逻辑集中在纯值层，写的时候就顺手推过一遍。

页面 12 这一层覆盖 10 组共 54 条断言：单位换算的方向与系数（含「lb 不等于原值」的回归守卫）、
「未记录」与「0」的分界、变化值（最近一条没该字段时为 nil 的边界）、输入范围（20–400 /
1–70 / 20–300 的闭区间端点）、`hasAnyValue`（只有备注不算有值）、趋势点过滤与升序、
同日唯一键（不同 id 同自然日冲突 / 排除自身）、以及趋势摘要的「不足两条」空状态。
**没有抓到新 bug**——本页逻辑集中在纯值层，写的时候就推过一遍；值得一提的边界是
「最新一条记录没体重时，变化值应为 nil 而不是拿两条更早的体重记录去算」，
这条在转写 Python 时被特意写成断言守住。

### 写这套断言时踩的坑

**断言本身也会写错。** 页面 07 首次跑出 3 条「失败」，逐条核对后 3 条全是断言写错、
代码是对的：

| 断言 | 我以为 | 实际（正确） |
|---|---|---|
| 代表组 | `85 kg × 6` 最大 | `80 × 8 = 640` > `85 × 6 = 510`，**按容量**取所以是 `80 kg × 8` |
| 同容量并列 | 取后者 | `max(by:)` 在相等时保留先遇到者，取前者 |
| 全角空格 | 应保留 | `U+3000` 属 Unicode `Zs` 类，`CharacterSet.whitespacesAndNewlines` 包含它，会被去掉 |
| 2024-02 的 2/29 网格下标 | `4 + 28` | 2024-02-01 是**周四** → 3 个空白，应为 `3 + 28` |
| 补记训练的新时长 | `777600` | `9/10 19:30 → 9/19 18:00` 是 8 天 22.5 小时 = `772200` |

页面 08 的规格审计首次跑出 **6 条假阳性**，逐条核对后 6 条全是断言写错、代码是对的：

| 误报 | 真实情况 |
|---|---|
| 「无分享功能」 | 唯一的 `UIActivityViewController` 在 `PlanDetailView`（计划导出备份），属页面 04 既有功能；规格的「不含分享」限定的是历史页 |
| 「不使用社交徽章」 | 命中的全是 `weekdayBadge`（星期圆钮）、`kindBadge`（类型标签）、`warmupBadge`（热身标签）、`calendar.badge.minus`（SF Symbol） |
| 「不用 `sensoryFeedback`」 | 唯一出现处在 `BottomDrawer.swift` 的注释里：**说明它是 iOS 17 API、故意不用** |
| 「不用 `scrollTargetBehavior`」 | 同上，出现在 `TrainingHomeView.swift` 的注释里 |
| 「不用 `containerRelativeFrame`」 | 同上，出现在 `TrainingHomeView.swift` 的注释里 |
| 「本地时区自然日筛选」 | `HistoryCalendar.swift:198` 提到 `Int(timeIntervalSince1970 / 86400)` 是在**注释里解释为何避免**这种写法 |

前三条是我的判定范围错了（把别的页面和无关命名算进来），后三条是**规则本身有缺陷**：
项目里大量注释写着「xxx 是 iOS 17 API，这里故意不用」，直接在全文搜关键字必然误报。
修法是给审计加一个 `strip_comments()`，先剥掉 `//` 与 `/* */` 再匹配，
并且把「不含分享」「自然日筛选」这类判定收窄到本页相关文件集合。

页面 09 的规格审计首次跑出 **7 条假阳性**，同样全是断言写错：

| 误报 | 成因 | 修法 |
|---|---|---|
| 「日期与开始时间同排」 | 正则把 Swift 插值 `\(summary.dateText)` 过度转义 | 改成纯子串匹配 |
| 「不做递增动画」 | 断言要查的是**注释**，但 `in_page()` 读的是剥过注释的 `PAGE_CODE` | 改读原始 `FILES[...]` |
| 「复制目标组数」 | 实现是整条 `var copy = entry`，字段名 `targetRepsLow/High` 根本不会出现 | 改为断言机制本身（整条拷贝 + 只改 `id`/`completedAt`） |
| 「刷新不是只靠 `onAppear`」 | 同「查注释」类误报 | 改读原始 `FILES` |
| 「兜底链：别名 → 原名 → id」 | 我把散文当代码写进了正则（`返回 trimmedID`） | 改为匹配 `let raw = item.name` 与 `return trimmedID` |
| 「`includeHidden` 注释」 | 同「查注释」类误报 | 改读原始 `FILES` |
| 「写入后不回到 loading 态」 | 同「查注释」类误报，且注释写法一改就失效 | 改为**切片结构断言**：截取 `reload()` 函数体，断言其中不含 `loadState = .loading` |

第 2、4、6 条暴露出一条新的通用规则，已补进下面的结论：

> **凡是「断言某段注释存在」的检查，必须读未剥注释的原文。**
> 这条是页面 08「`strip_comments()` 必须先行」的必然推论 —— 剥注释解决了误报，
> 但同时让「注释本身是被断言对象」的那类检查永久变红。
> 页面 09 有 3 条检查属于这一类，第一次跑全部报红。
> 第 7 条的教训更普适：**能用结构断言就别用注释断言**，结构不会因为有人改文案而失效。

页面 09 的值语义推演另抓到 1 条**我自己的算错**（代码是对的）：

| 断言 | 我以为 | 实际（正确） |
|---|---|---|
| 该训练的总容量 | `1080`（把热身组 `40 kg × 12` 也乘进去了） | `960`（`0 + 60×10 + 30×12`）|

`SetEntry.volume` 对热身组**恒返回 0** —— 这是页面 05 就定下的契约（热身不计入训练容量），
页面 07 的总结页同此。我写断言时用 `eval("k*12")` 复用了上一节的 `k` 绑定，
把一个热身组当正式组算了进去。修完断言后额外补了一条回归守卫
「热身组的正重量没有偷偷计入容量」，断言值 `!= 1080`，防止这个错误再犯。

页面 10 的规格审计首次跑出 **8 条假阳性**，加上第二轮 3 条共 **11 条**，全部是断言写错：

| 误报 | 成因 | 修法 |
|---|---|---|
| 「自定义范围终点早于起点时自动交换」 | 这句说明写在**文档注释**里，不在代码里 | 改读原始 `FILES`，并拆成「终点早于起点」「交换」两条独立断言（避免整句复制） |
| 「频率图有 VoiceOver 摘要」 | 函数签名跨两行，单行正则会漏 | 用两段式 `func accessibilitySummary\(\s*\n?\s*buckets:` |
| 「按主肌群统计完成组数」 | 实现用的是 `primaryMuscleText`（展示名），不是 `primaryMuscle`（原始值） | 改匹配 `primaryMuscleText` |
| 「每行显示代表色」 | `colorHex` 是 `UInt32`，我按 `String` 写的 | 改类型 |
| 「肌群代表色有固定映射表」 | 真实签名是 `static func hex(for group: MuscleIconGroup) -> UInt32` | 改正则 |
| 「可清除全部训练记录」 | 我把**协议声明**放到 `in_value` 里判，而 `in_value` 只覆盖两个值层文件 | 改 `in_scan` 全仓扫描 |
| 「合并按 id 去重，保留先出现的那条」 | 文档注释里是 `保留**先出现**的那条`（带 markdown 粗体 `**`），正则没写 `\*\*` | 正则加上 `\*\*` |
| 「分享面板只在导出时出现」 | 我自己写了一句含 `^$` 的同义反复，等于没判 | 改成两条结构断言：统计页本体不得含分享 API；数据管理页 `exportedFile = ExportedFile(url:` 出现且仅出现 1 次 |

第二轮剩 3 条，成因与上表第 6 条相同或仍是跨行签名：

| 误报（第二轮） | 成因 | 修法 |
|---|---|---|
| 「自定义范围兜底」 | 签名跨行 `customRange(\s*\n\s*start: Date?)` | 两段式匹配 |
| 「部位分布行」 | 签名跨行 `rows(\s*\n\s*sessions: [WorkoutSession]` | 两段式匹配 |
| 「可清除全部训练记录」 | `in_value` / `in_page` / `in_scan` 三个作用域用混 | 见上表第 6 条 |

这次新增三条通用规则：

> **规则 A：跨行签名必须用两段式正则。**
> Swift 的参数列表经常因为行宽限制而折行。`func name\([^)]*param:` 这类单行写法
> 在这类签名上必然失配，表现为「明明写了却报缺失」。页面 10 有 3 条缺口全出自这一条。
> 写法：`func name\(\s*\n?\s*param:`。

> **规则 B：作用域要挑对。** 审计脚本有三个文本作用域 —— `in_value`（值层文件）、
> `in_page`（本页文件）、`in_scan`（全仓）。断言一个**协议声明**时用 `in_value` 永远为假，
> 因为协议不在值层文件里。页面 10 因此误报过一条。
> 挑作用域的判断依据是「这段代码在物理上位于哪个文件」，不是「这个功能属于哪一层」。

> **规则 C：`strip_comments()` 与「断言注释存在」是互斥需求，必须显式选择。**
> 这是页面 08 / 09 那条规则的延续。页面 10 的做法是把两者分开：
> 检查「代码里没有 X」时读剥过注释的文本；检查「注释里说明了 Y」时读原文。
> 两者绝不混用同一个变量。

页面 10 的值语义推演首次跑出 **7 条失败**，同样**没有一条是代码的问题**，全是断言自己写歪了：

| 失败断言 | 成因 | 修法 |
|---|---|---|
| 「23:59:59.5 不被『今天 23:59:59』漏掉」 | 比较写反了：`23:59:59.5 > 23:59:59`，所以「会漏掉」的表现是终点 **<=** late，不是 `>` | 改成 `not (23:59:59 > late)`，并附一句说明为什么方向是反的 |
| 「最近记录只含该动作」（期望 3） | 实际 4 条。`recent_sessions` 按规格**不设时间窗口**，12 个月窗口外那条老记录仍应在里面 | 引入常量 `TREND_RECENT_ALL = 4`，并补一条**关系断言**「比窗口内组数多 1」 |
| 「只有热身时部位分布为空」 | 拿的 fixture 是 `warm_only`，而它里面其实混了一组正式组（那个 fixture 是给「热身不计入组数」用的） | 另建 `all_warm` fixture，两件事分开断言 |
| 第 10 / 11 组的肌群期望不可能成立 | `lookup` 字典漏登记一个动作，它落到 `other` | 补进 `lookup` |
| `available_filters` 的排序 | 我写了一句 `if False else` 的死排序，是个无操作 | 删掉，换成真正的单键排序 |

其中「最近记录」那条最值得记：**期望值 3 是我数出来的，不是推出来的**。
数的时候只看了本月和近月，漏了窗口外那条——而那条恰恰是「窗口内外行为不同」的证据。
修法不是把 3 改成 4，而是**把数字换成关系**：`len(recent) == 窗口内组数 + 1`。
硬编码的数字下次还会错，关系不会。

**结论**：门禁报错时，先确认源码，再改断言。不要看到红字就去改实现 ——
规格审计那一层尤其容易出假阳性（regex 匹配到注释、跨行写法、语义等价的不同表达）。

---

## 十五、已废弃的方案（历史记录）

早期版本以 **iOS 17.0 + SwiftData** 为目标，包含 `Entities.swift`（4 个 `@Model`）与
`SwiftDataFitnessRepository.swift`。因目标设备为 **iOS 16.3.1**，这两个文件已删除，
替换为 `JSONFitnessRepository.swift`。相关原因与替换清单见本文「一、目标平台」。

---

## 十六、预检脚本的一个坑（供后续维护参考）

`Tools/preflight.py` 需要在扫源码前**剥掉注释与字符串字面量**，否则注释里提到
`containerRelativeFrame` 之类的词会被误报成 API 残留。这里踩过两个坑，都已修掉：

### 坑 1：先剥注释会把 URL 的收尾引号吃掉

代码里有 `"© Gym visual — https://gymvisual.com/"` 这类字面量。
若先按 `//` 剥行注释，`https://` 会被当成注释起点，**连带吃掉该字符串的收尾引号**。
引号总数于是从偶数变奇数，后续状态机永久停在「字符串内」，
文件后半段所有 `func` 全部消失，表现为仓储协议一致性检查**大面积误报缺失方法**。

**正确顺序：先剥字符串，再剥注释**，两者合并进一个状态机（`strip_comments_and_literals`）。

### 坑 2：`\s` 会匹配换行

用 `re.sub(r"^\s*@\w+\s*$", "", text, flags=re.M)` 想去掉 `@discardableResult` 这类属性行，
`\s` 含换行符，会跨行吞掉整段代码。改为 `[ \t]`。

### 自查手段

改完预检后，用 `strip_comments_and_literals` 对全部 `.swift` 统计 `{}` `()` `[]` 差值，
全为 0 才算通过。这条检查也是在没有 Swift 编译器的 Windows 上唯一的静态保险。
