---
name: release
description: Cut OpenScribe releases with a repeatable flow aligned to docs/release.md, including preflight checks, artifact build, and publish commands.
metadata:
  short-description: Cut a release
---

# Skill: release

## Purpose

Cut OpenScribe releases with a repeatable flow aligned to `docs/release.md`.

## Policy

- GitHub Releases is the canonical release history.
- Do not maintain a manual `CHANGELOG.md`.

## Inputs

- Required:
  - `--version <semver>` (for example `0.2.0`)
  - `--build <integer>` (for example `2`)
- Optional:
  - `--artifact <zip-path>` to override default release artifact.

## Outputs

- Updated `CFBundleShortVersionString` and `CFBundleVersion` in `AppInfo.plist`.
- Built release artifact in `dist/`.
- Generated Homebrew cask snippet under `dist/homebrew/openscribe.rb`.
- Printed next-step commands for commit/tag/release.

## Workflow

1. Validate clean git working tree.
2. Update app version/build in `AppInfo.plist`.
3. Run release verification loop:
   - `swift build`
   - `swift test`
   - `RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests`
   - `zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest`
4. Build release artifact:
   - `zsh Scripts/build_release_app.sh`
5. Generate Homebrew cask from the zip:
   - `zsh Scripts/generate_homebrew_cask.sh ...`
6. Commit, tag, and publish GitHub release with generated notes using printed commands.
