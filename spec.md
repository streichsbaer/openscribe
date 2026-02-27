# SmartTranscript V1 Spec

## Target
- Native Apple Silicon macOS app (tested target: macOS 26, min package platform currently set to macOS 15 for tool compatibility).
- Menubar-only utility app.

## Core Flow
1. Global hotkey toggles recording.
2. Audio is captured to `audio.wav.part`.
3. On stop, audio is finalized atomically to `audio.wav`.
4. STT runs via selected provider.
5. Polish runs via selected LLM provider with `Rules/rules.md`.
6. Session artifacts are written: `audio.wav`, `session.json`, `raw.txt`, `polished.md`.

## Defaults
- Start/stop hotkey default: `Fn + Space` (configurable).
- Copy hotkey default: `Ctrl + Option + V` (configurable).
- Copy hotkey behavior: copy latest polished transcript then paste via synthetic `Cmd + V` (requires Accessibility permission).
- If hotkey registration fails, app shows blocking warning and requires manual change.
- Default STT provider: local `whisper.cpp`.
- Default local model: `base`.
- Language: `auto`.
- Copy-on-complete: enabled.

## Storage Layout
Root: `~/Library/Application Support/SmartTranscript`

- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/audio.wav`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/session.json`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/raw.txt`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/polished.md`
- `Rules/rules.md`
- `Rules/rules.history.jsonl`
- `Models/whisper/ggml-<model>.bin`
- `Config/settings.json`

## Providers
- STT:
  - Local `whisper.cpp`
  - OpenAI Whisper API
  - Groq Whisper API
- Polish:
  - OpenAI chat API
  - Groq chat API

## Transcript UI
- Raw transcript is shown in an editable text area.
- Polished transcript is shown directly below raw text.
- No raw/polished tab switcher.

## Out of Scope (V1)
- Streaming transcription.
- Sync/team dictionaries.
- Speaker diarization and timestamps.

## Improvement Backlog
- Show a clear processing state and elapsed timer while polish is running.
- Explore always-on wake phrase mode:
  - keep listening while active
  - start transcript on action phrase
  - auto-stop after silence cooldown
  - voice commands for `pause recording`, `resume recording`, `stop recording`
- Evaluate always-on mic coexistence behavior with other apps on macOS and define user-facing constraints.

## Build/Run
- `swift build`
- `swift run SmartTranscript`

For full app signing/notarization and polished packaging, use a follow-up release phase.
