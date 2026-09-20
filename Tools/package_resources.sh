#!/bin/bash
# 素材打包前校验。
# 委托给 verify_resources.py 做完整性核对（跨平台一致，行为可预测）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

MEDIA="Resources/ExerciseMedia"

if [ ! -d "$MEDIA" ]; then
  echo "!! 缺少媒体目录: $MEDIA"
  echo "   先运行: python3 Tools/download_media.py"
  exit 1
fi

echo "==> 媒体目录体积: $(du -sh "$MEDIA" | cut -f1)"

PY=python3
if ! command -v python3 >/dev/null 2>&1; then
  PY=python
fi

"$PY" Tools/verify_resources.py
