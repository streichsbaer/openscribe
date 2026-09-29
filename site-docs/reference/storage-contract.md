# Storage Contract

Root path:

`~/Library/Application Support/OpenScribe`

## Session artifacts

- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/audio.m4a`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/session.json`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/raw.txt`
- `Recordings/YYYY-MM-DD/HHmmss-<uuid>/polished.md`

## Shared data

- `Rules/rules.md`
- `Rules/rules.history.jsonl`
- `Rules/vocabulary.txt`
- `Stats/usage.events.jsonl`
- `Models/whisper/ggml-<model>.bin`
- `Models/parakeet/<model>/` (Core ML model folders: `parakeet-ultra`, `parakeet-vocabulary`)
- `Config/settings.json`

Local models download from Hugging Face at pinned revisions. OpenScribe verifies the SHA256 of every file and moves a model into place only once it is complete.

## Why this matters

This contract keeps each recording durable and inspectable.
