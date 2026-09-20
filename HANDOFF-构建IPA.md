# 交接文档：FitnessApp 未签名 IPA 构建

> **本文件记录当前真实进度。** 目标只有一个：产出一个可安装到 iOS 16.3.1 的未签名 IPA。
> **仓库已推送、CI 已跑通门禁链、只剩「编译器不再报错 → 出 IPA」这一步。**

---

## 一、任务背景（30 秒读完）

这是一个**离线优先的中文健身记录 App**，从 `训记.ipa` 逆推信息架构后独立实现。
- 用途：**个人自用**，通过 TrollStore 侧载到 iPhone，不上架 App Store
- 目标设备：**iOS 16.3.1**
- 代码规模：94 个 `.swift` 文件，`Resources/ExerciseMedia/` 有 2648 个媒体文件（约 131 MB）
- 技术栈：SwiftUI + `NavigationStack` + `ObservableObject`，本地 JSON 持久化，零第三方依赖，零网络

**核心约束（不可违反）**：目标 iOS 16.0 / 实机 16.3.1，所以**不得引入任何 iOS 16.4+ 或 17+ API**。
特别点名：`scrollBounceBehavior`（**整个修饰符都算 16.4+**）、`presentationBackground`、
`containerRelativeFrame`、`scrollTargetBehavior`、`scrollPosition`、`sensoryFeedback`、
`ContentUnavailableView`、`@Observable`、`@Bindable`、`#Predicate`、SwiftData 全家桶。
`.navigationBarHidden(true)` 是**必须保留**的（已废弃，但是 iOS 16.0 可用的唯一写法；
替代品 `.toolbar(.hidden, for:)` 是 16.4+，在 16.3.1 上编译不过）。

---

## 二、当前状态

### ✅ 已完成

| 项 | 状态 |
|---|---|
| 代码 | 页面 01–15 + 页面 31/51 全部实现 |
| 本地静态门禁 | **九层**，86 个脚本全绿（见 §三） |
| git 仓库 | 已推送 GitHub，分支 `main`，最新 `ea15a7e` |
| 仓库地址 | https://github.com/Jay9527-9/local-fitness |
| 媒体 | 2648 个文件已提交进仓库 |
| CI 工作流 | `.github/workflows/build-ipa.yml`，**16 个 step**，`push` 与 `workflow_dispatch` 双触发 |
| 构建脚本 | `Tools/build_ipa.sh`（含完整门禁链） |
| `.gitattributes` | 已加，媒体标记为 `binary`（防 GIF 被行尾转换损坏） |
| CI 构建前步骤 | **全绿**（含 8 层门禁 + 全部规格审计），`Build IPA` 进行中 |

### ⬜ 待做

1. **等 CI 的 `Build IPA` step 通过**（`ea15a7e` 这一轮，含动作库性能修复）
2. **下载 `FitnessApp-unsigned-ipa` 构件**，按 §六之二逐项校验
3. **在 iOS 16.3.1 设备上用 TrollStore 安装**，确认动作库三个问题已消除
4. **撤销已明文共享的 PAT**：https://github.com/settings/tokens

### 编译器错误收敛轨迹（`Build IPA` step）

| 轮次 | run | 报错 | 结果 |
|---|---|---|---|
| 1 | 35497428045 | `failed to produce diagnostic`（TrainingTab.body 66 层） | 拆 body → 冒出 11 个既有错误 |
| 2 | 35497818607 | `must precede`（CardioSessionView 顺序）+ `ambiguous`（homeRoot） | 修顺序；ambiguous 未解 |
| 3 | 35498159437 | 前 6 层门禁转绿，L6 与 L7 均通过；`Refactor equivalence` 报红 | 查出是**基准漂移**，非代码事故 |
| 4 | 35498309347 | **构建前 13 步全绿** | 等 `Build IPA` |

---

## 三、九层本地门禁（Windows 上没有 Swift 编译器，全靠这个）

