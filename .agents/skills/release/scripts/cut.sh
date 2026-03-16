#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT_DIR"

VERSION=""
BUILD=""
ARTIFACT_ARM64_OVERRIDE=""
ARTIFACT_X86_64_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD="$2"
      shift 2
      ;;
    --artifact-arm64)
      ARTIFACT_ARM64_OVERRIDE="$2"
      shift 2
      ;;
    --artifact-x86_64)
      ARTIFACT_X86_64_OVERRIDE="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "Usage: $0 --version <semver> --build <integer> [--artifact-arm64 <zip-path>] [--artifact-x86_64 <zip-path>]" >&2
  exit 1
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must match SemVer X.Y.Z" >&2
  exit 1
fi

if ! [[ "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "Build must be an integer" >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before preparing release." >&2
  exit 1
fi

PLIST_PATH="Sources/OpenScribe/Resources/AppInfo.plist"
if [[ ! -f "$PLIST_PATH" ]]; then
  echo "Missing plist at $PLIST_PATH" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST_PATH"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST_PATH"

echo "[release] preflight verification"
swift build
swift test
RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
if [[ "$(uname -m)" == "arm64" ]]; then
  /usr/bin/arch -x86_64 swift build --arch x86_64
  /usr/bin/arch -x86_64 swift test --arch x86_64
fi

echo "[release] build artifacts"
OPENSCRIBE_BUILD_ARCH=arm64 zsh Scripts/build_release_app.sh
OPENSCRIBE_BUILD_ARCH=x86_64 zsh Scripts/build_release_app.sh

APP_PATH_ARM64="dist/OpenScribe-$VERSION-arm64/OpenScribe.app"
APP_PATH_X86_64="dist/OpenScribe-$VERSION-x86_64/OpenScribe.app"
ARTIFACT_PATH_ARM64="dist/OpenScribe-$VERSION-arm64.zip"
ARTIFACT_PATH_X86_64="dist/OpenScribe-$VERSION-x86_64.zip"
NOTARIZED_PATH_ARM64="dist/OpenScribe-$VERSION-arm64/OpenScribe-notarized.zip"
NOTARIZED_PATH_X86_64="dist/OpenScribe-$VERSION-x86_64/OpenScribe-notarized.zip"

if [[ -n "$ARTIFACT_ARM64_OVERRIDE" || -n "$ARTIFACT_X86_64_OVERRIDE" ]]; then
  if [[ -z "$ARTIFACT_ARM64_OVERRIDE" || -z "$ARTIFACT_X86_64_OVERRIDE" ]]; then
    echo "Provide both --artifact-arm64 and --artifact-x86_64 when overriding release artifacts." >&2
    exit 1
  fi
  ARTIFACT_PATH_ARM64="$ARTIFACT_ARM64_OVERRIDE"
  ARTIFACT_PATH_X86_64="$ARTIFACT_X86_64_OVERRIDE"
else
  SIGNING_IDENTITY="${OPENSCRIBE_SIGNING_IDENTITY:-}"
  NOTARY_PROFILE="${OPENSCRIBE_NOTARY_PROFILE:-openscribe-notary}"
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "Set OPENSCRIBE_SIGNING_IDENTITY to the Developer ID Application identity before running release cut." >&2
    exit 1
  fi
  echo "[release] sign and notarize arm64 artifact"
  zsh Scripts/sign_and_notarize_app.sh \
    "$APP_PATH_ARM64" \
    "$SIGNING_IDENTITY" \
    "$NOTARY_PROFILE"
  echo "[release] sign and notarize x86_64 artifact"
  zsh Scripts/sign_and_notarize_app.sh \
    "$APP_PATH_X86_64" \
    "$SIGNING_IDENTITY" \
    "$NOTARY_PROFILE"
  cp "$NOTARIZED_PATH_ARM64" "$ARTIFACT_PATH_ARM64"
  cp "$NOTARIZED_PATH_X86_64" "$ARTIFACT_PATH_X86_64"
fi

if [[ ! -f "$ARTIFACT_PATH_ARM64" ]]; then
  echo "Release artifact not found: $ARTIFACT_PATH_ARM64" >&2
  exit 1
fi

if [[ ! -f "$ARTIFACT_PATH_X86_64" ]]; then
  echo "Release artifact not found: $ARTIFACT_PATH_X86_64" >&2
  exit 1
fi

cp "$ARTIFACT_PATH_ARM64" "dist/OpenScribe-latest-arm64.zip"
cp "$ARTIFACT_PATH_X86_64" "dist/OpenScribe-latest-x86_64.zip"

mkdir -p dist/homebrew
zsh Scripts/generate_homebrew_cask.sh "$ARTIFACT_PATH_ARM64" "$ARTIFACT_PATH_X86_64" "v$VERSION" "dist/homebrew/openscribe.rb"

echo "[release] draft release notes"
echo "  mkdir -p artifacts/release-notes"
echo "  cp site-docs/ops/release-notes-template.md artifacts/release-notes/v$VERSION.md"
echo "  \$EDITOR artifacts/release-notes/v$VERSION.md"
echo "  Keep notes short: opening sentence, Highlights, optional Notes."
echo "  Do not include verification commands or an asset list in the release body."

echo "[release] prepared locally"
echo "Next steps:"
echo "  git add $PLIST_PATH"
echo "  git commit -F - <<'EOF'"
echo "  chore: cut release v$VERSION"
echo ""
echo "  Why"
echo "  - Prepare release artifact and metadata for OpenScribe v$VERSION."
echo ""
echo "  What"
echo "  - Updated app version/build in AppInfo.plist."
echo "  - Prepared arm64 and x86_64 release assets."
echo ""
echo "  Instruction"
echo "  - Cut release v$VERSION."
echo "  EOF"
echo "  git tag v$VERSION"
echo "  git push origin main --tags"
echo "  gh release create v$VERSION $ARTIFACT_PATH_ARM64 $ARTIFACT_PATH_X86_64 dist/OpenScribe-latest-arm64.zip dist/OpenScribe-latest-x86_64.zip --title 'OpenScribe $VERSION' --notes-file artifacts/release-notes/v$VERSION.md"
