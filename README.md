# SmartTranscript

Native macOS menubar dictation app scaffold for Apple Silicon.

## Implemented V1 foundations

- Menubar-only app shell with popover UI.
- Global hotkey toggle (default `Fn + Space`).
- Copy-latest hotkey (default `Ctrl + Option + C`, configurable).
- Paste-latest hotkey (default `Ctrl + Option + V`, configurable) pastes into the frontmost app when Accessibility permission is granted.
- Crash-safe audio capture to `audio.wav.part` with atomic finalize to `audio.wav`.
- Session artifacts persisted under `~/Library/Application Support/SmartTranscript`.
- STT provider abstraction with implementations for:
  - Local `whisper.cpp`
  - OpenAI Whisper
  - Groq Whisper
- LLM polish provider abstraction with implementations for:
  - OpenAI chat completions
  - Groq chat completions
- Rules file editor + open in external editor.
- Transcript view shows Raw (editable) and Polished text in a single stacked layout (no tab switcher).
- Local model manager (install/remove) for `whisper.cpp` models.

## Build

```bash
swift build
```

## Run

```bash
swift run SmartTranscript
```

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
- Environment variable fallback is supported:
  - `OPENAI_API_KEY`
  - `GROQ_API_KEY`
  - Keychain values take precedence over environment values.
- `swift test` currently requires a full Xcode toolchain on this machine (`xcodebuild` is not installed in the active developer directory).
