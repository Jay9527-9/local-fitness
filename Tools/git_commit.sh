#!/bin/bash
# 提交全部内容到本地仓库（不推送）。
# 用法：bash Tools/git_commit.sh "提交说明"
set -euo pipefail

GIT="git"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MSG="${1:-更新}"

if [ ! -d .git ]; then
  echo "!! 当前目录不是 git 仓库，先跑 git init"
  exit 1
fi

git add -A
if git diff --cached --quiet; then
  echo "==> 没有需要提交的改动"
  exit 0
fi

git -c user.name="FitnessApp Builder" \
    -c user.email="builder@localhost" \
    commit -q -m "$MSG"

echo "==> 已提交"
git --no-pager log --oneline -1
echo
echo "文件数: $(git ls-files | wc -l | tr -d ' ')"
