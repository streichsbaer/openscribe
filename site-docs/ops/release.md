# Release

## Goal

Create a shareable `.app` and release zip from `main`.

## Preflight

- Clean working tree.
- Verification loop passes.

## Build unsigned app

```bash
zsh Scripts/build_release_app.sh
```

Outputs:

- `dist/OpenScribe-<version>/OpenScribe.app`
- `dist/OpenScribe-<version>.zip`

Notes:

- Release builds bundle a pinned Apple Silicon `whisper-cli` inside `OpenScribe.app`.
- Local whisper models are still downloaded on demand after install.

## Tag and publish

```bash
git tag v<version>
git push origin v<version>
```

Create GitHub Release from that tag and upload release zip.

## Optional signing and notarization

Use the signing script when external distribution requires notarization:

```bash
zsh Scripts/sign_and_notarize_app.sh \
  dist/OpenScribe-<version>/OpenScribe.app \
  "Developer ID Application: <Name> (<TEAMID>)" \
  openscribe-notary
```

## Related

- Validation loop: [Testing](testing.md)
