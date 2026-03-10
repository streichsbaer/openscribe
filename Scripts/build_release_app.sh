#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="OpenScribe"
PLIST_PATH="Sources/OpenScribe/Resources/AppInfo.plist"
ICON_PATH="Sources/OpenScribe/Resources/AppIcon.icns"

OUT_DIR="$ROOT_DIR/dist"
if [[ $# -gt 0 ]]; then
  OUT_DIR="$1"
fi

if [[ ! -f "$PLIST_PATH" ]]; then
  echo "Missing plist at $PLIST_PATH" >&2
  exit 1
fi
if [[ ! -f "$ICON_PATH" ]]; then
  echo "Missing app icon at $ICON_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST_PATH")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST_PATH")"

echo "[release] building $APP_NAME $VERSION ($BUILD_NUMBER)"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

EXECUTABLE="$BIN_PATH/$APP_NAME"
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing executable at $EXECUTABLE" >&2
  exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "Missing resource bundle at $RESOURCE_BUNDLE" >&2
  exit 1
fi

RELEASE_DIR="$OUT_DIR/$APP_NAME-$VERSION"
APP_DIR="$RELEASE_DIR/$APP_NAME.app"
ZIP_PATH="$OUT_DIR/$APP_NAME-$VERSION.zip"
WHISPER_STAGE_DIR="$RELEASE_DIR/whisper.cpp"

rm -rf "$RELEASE_DIR" "$ZIP_PATH"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Resources" \
  "$APP_DIR/Contents/Resources/bin" \
  "$APP_DIR/Contents/Resources/licenses"

zsh "$ROOT_DIR/Scripts/build_bundled_whisper_cli.sh" "$WHISPER_STAGE_DIR"

cp "$PLIST_PATH" "$APP_DIR/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$WHISPER_STAGE_DIR/whisper-cli" "$APP_DIR/Contents/Resources/bin/whisper-cli"
cp "$WHISPER_STAGE_DIR"/*.dylib "$APP_DIR/Contents/Resources/bin/"
cp "$WHISPER_STAGE_DIR/LICENSE.whisper.cpp.txt" "$APP_DIR/Contents/Resources/licenses/whisper.cpp-LICENSE.txt"

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "[release] app: $APP_DIR"
echo "[release] zip: $ZIP_PATH"
