# Product Spec

This is the canonical product spec for OpenScribe.

Roadmap execution lives in GitHub Issues and is summarized in [Roadmap](roadmap.md).

## Target

- Native Apple Silicon macOS app.
- Menubar-only utility app.

## Core flow

1. Global hotkey toggles recording.
2. Audio is captured to `audio.capture.wav.part`.
3. On stop, audio is finalized atomically to `audio.m4a`.
4. Audio activity guard validates speech signal before provider calls.
5. Empty or near-empty recordings skip STT and polish, store empty transcript outputs, and end with a `No audio captured` status.
6. STT runs via selected provider when speech signal is usable.
7. If polish is enabled, polish runs via selected LLM provider with `Rules/rules.md`.
8. If polish is disabled, polished output is passthrough from raw transcript.
9. Session artifacts are written: `audio.m4a`, `session.json`, `raw.txt`, `polished.md`.

## First-run setup assistant

- On a fresh install with no session history, OpenScribe opens a setup assistant in Settings on first launch.
- The assistant offers two paths: `Best setup` and `Local only`.
- `Best setup` guides Groq key entry, verification, Groq Whisper on `whisper-large-v3-turbo`, and Groq polish on `openai/gpt-oss-120b`.
- `Local only` guides local `whisper.cpp` model choice, model download, and a local test recording.
- Users can skip the assistant, hide it from future first launches, or reopen it later from Settings or the menu bar.

## Defaults

- Start or stop hotkey default: `Fn + Space`.
- Copy polished hotkey default: `Ctrl + Option + P`.
- Copy raw hotkey default: `Ctrl + Option + T`.
- Paste hotkey default: `Ctrl + Option + V`.
- Toggle popover hotkey default: `Ctrl + Option + O`.
- Open settings hotkey default: `Ctrl + Option + ,`.
- Popover tab hotkeys: `Ctrl + Option + L` (Live), `Ctrl + Option + H` (History), `Ctrl + Option + S` (Stats).
- Rules hotkey: `Ctrl + Option + R` opens Settings on the Rules tab.
- Paste hotkey behavior: copy latest polished transcript then paste via synthetic `Cmd + V` only when Accessibility permission is granted.
- If hotkey registration fails, app shows a blocking warning and requires manual change.
- Default STT provider: local `whisper.cpp`.
- Default local model: `base`.
- Default polish: disabled.
- Default polish provider and model: `OpenAI / gpt-5-nano`.
- Language: `auto`.
- Copy-on-complete: enabled.

## Storage layout

Root path:

- `~/Library/Application Support/OpenScribe`

- User guide: [Your Data](../guides/your-data.md)
- Technical contract: [Storage Contract](../reference/storage-contract.md)

## Providers

- STT:
  - Local `whisper.cpp`
  - OpenAI Whisper API
  - Groq Whisper API
  - OpenRouter (OpenAI-compatible API)
  - Gemini (OpenAI-compatible API)
- Polish:
  - OpenAI chat API
  - Groq chat API
  - OpenRouter chat API
  - Gemini chat API

User guide: [Providers and Models](../guides/providers.md)

## Transcript UI

- Popover has three main tabs: `Live`, `History`, `Stats`.
- Raw transcript is shown in a read-only text panel.
- Polished transcript is shown directly below raw text.
- No raw or polished tab switcher.
- Re-Transcribe supports per-session provider and model override with inline search and picker.
- Re-Polish supports per-session provider and model override with inline search and picker.
- Recording, transcribing, and polishing elapsed time is shown in the header state chip.
- Loading text remains inside transcript text panels to keep popover height stable.
- History starts with 10 sessions and supports load modes: `next 10`, `next 25`, `next 50`, `whole`.
- History rows include direct actions for open session, play audio, reveal in Finder, and delete.
- History supports bulk selection with bulk delete.
- Stats includes aggregate overview, latest run metrics, and current session details.

UI behavior contract:

- [Popover Contract](../reference/popover-contract.md)

## Out of scope (V1)

- Streaming transcription.
- Sync or team dictionaries.
- Speaker diarization and timestamps.

## Manual QA focus

1. Start recording and speak for 2 to 3 seconds.
2. Pause speaking for around 0.5 seconds.
3. Stay silent for at least 1.5 seconds.
4. Speak again.

Expected icon behavior is defined in the popover and smoke docs.

## Build and run

See [Development Setup](../reference/development-setup.md).

## Release status

- Current blocker: Apple Developer Program enrollment is pending.
- Until enrollment is complete, distribution uses unsigned GitHub release zips for tester installs.
