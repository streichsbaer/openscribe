#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: zsh Scripts/build_bundled_whisper_cli.sh <output-dir> [arm64|x86_64]" >&2
  exit 1
fi

TARGET_ARCH="${2:-${OPENSCRIBE_BUILD_ARCH:-$(uname -m)}}"
HOST_ARCH="$(uname -m)"
case "$TARGET_ARCH" in
  arm64|x86_64)
    ;;
  *)
    echo "Unsupported target architecture: $TARGET_ARCH" >&2
    exit 1
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bundled whisper-cli builds currently require macOS." >&2
  exit 1
fi

if ! command -v cmake >/dev/null 2>&1; then
  echo "cmake is required to build bundled whisper-cli." >&2
  exit 1
fi

WHISPER_CPP_VERSION="v1.8.3"
WHISPER_CPP_ARCHIVE_URL="https://github.com/ggml-org/whisper.cpp/archive/refs/tags/${WHISPER_CPP_VERSION}.tar.gz"
WHISPER_CPP_ARCHIVE_SHA256="870ba21409cdf66697dc4db15ebdb13bc67037d76c7cc63756c81471d8f1731a"
MACOS_DEPLOYMENT_TARGET="14.0"

OUTPUT_DIR="$1"
DOWNLOADS_DIR="$ROOT_DIR/.build/downloads"
CACHE_DIR="$ROOT_DIR/.build/vendor/whisper.cpp/${WHISPER_CPP_VERSION}/${TARGET_ARCH}"
ARCHIVE_PATH="$DOWNLOADS_DIR/whisper.cpp-${WHISPER_CPP_VERSION}.tar.gz"
SOURCE_DIR="$CACHE_DIR/source"
BUILD_DIR="$CACHE_DIR/build"

CMAKE_ARGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_OSX_ARCHITECTURES="$TARGET_ARCH"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_DEPLOYMENT_TARGET"
)

if [[ "$TARGET_ARCH" != "$HOST_ARCH" ]]; then
  # Cross-arch release builds must avoid host-native CPU tuning flags.
  CMAKE_ARGS+=(-DGGML_NATIVE=OFF)
fi

mkdir -p "$OUTPUT_DIR" "$DOWNLOADS_DIR" "$CACHE_DIR"

if [[ ! -f "$ARCHIVE_PATH" ]]; then
  curl -L "$WHISPER_CPP_ARCHIVE_URL" -o "$ARCHIVE_PATH"
fi

ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
if [[ "$ARCHIVE_SHA256" != "$WHISPER_CPP_ARCHIVE_SHA256" ]]; then
  echo "whisper.cpp archive checksum mismatch for $ARCHIVE_PATH" >&2
  echo "expected: $WHISPER_CPP_ARCHIVE_SHA256" >&2
  echo "actual:   $ARCHIVE_SHA256" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  rm -rf "$SOURCE_DIR"
  mkdir -p "$SOURCE_DIR"
  tar -xzf "$ARCHIVE_PATH" -C "$SOURCE_DIR" --strip-components=1
fi

rm -rf "$BUILD_DIR"
cmake -S "$SOURCE_DIR" -B "$BUILD_DIR" "${CMAKE_ARGS[@]}"

cmake --build "$BUILD_DIR" --target whisper-cli --config Release -j

BINARY_CANDIDATES=(
  "$BUILD_DIR/bin/whisper-cli"
  "$BUILD_DIR/bin/Release/whisper-cli"
  "$BUILD_DIR/Release/bin/whisper-cli"
)
REQUIRED_LIBRARY_CANDIDATES=(
  "$BUILD_DIR/src/libwhisper.1.dylib"
  "$BUILD_DIR/ggml/src/libggml.0.dylib"
  "$BUILD_DIR/ggml/src/libggml-cpu.0.dylib"
  "$BUILD_DIR/ggml/src/libggml-base.0.dylib"
)
OPTIONAL_LIBRARY_CANDIDATES=(
  "$BUILD_DIR/ggml/src/ggml-blas/libggml-blas.0.dylib"
  "$BUILD_DIR/ggml/src/ggml-metal/libggml-metal.0.dylib"
)
BUILD_RPATHS=(
  "$BUILD_DIR/src"
  "$BUILD_DIR/ggml/src"
  "$BUILD_DIR/ggml/src/ggml-blas"
  "$BUILD_DIR/ggml/src/ggml-metal"
)

WHISPER_CLI_PATH=""
for candidate in "${BINARY_CANDIDATES[@]}"; do
  if [[ -x "$candidate" ]]; then
    WHISPER_CLI_PATH="$candidate"
    break
  fi
done

if [[ -z "$WHISPER_CLI_PATH" ]]; then
  echo "Failed to locate built whisper-cli in $BUILD_DIR" >&2
  exit 1
fi

cp "$WHISPER_CLI_PATH" "$OUTPUT_DIR/whisper-cli"
cp "$SOURCE_DIR/LICENSE" "$OUTPUT_DIR/LICENSE.whisper.cpp.txt"

for candidate in "${REQUIRED_LIBRARY_CANDIDATES[@]}"; do
  if [[ ! -f "$candidate" ]]; then
    echo "Missing required whisper.cpp library at $candidate" >&2
    exit 1
  fi
  cp "$candidate" "$OUTPUT_DIR/"
done

for candidate in "${OPTIONAL_LIBRARY_CANDIDATES[@]}"; do
  if [[ -f "$candidate" ]]; then
    cp "$candidate" "$OUTPUT_DIR/"
  fi
done

for rpath in "${BUILD_RPATHS[@]}"; do
  install_name_tool -delete_rpath "$rpath" "$OUTPUT_DIR/whisper-cli" 2>/dev/null || true
done
install_name_tool -add_rpath "@executable_path" "$OUTPUT_DIR/whisper-cli"

for dylib in "$OUTPUT_DIR"/*.dylib; do
  for rpath in "${BUILD_RPATHS[@]}"; do
    install_name_tool -delete_rpath "$rpath" "$dylib" 2>/dev/null || true
  done
  install_name_tool -add_rpath "@loader_path" "$dylib"
done

echo "[whisper] target arch: $TARGET_ARCH"
echo "[whisper] bundled binary: $OUTPUT_DIR/whisper-cli"
echo "[whisper] bundled license: $OUTPUT_DIR/LICENSE.whisper.cpp.txt"