```
Tools/preflight.py                     L1  iOS 版本 / plist / 工程声明 / 协议一致性 / 资源
Tools/lint_swift.py                    L2  括号平衡 / 自定义类型 / 未知类型 / 重复定义
Tools/audit_pageNN.py            ×41   L3  逐页规格审计
Tools/probe_pageNN_semantics.py  ×42   L4  逐页纯值层语义推演
Tools/audit_call_sites.py              L5  跨文件调用点参数/标签一致性 + viewModel.member 归属
Tools/audit_body_size.py               L6  SwiftUI 视图体表达式规模（防类型检查器放弃）
Tools/audit_enum_arity.py              L7  枚举模式绑定的关联值**个数**是否与声明一致
Tools/audit_exercise_library_perf.py   L8  动作库性能与布局回归（见下）
Tools/verify_refactor_equivalence.py       拆方法后证明逻辑是「纯搬运」（基准钉在 db3df0a）
```

九层跑完：

```bash
cd "C:/Users/yangj/WorkBuddy/2026-09-19-12-55-00/FitnessApp"
python Tools/preflight.py
python Tools/lint_swift.py
python Tools/audit_call_sites.py
python Tools/audit_body_size.py
python Tools/audit_enum_arity.py
python Tools/audit_exercise_library_perf.py
python Tools/verify_refactor_equivalence.py
for f in Tools/audit_page*.py Tools/probe_page*_semantics.py; do python "$f" || echo "FAIL $f"; done
```

**第 4 层抓出过 7 个真 bug，第 5 层抓出过 `viewModel.paceSecondsPerKm` 不存在，
第 6 层抓出过四个 Tab 的超大 `body`，第 7 层抓出 `case .inProgress` 少绑 2 个 `_`。**
报红时**先读源码确认行为，再决定改代码还是改断言** ——
历史上门禁首跑失败里相当一部分是断言自己写歪了。

> **L7 的由来**：`RootView.swift:1358` 的 `type of expression is ambiguous` 看着
> 像规模问题，实测 `homeRoot` 只有 1602 字符。真因是 `case .inProgress(let id, _, _)`
> 只绑了 3 个占位，而枚举声明是 5 个关联值 —— **Swift 不会说「个数不对」**，
> 它报的是整段 match 推不出类型、把错误丢到链尾。前六层结构上都看不见这一类。

> **L8 的由来**：实机报「动作库加载慢、卡顿、底栏挡住界面」，四类根因分别是
> ①七个派生值写成计算属性 → 每次 `body` 求值全量重算 1324 条；
> ②1324 行被普通 `VStack` 包住 → `LazyVStack` 的惰性只对直接子视图生效，等于失效；
> ③缩略图 / GIF 在 `body` 内同步读盘解码，无缓存；
> ④动作库自己又叠了一层与外层 Tab 栏同向的 `safeAreaInset(.bottom)`，空分支也占位。
> **这四类全都「语法对、类型对、调用点齐、视图体也不大」**，
> 前七层从设计上就看不见 —— 它们不是正确性问题，是**性能与布局**问题。
> 加这一层是因为：能编过 ≠ 能用。

---

## 四、环境事实（这台机器上的实际情况）

| 项 | 值 |
|---|---|
| 项目路径 | `C:\Users\yangj\WorkBuddy\2026-09-19-12-55-00\FitnessApp` |
| 系统 | Windows（用户 `yangj`） |
| Git | `git` 在 PATH 的 `/c/Program Files/Git/cmd`，**须显式加进 PATH** |
| GitHub CLI | `gh`，用 `GH_TOKEN` 环境变量认证 |
| Python | `python`（3.13.12） |
| `xcodebuild` / `swift` / `xcrun` | **不存在** —— 本地**绝对无法**产出 IPA |

### ⚠️ 三个必须知道的环境陷阱

**1. Git Bash 的 PATH 是坏的**

每次调用都要先补 PATH，否则 `tail` / `head` / `ls` / `dirname` / `git` 全部
`command not found`：

```bash
export PATH="/usr/bin:/bin:/c/Program Files/Git/cmd:$PATH"
```

`cd` 在 Bash 工具里**不持久**，一律用绝对路径。

**2. 代理：两个端口，只有一个通**

| 代理 | 地址 | 能否访问 `github.com` |
|---|---|---|
| WorkBuddy 的 | `127.0.0.1:50096` | ❌ 不通 |
| 用户自己的 | `127.0.0.1:10808` | ✅ **通** |

