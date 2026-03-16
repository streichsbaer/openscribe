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
  - `--artifact-arm64 <zip-path>` to override the default arm64 release artifact.
  - `--artifact-x86_64 <zip-path>` to override the default Intel release artifact.

## Outputs

- Updated `CFBundleShortVersionString` and `CFBundleVersion` in `AppInfo.plist`.
- Built notarized arm64 and Intel release artifacts in `dist/`.
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
   - On Apple Silicon hosts, add `/usr/bin/arch -x86_64 swift build --arch x86_64` and `/usr/bin/arch -x86_64 swift test --arch x86_64`
4. Build release app bundles:
   - `OPENSCRIBE_BUILD_ARCH=arm64 zsh Scripts/build_release_app.sh`
   - `OPENSCRIBE_BUILD_ARCH=x86_64 zsh Scripts/build_release_app.sh`
5. Sign and notarize both apps:
   - `zsh Scripts/sign_and_notarize_app.sh dist/OpenScribe-<version>-arm64/OpenScribe.app "Developer ID Application: <Name> (<TEAMID>)" openscribe-notary`
   - `zsh Scripts/sign_and_notarize_app.sh dist/OpenScribe-<version>-x86_64/OpenScribe.app "Developer ID Application: <Name> (<TEAMID>)" openscribe-notary`
6. Copy the notarized zips to `dist/OpenScribe-<version>-arm64.zip`, `dist/OpenScribe-<version>-x86_64.zip`, `dist/OpenScribe-latest-arm64.zip`, and `dist/OpenScribe-latest-x86_64.zip`.
7. Generate Homebrew cask from the notarized release zips:
   - `zsh Scripts/generate_homebrew_cask.sh ...`
8. Draft short user-facing release notes from `site-docs/ops/release-notes-template.md`.
   - Use one opening sentence, `Highlights`, and optional `Notes`.
   - Do not include verification commands or an asset list in the published body.
9. Commit, tag, and publish GitHub release with both notarized zip assets, both latest aliases, and the drafted notes file.
