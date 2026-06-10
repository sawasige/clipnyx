#!/bin/bash
# マーケティング用スクリーンショットを再生成する。
# Debug ビルドの ScreenshotRenderer がデモデータでパネルを描画し、
# docs/（LP 用）と fastlane/screenshots/（App Store 用）を更新する。
#
# 使い方: scripts/generate_screenshots.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# 画面収録の TCC 許可をパス変動で失わないよう、固定パスへビルドする
# （初回にシステム設定 ▸ 画面収録 でこの .app を許可する）
BUILD_DIR="$PWD/build/screenshots"
APP="$BUILD_DIR/Clipnyx.app"

echo "==> Building (Debug) to $BUILD_DIR ..."
# Sparkle 除去フェーズの残骸と再ビルドが衝突するため、前回の成果物を消してから build
rm -rf "$BUILD_DIR/Clipnyx.app"
xcodebuild build \
  -project Clipnyx/Clipnyx.xcodeproj \
  -scheme Clipnyx \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  -quiet

# LaunchServices（open）経由で起動するとユーザー起動扱いになり、ウィンドウが
# アクティブ（色付き信号機）で撮れる。同じ Bundle ID の本番アプリと干渉しない
# よう、生成中だけ本番を終了して最後に復帰させる。
PROD_WAS_RUNNING=0
if pgrep -fx "/Applications/Clipnyx.app/Contents/MacOS/Clipnyx" >/dev/null; then
  PROD_WAS_RUNNING=1
  echo "==> Quitting production Clipnyx during rendering..."
  osascript -e 'tell application "Clipnyx" to quit' >/dev/null 2>&1 || true
  sleep 1
fi
restore_production() {
  if [ "$PROD_WAS_RUNNING" = "1" ]; then
    echo "==> Restoring production Clipnyx..."
    open /Applications/Clipnyx.app
  fi
}
trap restore_production EXIT

render() { # render <lang>
  local log
  log=$(mktemp)
  open -n -W --stdout "$log" --stderr /dev/null "$APP" --args --render-screenshots -AppleLanguages "($1)"
  if grep -q "SCREENSHOTS_ERROR" "$log"; then
    cat "$log" >&2
    exit 1
  fi
  awk '/^SCREENSHOTS_DIR:/{print $2}' "$log"
}

echo "==> Rendering (ja)..."
OUT_JA=$(render ja)
echo "==> Rendering (en)..."
OUT_EN=$(render en)

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
