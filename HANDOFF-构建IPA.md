# 交接文档：把 FitnessApp 推到 GitHub 并构建未签名 IPA

> 本文件是给另一个 AI 助手（或稍后的你自己）的执行说明书。
> 目标只有一个：**产出一个可安装到 iOS 16.3.1 的未签名 IPA**。
> 代码、门禁、文档、git 仓库**全部已就绪**，只剩「推送 + 触发 CI」这两步。

---

## 一、任务背景（30 秒读完）

这是一个**离线优先的中文健身记录 App**，从 `训记.ipa` 逆推信息架构后独立实现。
- 用途：**个人自用**，通过 TrollStore 侧载到 iPhone，不上架 App Store
- 目标设备：**iOS 16.3.1**
- 代码规模：94 个 `.swift` 文件，2842 个已跟踪文件，`Resources/ExerciseMedia/` 有 2649 个媒体文件（约 131 MB）
- 技术栈：SwiftUI + `NavigationStack` + `ObservableObject`，本地 JSON 持久化，零第三方依赖，零网络

**核心约束（不可违反）**：目标 iOS 16.0 / 实机 16.3.1，所以**不得引入任何 iOS 16.4+ 或 17+ API**。
特别点名：`scrollBounceBehavior`（整个修饰符都算 16.4+）、`presentationBackground`、
`containerRelativeFrame`、`scrollTargetBehavior`、`scrollPosition`、`sensoryFeedback`、
`ContentUnavailableView`、`@Observable`、`@Bindable`、`#Predicate`、SwiftData 全家桶。
`.navigationBarHidden(true)` 是**必须保留**的（已废弃，但是 iOS 16.0 可用的唯一写法；
替代品 `.toolbar(.hidden, for:)` 是 16.4+，在 16.3.1 上编译不过）。

---

## 二、当前状态（已完成的 vs 待做的）

### ✅ 已完成

| 项 | 状态 |
|---|---|
| 代码 | 页面 01–15 + 页面 51 全部实现 |
| 静态门禁 | preflight + lint + 87 个审计/推演脚本，**全绿** |
| git 仓库 | 已 `git init`，分支 `main`，2 个提交 |
| 提交哈希 | `f6aad4c`（最新）、`682a63e` |
| 工作区 | **干净**（`git status --porcelain` 为空） |
| 媒体 | 2649 个文件**已提交进仓库** |
| CI 工作流 | `.github/workflows/build-ipa.yml` 已写好并在本地提交 |
| 构建脚本 | `Tools/build_ipa.sh` 已写好（含完整门禁链） |
| `.gitattributes` | 已加，媒体标记为 `binary`（防 GIF 被行尾转换损坏） |

### ⬜ 待做（只有这两步）

1. **在 GitHub 建仓库并推送** —— 本地 `git remote` **为空**，从未推过任何东西
2. **触发 Actions 构建，下载 IPA**

---

## 三、环境事实（这台机器上的实际情况）

| 项 | 值 |
|---|---|
| 项目路径 | `C:\Users\yangj\WorkBuddy\2026-09-19-12-55-00\FitnessApp` |
| 系统 | Windows（用户 `yangj`） |
| Git | `C:\Program Files\Git\cmd\git.exe`（**新装的，2.55.0.windows.3**） |
| GitHub CLI | `C:\Program Files\GitHub CLI\gh.exe`（2.100.0，**未登录**） |
| Python | `C:\Users\yangj\.workbuddy\binaries\python\versions\3.13.12\python.exe` |
| `xcodebuild` / `swift` / `xcrun` | **不存在** —— 所以本地**绝对无法**产出 IPA |

### ⚠️ 网络问题（这是当前唯一的拦路虎）

这台机器的网络环境里有**两个代理端口**，其中一个走不通 GitHub：

| 代理 | 地址 | 能否访问 `github.com` |
|---|---|---|
| WorkBuddy 的代理 | `127.0.0.1:50096` | ❌ 不通 |
| 用户的代理软件 | `127.0.0.1:10808` | ✅ **通**（已验证） |

**症状**：环境变量里 `HTTPS_PROXY=http://127.0.0.1:50096`，导致 `gh` 连
`https://github.com/login/device/code` 时超时：

```
failed to authenticate via web browser: Post "https://github.com/login/device/code":
dial tcp 192.168.x.x:55651->20.205.243.166:443: A connection attempt failed ...
host has failed to respond.
```

**已验证的事实**：
- `api.github.com` 直连能通，但 `github.com` 直连**超时**
- 走 `10808` 代理访问 `https://github.com/login/device/code` 能得到 HTTP 响应（网络链路通）
- git 的全局配置里 `http.proxy` / `https.proxy` **本来就是 `127.0.0.1:10808`**，是对的

**结论**：只要在执行 `gh` / `git push` 的窗口里把 `HTTPS_PROXY` 覆盖成 `10808` 即可。

---

## 四、执行步骤（照抄即可）

### 步骤 1：登录 `gh`（在 Git Bash 里）

