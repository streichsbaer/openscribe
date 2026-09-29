#!/usr/bin/env zsh
# OpenScribe STT bench. See Scripts/stt-bench/README.md.
set -euo pipefail

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$BENCH_DIR/../.." && pwd)"
export STT_BENCH_HOME="${STT_BENCH_HOME:-$REPO_DIR/artifacts/stt-bench}"
export HF_HOME="$STT_BENCH_HOME/downloads/hf"
export UV_PROJECT_ENVIRONMENT="$STT_BENCH_HOME/.venv"
export PYTHONPATH="$BENCH_DIR"
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$STT_BENCH_HOME"

py() { uv run --quiet --project "$BENCH_DIR" python "$@"; }

usage() {
  cat <<'EOF'
Usage: zsh Scripts/stt-bench/bench.sh <command>

  setup                      create the Python env and build the Swift harness
  fetch [ID...]              download and verify inventory items, build whisper.cpp 1.9.4
  prep                       prepare audio sets and data/manifest.json
  synth [VOICE...]           render the developer-terms script with macOS voices
  record-devterms NAME       record the developer-terms script with your microphone
  run RUN --engines a,b [--sets s1,s2] [--max-clip SECONDS]
  score RUN                  write runs/RUN/summary.md and report_data.json
  compare RUN...             compare vocabulary variants across scored runs
  engines                    list engine names
  inventory                  show everything stored, with sizes
  clean ID... | --all        delete inventory items or everything
EOF
}

cmd="${1:-}"
[[ -n "$cmd" ]] && shift
case "$cmd" in
  setup)
    uv sync --quiet --project "$BENCH_DIR"
    swift build -c release --package-path "$BENCH_DIR/swift" --scratch-path "$STT_BENCH_HOME/build/swift"
    ;;
  fetch) py "$BENCH_DIR/fetch.py" "$@" ;;
  prep) py "$BENCH_DIR/prep.py" ;;
  synth) py -m devterms.build synth "$@" ;;
  record-devterms)
    [[ $# -eq 1 ]] || { echo "usage: bench.sh record-devterms NAME" >&2; exit 2; }
    "$STT_BENCH_HOME/build/swift/release/STTBench" record-devterms "$BENCH_DIR/devterms/sentences.json" "$STT_BENCH_HOME/data/devterms/$1"
    ;;
  run) py "$BENCH_DIR/run.py" "$@" ;;
  score) py "$BENCH_DIR/score.py" "$@" ;;
  compare) py "$BENCH_DIR/compare.py" "$@" ;;
  engines) py -c "import engines; print('\n'.join(engines.ENGINES))" ;;
  inventory) py "$BENCH_DIR/inventory.py" ;;
  clean) py "$BENCH_DIR/inventory.py" clean "$@" ;;
  *) usage; [[ -z "$cmd" ]] || exit 2 ;;
esac
