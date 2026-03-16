# OpenScribe

OpenScribe is a native macOS menu bar dictation app for fast speech-to-text with optional polish.

Download the latest stable version:

- Apple Silicon Mac: <https://github.com/streichsbaer/openscribe/releases/latest/download/OpenScribe-latest-arm64.zip>
- Intel Mac: <https://github.com/streichsbaer/openscribe/releases/latest/download/OpenScribe-latest-x86_64.zip>

Install with Homebrew:

```bash
brew install --cask streichsbaer/tap/openscribe
```

## Start Here

- Getting Started: <https://openscribe.dev/guides/getting-started/>
- Docs site: <https://openscribe.dev/>
- Latest stable Apple Silicon Mac download: <https://github.com/streichsbaer/openscribe/releases/latest/download/OpenScribe-latest-arm64.zip>
- Latest stable Intel Mac download: <https://github.com/streichsbaer/openscribe/releases/latest/download/OpenScribe-latest-x86_64.zip>
- Homebrew cask: `brew install --cask streichsbaer/tap/openscribe`
- Latest stable release page: <https://github.com/streichsbaer/openscribe/releases/latest>
- Product spec: <https://openscribe.dev/product/spec/>
- Roadmap: <https://openscribe.dev/product/roadmap/>
- Open issues: <https://github.com/streichsbaer/openscribe/issues>

## Compatibility

- macOS 14 Sonoma or later

## Build from Source

Prerequisites:

- Xcode and command line tools
- Swift toolchain compatible with `Package.swift`

Build and run:

```bash
swift build
swift run OpenScribe
```

First-run checks:

1. Confirm the menu bar icon appears.
2. Record and stop one short session.
3. Confirm text appears in the Live tab.
4. Confirm a session folder is created under `~/Library/Application Support/OpenScribe`.

More setup details:

- Getting Started: <https://openscribe.dev/guides/getting-started/>
- Development Setup: [site-docs/reference/development-setup.md](site-docs/reference/development-setup.md)

## License

MIT. See [LICENSE](LICENSE).
