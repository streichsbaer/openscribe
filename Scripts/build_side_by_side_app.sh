#!/usr/bin/env zsh
# Build "OpenScribe Dev.app" from the current checkout to test next to the installed OpenScribe.
# It gets its own bundle identifier (separate microphone and Accessibility permissions), its own
# data folder (~/Library/Application Support/OpenScribe Dev), and hotkeys that do not collide:
# Fn+Shift+Space records, and every Control-Option shortcut adds Command.
# Build for another Mac with OPENSCRIBE_BUILD_ARCH=arm64 or x86_64; the zip is ready to AirDrop.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR="${1:-$ROOT_DIR/dist/side-by-side}"
APP_NAME="OpenScribe Dev"
BUNDLE_ID="dev.openscribe.app.dev"
TARGET_ARCH="${OPENSCRIBE_BUILD_ARCH:-$(uname -m)}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/OpenScribe/Resources/AppInfo.plist)"

OPENSCRIBE_BUILD_ARCH="$TARGET_ARCH" zsh "$ROOT_DIR/Scripts/build_release_app.sh" "$OUT_DIR/release"

SOURCE_APP="$OUT_DIR/release/OpenScribe-$VERSION-$TARGET_ARCH/OpenScribe.app"
DEV_APP="$OUT_DIR/$APP_NAME.app"
rm -rf "$DEV_APP"
ditto "$SOURCE_APP" "$DEV_APP"

PLIST="$DEV_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  -c "Set :CFBundleName $APP_NAME" \
  -c "Set :CFBundleDisplayName $APP_NAME" \
  -c "Add :OpenScribeSideBySide bool true" \
  "$PLIST"

codesign --force --deep --sign - "$DEV_APP"
codesign --verify --deep --strict "$DEV_APP"

ZIP_PATH="$OUT_DIR/OpenScribe-Dev-$VERSION-$TARGET_ARCH.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$DEV_APP" "$ZIP_PATH"

echo "[side-by-side] app: $DEV_APP ($TARGET_ARCH)"
echo "[side-by-side] zip: $ZIP_PATH"
echo "[side-by-side] data: $HOME/Library/Application Support/$APP_NAME"
echo "[side-by-side] start it with: open \"$DEV_APP\""
