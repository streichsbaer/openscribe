# STT bench

Local speech-to-text benchmark for OpenScribe. It measures accuracy, latency, and developer-term recall for the local engines OpenScribe ships or considers, on this Mac.

Code lives here and is tracked. Everything the bench downloads, builds, or produces lives in a gitignored workspace, `artifacts/stt-bench/` by default (override with `STT_BENCH_HOME`).

## Layout

```text
Scripts/stt-bench/                 tracked
  bench.sh                         entry point
  inventory.json                   every download: source, pinned revision, sha256, size, license, purpose
  pyproject.toml, uv.lock          pinned Python environment
  workspace.py                     workspace paths
  fetch.py                         download and verify inventory items, build whisper.cpp 1.9.4
  prep.py                          prepare audio sets and data/manifest.json
  engines.py                       engine registry
  run.py                           run engines, one at a time
  score.py                         WER, term recall, false vocabulary hits, latency
  compare.py                       vocabulary variants side by side across runs
  vocabulary.py                    reads the vocabulary format OpenScribe ships
  inventory.py                     show and clean stored data
  devterms/                        developer-terms script and audio builder
  swift/                           STTBench: FluidAudio Parakeet, Apple SpeechTranscriber, recorder

artifacts/stt-bench/               gitignored workspace
  .venv/                           Python environment
  downloads/models/                whisper ggml, parakeet gguf, fluidaudio Core ML models
  downloads/hf/                    HF_HOME for MLX models
  downloads/datasets/              LibriSpeech archives and extracted audio
  downloads/sources/               whisper.cpp source archive
  build/                           whisper.cpp 1.9.4 build, Swift harness build
  data/                            16 kHz WAV sets and manifest.json
  runs/<name>/                     results/*.jsonl, logs/, summary.md, report_data.json
```

`zsh Scripts/stt-bench/bench.sh inventory` lists every item with its size, flags anything in the workspace that is not in the inventory, and shows locations outside the workspace that bench runs touch.

## First run

```bash
zsh Scripts/stt-bench/bench.sh setup
zsh Scripts/stt-bench/bench.sh fetch
zsh Scripts/stt-bench/bench.sh synth
zsh Scripts/stt-bench/bench.sh prep
zsh Scripts/stt-bench/bench.sh engines
zsh Scripts/stt-bench/bench.sh run my-run --engines fluidaudio-ultra-gpu,whispercpp194-large-v3-turbo-gpu
zsh Scripts/stt-bench/bench.sh score my-run
```

`setup` needs Swift 6.2 or later and macOS 26 for the Apple SpeechTranscriber engine. `fetch` downloads about 12 GB. The Swift harness downloads FluidAudio Core ML models at the revisions pinned in `inventory.json` on first use.

## Sets

| Set | Source | Reference |
|---|---|---|
| `test-clean`, `test-other` | 300 random LibriSpeech utterances each, seed 1234 | LibriSpeech transcripts |
| `clips` | 5, 15, 30, 60, 120 and 600 s built from LibriSpeech test-clean | LibriSpeech transcripts |
| `user` | your completed OpenScribe sessions, copied to `data/user` | the raw transcript OpenScribe stored, so it measures agreement with that provider, not accuracy |
| `devterms-<speaker>` | `devterms/sentences.json` read by a macOS voice or by you | the scripted text |

## Developer terms

`devterms/sentences.json` holds 40 developer sentences and 5 control sentences without terms. The vocabulary under test is the list OpenScribe ships, `Sources/OpenScribe/Resources/Vocabulary/developer-terms.txt`. Set `STT_BENCH_VOCABULARY` to evaluate another file.

Record your own set once:

```bash
zsh Scripts/stt-bench/bench.sh record-devterms stefan
zsh Scripts/stt-bench/bench.sh prep
```

The recorder asks for microphone access for your terminal on first use. Engines ending in `-vocab` use the vocabulary with the tuning OpenScribe ships; `fluidaudio-ultra-gpu-vocab@<variant>` engines override single knobs (see `BOOST_VARIANTS` in `engines.py`). The Parakeet booster is OpenScribe's own source, linked into the Swift harness, so results describe what ships. `score` reports:

- term recall: share of target terms transcribed exactly (case-insensitive)
- false vocabulary hits: vocabulary terms that appear in a transcript but not in its reference, on dev-terms, control, and LibriSpeech sets
- WER on every set, so vocabulary boosting cannot hide a regression

## Cleanup

```bash
zsh Scripts/stt-bench/bench.sh clean hf-mlx-models whisper-ggml-medium
zsh Scripts/stt-bench/bench.sh clean fluidaudio-default-cache
zsh Scripts/stt-bench/bench.sh clean --all
```

`clean --all` removes the workspace and every external location marked cleanable. It never touches OpenScribe's own data in `~/Library/Application Support/OpenScribe`.

The side-by-side test app lives in `dist/side-by-side/` and keeps its data in `~/Library/Application Support/OpenScribe Dev` (inventory item `openscribe-dev-data`).

## Runs

- `2026-09-29-baseline`: first comparison of Whisper, Parakeet, and Apple engines; published report in the run folder. Its scripts are archived with it.
- `2026-09-29-devterms-v1`: developer terms with and without vocabulary for Parakeet Ultra and Whisper large-v3-turbo. FluidAudio's default boosting reached 90 percent recall but inserted terms into 116 LibriSpeech utterances. The Whisper prompt helped short clips but made Whisper loop on the 10 minute clip.
- `2026-09-29-devterms-sweep`, `-sweep2`, `-sweep2-noalias`, `-sweep3`: boosting threshold sweeps. Winner, now shipped: rescue pass off, similarity 0.75, and 0.85 for terms of five characters or fewer. 84 percent recall, no false insertions, LibriSpeech error unchanged. Sounds-like aliases add about 7 points of recall at no cost.
- `2026-09-29-devterms-stefan`: the same engines on Stefan's own recording. Parakeet Ultra went from 65 to 84 percent term recall and from 8.7 to 4.9 WER with vocabulary, with no false insertions.

Compare vocabulary runs with `zsh Scripts/stt-bench/bench.sh compare RUN...`.
