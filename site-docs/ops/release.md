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

## First-Time Apple Setup

1. Create the explicit App ID in Apple Developer and make sure it matches `CFBundleIdentifier` exactly.
2. On the Mac that will perform the final release signing, generate the certificate signing request in Keychain Access.
3. Have the Apple Developer `Account Holder` create the `Developer ID Application` certificate from that CSR.
4. Install the returned `.cer` on the same Mac that generated the CSR so the certificate pairs with the local private key.
5. If Keychain Access shows the certificate as untrusted or `security find-identity -v -p codesigning` reports `0 valid identities`, install the Apple `Developer ID - G2` intermediate certificate and re-check.
6. Store notarization credentials with `notarytool` and confirm the profile validates before the release build.

## Signing Notes

- `Scripts/sign_and_notarize_app.sh` signs bundled Mach-O files inside `OpenScribe.app/Contents/Resources/bin` before signing the outer app bundle.
- The hardened runtime release app must include the microphone entitlement `com.apple.security.device.audio-input` so macOS can present the microphone permission prompt.
- If new bundled executables, dynamic libraries, or frameworks are added later, they must be signed with the same `Developer ID` identity before the app bundle is signed and submitted for notarization.

## Troubleshooting

- Symptom: `security find-identity -v -p codesigning` reports `0 valid identities`
  Cause: the certificate is missing its matching private key on the signing Mac, or the Apple `Developer ID - G2` intermediate certificate is not installed.
- Symptom: notarization reports bundled binaries are not signed with a valid `Developer ID` certificate, are missing a secure timestamp, or do not have hardened runtime
  Cause: nested Mach-O code inside the app bundle was not signed explicitly before the outer app signature was applied.
- Symptom: the app never appears in Microphone settings and recording is denied immediately after launch
  Cause: the hardened runtime app was signed without the `com.apple.security.device.audio-input` entitlement, so TCC refuses to prompt for microphone access.
- Symptom: stapling fails with `Record not found`
  Cause: the notarization submission was rejected. Fetch the notarization log with `xcrun notarytool log <submission-id> --keychain-profile openscribe-notary` and fix the reported validation errors before retrying.

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

Create GitHub Release from that tag and upload:

- `dist/OpenScribe-<version>.zip`
- `dist/OpenScribe-latest.zip`

The docs landing page and README currently depend on this stable release asset name:

- `OpenScribe-latest.zip`

## Homebrew tap

OpenScribe ships via the sibling tap repo at `../homebrew-tap`.

After publishing the GitHub release, regenerate the tap cask from the released zip:

```bash
zsh Scripts/generate_homebrew_cask.sh \
  dist/OpenScribe-<version>.zip \
  v<version> \
  ../homebrew-tap/Casks/openscribe.rb
```

Then verify the tap repo:

- `brew style --display-cop-names Casks/openscribe.rb`
- `brew audit --strict --online --cask streichsbaer/tap/openscribe`

Then verify install behavior:

```bash
cd ../homebrew-tap
brew uninstall --cask openscribe || true
brew untap streichsbaer/tap || true
brew tap streichsbaer/tap
brew install --cask streichsbaer/tap/openscribe
```

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
