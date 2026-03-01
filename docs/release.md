# OpenScribe Release Guide

## Goal

Create a shareable `.app` and optional signed+notarized package from `main`.

## Versioning Policy

- Use SemVer: `MAJOR.MINOR.PATCH`.
- Use git tag format: `vMAJOR.MINOR.PATCH`.
- Keep `CFBundleShortVersionString` in sync with SemVer.
- Increment `CFBundleVersion` for each release cut.

## Release Notes Policy

- GitHub Releases is the canonical release history.
- Do not maintain a manual `CHANGELOG.md`.
- Generate release notes from GitHub during release creation.

## Prerequisites

1. Xcode + command line tools installed.
2. Clean working tree on `main`.
3. Local verification passed:
   - `swift build`
   - `swift test`
   - `RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests`
   - `zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest`

## Build Unsigned App

```bash
zsh Scripts/build_release_app.sh
```

Outputs:

- `dist/OpenScribe-<version>/OpenScribe.app`
- `dist/OpenScribe-<version>.zip`

## Publish GitHub Release

1. Create a tag from `main`:

```bash
git tag v<version>
git push origin v<version>
```

2. Create a GitHub release for that tag with generated notes and upload:
   - `dist/OpenScribe-<version>.zip` for unsigned internal testing, or
   - `dist/OpenScribe-<version>/OpenScribe-notarized.zip` for external users.

## Sign + Notarize

First, create a notary profile once:

```bash
xcrun notarytool store-credentials openscribe-notary \
  --apple-id "<apple-id>" \
  --team-id "<team-id>" \
  --password "<app-specific-password>"
```

Then run:

```bash
zsh Scripts/sign_and_notarize_app.sh \
  dist/OpenScribe-<version>/OpenScribe.app \
  "Developer ID Application: <Name> (<TEAMID>)" \
  openscribe-notary
```

Outputs:

- `dist/OpenScribe-<version>/OpenScribe-signed.zip`
- `dist/OpenScribe-<version>/OpenScribe-notarized.zip`

## Homebrew Cask (streichsbaer/homebrew-tap)

Generate a cask file from your release zip and tag:

```bash
zsh Scripts/generate_homebrew_cask.sh \
  dist/OpenScribe-<version>.zip \
  v<version> \
  /tmp/openscribe.rb
```

Then:

1. Open your tap repository `streichsbaer/homebrew-tap`.
2. Copy generated cask to `Casks/openscribe.rb`.
3. Commit and push.
4. Install test:

```bash
brew tap streichsbaer/tap
brew install --cask openscribe
```

## Release Checklist

1. Version in `Sources/OpenScribe/Resources/AppInfo.plist` is updated.
2. Tests and smoke run pass.
3. Build output exists under `dist/`.
4. If distributing outside your own machine, signed+notarized zip is produced.
5. Install smoke check on a second machine:
   - launch app
   - grant microphone permission
   - run one short recording
   - verify raw + polished output

## Optional Automation Skill

Use the repo-local release skill to run the standard release flow:

```bash
zsh .agents/skills/release/scripts/cut.sh --version <x.y.z> --build <n>
```
The script prepares version/build, preflight checks, artifact build, and Homebrew cask output, then prints commit/tag/release commands.
