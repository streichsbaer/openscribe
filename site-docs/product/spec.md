# Product Spec

This is the canonical product spec for OpenScribe.

Roadmap execution lives in GitHub Issues and is summarized in [Roadmap](roadmap.md).

## Target

- Native macOS app.
- Menubar-only utility app.

## Core flow

1. Global hotkey toggles recording.
2. Audio is captured to `audio.capture.wav.part`.
3. On stop, audio is finalized atomically to `audio.m4a`.
4. A shared adaptive audio activity detector validates speech signal and drives the live input indicators.
5. Empty or near-empty recordings skip STT and polish, store empty transcript outputs, and end with actionable audio input guidance.
6. For usable file-based recordings, OpenScribe creates a transient STT input trimmed to the detected speech span with protective leading and trailing padding. The original `audio.m4a` remains unchanged.
7. File-based STT runs via the selected provider with the prepared input.
8. OpenAI Realtime keeps bounded leading and trailing audio buffers, streams interim raw transcript text while recording, and commits the final transcript after stop. If streaming falls behind or disconnects, OpenScribe retries from the saved recording.
9. If polish is enabled, polish runs via selected LLM provider with `Rules/rules.md`.
10. If polish is disabled, polished output is passthrough from raw transcript.
11. Session artifacts are written: `audio.m4a`, `session.json`, `raw.txt`, `polished.md`.

## First-run setup assistant

- On a fresh install with no session history, OpenScribe opens a setup assistant in Settings on first launch.
- The assistant offers two paths: `Local only` and `Groq cloud`.
- The assistant recommends a path from the Mac it runs on. Apple silicon Macs get `Local only` first. Intel Macs get `Groq cloud` first because local models run on the CPU there and are much slower.
- `Local only` guides local model choice (Parakeet Ultra recommended, or a `whisper.cpp` model), model download, and a local test recording.
- `Groq cloud` guides Groq key entry, verification, Groq Whisper on `whisper-large-v3-turbo`, and Groq polish on `openai/gpt-oss-120b`.
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
- Default STT provider: local Parakeet.
- Default local model: `Parakeet Ultra`, running on the GPU. The Neural Engine is a setting.
- Vocabulary: enabled, including the built-in developer terms.
- Default polish: disabled.
- Default polish provider and model: `OpenAI / gpt-5-nano`.
- Language: `auto`.
- Copy-on-complete: enabled.

## Storage layout

Root path:

- `~/Library/Application Support/OpenScribe`

- User guide: [Your Data](../guides/your-data.md)
- Technical contract: [Storage Contract](../reference/storage-contract.md)

## Vocabulary

- Users keep their own vocabulary in `Rules/vocabulary.txt`, edited in Settings on the Vocabulary tab. Each line holds a term and optional sounds-like spellings.
- OpenScribe ships a built-in developer terms list that updates with each release. User entries replace built-in entries with the same term.
- Local Parakeet rescores transcripts with a vocabulary model, downloaded on demand, and replaces a word only when the audio supports the term. Boosting starts once that model is installed.
- Local `whisper.cpp` receives the terms as a prompt for recordings up to 2 minutes.
- Polish receives the terms as a glossary.
- Cloud transcription providers do not receive the vocabulary.
- Guide: [Vocabulary](../guides/vocabulary.md)

## Providers

- STT:
  - Local Parakeet (Parakeet Ultra on Core ML through FluidAudio)
  - Local `whisper.cpp` (Metal GPU on Apple Silicon)
  - OpenAI Whisper API
  - OpenAI Realtime API
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

- Popover has three main tabs: `Live`, `History`, `Stats`, all at one size (`540 x 680`).
- Blue marks work done on this Mac and orange marks work done in the cloud, in light and dark mode.
- Live shows the record button with a live waveform, the timer, and the microphone picker.
- Live shows the route of the current session: the transcription engine, polish (or a `Polish off` pill that opens Polish settings), and delivery, with timings once done.
- Live states in one sentence what leaves the Mac, for example `Stayed on this Mac. Nothing was sent anywhere.`
- With polish off, Live shows one transcript. With polish on, it switches between `Polished`, `Raw`, and `Changes`, a word-level comparison.
- Words the vocabulary corrected are highlighted, with a note of what was heard and what it became.
- OpenAI Realtime can update the raw transcript while recording.
- Transcribe again and Polish again support a per-session provider and model override with inline search.
- Model downloads show progress in Live, the setup assistant, and Settings.
- History groups sessions by day and shows each time with its recording length.
- History marks only exceptions: a cloud badge when audio or text left the Mac, and failed sessions with a Retry action.
- The selected History session offers play, copy, open in Live, transcribe again, reveal in Finder, select several, and move to Trash.
- History starts with 10 sessions and loads 25 more on request.
- Stats shows words, speaking time, and pace for the last 7 days, 30 days, or all time, with a chart.
- Stats shows a year of activity as a heatmap with the current and longest streak.
- Stats shows where words went: sessions that stayed on this Mac, sent text to a polish provider, or sent audio to a cloud transcription provider.
- Stats counts each session once, with its latest transcription, so retries do not add words twice.

UI behavior contract:

- [Popover Contract](../reference/popover-contract.md)

## Out of scope (V1)

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
