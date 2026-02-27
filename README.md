# SmartTranscript

Native macOS menubar dictation app scaffold for Apple Silicon.

## Implemented V1 foundations
- Menubar-only app shell with popover UI.
- Global hotkey toggle (default `Fn + Space`) and paste-latest hotkey (default `Ctrl + Option + V`).
- `Ctrl + Option + V` hotkey pastes the latest polished transcript into the frontmost app (requires Accessibility permission).
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
- Feedback loop that generates a unified diff, requires approval, updates rules, and auto re-polishes.
- Local model manager (install/remove) for `whisper.cpp` models.

## Build
```bash
swift build
```

## Run
```bash
swift run SmartTranscript
```

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