打开 **Git Bash**（开始菜单搜「Git Bash」），**逐行**粘贴回车（不要一次粘多行，
Git Bash 的多行粘贴会被拆坏；用右键 Paste 或 Shift+Insert 更稳）：

```bash
export HTTPS_PROXY=http://127.0.0.1:10808
export HTTP_PROXY=http://127.0.0.1:10808
gh auth login
```

`gh auth login` 的四个选择（方向键 + Enter）：

| 提示 | 选 |
|---|---|
| Where do you use GitHub? | **GitHub.com** |
| What is your preferred protocol for Git operations? | **HTTPS** |
| Authenticate Git with your GitHub credentials? | **Yes** |
| How would you like to authenticate GitHub CLI? | **Login with a web browser** |

出现 8 位一次性代码（形如 `AB12-CD34`）时：
1. **先用鼠标复制那个代码**（按 Enter 会立刻打开浏览器，来不及复制）
2. 再按 Enter
3. 浏览器里粘贴代码 → 点 **Authorize github**

成功标志：`✓ Logged in as <用户名>`

**备选方案（如果浏览器授权始终失败）**：让用户去
https://github.com/settings/tokens 建一个 **Classic Personal Access Token**，
勾选 `repo` + `workflow` 两个 scope，然后：

```bash
export GH_TOKEN=<粘贴token>
gh auth status        # 应该显示已登录
```

### 步骤 2：建仓库并推送

**推荐用一条命令搞定建仓库 + 推送**（`gh repo create` 支持 `--source` 直接关联本地仓库）：

```bash
cd "C:/Users/yangj/WorkBuddy/2026-09-19-12-55-00/FitnessApp"

export HTTPS_PROXY=http://127.0.0.1:10808
export HTTP_PROXY=http://127.0.0.1:10808

gh repo create local-fitness --public --source=. --remote=origin --push
```

参数说明：
- `local-fitness` 是仓库名，可改成任意名字
- `--public` 公开仓库（**Actions 免费不限时长**，推荐）
  若要私有，改 `--private`（每月 2000 分钟免费额度，一次构建约 10 分钟，够用很久）
- `--source=.` 用当前目录作为源
- `--remote=origin` 自动配好 remote
- `--push` 建完立即推送

**这一步会传约 131 MB**（`.git` 目录 123 MB + 工作区），耗时取决于代理速度，
几分钟到十几分钟都正常。**不要中断。**

> 如果 `gh repo create --push` 失败，退化成手动两步：
> ```bash
> gh repo create local-fitness --public          # 只建仓库
> git remote add origin https://github.com/<用户名>/local-fitness.git
> git push -u origin main
> ```
> 注意 `git remote add` 之前先确认没有同名 remote：`git remote -v`（当前应为空）。

### 步骤 3：触发构建

```bash
gh workflow run build-ipa.yml --ref main -f configuration=Release
```

然后盯着状态（`gh run watch` 实时刷新，或 `gh run list` 看一眼）：

```bash
gh run list --workflow=build-ipa.yml --limit 3
gh run watch          # 实时跟随，Ctrl-C 退出
```

**工作流做了什么**（`.github/workflows/build-ipa.yml`，11 个 step，runner `macos-14`）：

1. Checkout
2. 选最新 Xcode
3. 装 `xcodegen` 和 `ldid`
4. 准备媒体资源（媒体数 < 2648 才下载；本仓库已全量提交，会直接跳过）
5. 校验资源完整性（`Tools/verify_resources.py`）
6. **预检**（`Tools/preflight.py`）—— iOS 版本 / plist / 工程声明 / 协议一致性
7. **Swift 结构检查**（`Tools/lint_swift.py`）
8. **规格审计 + 值语义推演**（全部 87 个脚本，任一失败即中止）
9. 展示仓库布局（调试用）
10. 构建 IPA（`./Tools/build_ipa.sh Release`）
11. 上传 Artifact + 写 Summary

预计 **10 分钟左右**（首次会久一些，装依赖 + 编译 94 个文件 + 打包 131 MB 媒体）。

### 步骤 4：下载 IPA

```bash
# 列出该次运行的 artifacts
gh run view --json databaseId,conclusion,status

# 下载（用上面拿到的 run id）
gh run download <run-id> --name FitnessApp-unsigned-ipa --dir ./ipa-out
```

或者直接走网页：仓库页 → Actions → 点进那次运行 → 页面底部 **Artifacts** 区
→ 下载 `FitnessApp-unsigned-ipa`（保留 30 天）。

产物文件名为 **`FitnessApp-unsigned.ipa`**。

### 步骤 5：安装到 iPhone（用户自己操作）

1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 局域网 HTTP 服务）
2. 用 **TrollStore** 打开该 IPA
3. 点 **Install**

**TrollStore 版本要求**：iOS 16.3.1 处于 TrollStore 2 的**完整支持区间**
（15.6 – 16.5 全设备支持），无需降级、无需证书、无需电脑。
TrollStore 走 CoreTrust 漏洞做 perma-sign，**要求 IPA 未签名** ——
`build_ipa.sh` 会移除 `_CodeSignature` 并用 `ldid` 伪签名，符合要求。

