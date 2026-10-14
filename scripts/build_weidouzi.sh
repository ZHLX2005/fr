#!/usr/bin/env bash
# 微豆子（weidouzi）变体一键本地构建 —— 构建期注入身份，不动任何提交的源文件。
#
# 用法：
#   scripts/build_weidouzi.sh           # 默认：主动瘦身 split-per-abi（arm64 单架构）
#   scripts/build_weidouzi.sh --fat     # 对照模式：与 v1 对齐的 fat 构建
#
# 前置：android/app/weidouzi.keystore 已存在（生成方式见 .github/KEYSTORE_SETUP.md 微豆子一节）。
# 产物：build/app/outputs/flutter-apk/app-arm64-v8a.apk
#       包名 io.github.xiaodouzi.fr.wdz，应用名「微豆子」，可与小豆子并存安装。
#
# 机制：向 android/gradle.properties 追加一行 appVariant=weidouzi（构建完删除），
#       配合 --dart-define=APP_VARIANT=weidouzi。源码零改动，小豆子默认构建不受影响。
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -f android/app/weidouzi.keystore ]; then
  echo "错误：缺少 android/app/weidouzi.keystore（微豆子签名）"
  echo "  生成方式见 .github/KEYSTORE_SETUP.md 「微豆子 keystore」一节"
  exit 1
fi

# ABI 过滤：默认走 --target-platform（单 arm64，主动瘦身）；
# --fat 模式不带 target-platform（与 v1 一致，ndk.abiFilters 在 defaultConfig 已经限 arm64）
if [ "${1:-}" = "--fat" ]; then
  ABI_FLAGS=()
else
  ABI_FLAGS=(--target-platform android-arm64)
fi

GRADLE_PROPS=android/gradle.properties
restore_props() {
  # 直接还原 gradle.properties 到 HEAD（最稳妥：只清脚本自己的追加）
  git checkout -- "$GRADLE_PROPS" 2>/dev/null || true
}
trap restore_props EXIT

# 不留任何残留行：用唯一的 marker 包住本次追加内容，trap 时按范围 sed 删除
MARKER="## weidouzi-build-tmp $$ ##"
printf '%s\nappVariant=weidouzi\n' "$MARKER" >> "$GRADLE_PROPS"

flutter build apk --release \
  --dart-define=APP_VARIANT=weidouzi \
  --obfuscate --split-debug-info=./debug_symbols_weidouzi \
  "${ABI_FLAGS[@]}"

restore_props
trap - EXIT

echo ""
echo "✅ 微豆子构建完成：build/app/outputs/flutter-apk/"
ls -la build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
