---
name: release
description: Cut OpenScribe releases with a repeatable flow aligned to docs/release.md, including verification, notarized artifact creation, and publish commands.
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
- Built notarized release artifacts in `dist/`.
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
4. Build release app bundle:
   - `zsh Scripts/build_release_app.sh`
5. Sign and notarize the app:
   - `zsh Scripts/sign_and_notarize_app.sh dist/OpenScribe-<version>/OpenScribe.app "Developer ID Application: <Name> (<TEAMID>)" openscribe-notary`
6. Copy the notarized zip to `dist/OpenScribe-<version>.zip` and `dist/OpenScribe-latest.zip`.
7. Generate Homebrew cask from the notarized release zip:
   - `zsh Scripts/generate_homebrew_cask.sh ...`
8. Draft release notes from `site-docs/ops/release-notes-template.md` and fill the sections deliberately.
9. Commit, tag, and publish GitHub release with the notarized zip assets and the drafted notes file.