```bash
export HTTP_PROXY=http://127.0.0.1:10808
export HTTPS_PROXY=http://127.0.0.1:10808
export NO_PROXY= no_proxy=      # 必须清空，否则代理被绕过
```

**3. `git push` 假死（踩过两次，一共耗掉近 20 分钟）**

- 症状：`git push` 后台跑 14 分 39 秒零输出。**不是仓库大在慢传**，
  是 TLS 握手从未成功、git 在无限重试。
- 诊断：`timeout 60 git ls-remote origin` 秒拿到真实错误
  `schannel: SEC_E_ILLEGAL_MESSAGE (0x80090326)`。
- 根因：Git for Windows 默认 `http.sslbackend=schannel`，它会强制联网做证书
  吊销检查（CRL/OCSP），代理下走不通。
- 修法（**`.git/config` 里已有，无需重做**）：

  ```bash
  git config --unset-all http.sslbackend   # 先全清！见下
  git config http.sslbackend openssl
  git config http.postBuffer 524288000
  git config http.version HTTP/1.1
  ```

- **暗坑**：`git config http.sslbackend openssl` 执行两次会**追加而非覆盖**，
  于是 `ls-remote` 能过、`push` 却报 `SSL routines::ssl/tls alert handshake failure`。
  改配置前先 `--unset-all`。查重复键：

  ```bash
  python -c "import re,collections;t=open('.git/config',encoding='utf-8').read();k=re.findall(r'^\s*([A-Za-z0-9_.-]+)\s*=',t,re.M);print({a:b for a,b in collections.Counter(k).items() if b>1})"
  ```

- **纪律**：push 超过 2 分钟无输出（连 `Enumerating objects` 都没有）立刻杀掉排查。

### 取 CI 日志

`gh run view --log` 常因 TLS 失败（`unexpected EOF`）。用 `curl` 打 API 拿纯文本：

```bash
curl -s --ssl-no-revoke -x http://127.0.0.1:10808 \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/Jay9527-9/local-fitness/actions/jobs/<job_id>/logs"
```

`curl` 是 Windows 自带的、同样走 schannel，所以**必须加 `--ssl-no-revoke`**。
Python 里用 `subprocess` 调 curl 时**不要加 `text=True`**（stderr 含非 UTF-8 字节会
`UnicodeDecodeError`）。

---

## 五、执行步骤

### 步骤 1：本地跑门禁

见 §三。**六层全绿再推**，否则 CI 会在第 5–9 步白跑一遍。

### 步骤 2：推送

```bash
export PATH="/usr/bin:/bin:/c/Program Files/Git/cmd:$PATH"
cd /c/Users/yangj/WorkBuddy/2026-09-19-12-55-00/FitnessApp
export HTTP_PROXY=http://127.0.0.1:10808 HTTPS_PROXY=http://127.0.0.1:10808 NO_PROXY= no_proxy=
timeout 120 git push origin HEAD:main
```

push 到 `main` 会**自动触发** CI（workflow 里有 `on: push: branches: [main]`）。
正常耗时 **约 11 秒**。

### 步骤 3：监控

```bash
export GH_TOKEN=<token>
gh run list --limit 5
gh run view <run-id> --json status,conclusion -q '.status+" "+(.conclusion//"-")'
```

**工作流 13 个 step**（runner `macos-14`）：

1. Checkout
2. 选最新 Xcode
3. 装 `xcodegen` 和 `ldid`
4. 准备媒体资源（媒体数 < 2648 才下载；已全量提交会跳过）
5. Preflight checks（L1）
6. Swift structure lint（L2）
7. Call-site consistency（L5）
8. View body size（L6）
9. Spec audits and value-layer probes（L3+L4，83 个脚本）
10. Show repo layout
11. **Build IPA**（`./Tools/build_ipa.sh Release`）
12. Upload IPA
13. Summary

首次约 10 分钟。**第 11 步是唯一会产生编译错误的地方。**

### 步骤 4：下载 IPA

```bash
gh run download <run-id> --name FitnessApp-unsigned-ipa --dir ./ipa-out
```

或走网页：仓库页 → Actions → 点进那次运行 → 底部 **Artifacts** → `FitnessApp-unsigned-ipa`（保留 30 天）。

