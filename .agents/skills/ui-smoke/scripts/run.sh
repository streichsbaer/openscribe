#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  OUT_DIR="$ROOT_DIR/artifacts/ui-smoke/$stamp"
fi

mkdir -p "$OUT_DIR"
appearance_modes=(system light dark)
icon_states=(idle recording-working recording-paused recording-no-audio transcribing polishing)
rm -f "$OUT_DIR"/build.log \
      "$OUT_DIR"/test.log \
      "$OUT_DIR"/run.log \
      "$OUT_DIR"/report.md \
      "$OUT_DIR"/ui-smoke-status.txt \
      "$OUT_DIR"/ui-smoke-debug.txt \
      "$OUT_DIR"/openscribe-window.png \
      "$OUT_DIR"/settings-window.png \
      "$OUT_DIR"/settings-general.png \
      "$OUT_DIR"/settings-providers.png \
      "$OUT_DIR"/settings-hotkeys.png \
      "$OUT_DIR"/settings-rules.png \
      "$OUT_DIR"/settings-data.png \
      "$OUT_DIR"/settings-about.png
for mode in "${appearance_modes[@]}"; do
  for state in "${icon_states[@]}"; do
    rm -f "$OUT_DIR/menubar-icon-$mode-$state.png"
  done
done

echo "[ui-smoke] output: $OUT_DIR"

echo "[ui-smoke] swift build"
if swift build >"$OUT_DIR/build.log" 2>&1; then
  build_status="pass"
else
  build_status="fail"
fi

echo "[ui-smoke] swift test"
if swift test >"$OUT_DIR/test.log" 2>&1; then
  test_status="pass"
else
  test_status="fail"
fi

app_pid=""
app_launch_status="pass"
popover_capture_status="skipped"
settings_capture_status="skipped"
settings_tab_capture_status="skipped"
menubar_icon_capture_status="skipped"

echo "[ui-smoke] launch app (internal capture mode)"
if OPENSCRIBE_UI_SMOKE=1 OPENSCRIBE_UI_SMOKE_OUT="$OUT_DIR" swift run OpenScribe >"$OUT_DIR/run.log" 2>&1 & then
  app_pid=$!
  timeout_seconds=45
  elapsed=0
  expected_files=(
    "$OUT_DIR/openscribe-window.png"
    "$OUT_DIR/settings-window.png"
    "$OUT_DIR/settings-general.png"
    "$OUT_DIR/settings-providers.png"
    "$OUT_DIR/settings-hotkeys.png"
    "$OUT_DIR/settings-rules.png"
    "$OUT_DIR/settings-data.png"
    "$OUT_DIR/settings-about.png"
    "$OUT_DIR/ui-smoke-status.txt"
  )
  for mode in "${appearance_modes[@]}"; do
    for state in "${icon_states[@]}"; do
      expected_files+=("$OUT_DIR/menubar-icon-$mode-$state.png")
    done
  done
  while [[ $elapsed -lt $timeout_seconds ]]; do
    all_ready=1
    for expected_file in "${expected_files[@]}"; do
      if [[ ! -s "$expected_file" ]]; then
        all_ready=0
        break
      fi
    done
    if [[ $all_ready -eq 1 ]]; then
      break
    fi
    if ! kill -0 "$app_pid" >/dev/null 2>&1; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if kill -0 "$app_pid" >/dev/null 2>&1; then
    app_launch_status="timeout"
    kill "$app_pid" >/dev/null 2>&1 || true
  fi
  wait "$app_pid" >/dev/null 2>&1 || true
else
  app_launch_status="fail"
fi

if [[ -s "$OUT_DIR/openscribe-window.png" ]]; then
  popover_capture_status="pass"
else
  popover_capture_status="missing"
fi

if [[ -s "$OUT_DIR/settings-window.png" ]]; then
  settings_capture_status="pass"
else
  settings_capture_status="missing"
fi

settings_tab_files=(
  "$OUT_DIR/settings-general.png"
  "$OUT_DIR/settings-providers.png"
  "$OUT_DIR/settings-hotkeys.png"
  "$OUT_DIR/settings-rules.png"
  "$OUT_DIR/settings-data.png"
  "$OUT_DIR/settings-about.png"
)
missing_tab_count=0
for tab_file in "${settings_tab_files[@]}"; do
  if [[ ! -s "$tab_file" ]]; then
    missing_tab_count=$((missing_tab_count + 1))
  fi
done
if [[ $missing_tab_count -eq 0 ]]; then
  settings_tab_capture_status="pass"
else
  settings_tab_capture_status="missing:$missing_tab_count"
fi

missing_icon_count=0
for mode in "${appearance_modes[@]}"; do
  for state in "${icon_states[@]}"; do
    icon_file="$OUT_DIR/menubar-icon-$mode-$state.png"
    if [[ ! -s "$icon_file" ]]; then
      missing_icon_count=$((missing_icon_count + 1))
    fi
  done
done
if [[ $missing_icon_count -eq 0 ]]; then
  menubar_icon_capture_status="pass"
else
  menubar_icon_capture_status="missing:$missing_icon_count"
fi

overall_status=0
if [[ "$build_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$test_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$app_launch_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$popover_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_tab_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$menubar_icon_capture_status" != "pass" ]]; then
  overall_status=1
fi

cat > "$OUT_DIR/report.md" <<REPORT
# UI Smoke Report

- Timestamp: $(date -u +"%Y-%m-%d %H:%M UTC")
- Build: $build_status
- Tests: $test_status
- App launch: $app_launch_status
- OpenScribe window screenshot: $popover_capture_status
- Settings window screenshot: $settings_capture_status
- Settings tab screenshots: $settings_tab_capture_status
- Menubar icon screenshots: $menubar_icon_capture_status

## Artifacts

- build.log
- test.log
- run.log
- ui-smoke-status.txt
- ui-smoke-debug.txt
- openscribe-window.png
- settings-window.png
- settings-general.png
- settings-providers.png
- settings-hotkeys.png
- settings-rules.png
- settings-data.png
- settings-about.png
- menubar-icon-<mode>-<state>.png (18 files)

## Notes

- OpenScribe writes screenshots from inside the app in smoke mode for deterministic captures.
REPORT

echo "[ui-smoke] done"
echo "[ui-smoke] report: $OUT_DIR/report.md"
if [[ $overall_status -ne 0 ]]; then
  echo "[ui-smoke] failed"
  exit 1
fi
