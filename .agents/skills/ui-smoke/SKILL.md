---
name: ui-smoke
description: Run autonomous OpenScribe UI smoke checks that build/test the app and produce screenshot/report artifacts for validation.
metadata:
  short-description: Run UI smoke checks
---

# Skill: ui-smoke

## Purpose

Run autonomous UI smoke checks for OpenScribe with reproducible artifacts.

## Inputs

- Optional output directory via `--out <dir>`.
- Optional packaged app path via `--app <path-to-app>`.

## Run

From repo root (`pwd=/path/to/OpenScribe`):

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh
```

Custom output path from current `pwd`:

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
```

Packaged app smoke from current `pwd`:

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh \
  --app dist/OpenScribe-0.2.3-arm64/OpenScribe.app \
  --out artifacts/ui-smoke/release-arm64
```

## Outputs

- `build.log`
- `test.log`
- `run.log`
- `openscribe-window.png`
- `openscribe-window-hotkey-history-direct.png`
- `openscribe-window-click-history.png`
- `openscribe-window-click-history-full.png`
- `openscribe-window-click-stats.png`
- `openscribe-window-hotkey-history.png`
- `openscribe-window-hotkey-history-full.png`
- `openscribe-window-hotkey-stats.png`
- `openscribe-window-hotkey-live.png`
- `openscribe-window-live-expanded-content.png`
- `settings-window.png`
- `settings-window-dark.png`
- `settings-general.png`
- `settings-general-dark.png`
- `settings-transcribe.png`
- `settings-transcribe-dark.png`
- `settings-polish.png`
- `settings-polish-dark.png`
- `settings-providers.png`
- `settings-providers-dark.png`
- `settings-hotkeys.png`
- `settings-hotkeys-dark.png`
- `settings-rules.png`
- `settings-rules-dark.png`
- `settings-data.png`
- `settings-data-dark.png`
- `settings-about.png`
- `settings-about-dark.png`
- `menubar-icon-<mode>-<state>.png` (18 files across 3 appearance modes and 6 icon states)
- `ui-smoke-status.txt`
- `ui-smoke-debug.txt`
- `report.md`

Default output directory:

- Relative to repo root: `artifacts/ui-smoke/<timestamp>/`
- Absolute pattern: `/path/to/OpenScribe/artifacts/ui-smoke/<timestamp>/`

When `--out` is set:

- Absolute values stay absolute.
- Relative values are resolved from the command invocation `pwd`.

## Workflow

1. Build app (`swift build`)
2. Run tests (`swift test`)
3. Launch app in smoke mode (`OPENSCRIBE_UI_SMOKE=1 swift run OpenScribe`)
4. App captures regression popover artifacts plus light and dark settings screenshots internally.
5. App captures menubar icon state snapshots for `system`, `light`, and `dark` appearances.
6. Script validates screenshot artifacts and writes markdown report
7. Review screenshots manually to confirm visual correctness.
8. For faster manual QA, open screenshots with the image viewer tool in parallel batches instead of one at a time.

When `--app` is set:

1. Skip `swift build` and `swift test`
2. Launch the packaged app executable from `<App>.app/Contents/MacOS/<App>`
3. Reuse the same internal screenshot and status capture flow against the bundled app layout
4. Use this mode for release-shape verification of resource, bundle, and packaging regressions

## Notes

- Internal capture avoids transient macOS focus/automation races for popover windows.
- Settings screenshots are moved to the built-in Retina display when available so light and dark docs assets stay crisp.
- Popover screenshots remain smoke-only regression artifacts. Published docs reuse curated assets from `site-docs/images/ui/`.
- The run is strict: missing required screenshots causes a failing exit code.
- The run is strict: tab parity checks must use real segmented-control click dispatch in smoke mode.
- The run is strict: hotkey tab checks must use real hotkey dispatch in smoke mode.
- The run is strict: history layout parity between click and hotkey tab switching must pass.
- The run is strict: compact history view must fill vertically without large leftover slack.
- The run is strict: expanded live view with transcript content must capture successfully.
- Artifact validation checks presence and required coverage. Visual QA is manual.
- Agent-side image review can be parallelized by opening multiple screenshots at once with the image viewer tool.
