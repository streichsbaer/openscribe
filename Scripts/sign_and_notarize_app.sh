#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <app-path> <developer-id-identity> <notary-profile>" >&2
  echo "Example: $0 dist/OpenScribe-0.1.0/OpenScribe.app \"Developer ID Application: Your Name (TEAMID)\" openscribe-notary" >&2
  exit 1
fi

APP_PATH="$1"
SIGNING_IDENTITY="$2"
NOTARY_PROFILE="$3"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

APP_DIR="$(cd "$(dirname "$APP_PATH")" && pwd)"
APP_NAME="$(basename "$APP_PATH" .app)"
ZIP_PATH="$APP_DIR/$APP_NAME-signed.zip"
NOTARIZED_ZIP_PATH="$APP_DIR/$APP_NAME-notarized.zip"
BIN_DIR="$APP_PATH/Contents/Resources/bin"

sign_nested_code() {
  local code_path="$1"
  local options=()

  if [[ "$code_path" == *"/whisper-cli" ]]; then
    options+=(--options runtime)
  fi

  codesign --force --timestamp "${options[@]}" --sign "$SIGNING_IDENTITY" "$code_path"
}

echo "[release] signing $APP_PATH"
if [[ -d "$BIN_DIR" ]]; then
  echo "[release] signing bundled binaries in $BIN_DIR"
  for bin_path in "$BIN_DIR"/*; do
    if [[ -f "$bin_path" ]]; then
      sign_nested_code "$bin_path"
    fi
  done
fi

codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "[release] zipping signed app"
rm -f "$ZIP_PATH" "$NOTARIZED_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "[release] submitting for notarization"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "[release] stapling ticket"
xcrun stapler staple "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

echo "[release] creating notarized zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARIZED_ZIP_PATH"

echo "[release] signed zip: $ZIP_PATH"
echo "[release] notarized zip: $NOTARIZED_ZIP_PATH"
