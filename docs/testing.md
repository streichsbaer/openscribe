# OpenScribe Testing Guide

## Pre-Commit Loop

Run this sequence before committing behavior changes:

```bash
swift build
swift test
RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
```

## Expected Smoke Artifacts

`artifacts/ui-smoke/latest/` must include:

- `report.md`
- `ui-smoke-status.txt`
- `ui-smoke-debug.txt`
- `openscribe-window.png`
- `settings-window.png`
- `settings-<tab>.png` for all tabs
- `menubar-icon-<mode>-<state>.png` for all icon-state snapshots
- Popover parity artifacts from `docs/popover-spec.md`:
  - `openscribe-window-click-history.png`
  - `openscribe-window-click-history-full.png`
  - `openscribe-window-hotkey-history.png`
  - `openscribe-window-hotkey-history-full.png`
  - `openscribe-window-hotkey-live.png`
  - `openscribe-window-live-expanded-content.png`

Settings screenshots are the docs refresh candidates and should be captured on the built-in Retina display when available. Popover smoke screenshots remain regression-only artifacts. The published docs reuse the curated assets in `site-docs/images/ui/openscribe-*.png`.

The smoke script exits non-zero if required artifacts are missing.

## Fixture Audio Tests

Fixture tests are offline and deterministic:

- `Tests/OpenScribeTests/Fixtures/cases.json`
- `Tests/OpenScribeTests/Fixtures/audio/*.wav`

Regenerate fixtures when needed:

```bash
zsh Scripts/generate_audio_fixtures.sh
```

## Release Validation

After building a release package, run one install smoke pass:

1. Launch app.
2. Confirm menubar icon appears.
3. Record and stop once.
4. Confirm `audio.m4a`, `session.json`, `raw.txt`, and `polished.md` exist.
5. Confirm copy latest works.
