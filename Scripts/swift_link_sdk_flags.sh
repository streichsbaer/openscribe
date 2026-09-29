# Source from zsh scripts that build the app with SwiftPM. Requires ROOT_DIR.
# SwiftPM's default build system links with --sysroot, so the linker records the deployment
# target as the SDK version. macOS then runs the app with the compatibility behavior of that
# old SDK: legacy control styles and an empty Settings window at launch. These flags record
# the real SDK version.
MACOS_DEPLOYMENT_TARGET="$(sed -n 's/.*\.macOS(\.v\([0-9]*\)).*/\1.0/p' "$ROOT_DIR/Package.swift")"
MACOS_SDK_VERSION="$(xcrun --show-sdk-version)"
SWIFT_LINK_SDK_FLAGS=(
  -Xlinker -platform_version
  -Xlinker macos
  -Xlinker "$MACOS_DEPLOYMENT_TARGET"
  -Xlinker "$MACOS_SDK_VERSION"
)

linked_sdk_version() {
  vtool -show-build "$1" | awk '$1 == "sdk" { print $2; exit }'
}
