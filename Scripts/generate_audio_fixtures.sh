#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/Tests/OpenScribeTests/Fixtures/audio"
mkdir -p "$OUT_DIR"

synthesize() {
  local id="$1"
  local text="$2"
  local tmp_aiff
  tmp_aiff="$(mktemp /tmp/openscribe-fixture-${id}.XXXXXX.aiff)"

  say -v Samantha -r 175 -o "$tmp_aiff" "$text"
  afconvert -f WAVE -d LEI16@16000 "$tmp_aiff" "$OUT_DIR/${id}.wav" >/dev/null 2>&1
  rm -f "$tmp_aiff"

  echo "Generated: $OUT_DIR/${id}.wav"
}

synthesize "basic_en_smoke" "Open Scribe fixture smoke test one."
synthesize "commands_markdown" "New paragraph. Bullet point first item. New line second item."
synthesize "vocabulary_everyday_phrase" "That build was super fast. We keep the data in Supabase, and the work tree is clean."

echo "Fixture generation complete."
