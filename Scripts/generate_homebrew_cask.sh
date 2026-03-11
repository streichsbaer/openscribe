#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 2 || $# -gt 3 ]]; then
  echo "Usage: $0 <zip-path> <tag> [out-file]" >&2
  echo "Example: $0 dist/OpenScribe-0.1.0.zip v0.1.0 /tmp/openscribe.rb" >&2
  exit 1
fi

ZIP_PATH="$1"
TAG="$2"
OUT_FILE="${3:-}"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Zip not found: $ZIP_PATH" >&2
  exit 1
fi

if [[ "$TAG" == v* ]]; then
  VERSION="${TAG#v}"
else
  VERSION="$TAG"
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
TEMPLATE_PATH="$ROOT_DIR/packaging/homebrew/Casks/openscribe.rb.template"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

CASK_CONTENT="$(<"$TEMPLATE_PATH")"
CASK_CONTENT="${CASK_CONTENT//__VERSION__/$VERSION}"
CASK_CONTENT="${CASK_CONTENT//__SHA256__/$SHA256}"

if [[ -n "$OUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf "%s\n" "$CASK_CONTENT" > "$OUT_FILE"
  echo "[homebrew] wrote $OUT_FILE"
else
  printf "%s\n" "$CASK_CONTENT"
fi
