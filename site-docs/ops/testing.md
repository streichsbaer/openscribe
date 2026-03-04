# Testing

## Pre-commit loop

Run this sequence before behavior changes are merged:

```bash
swift build
swift test
RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
```

For docs specific verification before or after push, use:

- [Docs Verification](./docs-verification.md)

## Smoke artifacts

Required artifacts live under `artifacts/ui-smoke/latest/`.

- `report.md`
- `ui-smoke-status.txt`
- `ui-smoke-debug.txt`
- `openscribe-window.png`
- `settings-window.png`
- `settings-<tab>.png`
- `menubar-icon-<mode>-<state>.png`

Popover parity artifacts:

- `openscribe-window-click-history.png`
- `openscribe-window-click-history-full.png`
- `openscribe-window-hotkey-history.png`
- `openscribe-window-hotkey-history-full.png`
- `openscribe-window-hotkey-live.png`
- `openscribe-window-live-expanded-content.png`

## Fixture audio

```bash
zsh Scripts/generate_audio_fixtures.sh
```

## Release smoke

1. Launch app.
2. Confirm menu bar icon appears.
3. Record and stop once.
4. Confirm `audio.m4a`, `session.json`, `raw.txt`, and `polished.md` exist.
5. Confirm copy latest works.
