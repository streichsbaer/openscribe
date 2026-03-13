# Summary

- Replace this line with a short user-facing summary of the release.

# What Is New

- Replace this line with the primary shipped capability.

# Verification

- `swift build`
- `swift test`
- `RUN_AUDIO_FIXTURE_TESTS=1 swift test --filter FixturePipelineTests`
- `zsh .agents/skills/ui-smoke/scripts/run.sh --out artifacts/ui-smoke/latest`
- `zsh Scripts/build_release_app.sh`
- `zsh Scripts/sign_and_notarize_app.sh ...`

# Notes

- Replace this line with any concise install, distribution, or upgrade note.
