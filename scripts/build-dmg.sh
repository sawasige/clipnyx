#!/bin/bash
set -euo pipefail

APP_NAME="Clipnyx"
SCHEME="Clipnyx-Full"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="${PROJECT_DIR}/Clipnyx/Clipnyx.xcodeproj"
BUILD_DIR="${PROJECT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
EXPORT_OPTIONS="${PROJECT_DIR}/scripts/ExportOptions.plist"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving ${APP_NAME}..."
xcodebuild archive \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release-Full \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

echo "==> Exporting ${APP_NAME}.app..."
if xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -quiet 2>/dev/null; then
    APP_PATH="${EXPORT_DIR}/${APP_NAME}.app"
else
    echo "    exportArchive failed (Developer ID certificate not found)."
    echo "    Falling back to archive .app bundle..."
    APP_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
fi

if [ ! -d "$APP_PATH" ]; then
    echo "Error: ${APP_PATH} not found" >&2
    exit 1
fi

echo "==> Creating DMG..."
STAGING_DIR="${BUILD_DIR}/dmg-staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> Done: ${DMG_PATH}"
