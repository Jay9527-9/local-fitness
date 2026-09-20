#!/bin/bash
# 一键构建未签名 IPA，供 TrollStore 安装。
# 用法：./Tools/build_ipa.sh [Release|Debug]
set -euo pipefail

CONFIG="${1:-Release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=========================================="
echo " Build unsigned IPA for TrollStore"
echo " configuration: $CONFIG"
echo " target: iOS 16.0 (device iOS 16.3.1)"
echo "=========================================="

# 0. 环境检查
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "!! 未找到 xcodebuild。请在 macOS 上运行本脚本。"
  exit 1
fi

echo "==> Xcode: $(xcodebuild -version | head -1)"

# 0.5 预检：iOS 版本兼容性、Info.plist、工程声明、资源完整性
echo
echo "==> 预检"
python3 Tools/preflight.py || {
  echo "!! 预检未通过，已中止。"
  exit 1
}

# 0.6 Swift 结构检查：括号平衡、重复定义、未知类型引用
#     在没有编译器的环境下提前拦掉最常见的语法级错误
echo
echo "==> Swift 结构检查"
python3 Tools/lint_swift.py || {
  echo "!! 结构检查未通过，已中止。"
  exit 1
}

# 0.7 规格审计 + 值语义推演（按页留档，逐页跑一遍）
#     审计查「规格要求的东西在不在」，推演查「纯值层的算法对不对」。
#     本机没有编译器，这两层是唯一能发现逻辑错误的防线。
echo
echo "==> 规格审计与值语义推演"
GATE_FAIL=0
for f in Tools/audit_page*.py; do
  [ -e "$f" ] || continue
  if ! python3 "$f" >/dev/null 2>&1; then
    echo "   !! 未通过: $f"
    python3 "$f" || true
    GATE_FAIL=1
  fi
done
for f in Tools/probe_page*_semantics.py; do
  [ -e "$f" ] || continue
  if ! python3 "$f" >/dev/null 2>&1; then
    echo "   !! 未通过: $f"
    python3 "$f" || true
    GATE_FAIL=1
  fi
done
# 调用点一致性：声明在 A 文件、调用在 B 文件的参数个数/标签错误。
# 上面两层都是单文件内的检查，看不见这类问题 —— 2026-09-20 第一次真编译
# 报出的 14 个错误里有 5 个是这一层才能发现的。
if ! python3 Tools/audit_call_sites.py; then
  echo "   !! 未通过: Tools/audit_call_sites.py"
  GATE_FAIL=1
fi
# 视图体规模：单个 some View 表达式过大 → 类型检查器直接放弃。
# 2026-09-20 第二次真编译就是被 RootView 的 66 层大括号 body 挡住的，
# 前五层全绿也看不见（括号平衡、类型存在、调用点齐全、值语义都对）。
if ! python3 Tools/audit_body_size.py; then
  echo "   !! 未通过: Tools/audit_body_size.py"
  GATE_FAIL=1
fi
if [ "$GATE_FAIL" -ne 0 ]; then
  echo "!! 规格审计 / 值语义推演 / 规模审计未通过，已中止。"
  exit 1
fi
echo "    全部通过"

# 1. 校验素材
echo
echo "==> 校验资源"
chmod +x Tools/package_resources.sh
./Tools/package_resources.sh

# 2. 生成工程
echo
echo "==> 生成 Xcode 工程"
chmod +x Tools/make_project.sh
./Tools/make_project.sh

# 3. 编译
echo
echo "==> 编译 ($CONFIG)"
rm -rf build
xcodebuild \
  -project FitnessApp.xcodeproj \
  -scheme FitnessApp \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -derivedDataPath build \
  -destination 'generic/platform=iOS' \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ONLY_ACTIVE_ARCH=NO \
  clean build

# 4. 定位 .app
APP="$(find build -name 'FitnessApp.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "!! 未找到 FitnessApp.app"
  exit 1
fi
echo "==> .app: $APP ($(du -sh "$APP" | cut -f1))"

# 5. 伪签名
echo
echo "==> 伪签名"
if command -v ldid >/dev/null 2>&1; then
  ldid -S"Tools/entitlements.plist" "$APP/FitnessApp" || ldid -S "$APP/FitnessApp"
  echo "    ldid 完成"
else
  echo "    !! 未找到 ldid，跳过（TrollStore 设备端仍会签名）"
  echo "    安装 ldid: brew install ldid"
fi

# 6. 打包 IPA
echo
echo "==> 打包 IPA"
rm -rf out FitnessApp-unsigned.ipa
mkdir -p out/Payload
cp -R "$APP" out/Payload/
rm -rf "out/Payload/FitnessApp.app/_CodeSignature" || true
rm -rf out/Payload/FitnessApp.app/*.dSYM || true
cd out
zip -qry "../FitnessApp-unsigned.ipa" Payload
cd ..

rm -rf out

echo
echo "=========================================="
echo " 完成"
echo " IPA: $ROOT/FitnessApp-unsigned.ipa"
echo " 体积: $(du -h FitnessApp-unsigned.ipa | cut -f1)"
echo "=========================================="
echo
echo "安装到设备："
echo "  1. 把 IPA 传到 iPhone（AirDrop / 文件 App / 局域网服务）"
echo "  2. 用 TrollStore 打开该 IPA"
echo "  3. 点击 Install"