产物文件名 **`FitnessApp-unsigned.ipa`**。

### 步骤 5：安装到 iPhone（用户自己操作）

1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 局域网 HTTP 服务）
2. 用 **TrollStore** 打开该 IPA
3. 点 **Install**

**TrollStore 版本要求**：iOS 16.3.1 处于 TrollStore 2 的**完整支持区间**
（15.6 – 16.5 全设备支持），无需降级、无需证书、无需电脑。
TrollStore 走 CoreTrust 漏洞做 perma-sign，**要求 IPA 未签名** ——
`build_ipa.sh` 会移除 `_CodeSignature` 并用 `ldid` 伪签名，符合要求。

---

## 六、关键文件清单

| 文件 | 作用 |
|---|---|
| `project.yml` | XcodeGen 工程声明。`Resources/ExerciseMedia` **必须是 `type: folder`**，否则 Bundle 内子目录被打平 |
| `FitnessApp/Info.plist` | 最低 iOS 16.0、深色锁定、仅竖屏 arm64、无网络权限 |
| `Tools/build_ipa.sh` | 一键构建。内部先跑全部门禁脚本，失败即中止 |
| `Tools/preflight.py` | L1 硬门禁 |
| `Tools/lint_swift.py` | L2 结构检查 |
| `Tools/audit_pageNN.py` | L3 逐页规格审计（41 个） |
| `Tools/probe_pageNN_semantics.py` | L4 逐页值语义推演（46 个） |
| `Tools/audit_call_sites.py` | L5 跨文件调用点一致性 |
| `Tools/audit_body_size.py` | L6 视图体规模 |
| `Tools/audit_enum_arity.py` | L7 枚举模式绑定的关联值个数 |
| `Tools/audit_exercise_library_perf.py` | **L8 性能与布局回归（49 条断言）** |
| `Tools/verify_refactor_equivalence.py` | 拆方法后证明逻辑是纯搬运（基准钉 `db3df0a`） |
| `Tools/parallel_download.py` | 8 并发 Range 分块下载 CI 构件（绕开 Azure Blob 单连接限速） |
| `Tools/verify_ipa.py` | 内层 IPA 结构断言（递归剥壳 + 6 组断言） |
| `.github/workflows/build-ipa.yml` | GitHub Actions 工作流（16 步） |
| `.gitattributes` | 媒体标 `binary`，文本统一 `eol=lf` |
| `README.md` | 完整工程说明书，§二 是 IPA 打包指引 |

---

## 六之二、产出物校验（下载后必做）

**「能下载」不等于「能装」。** 解包查结构才算数。已把这件事固化成脚本：

```bash
python Tools/verify_ipa.py FitnessApp-unsigned-v2.ipa
```

**先说三层嵌套**（这里踩过两次坑，务必记住）：

```
GitHub Actions 构件 zip            ← 你从网页/API 下载到的就是这个
  └── FitnessApp-unsigned.ipa      ← 真 IPA，132 MB
        └── Payload/FitnessApp.app/**   ← app 包内容
```

所以「解包」要**剥两层**才对得上 `Payload/`。脚本会自动逐层剥壳，
并在第 0 行打印剥壳链，方便肉眼确认：

```
0. 层级剥壳               : FitnessApp-unsigned-v2.ipa → FitnessApp-unsigned.ipa (132354695 字节)
   条目总数               : 2657
```

断言项（6 组，任一失败退出码非 0）：

| # | 断言 | 说明 |
|---|---|---|
| 1 | 内层 zip `testzip()` 为 `None` | CRC 全通过 |
| 2 | jpg == 1324 且 gif == 1324 | 媒体齐全（**两个数都要**，不要只查合计） |
| 3 | `Info.plist` 的 `CFBundleIdentifier` / `MinimumOSVersion` / `UIDeviceFamily` | app 身份 + 可装性 |
| 4 | 可执行文件存在、Mach-O magic `feedfacf`、cputype 低 24 位 == 12 | arm64 |
| 5 | `_CodeSignature` **0** 条、`mobileprovision` **0** 条 | 未签名，TrollStore 需要的形式 |
| 6 | `Payload/FitnessApp.app/exerciseLibrary.seed.json` 存在 | 种子数据落位 |

