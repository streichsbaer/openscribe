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
