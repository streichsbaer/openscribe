# OpenScribe

OpenScribe is a native macOS menu bar dictation app for fast speech-to-text with optional polish.

## Start Here

- Docs site: <https://openscribe.dev/>
- Product spec: <https://openscribe.dev/product/spec/>
- Roadmap: <https://openscribe.dev/product/roadmap/>
- Open issues: <https://github.com/streichsbaer/OpenScribe/issues>

## Quick Start

Prerequisites:

- Apple Silicon Mac
- Xcode and command line tools

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

## What OpenScribe Does

- Global hotkey recording flow.
- Local and API transcription providers.
- Optional polish step with configurable rules.
- Live, History, and Stats popover tabs.
- Session artifacts for replay and traceability.
- Copy and paste hotkeys for fast output handoff.

## Learn More

- Product overview: [site-docs/product/index.md](site-docs/product/index.md)
- Guides: [site-docs/guides/](site-docs/guides)
- Menu and settings: [site-docs/guides/menu-and-settings.md](site-docs/guides/menu-and-settings.md)
- Testing: [site-docs/ops/testing.md](site-docs/ops/testing.md)
- Release flow: [site-docs/ops/release.md](site-docs/ops/release.md)
- Reference contracts: [site-docs/reference/](site-docs/reference)

## Docs Development

```bash
uv sync --frozen --only-group docs --no-install-project
uv run mkdocs build --strict
uv run mkdocs serve --dev-addr 127.0.0.1:8000
```

Local preview URL:

- `http://127.0.0.1:8000/`

Post-push docs verification:

- [site-docs/ops/docs-verification.md](site-docs/ops/docs-verification.md)

## Contributing and Tracking

- Use GitHub Issues for features, bugs, and docs work.
- Tracking workflow: [site-docs/ops/issue-tracking.md](site-docs/ops/issue-tracking.md)
- Label taxonomy: [site-docs/ops/label-conventions.md](site-docs/ops/label-conventions.md)

## License

MIT. See [LICENSE](LICENSE).
