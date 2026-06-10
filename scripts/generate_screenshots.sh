#!/bin/bash
# マーケティング用スクリーンショットを再生成する。
# Debug ビルドの ScreenshotRenderer がデモデータでパネルを描画し、
# docs/（LP 用）と fastlane/screenshots/（App Store 用）を更新する。
#
# 使い方: scripts/generate_screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Building (Debug)..."
xcodebuild build \
  -project Clipnyx/Clipnyx.xcodeproj \
  -scheme Clipnyx \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -quiet

PRODUCTS_DIR=$(xcodebuild \
  -project Clipnyx/Clipnyx.xcodeproj \
  -scheme Clipnyx \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR/{print $3; exit}')
BIN="$PRODUCTS_DIR/Clipnyx.app/Contents/MacOS/Clipnyx"

echo "==> Rendering (ja)..."
OUT_JA=$("$BIN" --render-screenshots -AppleLanguages '(ja)' | awk '/^SCREENSHOTS_DIR:/{print $2}')
echo "==> Rendering (en)..."
OUT_EN=$("$BIN" --render-screenshots -AppleLanguages '(en)' | awk '/^SCREENSHOTS_DIR:/{print $2}')

echo "==> Copying outputs..."
# App Store 用は 2560×1600 のまま
cp "$OUT_JA/marketing-ja-light.png" "fastlane/screenshots/ja/1_履歴パネル.png"
cp "$OUT_EN/marketing-en-light.png" fastlane/screenshots/en-US/1_history_panel.png
# LP 用は表示幅 720px（@2x = 1440px）に縮小してファイルサイズを抑える
sips --resampleWidth 1440 "$OUT_JA/marketing-ja-light.png" --out docs/screenshot-ja.png >/dev/null
sips --resampleWidth 1440 "$OUT_EN/marketing-en-light.png" --out docs/screenshot-en.png >/dev/null

echo "==> Done. All variants (incl. dark) are in:"
echo "    ja: $OUT_JA"
echo "    en: $OUT_EN"
