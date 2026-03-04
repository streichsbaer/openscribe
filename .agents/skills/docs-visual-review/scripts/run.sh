#!/usr/bin/env zsh
set -euo pipefail

START_PWD="$(pwd)"
ROOT_DIR="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT_DIR"

OUT_DIR=""
HOST="127.0.0.1"
PORT="8000"
TIMEOUT_SECONDS=40
DOCS_URL=""
KEEP_SERVER=0
RUN_SWIFT_BUILD=0
SKIP_DOCS_BUILD=0
NO_SERVE=0
SWIFT_BUILD_STATUS="skipped"
DOCS_BUILD_STATUS="skipped"
PLAYWRIGHT_STATUS="fail"
SERVE_PID=""
SERVE_STARTED=0
LOG_SECTION=""

usage() {
  cat <<USAGE
Usage: zsh .agents/skills/docs-visual-review/scripts/run.sh [options]

Options:
  --out <dir>              Output directory (default: artifacts/docs-visual/<timestamp>)
  --host <host>            MkDocs serve host (default: 127.0.0.1)
  --port <port>            MkDocs serve port (default: 8000)
  --url <url>              Docs base URL (default: http://<host>:<port>/)
  --remote-url <url>       Verify a deployed docs URL (implies --no-serve and --skip-docs-build)
  --timeout <seconds>      Server readiness timeout (default: 40)
  --keep-server            Keep MkDocs server running after capture
  --with-swift-build       Include swift build precheck
  --no-serve               Skip local docs server startup and verify existing URL
  --skip-docs-build        Skip mkdocs build
  -h, --help               Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --out" >&2
        exit 1
      fi
      OUT_DIR="$2"
      shift 2
      ;;
    --host)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --host" >&2
        exit 1
      fi
      HOST="$2"
      shift 2
      ;;
    --port)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --port" >&2
        exit 1
      fi
      PORT="$2"
      shift 2
      ;;
    --url)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --url" >&2
        exit 1
      fi
      DOCS_URL="$2"
      shift 2
      ;;
    --remote-url)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --remote-url" >&2
        exit 1
      fi
      DOCS_URL="$2"
      NO_SERVE=1
      SKIP_DOCS_BUILD=1
      shift 2
      ;;
    --timeout)
      if [[ $# -lt 2 ]]; then
        echo "Missing value for --timeout" >&2
        exit 1
      fi
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --keep-server)
      KEEP_SERVER=1
      shift 1
      ;;
    --with-swift-build)
      RUN_SWIFT_BUILD=1
      shift 1
      ;;
    --no-serve)
      NO_SERVE=1
      shift 1
      ;;
    --skip-docs-build)
      SKIP_DOCS_BUILD=1
      shift 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)"
  OUT_DIR="$ROOT_DIR/artifacts/docs-visual/$stamp"
