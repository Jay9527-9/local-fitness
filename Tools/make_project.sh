#!/bin/bash
# 生成 Xcode 工程。
# 优先使用 XcodeGen（由 project.yml 声明式生成，最可靠）；
# 若环境无 XcodeGen，则退回手写 pbxproj 生成。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> working dir: $ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> using XcodeGen"
  xcodegen generate --spec project.yml
  echo "==> generated FitnessApp.xcodeproj"
  exit 0
fi

echo "==> XcodeGen not found, installing via Homebrew"
if command -v brew >/dev/null 2>&1; then
  brew install xcodegen
  xcodegen generate --spec project.yml
  echo "==> generated FitnessApp.xcodeproj"
  exit 0
fi

echo "!! Neither xcodegen nor brew available."
echo "!! Install XcodeGen: https://github.com/yonaskolb/XcodeGen"
exit 1
