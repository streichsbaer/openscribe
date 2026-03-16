#!/usr/bin/env zsh
set -euo pipefail

START_PWD="$(pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR=""
APP_PATH=""

usage() {
  cat <<USAGE
Usage: zsh .agents/skills/ui-smoke/scripts/run.sh [--out <dir>] [--app <path-to-app>]

Defaults:
  --app omitted  -> launch via swift run OpenScribe
  --app set      -> launch the packaged app at <path-to-app>/Contents/MacOS/<AppName>
  --out omitted  -> artifacts/ui-smoke/<timestamp> under repo root
  --out relative -> resolved from invocation working directory (pwd)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --out)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --out" >&2
        usage >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    --app)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --app" >&2
        usage >&2
        exit 1
      fi
      APP_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown arg: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  OUT_DIR="$ROOT_DIR/artifacts/ui-smoke/$stamp"
elif [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$START_PWD/$OUT_DIR"
fi

if [[ -n "$APP_PATH" && "$APP_PATH" != /* ]]; then
  APP_PATH="$START_PWD/$APP_PATH"
fi

mkdir -p "$OUT_DIR"
appearance_modes=(system light dark)
icon_states=(idle recording-working recording-paused recording-no-audio transcribing polishing)
settings_tabs=(general transcribe polish providers hotkeys rules data about)
settings_variant_suffixes=("" "-dark")
rm -f "$OUT_DIR"/build.log \
      "$OUT_DIR"/test.log \
      "$OUT_DIR"/run.log \
      "$OUT_DIR"/report.md \
      "$OUT_DIR"/ui-smoke-status.txt \
      "$OUT_DIR"/ui-smoke-debug.txt \
      "$OUT_DIR"/openscribe-window.png \
      "$OUT_DIR"/openscribe-window-hotkey-history-direct.png \
      "$OUT_DIR"/openscribe-window-click-history.png \
      "$OUT_DIR"/openscribe-window-click-history-full.png \
      "$OUT_DIR"/openscribe-window-click-stats.png \
      "$OUT_DIR"/openscribe-window-hotkey-history.png \
      "$OUT_DIR"/openscribe-window-hotkey-history-full.png \
      "$OUT_DIR"/openscribe-window-hotkey-stats.png \
      "$OUT_DIR"/openscribe-window-hotkey-live.png \
      "$OUT_DIR"/openscribe-window-live-expanded-content.png
for suffix in "${settings_variant_suffixes[@]}"; do
  rm -f "$OUT_DIR/settings-window$suffix.png"
  for tab in "${settings_tabs[@]}"; do
    rm -f "$OUT_DIR/settings-$tab$suffix.png"
  done
done
for mode in "${appearance_modes[@]}"; do
  for state in "${icon_states[@]}"; do
    rm -f "$OUT_DIR/menubar-icon-$mode-$state.png"
  done
done

echo "[ui-smoke] output: $OUT_DIR"

launch_mode="swift-run"
launch_target="swift run OpenScribe"
app_executable=""
launch_prefix=()
timeout_seconds=45

if [[ -n "$APP_PATH" ]]; then
  app_name="$(basename "$APP_PATH" .app)"
  app_executable="$APP_PATH/Contents/MacOS/$app_name"
  launch_mode="packaged-app"
  launch_target="$app_executable"
fi

if [[ "$launch_mode" == "swift-run" ]]; then
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
else
  build_status="skipped"
  test_status="skipped"
  : >"$OUT_DIR/build.log"
  : >"$OUT_DIR/test.log"
  if [[ ! -d "$APP_PATH" ]]; then
    echo "Missing app bundle at $APP_PATH" >"$OUT_DIR/run.log"
    echo "[ui-smoke] missing app bundle: $APP_PATH" >&2
    exit 1
  fi
  if [[ ! -x "$app_executable" ]]; then
    echo "Missing app executable at $app_executable" >"$OUT_DIR/run.log"
    echo "[ui-smoke] missing app executable: $app_executable" >&2
    exit 1
  fi
fi

existing_pids="$(pgrep -x OpenScribe || true)"
if [[ -n "$existing_pids" ]]; then
  echo "[ui-smoke] stopping existing OpenScribe process(es): $existing_pids"
  kill $existing_pids >/dev/null 2>&1 || true
  sleep 1

  remaining_pids="$(pgrep -x OpenScribe || true)"
  if [[ -n "$remaining_pids" ]]; then
    echo "[ui-smoke] force stopping stubborn OpenScribe process(es): $remaining_pids"
    kill -9 $remaining_pids >/dev/null 2>&1 || true
  fi
fi

app_pid=""
app_launch_status="pass"
popover_capture_status="skipped"
click_history_capture_status="skipped"
click_stats_capture_status="skipped"
settings_capture_status="skipped"
settings_tab_capture_status="skipped"
settings_dark_capture_status="skipped"
settings_dark_tab_capture_status="skipped"
menubar_icon_capture_status="skipped"
hotkey_tab_capture_status="skipped"
history_layout_parity_status="missing"
history_layout_parity_reason="missing"
history_layout_parity_direct_status="missing"
history_layout_parity_direct_reason="missing"
history_vertical_fill_status="missing"
history_vertical_fill_reason="missing"
live_expanded_content_capture_status="missing"
hotkey_dispatch_status="missing"
tab_click_dispatch_status="missing"

echo "[ui-smoke] launch app (internal capture mode)"
if [[ "$launch_mode" == "swift-run" ]]; then
  launch_command=(swift run OpenScribe)
else
  executable_description="$(file "$app_executable" 2>/dev/null || true)"
  if [[ "$(uname -m)" == "arm64" && "$executable_description" == *"x86_64"* && "$executable_description" != *"arm64"* ]]; then
    launch_prefix=(/usr/bin/arch -x86_64)
    launch_target="/usr/bin/arch -x86_64 $app_executable"
    timeout_seconds=90
  fi
  launch_command=("${launch_prefix[@]}" "$app_executable")
fi

if OPENSCRIBE_UI_SMOKE=1 OPENSCRIBE_UI_SMOKE_OUT="$OUT_DIR" "${launch_command[@]}" >"$OUT_DIR/run.log" 2>&1 & then
  app_pid=$!
  elapsed=0
  expected_files=(
    "$OUT_DIR/openscribe-window.png"
    "$OUT_DIR/openscribe-window-hotkey-history-direct.png"
    "$OUT_DIR/openscribe-window-click-history.png"
    "$OUT_DIR/openscribe-window-click-history-full.png"
    "$OUT_DIR/openscribe-window-click-stats.png"
    "$OUT_DIR/openscribe-window-hotkey-history.png"
    "$OUT_DIR/openscribe-window-hotkey-history-full.png"
    "$OUT_DIR/openscribe-window-hotkey-stats.png"
    "$OUT_DIR/openscribe-window-hotkey-live.png"
    "$OUT_DIR/openscribe-window-live-expanded-content.png"
    "$OUT_DIR/ui-smoke-status.txt"
  )
  for suffix in "${settings_variant_suffixes[@]}"; do
    expected_files+=("$OUT_DIR/settings-window$suffix.png")
    for tab in "${settings_tabs[@]}"; do
      expected_files+=("$OUT_DIR/settings-$tab$suffix.png")
    done
  done
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

if [[ -s "$OUT_DIR/openscribe-window-click-history.png" ]]; then
  click_history_capture_status="pass"
else
  click_history_capture_status="missing"
fi

if [[ -s "$OUT_DIR/openscribe-window-click-stats.png" ]]; then
  click_stats_capture_status="pass"
else
  click_stats_capture_status="missing"
fi

hotkey_tab_files=(
  "$OUT_DIR/openscribe-window-hotkey-history-direct.png"
  "$OUT_DIR/openscribe-window-hotkey-history.png"
  "$OUT_DIR/openscribe-window-hotkey-stats.png"
  "$OUT_DIR/openscribe-window-hotkey-live.png"
)
missing_hotkey_tab_count=0
for hotkey_tab_file in "${hotkey_tab_files[@]}"; do
  if [[ ! -s "$hotkey_tab_file" ]]; then
    missing_hotkey_tab_count=$((missing_hotkey_tab_count + 1))
  fi
done
if [[ $missing_hotkey_tab_count -eq 0 ]]; then
  hotkey_tab_capture_status="pass"
else
  hotkey_tab_capture_status="missing:$missing_hotkey_tab_count"
fi

if [[ -s "$OUT_DIR/settings-window.png" ]]; then
  settings_capture_status="pass"
else
  settings_capture_status="missing"
fi

if [[ -s "$OUT_DIR/settings-window-dark.png" ]]; then
  settings_dark_capture_status="pass"
else
  settings_dark_capture_status="missing"
fi

if [[ -s "$OUT_DIR/ui-smoke-status.txt" ]]; then
  parsed_tab_click_dispatch_status="$(awk -F= '/^tabClickDispatch=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_click_stats_capture_status="$(awk -F= '/^statsCapture=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_hotkey_dispatch_status="$(awk -F= '/^hotkeyDispatch=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_parity_direct_status="$(awk -F= '/^historyLayoutParityDirect=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_parity_direct_reason="$(awk -F= '/^historyLayoutParityDirectReason=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | sed 's/^[[:space:]]*//')"
  parsed_parity_status="$(awk -F= '/^historyLayoutParity=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_parity_reason="$(awk -F= '/^historyLayoutParityReason=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | sed 's/^[[:space:]]*//')"
  parsed_vertical_fill_status="$(awk -F= '/^historyVerticalFill=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  parsed_vertical_fill_reason="$(awk -F= '/^historyVerticalFillReason=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | sed 's/^[[:space:]]*//')"
  parsed_live_expanded_content_capture_status="$(awk -F= '/^liveExpandedContentCapture=/{print $2}' "$OUT_DIR/ui-smoke-status.txt" | tail -n1 | tr -d '[:space:]')"
  if [[ -n "$parsed_tab_click_dispatch_status" ]]; then
    tab_click_dispatch_status="$parsed_tab_click_dispatch_status"
  fi
  if [[ -n "$parsed_hotkey_dispatch_status" ]]; then
    hotkey_dispatch_status="$parsed_hotkey_dispatch_status"
  fi
  if [[ -n "$parsed_click_stats_capture_status" ]]; then
    click_stats_capture_status="$parsed_click_stats_capture_status"
  fi
  if [[ -n "$parsed_parity_direct_status" ]]; then
    history_layout_parity_direct_status="$parsed_parity_direct_status"
  fi
  if [[ -n "$parsed_parity_direct_reason" ]]; then
    history_layout_parity_direct_reason="$parsed_parity_direct_reason"
  fi
  if [[ -n "$parsed_parity_status" ]]; then
    history_layout_parity_status="$parsed_parity_status"
  fi
  if [[ -n "$parsed_parity_reason" ]]; then
    history_layout_parity_reason="$parsed_parity_reason"
  fi
  if [[ -n "$parsed_vertical_fill_status" ]]; then
    history_vertical_fill_status="$parsed_vertical_fill_status"
  fi
  if [[ -n "$parsed_vertical_fill_reason" ]]; then
    history_vertical_fill_reason="$parsed_vertical_fill_reason"
  fi
  if [[ -n "$parsed_live_expanded_content_capture_status" ]]; then
    live_expanded_content_capture_status="$parsed_live_expanded_content_capture_status"
  fi
fi

missing_tab_count=0
for tab in "${settings_tabs[@]}"; do
  if [[ ! -s "$OUT_DIR/settings-$tab.png" ]]; then
    missing_tab_count=$((missing_tab_count + 1))
  fi
done
if [[ $missing_tab_count -eq 0 ]]; then
  settings_tab_capture_status="pass"
else
  settings_tab_capture_status="missing:$missing_tab_count"
fi

missing_dark_tab_count=0
for tab in "${settings_tabs[@]}"; do
  if [[ ! -s "$OUT_DIR/settings-$tab-dark.png" ]]; then
    missing_dark_tab_count=$((missing_dark_tab_count + 1))
  fi
done
if [[ $missing_dark_tab_count -eq 0 ]]; then
  settings_dark_tab_capture_status="pass"
else
  settings_dark_tab_capture_status="missing:$missing_dark_tab_count"
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
  if [[ "$build_status" != "skipped" ]]; then
    overall_status=1
  fi
fi
if [[ "$test_status" != "pass" ]]; then
  if [[ "$test_status" != "skipped" ]]; then
    overall_status=1
  fi
fi
if [[ "$app_launch_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$popover_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$click_history_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$click_stats_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$hotkey_tab_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$tab_click_dispatch_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$hotkey_dispatch_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$history_layout_parity_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$history_layout_parity_direct_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$history_vertical_fill_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$live_expanded_content_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_tab_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_dark_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$settings_dark_tab_capture_status" != "pass" ]]; then
  overall_status=1
fi
if [[ "$menubar_icon_capture_status" != "pass" ]]; then
  overall_status=1
fi

cat > "$OUT_DIR/report.md" <<REPORT
# UI Smoke Report

- Timestamp: $(date -u +"%Y-%m-%d %H:%M UTC")
- Smoke mode: $launch_mode
- Launch target: $launch_target
- Build: $build_status
- Tests: $test_status
- App launch: $app_launch_status
- OpenScribe window screenshot: $popover_capture_status
- Click History screenshot: $click_history_capture_status
- Click Stats screenshot: $click_stats_capture_status
- Hotkey tab screenshots: $hotkey_tab_capture_status
- Tab click dispatch path: $tab_click_dispatch_status
- Hotkey dispatch path: $hotkey_dispatch_status
- History layout parity direct (open -> hotkey): $history_layout_parity_direct_status
- History layout parity direct reason: $history_layout_parity_direct_reason
- History layout parity (click vs hotkey): $history_layout_parity_status
- History layout parity reason: $history_layout_parity_reason
- History vertical fill (compact): $history_vertical_fill_status
- History vertical fill reason: $history_vertical_fill_reason
- Live expanded content screenshot: $live_expanded_content_capture_status
- Settings window screenshot (light): $settings_capture_status
- Settings tab screenshots (light): $settings_tab_capture_status
- Settings window screenshot (dark): $settings_dark_capture_status
- Settings tab screenshots (dark): $settings_dark_tab_capture_status
- Menubar icon screenshots: $menubar_icon_capture_status

## Artifacts

- build.log
- test.log
- run.log
- ui-smoke-status.txt
- ui-smoke-debug.txt
- openscribe-window.png
- openscribe-window-hotkey-history-direct.png
- openscribe-window-click-history.png
- openscribe-window-click-history-full.png
- openscribe-window-click-stats.png
- openscribe-window-hotkey-history.png
- openscribe-window-hotkey-history-full.png
- openscribe-window-hotkey-stats.png
- openscribe-window-hotkey-live.png
- openscribe-window-live-expanded-content.png
- settings-window.png
- settings-window-dark.png
- settings-general.png
- settings-general-dark.png
- settings-transcribe.png
- settings-transcribe-dark.png
- settings-polish.png
- settings-polish-dark.png
- settings-providers.png
- settings-providers-dark.png
- settings-hotkeys.png
- settings-hotkeys-dark.png
- settings-rules.png
- settings-rules-dark.png
- settings-data.png
- settings-data-dark.png
- settings-about.png
- settings-about-dark.png
- menubar-icon-<mode>-<state>.png (18 files)

## Notes

- OpenScribe writes screenshots from inside the app in smoke mode for deterministic captures.
- Settings screenshots are intended for docs refreshes and are captured on the built-in Retina display when available in both light and dark appearances.
- Popover screenshots remain regression artifacts only. Published docs reuse curated assets from site-docs/images/ui/.
- The smoke run validates artifact presence and required file coverage.
- Visual correctness still requires manual screenshot review.
REPORT

echo "[ui-smoke] done"
echo "[ui-smoke] report: $OUT_DIR/report.md"
if [[ $overall_status -ne 0 ]]; then
  echo "[ui-smoke] failed"
  exit 1
fi
