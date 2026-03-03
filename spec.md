# OpenScribe V1 Spec

## Target
- Native Apple Silicon macOS app (tested target: macOS 26, min package platform currently set to macOS 15 for tool compatibility).
- Menubar-only utility app.

## Core Flow
1. Global hotkey toggles recording.
2. Audio is captured to `audio.capture.wav.part`.
3. On stop, audio is finalized atomically to `audio.m4a`.
4. STT runs via selected provider.
5. If polish is enabled, polish runs via selected LLM provider with `Rules/rules.md`.
6. If polish is disabled, polished output is passthrough from raw transcript.
7. Session artifacts are written: `audio.m4a`, `session.json`, `raw.txt`, `polished.md`.

## Defaults
- Start/stop hotkey default: `Fn + Space` (configurable).
- Copy polished hotkey default: `Ctrl + Option + P` (configurable).
- Copy raw hotkey default: `Ctrl + Option + T` (configurable).
- Paste hotkey default: `Ctrl + Option + V` (configurable).
- Toggle popover hotkey default: `Ctrl + Option + O` (configurable).
- Open settings hotkey default: `Ctrl + Option + ,` (configurable).
- Popover tab hotkeys: `Ctrl + Option + L` (Live), `Ctrl + Option + H` (History), `Ctrl + Option + S` (Stats).
- Rules hotkey: `Ctrl + Option + R` opens Settings on the Rules tab.
- Paste hotkey behavior: copy latest polished transcript then paste via synthetic `Cmd + V` only when Accessibility permission is granted.
- If hotkey registration fails, app shows blocking warning and requires manual change.
- Default STT provider: local `whisper.cpp`.
- Default local model: `base`.
- Default polish: disabled.
- Default polish provider/model: `OpenAI / gpt-5-nano`.
- Language: `auto`.
- Copy-on-complete: enabled.

## Storage Layout
Root: `~/Library/Application Support/OpenScribe`

- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/audio.m4a`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/session.json`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/raw.txt`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/polished.md`
- `Rules/rules.md`
- `Rules/rules.history.jsonl`
- `Stats/usage.events.jsonl`
- `Models/whisper/ggml-<model>.bin`
- `Config/settings.json`

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

## Transcript UI
- Popover has three main tabs: `Live`, `History`, `Stats`.
- Raw transcript is shown in a read-only text panel.
- Polished transcript is shown directly below raw text.
- No raw/polished tab switcher.
- Re-Transcribe supports per-session provider/model override with inline search + picker.
- Re-Polish supports per-session provider/model override with inline search + picker.
- Recording, transcribing, and polishing elapsed time is shown in the header state chip.
- Loading text remains inside transcript text panels to keep popover height stable.
- History starts with 10 sessions and supports load modes: `next 10`, `next 25`, `next 50`, `whole`.
- History rows include direct actions for open session, play audio, reveal in Finder, and delete.
- History supports bulk selection with bulk delete.
- Stats includes aggregate overview, latest run metrics, and current session details.
- Popover and tab behavior contract is defined in `docs/popover-spec.md`.

## Out of Scope (V1)
- Streaming transcription.
- Sync/team dictionaries.
- Speaker diarization and timestamps.

## Roadmap (Post V1)

### Status Snapshot (March 3, 2026)
- R1. Session History Browser: In progress.
  - Completed: browse, open, replay audio, re-run processing, row actions, bulk delete.
  - Open: session search and filtering.
- R2. Processing Statistics and Cost Tracking: In progress.
  - Completed: usage ledger (`Stats/usage.events.jsonl`), aggregate stats, latest run metrics, streak and WPM cards, token capture when provided by provider APIs.
  - Open: cost calculator and configurable pricing table.
- R3. Price Catalog and Savings View: Planned.
- R4. Retention Policy and Cleanup: Planned.
- R5. Documentation Pyramid and Agent-Facing Docs Skill: Planned.
- R6. Per-Recording Temporary Instructions: Planned.
- R7. Wake Phrase Research Track: Planned.
- R8. Test Roadmap: In progress.
  - Completed: deterministic UI smoke captures and parity checks for click and hotkey paths.
  - Open: baseline image diff workflow and CI failure visualization.

### R1. Session History Browser
- Goal: let users browse, search, and reopen previous sessions.
- Scope:
  - List sessions from `Recordings/` sorted by time.
  - Show provider/model, duration, state, and short transcript preview.
  - Open one session to inspect raw/polished text and replay audio.
  - Re-run transcribe/polish from history view.
