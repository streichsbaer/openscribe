# Skill: ui-smoke

## Purpose

Run autonomous UI smoke checks for OpenScribe with reproducible artifacts.

## Inputs

- Optional output directory via `--out <dir>`.

## Outputs

- `build.log`
- `test.log`
- `run.log`
- `openscribe-window.png`
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

All outputs are stored in `artifacts/ui-smoke/<timestamp>/` by default.

## Workflow

1. Build app (`swift build`)
2. Run tests (`swift test`)
3. Launch app in smoke mode (`OPENSCRIBE_UI_SMOKE=1 swift run OpenScribe`)
4. App captures popover + settings screenshots internally (including all settings tabs)
5. App captures menubar icon state snapshots for `system`, `light`, and `dark` appearances.
6. Script validates screenshot artifacts and writes markdown report

## Notes

- Internal capture avoids transient macOS focus/automation races for popover windows.
- The run is strict: missing required screenshots causes a failing exit code.