elif [[ "$OUT_DIR" != /* ]]; then
  OUT_DIR="$START_PWD/$OUT_DIR"
fi

if [[ -z "$DOCS_URL" ]]; then
  DOCS_URL="http://$HOST:$PORT/"
fi
DOCS_URL="${DOCS_URL%/}/"

mkdir -p "$OUT_DIR"
PLAYWRIGHT_LOG="$OUT_DIR/playwright.log"
SERVE_LOG="$OUT_DIR/mkdocs-serve.log"
SWIFT_LOG="$OUT_DIR/swift-build.log"
MKDOCS_LOG="$OUT_DIR/mkdocs-build.log"
UV_CACHE_DIR_PATH="$ROOT_DIR/.build/uv-cache"

required_tools=(playwright-cli curl)
if (( SKIP_DOCS_BUILD == 0 || NO_SERVE == 0 )); then
  required_tools+=(uv)
fi
if (( RUN_SWIFT_BUILD == 1 )); then
  required_tools+=(swift)
fi

for tool in "${required_tools[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

if (( SKIP_DOCS_BUILD == 0 || NO_SERVE == 0 )); then
  mkdir -p "$UV_CACHE_DIR_PATH"
  export UV_CACHE_DIR="$UV_CACHE_DIR_PATH"
fi

if (( NO_SERVE == 1 && KEEP_SERVER == 1 )); then
  echo "Cannot use --keep-server with --no-serve because no local server is started." >&2
  exit 1
fi

existing_port_pids=()
if (( NO_SERVE == 0 )); then
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && existing_port_pids+=("$pid")
  done < <(lsof -ti "tcp:$PORT" 2>/dev/null || true)
fi

if (( ${#existing_port_pids[@]} > 0 )); then
  echo "[docs-visual-review] stopping existing process(es) on port $PORT: ${existing_port_pids[*]}"
  for pid in "${existing_port_pids[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done

  wait_seconds=0
  while lsof -ti "tcp:$PORT" >/dev/null 2>&1; do
    if (( wait_seconds >= 8 )); then
      lingering_pids=()
      while IFS= read -r pid; do
        [[ -n "$pid" ]] && lingering_pids+=("$pid")
      done < <(lsof -ti "tcp:$PORT" 2>/dev/null || true)
      echo "Could not free port $PORT after stop attempt. Remaining pid(s): ${lingering_pids[*]}" >&2
      exit 1
    fi
    sleep 1
    wait_seconds=$((wait_seconds + 1))
  done
fi

cleanup() {
  local exit_code="${1:-0}"
  playwright-cli close-all >/dev/null 2>&1 || true
  if [[ -n "$SERVE_PID" ]] && kill -0 "$SERVE_PID" >/dev/null 2>&1; then
    if (( KEEP_SERVER == 1 )); then
      echo "[docs-visual-review] leaving mkdocs server running with pid $SERVE_PID"
    else
      kill "$SERVE_PID" >/dev/null 2>&1 || true
      wait "$SERVE_PID" >/dev/null 2>&1 || true
      echo "[docs-visual-review] stopped mkdocs server"
    fi
  fi
  return "$exit_code"
}

trap 'cleanup $?' EXIT INT TERM

echo "[docs-visual-review] output: $OUT_DIR"

if (( RUN_SWIFT_BUILD == 1 )); then
  echo "[docs-visual-review] swift build"
  if swift build >"$SWIFT_LOG" 2>&1; then
    SWIFT_BUILD_STATUS="pass"
  else
    SWIFT_BUILD_STATUS="fail"
    echo "swift build failed. See $SWIFT_LOG" >&2
    exit 1
  fi
fi

if (( SKIP_DOCS_BUILD == 0 )); then
  echo "[docs-visual-review] uv cache: $UV_CACHE_DIR"
  echo "[docs-visual-review] uv run mkdocs build --strict"
  if uv run mkdocs build --strict >"$MKDOCS_LOG" 2>&1; then
    DOCS_BUILD_STATUS="pass"
  else
    DOCS_BUILD_STATUS="fail"
    echo "mkdocs build failed. See $MKDOCS_LOG" >&2
    exit 1
  fi
fi

if (( NO_SERVE == 0 )); then
  echo "[docs-visual-review] starting docs server on $HOST:$PORT"
  uv run mkdocs serve --dev-addr "$HOST:$PORT" >"$SERVE_LOG" 2>&1 &
  SERVE_PID="$!"
  SERVE_STARTED=1

  elapsed=0
  while ! curl -fsS "$DOCS_URL" >/dev/null 2>&1; do
    if (( elapsed >= TIMEOUT_SECONDS )); then
      echo "Timed out waiting for docs server at $DOCS_URL. See $SERVE_LOG" >&2
      exit 1
    fi
    if [[ -n "$SERVE_PID" ]] && ! kill -0 "$SERVE_PID" >/dev/null 2>&1; then
      echo "MkDocs server exited early. See $SERVE_LOG" >&2
      exit 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  echo "[docs-visual-review] docs server is ready"
else
  echo "[docs-visual-review] no-serve mode, verifying URL: $DOCS_URL"
  elapsed=0
  while ! curl -fsS "$DOCS_URL" >/dev/null 2>&1; do
    if (( elapsed >= TIMEOUT_SECONDS )); then
      echo "Timed out waiting for URL: $DOCS_URL" >&2
      exit 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo "[docs-visual-review] target URL is reachable"
fi

base_url="${DOCS_URL%/}"
home_url="$DOCS_URL"
menu_url="$base_url/guides/menu-and-settings/"
spec_url="$base_url/product/spec/"

echo "[docs-visual-review] running Playwright capture"
{
  playwright-cli open about:blank
  playwright-cli goto "$home_url"
  playwright-cli screenshot --filename "$OUT_DIR/home.png" --full-page
  playwright-cli goto "$menu_url"
  playwright-cli screenshot --filename "$OUT_DIR/menu-and-settings.png" --full-page
  playwright-cli goto "$spec_url"
  playwright-cli screenshot --filename "$OUT_DIR/product-spec.png" --full-page
  playwright-cli console error
  playwright-cli close-all
} >"$PLAYWRIGHT_LOG" 2>&1
PLAYWRIGHT_STATUS="pass"

log_lines=()
if [[ "$SWIFT_BUILD_STATUS" == "pass" || "$SWIFT_BUILD_STATUS" == "fail" ]]; then
  log_lines+=("- swift build: \`swift-build.log\`")
else
  log_lines+=("- swift build: skipped")
fi

if [[ "$DOCS_BUILD_STATUS" == "pass" || "$DOCS_BUILD_STATUS" == "fail" ]]; then
  log_lines+=("- docs build: \`mkdocs-build.log\`")
else
  log_lines+=("- docs build: skipped")
fi

if (( SERVE_STARTED == 1 )); then
  log_lines+=("- docs serve: \`mkdocs-serve.log\`")
else
  log_lines+=("- docs serve: skipped")
fi

log_lines+=("- playwright: \`playwright.log\`")
LOG_SECTION="$(printf '%s\n' "${log_lines[@]}")"

cat >"$OUT_DIR/report.md" <<EOF
# Docs Visual Review

- output: $OUT_DIR
- docs_url: $DOCS_URL
- swift_build: $SWIFT_BUILD_STATUS
- docs_build: $DOCS_BUILD_STATUS
- playwright: $PLAYWRIGHT_STATUS
- server_started: $SERVE_STARTED
- no_serve: $NO_SERVE

## Screenshots

- home: \`home.png\`
- menu and settings: \`menu-and-settings.png\`
- product spec: \`product-spec.png\`

## Logs

$LOG_SECTION
EOF

echo "[docs-visual-review] done"
echo "[docs-visual-review] report: $OUT_DIR/report.md"
