#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <arm64-zip-path> <x86_64-zip-path> <tag> [out-file]" >&2
  echo "Example: $0 dist/OpenScribe-0.1.0-arm64.zip dist/OpenScribe-0.1.0-x86_64.zip v0.1.0 /tmp/openscribe.rb" >&2
  exit 1
fi

ARM_ZIP_PATH="$1"
INTEL_ZIP_PATH="$2"
TAG="$3"
OUT_FILE="${4:-}"

if [[ ! -f "$ARM_ZIP_PATH" ]]; then
  echo "Zip not found: $ARM_ZIP_PATH" >&2
  exit 1
fi

if [[ ! -f "$INTEL_ZIP_PATH" ]]; then
  echo "Zip not found: $INTEL_ZIP_PATH" >&2
  exit 1
fi

if [[ "$TAG" == v* ]]; then
  VERSION="${TAG#v}"
else
  VERSION="$TAG"
fi

SHA256_ARM="$(shasum -a 256 "$ARM_ZIP_PATH" | awk '{print $1}')"
SHA256_INTEL="$(shasum -a 256 "$INTEL_ZIP_PATH" | awk '{print $1}')"
TEMPLATE_PATH="$ROOT_DIR/packaging/homebrew/Casks/openscribe.rb.template"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "Template not found: $TEMPLATE_PATH" >&2
  exit 1
fi

CASK_CONTENT="$(<"$TEMPLATE_PATH")"
CASK_CONTENT="${CASK_CONTENT//__VERSION__/$VERSION}"
CASK_CONTENT="${CASK_CONTENT//__SHA256_ARM__/$SHA256_ARM}"
CASK_CONTENT="${CASK_CONTENT//__SHA256_INTEL__/$SHA256_INTEL}"

if [[ -n "$OUT_FILE" ]]; then
  mkdir -p "$(dirname "$OUT_FILE")"
  printf "%s\n" "$CASK_CONTENT" > "$OUT_FILE"
  echo "[homebrew] wrote $OUT_FILE"
else
  printf "%s\n" "$CASK_CONTENT"
fi
