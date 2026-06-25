#!/bin/bash
# デモ録画モードで Clipnyx を起動する（画面収録用）。
# Debug ビルドを --demo-mode で起動すると、見栄えのするデモデータが入った状態で
# フル機能のアプリが立ち上がる。ストアは読み取り専用なので本物の履歴には一切
# 触れない・書き込まない（録画中にコピーした内容も永続化されない）。
#
# 使い方:
#   scripts/demo_mode.sh        # 言語は OS 設定に従う
#   scripts/demo_mode.sh ja     # 日本語デモデータで起動
#   scripts/demo_mode.sh en     # 英語デモデータで起動
#
# QuickTime か ⌘⇧5 で画面収録しながら、メニューバー / ホットキー / パネル /
# コレクションを普通に操作してください。アプリを終了すると本番 Clipnyx が復帰します。
set -euo pipefail
cd "$(dirname "$0")/.."

LANG_ARG="${1:-}"

BUILD_DIR="$PWD/build/demo"
APP="$BUILD_DIR/Clipnyx.app"

echo "==> Building (Debug) to $BUILD_DIR ..."
rm -rf "$BUILD_DIR/Clipnyx.app"
xcodebuild build \
  -project Clipnyx/Clipnyx.xcodeproj \
  -scheme Clipnyx \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
  -quiet

# 同じ Bundle ID の本番アプリと干渉しないよう、録画中だけ本番を終了して
# 最後に復帰させる（本番とコンテナを共有するため）。
PROD_WAS_RUNNING=0
if pgrep -fx "/Applications/Clipnyx.app/Contents/MacOS/Clipnyx" >/dev/null; then
  PROD_WAS_RUNNING=1
  echo "==> Quitting production Clipnyx during recording..."
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

ARGS=(--demo-mode)
if [ -n "$LANG_ARG" ]; then
  ARGS+=(-AppleLanguages "($LANG_ARG)")
fi

echo "==> Launching demo mode. 終了するまで待機します（録画してください）..."
echo "    メニューバーの Clipnyx アイコン / ホットキーでパネルを開けます。"
# -W: アプリが終了するまでブロック。終了したら trap で本番復帰。
open -n -W "$APP" --args "${ARGS[@]}"

echo "==> Demo mode finished."
