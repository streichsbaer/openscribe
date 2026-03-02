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

## Run

From repo root (`pwd=/path/to/OpenScribe`):

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh
```

Custom output path from current `pwd`:

```bash
zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest
```

## Outputs

- `build.log`
- `test.log`
- `run.log`
- `openscribe-window.png`
- `openscribe-window-hotkey-history-direct.png`
- `openscribe-window-click-history.png`
- `openscribe-window-hotkey-history.png`
- `openscribe-window-hotkey-live.png`
- `settings-window.png`
- `settings-general.png`
- `settings-providers.png`
- `settings-hotkeys.png`
- `settings-rules.png`
- `settings-data.png`
- `settings-about.png`
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
4. App captures popover + settings screenshots internally (including all settings tabs)
5. App captures menubar icon state snapshots for `system`, `light`, and `dark` appearances.
6. Script validates screenshot artifacts and writes markdown report
7. Review screenshots manually to confirm visual correctness.
8. For faster manual QA, open screenshots with the image viewer tool in parallel batches instead of one at a time.

## Notes

- Internal capture avoids transient macOS focus/automation races for popover windows.
- The run is strict: missing required screenshots causes a failing exit code.
- The run is strict: tab parity checks must use real segmented-control click dispatch in smoke mode.
- The run is strict: hotkey tab checks must use real hotkey dispatch in smoke mode.
- The run is strict: history layout parity between click and hotkey tab switching must pass.
- Artifact validation checks presence and required coverage. Visual QA is manual.
- Agent-side image review can be parallelized by opening multiple screenshots at once with the image viewer tool.