**已实测通过**（`FitnessApp-unsigned-v2.ipa`，131,977,015 字节，
run `35511946358` / `ea15a7e`，构件 `10605947464`）：

| 项 | 值 |
|---|---|
| 内层 IPA | 132,354,695 字节，条目 2657 |
| Mach-O | `feedfacf`（MH_MAGIC_64）/ cputype 12（arm64）/ 18,676,272 字节 |
| `MinimumOSVersion` | 16.0 |
| `UIDeviceFamily` | `[1, 2]`（iPhone + iPad） |
| `CFBundleIdentifier` | `com.local.fitness.trainnote` |
| `CFBundleExecutable` | `FitnessApp` |
| 媒体 | jpg 1324 + gif 1324 = 2648，位于 `ExerciseMedia/images/` 与 `ExerciseMedia/videos/` |
| `_CodeSignature` / `mobileprovision` | 均 **0** 条 |
| app 包根文件 | `Info.plist` / `PkgInfo` / `FitnessApp` / `exerciseLibrary.seed.json` |

> **两个已修正的判据错误**（写脚本时别再犯）：
> 1. 用 `n.count("/") == 1` 判 `Info.plist` / 可执行文件 ——
>    `Payload/FitnessApp.app/Info.plist` 是**两层**斜杠，永远匹配不上，
>    表现为「条目总数 2657 但 Info.plist 未找到」这种自相矛盾的输出。
>    正确写法：`n.startswith("Payload/FitnessApp.app/") and n.count("/") == 2`。
> 2. 只剥一层就取 `namelist()` —— 拿到的是**构件 zip 的外壳**，
>    条目总数会是 1（就一个 `.ipa` 条目）。要先按 `.ipa` 后缀下钻。

> **注意**：工程内 `FitnessApp/Resources/ExerciseMedia/` 在本机是 **0 个文件**
> （媒体未提交进仓库，由 CI 上 `download_media.py` 补齐）。
> 所以「本机源目录为空」**不代表** IPA 缺媒体 —— 要查就查 IPA 内部。

---

## 七、重要陷阱（踩过的坑，别重复踩）

### 1. `error: failed to produce diagnostic for expression` = 类型检查器**放弃**

它**不是语法错误**，只指出 `var body` 那一行，不给原因。根因是**单个表达式太大**。

**关键副作用：编译器放弃后，同一批编译里后续的错误不再报。** 于是很多真错误被
"掩盖"到下一轮才暴露。本项目实测：修掉四个 Tab 的巨型 `body` 之后，**下一轮冒出 11 个
既有 bug**（`popOne` 不存在、`Double?` 未解包、实参顺序错……）。

**修法**：把大表达式拆成小方法 —— `body` → `navHost`（导航宿主）+
`xxxDestination(for:)`（路由分派）+ 弹出层。**不要用 `AnyView` 去"压"类型**。
用量化工具找靶子，不要靠猜：

```bash
python Tools/audit_body_size.py --list    # 列最大的 15 个，不判红
```

阈值 `7000 字符 / 40 层大括号`，实测踩雷点是 `10821 / 66`。

### 2. 一次编译报红消失 ≠ 修干净

见上条。修完一轮要**按同类全仓扫描**，不要只修报出的那一处。
本轮就是这么找出 `FormatterKit.distance(meters:)` 的另外 4 处同类调用的。

### 3. `private` 方法的作用域是**类型本身**

同一个文件里另一个 `struct` 的同名方法**不可见**。四个 Tab 各自需要自己的
`popOne` / `popExerciseOne` / `lookupExerciseName`。这类"方法不存在"的错误，
在巨型 `body` 拆开之前**根本不会被报出来**。

### 4. 闭包参数显式标注类型可消除 `type of expression is ambiguous`

当构造一个有 8 个闭包的视图、其中一个闭包内还要 `switch` 枚举时，推断规模叠加会失败。
写 `{ (state: TodayTrainingState) in }` 就给了一个锚点。

### 5. 多行粘贴会坏

Git Bash 里一次粘贴多行会被拆成乱码（实测粘贴三行只剩 `\M`）。
**逐行粘，或用右键 Paste / Shift+Insert。**

### 6. 别动 `git config` 的代理

