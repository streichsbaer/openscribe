# Development Setup

## Prerequisites

- Mac capable of running macOS 14 Sonoma.
- Xcode and command line tools.
- Swift toolchain compatible with `Package.swift`.
- If you want local `whisper.cpp` transcription while running from source, install `whisper-cli` separately. Release builds bundle an architecture-matched binary automatically.

## Build and run

```bash
swift build
swift run OpenScribe
```

## First-run checks

1. Confirm the menu bar icon appears.
2. Start and stop one short recording.
3. Verify raw and polished output are visible in the popover.
4. Verify a session folder is created under `~/Library/Application Support/OpenScribe/Recordings/`.

## Side-by-side test build

To try a change next to your installed OpenScribe, build `OpenScribe Dev.app`. The build compiles the bundled whisper.cpp, so it needs `cmake` (`brew install cmake`):

```bash
zsh Scripts/build_side_by_side_app.sh
open "dist/side-by-side/OpenScribe Dev.app"
```

It runs with its own identity so both apps work at the same time:

- Data lives in `~/Library/Application Support/OpenScribe Dev`, so settings, recordings, and models stay separate.
- Start or stop recording with `Fn + Shift + Space`. Every other shortcut adds `Cmd` to its usual `Ctrl + Option` combination.
- The menu bar icon shows a `Dev` label.
- API keys are shared through the Keychain. macOS asks once whether the dev build may read them.
- Microphone and Accessibility permissions are granted separately.

Delete the dev app and `~/Library/Application Support/OpenScribe Dev` when you are done.

### Test on another Mac

The build also writes a zip next to the app, ready to AirDrop. Build for an Intel Mac with:

```bash
OPENSCRIBE_BUILD_ARCH=x86_64 zsh Scripts/build_side_by_side_app.sh dist/side-by-side-x86_64
```

On the receiving Mac, unzip the app. It is not notarized, so macOS blocks the first launch. Allow it once with Control-click > Open, or from System Settings > Privacy & Security > Open Anyway, or clear the download flag:

```bash
xattr -dr com.apple.quarantine "OpenScribe Dev.app"
```

Each rebuild counts as a new app for macOS permissions. After replacing the app, remove OpenScribe Dev from System Settings > Privacy & Security > Accessibility and grant it again, or auto-paste stops working.

## Docs site

The documentation site uses MkDocs with Material theme. To build and preview locally:

```bash
uv sync --frozen --only-group docs --no-install-project
uv run mkdocs build --strict
uv run mkdocs serve --dev-addr 127.0.0.1:8000
```

Preview URL: `http://127.0.0.1:8000/`

## Continue

- Verification loop: [Testing](../ops/testing.md)
- Product behavior contract: [Product Spec](../product/spec.md)
- How to contribute: [Contributing](../product/contributing.md)
