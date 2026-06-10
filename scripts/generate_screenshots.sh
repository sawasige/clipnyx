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
cp "$OUT_JA/marketing-history-ja-light.png" "fastlane/screenshots/ja/1_履歴パネル.png"
cp "$OUT_JA/marketing-collection-ja-light.png" "fastlane/screenshots/ja/2_コレクション.png"
cp "$OUT_EN/marketing-history-en-light.png" fastlane/screenshots/en-US/1_history_panel.png
cp "$OUT_EN/marketing-collection-en-light.png" fastlane/screenshots/en-US/2_collection.png
# LP 用は表示幅 720px（@2x = 1440px）に縮小してファイルサイズを抑える
for lang in ja en; do
  OUT_VAR="OUT_JA"; [ "$lang" = "en" ] && OUT_VAR="OUT_EN"
  OUT="${!OUT_VAR}"
  sips --resampleWidth 1440 "$OUT/marketing-history-$lang-light.png" --out "docs/screenshot-$lang.png" >/dev/null
  sips --resampleWidth 1440 "$OUT/marketing-history-$lang-dark.png" --out "docs/screenshot-$lang-dark.png" >/dev/null
  sips --resampleWidth 1440 "$OUT/marketing-collection-$lang-light.png" --out "docs/screenshot-collection-$lang.png" >/dev/null
  sips --resampleWidth 1440 "$OUT/marketing-collection-$lang-dark.png" --out "docs/screenshot-collection-$lang-dark.png" >/dev/null
done

echo "==> Done. All variants (incl. dark) are in:"
echo "    ja: $OUT_JA"
echo "    en: $OUT_EN"