全局配置里 `http.proxy=http://127.0.0.1:10808` 是**正确的**，不需要改。
冲突的是**环境变量** `HTTPS_PROXY`（值是 50096），用 `export` 临时覆盖即可。

### 7. 本机绝不可能出 IPA

没有 `xcodebuild` / `swift`，iOS 二进制只能在 macOS + Xcode 上编译。
任何声称「在 Windows 上本地编译出 IPA」的方案都是错的。

### 8. 不要「优化」`.gitattributes`

媒体文件（2648 个 JPG/GIF）必须标记为 `binary`。去掉之后 git 会尝试做行尾转换，
**GIF 会被损坏**，App 里动作演示动画全废。

### 9. 不要用 shell heredoc 写含反引号的文件

被命令替换吃掉，会写进一堆乱码。用带 `encoding='utf-8'` 的 Python 脚本写文件，
路径写死在脚本里，不经 shell。

### 10. `/tmp` 在 Windows 不存在

输出重定向到 `/tmp` 会失败，并**掩盖脚本的真实 exit code**。用工作目录下的绝对路径。

### 11. `type of expression is ambiguous` 未必是规模问题

它**会指错地方**，且指向的位置常与根因相距几十行。

实测 `RootView.swift:1358 .navigationBarHidden(true)` 报 ambiguous，
看着像 `homeRoot` 太大，实测只有 **1602 字符**。真因是 30 行之上：

```swift
case .inProgress(let sessionID, _, _)      // 只绑了 3 个，声明是 5 个
```

**`_` 个数与枚举声明不一致时，Swift 不报「个数不对」**，而是整段 match
推不出类型。修完记得跑 `python Tools/audit_enum_arity.py` 复查全仓同类。

### 12. 对比型门禁的基准不能用 `HEAD~1`

`verify_refactor_equivalence.py` 的基准必须是**绝对 sha**
（现为 `REFACTOR_BASE = "db3df0a"`，即重构前那个提交）。
用 `HEAD~1` 会漂：重构提交之上再有提交，`HEAD~1` 就变成已经重构过的版本，
六处全部误报「旧 1 行 → 新 N 行」，**与「搬运丢行」外观完全一致**。

另：CI 的 Checkout 必须 `with: fetch-depth: 0`，否则脚本拿不到父提交、
静默跳过而一直"绿" —— **跳过等于没查**。

### 13. 「跳过」和「通过」必须能区分

任何门禁在不具备检查条件时**要打印醒目提示**，不能静默 `return 0`。
历史上 `verify_refactor_equivalence.py` 因浅克隆静默跳过，伪装成功很久，
直到加 `fetch-depth: 0` 才暴露。**静默的检查比没有检查更危险**。

---

## 八、验收标准

- [ ] `git ls-remote origin main` 返回 `main` 的哈希
- [ ] Actions 运行结束，`conclusion == "success"`
- [ ] 下载到的 `FitnessApp-unsigned.ipa` 存在且体积合理（约 130–160 MB）
- [ ] IPA 内 `Payload/FitnessApp.app/` 下有 `FitnessApp` 可执行文件、`Info.plist`、
      以及 `images/` + `videos/` 两个媒体目录（共 2648 个文件）

**最终交付给用户的是那个 .ipa 文件**，装在 iOS 16.3.1 设备的 TrollStore 里。

---

## 九、给接手 AI 的一句话总结

> 项目在 `C:\Users\yangj\WorkBuddy\2026-09-19-12-55-00\FitnessApp`，
> 已推到 https://github.com/Jay9527-9/local-fitness（分支 `main`），
> push 到 `main` 即自动触发 CI。**六个 step 是本地门禁的镜像，第 11 步才是真编译。**
> 报 `failed to produce diagnostic for expression` 时不要看那一行 —— 用
> `python Tools/audit_body_size.py --list` 找过大的 `body`，拆它；拆完会冒出被掩盖的
> 既有错误，**按同类全仓扫描**一起修。
> 每次调 Bash 都要 `export PATH="/usr/bin:/bin:/c/Program Files/Git/cmd:$PATH"`，
> 联网要 `export HTTPS_PROXY=http://127.0.0.1:10808 NO_PROXY=`。
> 这台机器没有 `xcodebuild`，本地不可能出包。