- Current behavior: show latest 10 entries first, then load more with `next 10`, `next 25`, `next 50`, or `whole`.
- Acceptance:
  - User can locate and open any historical session without Finder.
  - User can re-run processing from a selected history item.

### R2. Processing Statistics and Cost Tracking
- Goal: show per-session and aggregate pipeline metrics, including cost.
- Scope:
  - Track per-step latency (`recording`, `transcribing`, `polishing`).
  - Track provider/model usage per step.
  - Compute estimated cost by provider/model price table.
  - Show totals (today, 7 days, 30 days, all time).
- Data contract:
  - Immutable usage ledger file: `Stats/usage.events.jsonl`.
  - Write one ledger record per completed step with timestamp and session ID.
- Acceptance:
  - User can see session-level and aggregate time and cost numbers.
  - Cost view distinguishes free local runs (for example `whisper.cpp`) from paid API runs.

### R3. Price Catalog and Savings View
- Goal: maintain transparent pricing assumptions and show practical savings.
- Scope:
  - Add local price catalog file, example: `Config/pricing.json`.
  - Version the catalog and show last-updated date in UI.
  - Add simple savings comparison view against user-entered subscription baseline.
- Default behavior:
  - Use maintained app pricing table.
  - User can override baseline subscription values for comparison.
- Acceptance:
  - UI shows both actual estimated spend and baseline comparison delta.

### R4. Retention Policy and Cleanup
- Goal: allow automatic cleanup without breaking analytics.
- Scope:
  - Retention modes: `Keep forever`, `Delete audio only after X days`, `Delete full sessions after X days`.
  - Scheduled cleanup at app launch and optional daily run.
  - Before deletion, preserve derived metrics in ledger.
- Proposed default: `Keep forever` (safe, current behavior).
- Acceptance:
  - Cleanup removes targeted files only.
  - Statistics remain consistent after cleanup.

### R5. Documentation Pyramid and Agent-Facing Docs Skill
- Goal: make docs easy to navigate for humans and agents.
- Scope:
  - Top-level overview page with clickable deep dives.
  - Feature pages for recording, providers, polish, history, stats, release.
  - Add dedicated docs Q&A skill in `.agents/skills/docs/` that indexes and answers from repo docs.
- Acceptance:
  - New contributor can navigate from overview to implementation details quickly.
  - Agent can answer product and technical questions from local docs with source references.

### R6. Per-Recording Temporary Instructions
- Goal: support one-off dictation rules for a single recording.
- Scope:
  - Optional “Instruction preamble” mode at recording start.
  - User speaks instructions, then marks start of content.
  - Pass parsed instructions into polish prompt context for this session only.
  - Setting toggle to enable or disable this mode.
- Acceptance:
  - Session can include temporary style rules without changing global `rules.md`.
  - Instructions are visible in session metadata for traceability.

### R7. Wake Phrase Research Track
- Goal: evaluate optional always-listening mode for hands-free start/stop.
- Scope:
  - Start transcript on action phrase.
  - Auto-stop after silence cooldown.
  - Voice commands: `pause recording`, `resume recording`, `stop recording`.
  - Define coexistence constraints with other macOS mic users.
- Acceptance:
  - Clear feasibility decision with UX and technical constraints documented.

### R8. Test Roadmap
- Scope:
  - Add baseline comparison to existing menubar icon snapshots:
    - idle, recording-working, recording-paused, recording-no-audio, transcribing, polishing
    - system, light, dark appearance modes
  - Add thresholded image-diff reporting and CI-friendly failure output.

## Manual QA Focus
1. Start recording and speak for 2 to 3 seconds:
   - menu bar icon should blink green and keep updating while speaking.
2. Pause speaking for around 0.5 seconds:
   - menu bar icon should alternate green and gray.
3. Stay silent for at least 1.5 seconds:
   - menu bar icon should turn red.
4. Speak again:
   - menu bar icon should return to working state within 0.5 seconds.

## Build/Run
- `swift build`
- `swift run OpenScribe`

For full app signing/notarization and polished packaging, use a follow-up release phase.

## Release Status
- Current blocker: Apple Developer Program enrollment is pending.
- Until enrollment is complete, distribution uses unsigned GitHub release zips for tester installs.