---

## 五、关键文件清单

| 文件 | 作用 |
|---|---|
| `project.yml` | XcodeGen 工程声明。`Resources/ExerciseMedia` **必须是 `type: folder`**，否则 Bundle 内子目录被打平 |
| `FitnessApp/Info.plist` | 最低 iOS 16.0、深色锁定、仅竖屏 arm64、无网络权限 |
| `Tools/build_ipa.sh` | 一键构建。内部先跑 preflight + lint + 全部 87 个审计推演脚本，失败即中止 |
| `Tools/preflight.py` | 硬门禁：iOS 版本 / plist / 工程声明 / 资源完整性 / 协议一致性 |
| `Tools/lint_swift.py` | 结构检查：括号平衡 / 顶层类型重复定义 / 未知类型引用 |
| `Tools/audit_pageNN.py` | 逐页规格审计（页面 07–51，共 41 个） |
| `Tools/probe_pageNN_semantics.py` | 逐页值语义推演（46 个） |
| `.github/workflows/build-ipa.yml` | GitHub Actions 工作流（`workflow_dispatch`，手动触发） |
| `Tools/push_and_build.sh` | 一键推送到已有仓库 + 触发构建（需要先有 remote） |
| `.gitattributes` | 媒体标 `binary`，文本统一 `eol=lf` |
| `README.md` | 完整工程说明书（3187 行），§二 就是 IPA 打包指引 |

---

## 六、重要陷阱（踩过的坑，别重复踩）

### 1. 多行粘贴会坏
Git Bash 里一次粘贴多行会被拆成乱码（实测粘贴三行只剩 `\M`）。
**逐行粘，或用右键 Paste / Shift+Insert。**

### 2. 代理必须显式指定
`export HTTPS_PROXY=http://127.0.0.1:10808` 只在**当前窗口**有效。
每开一个新窗口都要重设。`gh` 和 `git push` 都需要。

### 3. 别动 `git config` 的代理
全局配置里 `http.proxy=http://127.0.0.1:10808` 是**正确的**，不需要改。
冲突的是**环境变量** `HTTPS_PROXY`（值是 50096），用 `export` 临时覆盖即可。

### 4. 本机绝不可能出 IPA
没有 `xcodebuild` / `swift`，iOS 二进制只能在 macOS + Xcode 上编译。
任何声称「在 Windows 上本地编译出 IPA」的方案都是错的。

### 5. 不要「优化」`.gitattributes`
媒体文件（2649 个 JPG/GIF）必须标记为 `binary`。去掉之后 git 会尝试做行尾
转换，**GIF 会被损坏**，App 里动作演示动画全废。

### 6. 不要在 Windows 上用 shell heredoc 写含反引号的文件
被命令替换吃掉，会写进一堆乱码（本项目实际踩过，日志被污染过一次）。
用带 `encoding='utf-8'` 的 Python 脚本写文件，路径写死在脚本里，不经 shell。

### 7. 构建失败时的第一反应
CI 里任何一个门禁脚本报红都会中止构建。**先读源码确认行为，再决定改代码还是改断言** ——
本项目历史上门禁首跑失败 20+ 次，绝大多数是**断言自己写歪了**，代码本身是对的。
只有第 4 层「值语义推演」抓出过 7 个真 bug。

---

## 七、验收标准

任务完成的最低标准：

- [ ] `gh auth status` 显示已登录，账号是用户的
- [ ] 远程仓库存在，且 `git ls-remote origin main` 能返回 `main` 的哈希
- [ ] Actions 运行结束，`conclusion == "success"`
- [ ] 下载到的 `FitnessApp-unsigned.ipa` 存在且体积合理（约 130–160 MB）
- [ ] IPA 内 `Payload/FitnessApp.app/` 下有 `FitnessApp` 可执行文件、`Info.plist`、
      以及 `images/` + `videos/` 两个媒体目录（共 2648 个文件）

**最终交付给用户的是那个 .ipa 文件**，装在 iOS 16.3.1 设备的 TrollStore 里。

---

## 八、给接手 AI 的一句话总结

> 项目在 `C:\Users\yangj\WorkBuddy\2026-09-19-12-55-00\FitnessApp`，
> git 仓库已就绪（分支 `main`，提交 `f6aad4c`，2842 个文件已提交，remote 为空）。
> 用 `C:\Program Files\GitHub CLI\gh.exe` 建仓库并推送，
> **执行前必须在窗口里 `export HTTPS_PROXY=http://127.0.0.1:10808`**（环境变量默认的
> 50096 端口走不通 GitHub，10808 才通）。推送约 131 MB。
> 然后 `gh workflow run build-ipa.yml --ref main -f configuration=Release`，
> 约 10 分钟后从 artifact `FitnessApp-unsigned-ipa` 取回 `FitnessApp-unsigned.ipa`。
> 这台机器没有 `xcodebuild`，本地不可能出包。
