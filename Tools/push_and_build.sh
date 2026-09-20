#!/bin/bash
# 一键推到 GitHub 并触发 IPA 构建。
#
# 用法（在本机 FitnessApp 目录下，用 Git Bash 或任意 bash）：
#   bash Tools/push_and_build.sh https://github.com/<用户名>/<仓库名>.git
#
# 前置条件：
#   1. 已在 GitHub 网页上建好一个空仓库（不要勾选 README / .gitignore / License）
#   2. 本机 git 能通过 HTTPS 或 SSH 访问该仓库
#   3. 若装了 gh 并已 `gh auth login`，可用 `gh auth setup-git` 让 git 复用凭据
#
# 本脚本做三件事：建 remote → push main → 尝试用 gh 触发 workflow。
set -euo pipefail

REMOTE="${1:-}"
if [ -z "$REMOTE" ]; then
  echo "用法: bash Tools/push_and_build.sh <git-remote-url>"
  echo "例如: bash Tools/push_and_build.sh https://github.com/me/local-fitness.git"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> 工作目录: $ROOT"
echo "==> 当前分支: $(git rev-parse --abbrev-ref HEAD)"
echo "==> 待推送文件数: $(git ls-files | wc -l | tr -d ' ')"
echo "==> 仓库体积: $(du -sh .git | cut -f1)（.git 目录）"
echo

# 幂等设置 remote
if git remote get-url origin >/dev/null 2>&1; then
  echo "==> 已存在 origin，更新为 $REMOTE"
  git remote set-url origin "$REMOTE"
else
  echo "==> 添加 origin = $REMOTE"
  git remote add origin "$REMOTE"
fi

echo
echo "==> 开始推送（131 MB，稍等）"
git push -u origin main

echo
echo "=========================================="
echo " 推送完成"
echo "=========================================="
echo

# 尝试用 gh 触发构建
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    echo "==> 触发 Actions 构建"
    gh workflow run build-ipa.yml --ref main -f configuration=Release || {
      echo "   !! 自动触发失败，请到仓库 Actions 页面手动 Run workflow"
    }
    echo
    echo "==> 查看运行状态（Ctrl-C 退出）"
    sleep 5
    gh run list --workflow=build-ipa.yml --limit 3 || true
  else
    echo "==> gh 未登录，跳过自动触发"
    echo "    登录后可自动触发：gh auth login && gh workflow run build-ipa.yml"
  fi
else
  echo "==> 未找到 gh，跳过自动触发"
fi

echo
echo "手动触发路径："
echo "  1. 打开仓库页面 → Actions"
echo "  2. 左侧选 'Build unsigned IPA' → 右侧 Run workflow"
echo "  3. 等约 10 分钟"
echo "  4. 在该次运行页面底部 Artifacts 下载 FitnessApp-unsigned-ipa"
echo
echo "安装：把 IPA 传到 iPhone（AirDrop / 文件 App），用 TrollStore 打开并 Install。"
