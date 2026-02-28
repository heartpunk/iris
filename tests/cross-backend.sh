#!/usr/bin/env bash
set -euo pipefail

# Cross-backend tests: verify iris-native produces the same screen output
# as tmux for identical commands.
#
# Strategy:
#   1. Run a scenario in tmux — record PTY output with ovh-ttyrec inside
#      the pane, then replay the recording with iris-replay to reconstruct
#      final screen state.
#   2. Run the same scenario in iris-native — record with ovh-ttyrec
#      wrapping iris-native, then replay identically.
#   3. Compare replayed outputs byte-for-byte. No fuzzy matching, no capture-pane.
#
# Three-way outcome:
#   PASS       — iris-native replay matches tmux gold standard
#   BASELINE   — iris-native replay matches known broken baseline (expected)
#   REGRESSION — iris-native replay differs from both tmux AND known baseline (new breakage)
#   FAIL       — test infrastructure error

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REC_BIN="${IRIS_REC_BIN:-$ROOT_DIR/iris-rec/build/exec/iris-rec}"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"
IRIS_NATIVE_BIN="${IRIS_NATIVE_BIN:-$ROOT_DIR/iris-native/build/exec/iris-native}"
BASELINES_DIR="$ROOT_DIR/tests/fixtures/cross-backend-baselines"

# Default terminal dimensions for all tests
TERM_COLS=80
TERM_ROWS=24

usage() {
  cat <<'EOF'
Usage: tests/cross-backend.sh [--test simple-echo|multiline|ls-colors|prompt-basic|cat-binary] [--update-baselines] [--tmux-only] [--native-only]

Options:
  --test NAME          Run a single test scenario
  --update-baselines   Re-record and save baseline files
  --tmux-only          Only run tmux gold standard (skip iris-native)
  --native-only        Only run iris-native (skip tmux, compare to baselines)
EOF
}

selected_test=""
update_baselines=false
tmux_only=false
native_only=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)
      selected_test="${2:-}"
      shift 2
      ;;
    --update-baselines)
      update_baselines=true
      shift
      ;;
    --tmux-only)
      tmux_only=true
      shift
      ;;
    --native-only)
      native_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

# --- Dependency checks ---

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd tmux
require_cmd ttyrec
require_cmd xxd
require_cmd cmp

if [[ ! -x "$IRIS_REPLAY_BIN" ]]; then
  echo "missing binary: $IRIS_REPLAY_BIN" >&2
  exit 1
fi

# iris-native is optional (might not be built yet)
has_native=true
if [[ ! -x "$IRIS_NATIVE_BIN" ]]; then
  if [[ "$native_only" == "true" ]]; then
    echo "missing binary: $IRIS_NATIVE_BIN" >&2
    exit 1
  fi
  has_native=false
fi

# ============================================================
# Controlled shell environment
# ============================================================

# Create a minimal shell init file for reproducible output.
# Args: $1 = tmp_dir
# Sets: CONTROLLED_ENV_FILE
setup_controlled_env() {
  local tmp_dir="$1"
  CONTROLLED_ENV_FILE="$tmp_dir/test-bashrc"
  cat > "$CONTROLLED_ENV_FILE" <<'BASHRC'
# Minimal bashrc for cross-backend tests — deterministic output
export PS1='$ '
export TERM=xterm
export LC_ALL=C
export LANG=C
export BASH_SILENCE_DEPRECATION_WARNING=1
unset PROMPT_COMMAND
BASHRC
}

# ============================================================
# Tmux backend: record PTY output with ttyrec inside a pane
# ============================================================

# Run a scenario in tmux, recording the PTY output with ovh-ttyrec.
# The tmux pane runs `ttyrec -f <recording> -- bash --rcfile <env>`,
# so ttyrec captures everything the shell emits.
# Args: $1 = scenario name, $2 = tmp_dir, $3 = commands (newline-separated)
# Produces: $tmp_dir/$scenario-tmux.ttyrec
run_tmux_scenario() {
  local scenario="$1"
  local tmp_dir="$2"
  local commands="$3"
  local recording="$tmp_dir/${scenario}-tmux.ttyrec"
  local tmux_tmpdir="$tmp_dir/tmux-$scenario"
  local session="iris-test-$scenario"

  mkdir -p "$tmux_tmpdir"

  # Launch ttyrec inside a tmux session. ttyrec wraps the shell, recording
  # all PTY output to the ttyrec file.
  TMUX_TMPDIR="$tmux_tmpdir" tmux new-session -d \
    -s "$session" \
    -x "$TERM_COLS" \
    -y "$TERM_ROWS" \
    "ttyrec -f $recording -- bash --rcfile $CONTROLLED_ENV_FILE --noprofile"

  # Give ttyrec + shell time to start
  sleep 0.8

  # Send commands
  if [[ -n "$commands" ]]; then
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      TMUX_TMPDIR="$tmux_tmpdir" tmux send-keys -t "$session" "$cmd" Enter
      sleep 0.3
    done <<< "$commands"
  fi

  # Wait for output to settle
  sleep 0.5

  # Exit the shell cleanly so ttyrec finishes writing
  TMUX_TMPDIR="$tmux_tmpdir" tmux send-keys -t "$session" "exit" Enter
  sleep 0.5

  # Kill session if still alive
  TMUX_TMPDIR="$tmux_tmpdir" tmux kill-session -t "$session" 2>/dev/null || true
}

# ============================================================
# Replay: reconstruct screen state from ttyrec recording
# ============================================================

# Replay a ttyrec recording with iris-replay and write the full replayed
# byte stream to an output file. This is the "screen state" we compare.
# Args: $1 = ttyrec file, $2 = output file
replay_to_screen() {
  local ttyrec_file="$1"
  local output_file="$2"

  if [[ ! -f "$ttyrec_file" ]]; then
    echo "  ERROR: recording not found: $ttyrec_file" >&2
    return 1
  fi

  "$IRIS_REPLAY_BIN" replay "$ttyrec_file" > "$output_file"
}

# --- Main (tests added in subsequent commits) ---
main() {
  tmp_dir="$(mktemp -d /tmp/iris-cross-backend.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT

  setup_controlled_env "$tmp_dir"

  local failures=0

  case "$selected_test" in
    "")
      echo "no scenarios yet — skeleton only"
      ;;
    *)
      echo "unknown test: $selected_test" >&2
      usage
      exit 2
      ;;
  esac

  if [[ "$failures" -eq 0 ]]; then
    echo "ALL PASS"
  else
    echo "FAILURES: $failures"
    exit 1
  fi
}

main
