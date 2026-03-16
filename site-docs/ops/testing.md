# Testing

## Pre-commit loop

Run this sequence before behavior changes are merged:

```bash
swift build
swift test
RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
```

## Intel build and test on Apple Silicon

When release or packaging work touches Intel support, use Rosetta on an Apple Silicon Mac to add `x86_64` build and test coverage:

```bash
/usr/bin/arch -x86_64 swift build --arch x86_64
/usr/bin/arch -x86_64 swift test --arch x86_64
```

Notes:

- This is strong routine coverage for compilation and unit tests.
- Full Intel UI smoke remains a native Intel hardware check for now.

Maintainer-only runbooks for docs verification and marketing screenshots live in `docs/ops/` and are not part of the published docs site.

## Smoke artifacts

Required artifacts live under `artifacts/ui-smoke/latest/`.

- `report.md`
- `ui-smoke-status.txt`
- `ui-smoke-debug.txt`
- `openscribe-window.png`
- `settings-window.png`
- `settings-window-dark.png`
- `settings-<tab>.png`
- `settings-<tab>-dark.png`
- `menubar-icon-<mode>-<state>.png`

Notes:

- Settings screenshots are the docs refresh candidates and should come from the built-in Retina display when available in both light and dark appearances.
- Popover smoke screenshots are regression artifacts only. Published docs reuse curated assets in `site-docs/images/ui/`.

## UI layout checks

For app UI changes, verify both a compact laptop-sized window and a larger window on supported hardware.

Pass criteria:

- Primary actions stay visible or are reachable by scrolling.
- Required content and status text remain visible without clipped controls.
- No critical panel or sheet assumes an external display or oversized resolution.
- Images and screenshots shown in the app remain legible and do not crop required detail.

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
6. For UI changes, confirm the changed surface still works in a compact laptop-sized window and a larger window.
