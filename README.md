# OpenScribe

Native macOS menubar dictation app scaffold for Apple Silicon.

## Implemented V1 foundations

- Menubar-only app shell with popover UI.
- Global hotkey toggle (default `Fn + Space`).
- Copy-latest hotkey (default `Ctrl + Option + C`, configurable).
- Paste-latest hotkey (default `Ctrl + Option + V`, configurable) pastes into the frontmost app when Accessibility permission is granted.
- Crash-safe audio capture to `audio.capture.wav.part` with atomic finalize to `audio.m4a`.
- Session artifacts persisted under `~/Library/Application Support/OpenScribe`.
- STT provider abstraction with implementations for:
  - Local `whisper.cpp`
  - OpenAI Whisper
  - Groq Whisper
  - OpenRouter (OpenAI-compatible audio chat transcription)
  - Gemini (OpenAI-compatible audio chat transcription)
- LLM polish provider abstraction with implementations for:
  - OpenAI chat completions
  - Groq chat completions
  - OpenRouter chat completions
  - Gemini chat completions
- Rules file editor + open in external editor.
- Transcript view shows Raw (editable) and Polished text in a single stacked layout (no tab switcher).
- Local model manager (install/remove) for `whisper.cpp` models.

## Build

```bash
swift build
```

## Run

```bash
swift run OpenScribe
```

## Live Provider Smoke (TTS Generated Audio)

Generate a local TTS WAV and run live transcription + polish smoke tests for selected/OpenRouter/Gemini providers:

```bash
zsh Scripts/run_live_provider_smoke.sh
```

Artifacts and per-case logs are written under `artifacts/live-provider-smoke/<timestamp>/`.

## Release

- Build local release app bundle and zip:

```bash
zsh Scripts/build_release_app.sh
```

- Full shipping guide:
  - [docs/release.md](docs/release.md)
- Testing and smoke workflow:
  - [docs/testing.md](docs/testing.md)
- Homebrew cask template:
  - [packaging/homebrew/Casks/openscribe.rb.template](packaging/homebrew/Casks/openscribe.rb.template)

## License

MIT. See [LICENSE](LICENSE).

## Agent Guidance

- `SOUL.md` captures the app values and priorities that the agent follows.
- `AGENTS.md` defines how agents should work in this repo.
- Add agent specific guidance by updating `SOUL.md` and `AGENTS.md`.

## Notes

- For local STT, install `whisper-cli` or package a bundled binary in app resources at `bin/whisper-cli`.
- API keys are stored in Keychain entries:
  - `openai_api_key`
  - `groq_api_key`
  - `openrouter_api_key`
  - `gemini_api_key`
- Environment variable fallback is supported:
  - `OPENAI_API_KEY`
  - `GROQ_API_KEY`
  - `SCRIBE_OPENROUTER_API_KEY` or `OPENROUTER_API_KEY`
  - `GEMINI_API_KEY`
  - Keychain values take precedence over environment values.
