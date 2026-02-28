#!/usr/bin/env bash
set -euo pipefail

# Recording cross-product tests: every combination of
# recording tool × replay tool produces consistent results.
#
# Matrix (2 recorders × 2 readers = 4 combinations):
#   ovh-ttyrec  → iris-replay
#   ovh-ttyrec  → ipbt
#   iris-rec    → iris-replay  (already in cli-regressions.sh, re-verified here)
#   iris-rec    → ipbt
#
# Cross-tool agreement: same input recorded by both tools should produce
# recordings that both readers agree on (frame count, payload bytes).

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REC_BIN="${IRIS_REC_BIN:-$ROOT_DIR/iris-rec/build/exec/iris-rec}"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"

usage() {
  cat <<'EOF'
Usage: tests/recording-cross-product.sh [--test ovh-to-iris-replay|ovh-to-ipbt|iris-rec-to-ipbt|cross-tool-agreement]
EOF
}

selected_test=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --test)
      selected_test="${2:-}"
      shift 2
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

require_cmd ttyrec
require_cmd ipbt-dump
require_cmd xxd
require_cmd cmp

if [[ ! -x "$IRIS_REC_BIN" ]]; then
  echo "missing binary: $IRIS_REC_BIN" >&2
  exit 1
fi

if [[ ! -x "$IRIS_REPLAY_BIN" ]]; then
  echo "missing binary: $IRIS_REPLAY_BIN" >&2
  exit 1
fi

# --- Helper: record with ovh-ttyrec ---
# Records a known byte sequence by piping it through `ttyrec -e cat`.
# Args: $1 = input file, $2 = output ttyrec file
record_with_ovh() {
  local input_file="$1"
  local output_file="$2"
  # ttyrec -e CMD records the output of CMD into a ttyrec file.
  # Using `cat` as the command: it reads stdin and writes to stdout,
  # so the ttyrec captures exactly the bytes from input_file.
  ttyrec -e "cat" "$output_file" < "$input_file" >/dev/null 2>&1
}

# --- Helper: record with iris-rec ---
# Records a known byte sequence using iris-rec.
# Args: $1 = input file, $2 = output ttyrec file
record_with_iris_rec() {
  local input_file="$1"
  local output_file="$2"
  "$IRIS_REC_BIN" record "$output_file" < "$input_file" >/dev/null
}

# --- Helper: read frame count with iris-replay ---
# Returns frame count via iris-replay info.
# Args: $1 = ttyrec file
# Outputs: frame count to stdout
frame_count_iris_replay() {
  local ttyrec_file="$1"
  "$IRIS_REPLAY_BIN" info "$ttyrec_file" 2>&1 | awk '/^frames: [0-9]+$/ { print $2; exit }'
}

# --- Helper: extract frame payload with iris-replay ---
# Extracts raw bytes of a single frame.
# Args: $1 = ttyrec file, $2 = frame index
# Outputs: raw bytes to stdout
frame_payload_iris_replay() {
  local ttyrec_file="$1"
  local frame_idx="$2"
  "$IRIS_REPLAY_BIN" raw-dump "$ttyrec_file" "$frame_idx"
}

# --- Helper: read frame count with ipbt ---
# Returns frame count via ipbt-dump.
# Args: $1 = ttyrec file
# Outputs: frame count to stdout
frame_count_ipbt() {
  local ttyrec_file="$1"
  ipbt-dump -T -H "$ttyrec_file" 2>/dev/null \
    | awk -F: '/:offset / { c += 1 } END { print c + 0 }'
}

# --- Helper: create canonical test input ---
# Creates a known byte sequence for recording tests.
# Args: $1 = output file path
make_test_input() {
  local output_file="$1"
  # A simple, deterministic payload: printable ASCII + newline.
  # No binary bytes here — that's for cross-backend tests.
  # This tests the recording/replay machinery itself.
  printf 'hello from iris recording test\n' > "$output_file"
}

# --- Tests (added in subsequent commits) ---

# --- Main ---
main() {
  tmp_dir="$(mktemp -d /tmp/iris-recording-cross-product.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local failures=0

  case "$selected_test" in
    "")
      echo "no tests yet — skeleton only"
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
