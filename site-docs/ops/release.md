# Release

## Goal

Create a shareable `.app` and release zip from `main`.

## Signing Prerequisites

- Use an explicit Apple identifier that matches the app bundle ID exactly.
- For the current direct-download release path, use `Developer ID Application` signing plus notarization.
- `Developer ID Application` certificate creation may require the Apple Developer `Account Holder`.
- Generate the certificate signing request on the Mac that will perform final signing, then create the certificate in Apple Developer and install the returned `.cer` on that same Mac.
- If the `Developer ID Application` certificate appears as untrusted, install the Apple `Developer ID - G2` intermediate certificate from the Apple PKI page.
- Store notarization credentials on the signing Mac before the release build:

```bash
xcrun notarytool store-credentials openscribe-notary \
  --apple-id "<apple-id-email>" \
  --team-id "<TEAMID>"
```

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
