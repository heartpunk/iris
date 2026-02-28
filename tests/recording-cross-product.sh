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

# --- Test: ovh-ttyrec → iris-replay ---
run_ovh_to_iris_replay() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/ovh-input.txt"
  local ttyrec_file="$tmp_dir/ovh-recording.ttyrec"
  local payload_file="$tmp_dir/ovh-iris-payload.bin"

  make_test_input "$input_file"
  record_with_ovh "$input_file" "$ttyrec_file"

  # Verify iris-replay can read the recording
  local frames
  frames="$(frame_count_iris_replay "$ttyrec_file")"
  if [[ -z "$frames" || "$frames" -le 0 ]]; then
    echo "FAIL ovh-to-iris-replay: iris-replay reports 0 or missing frame count"
    return 1
  fi

  # Extract frame 0 payload and verify it contains our input
  frame_payload_iris_replay "$ttyrec_file" 0 > "$payload_file"
  local payload_size
  payload_size="$(wc -c < "$payload_file" | tr -d ' ')"
  if [[ "$payload_size" -eq 0 ]]; then
    echo "FAIL ovh-to-iris-replay: frame 0 payload is empty"
    return 1
  fi

  # The payload should contain our test string
  if ! grep -q "hello from iris recording test" "$payload_file"; then
    echo "FAIL ovh-to-iris-replay: frame 0 payload missing expected content"
    echo "payload:"
    xxd -g 1 "$payload_file" | head -5
    return 1
  fi

  echo "PASS ovh-to-iris-replay (frames=$frames)"
  return 0
}

# --- Test: ovh-ttyrec → ipbt ---
run_ovh_to_ipbt() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/ovh-ipbt-input.txt"
  local ttyrec_file="$tmp_dir/ovh-ipbt-recording.ttyrec"

  make_test_input "$input_file"
  record_with_ovh "$input_file" "$ttyrec_file"

  # Verify ipbt can read the recording
  local frames
  frames="$(frame_count_ipbt "$ttyrec_file")"
  if [[ -z "$frames" || "$frames" -le 0 ]]; then
    echo "FAIL ovh-to-ipbt: ipbt reports 0 or missing frame count"
    return 1
  fi

  # Cross-check: iris-replay should agree on frame count
  local iris_frames
  iris_frames="$(frame_count_iris_replay "$ttyrec_file")"
  if [[ "$frames" -ne "$iris_frames" ]]; then
    echo "FAIL ovh-to-ipbt: frame count mismatch ipbt=$frames iris=$iris_frames"
    return 1
  fi

  echo "PASS ovh-to-ipbt (frames=$frames)"
  return 0
}

# --- Test: iris-rec → ipbt ---
run_iris_rec_to_ipbt() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/iris-rec-ipbt-input.txt"
  local ttyrec_file="$tmp_dir/iris-rec-ipbt-recording.ttyrec"

  make_test_input "$input_file"
  record_with_iris_rec "$input_file" "$ttyrec_file"

  # Verify ipbt can read the iris-rec recording
  local frames
  frames="$(frame_count_ipbt "$ttyrec_file")"
  if [[ -z "$frames" || "$frames" -le 0 ]]; then
    echo "FAIL iris-rec-to-ipbt: ipbt reports 0 or missing frame count"
    return 1
  fi

  # Cross-check: iris-replay should agree
  local iris_frames
  iris_frames="$(frame_count_iris_replay "$ttyrec_file")"
  if [[ "$frames" -ne "$iris_frames" ]]; then
    echo "FAIL iris-rec-to-ipbt: frame count mismatch ipbt=$frames iris=$iris_frames"
    return 1
  fi

  echo "PASS iris-rec-to-ipbt (frames=$frames)"
  return 0
}

# --- Test: cross-tool agreement ---
# Record the same input with both tools, read with both readers,
# verify all 4 combinations agree on frame count and payload content.
run_cross_tool_agreement() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/cross-input.txt"
  local ovh_ttyrec="$tmp_dir/cross-ovh.ttyrec"
  local iris_ttyrec="$tmp_dir/cross-iris.ttyrec"
  local ovh_payload="$tmp_dir/cross-ovh-payload.bin"
  local iris_payload="$tmp_dir/cross-iris-payload.bin"

  make_test_input "$input_file"
  record_with_ovh "$input_file" "$ovh_ttyrec"
  record_with_iris_rec "$input_file" "$iris_ttyrec"

  # Read frame counts with both readers for both recordings
  local ovh_iris_frames ovh_ipbt_frames iris_iris_frames iris_ipbt_frames
  ovh_iris_frames="$(frame_count_iris_replay "$ovh_ttyrec")"
  ovh_ipbt_frames="$(frame_count_ipbt "$ovh_ttyrec")"
  iris_iris_frames="$(frame_count_iris_replay "$iris_ttyrec")"
  iris_ipbt_frames="$(frame_count_ipbt "$iris_ttyrec")"

  # Both readers should agree on each recording's frame count
  if [[ "$ovh_iris_frames" -ne "$ovh_ipbt_frames" ]]; then
    echo "FAIL cross-tool-agreement: ovh recording frame count mismatch iris=$ovh_iris_frames ipbt=$ovh_ipbt_frames"
    return 1
  fi

  if [[ "$iris_iris_frames" -ne "$iris_ipbt_frames" ]]; then
    echo "FAIL cross-tool-agreement: iris-rec recording frame count mismatch iris=$iris_iris_frames ipbt=$iris_ipbt_frames"
    return 1
  fi

  # Both recordings should have at least 1 frame
  if [[ "$ovh_iris_frames" -le 0 ]]; then
    echo "FAIL cross-tool-agreement: ovh recording has 0 frames"
    return 1
  fi

  if [[ "$iris_iris_frames" -le 0 ]]; then
    echo "FAIL cross-tool-agreement: iris-rec recording has 0 frames"
    return 1
  fi

  # Extract frame 0 payloads from both recordings via iris-replay
  frame_payload_iris_replay "$ovh_ttyrec" 0 > "$ovh_payload"
  frame_payload_iris_replay "$iris_ttyrec" 0 > "$iris_payload"

  # Both payloads should contain our test string
  if ! grep -q "hello from iris recording test" "$ovh_payload"; then
    echo "FAIL cross-tool-agreement: ovh frame 0 missing expected content"
    echo "ovh payload:"
    xxd -g 1 "$ovh_payload" | head -5
    return 1
  fi

  if ! grep -q "hello from iris recording test" "$iris_payload"; then
    echo "FAIL cross-tool-agreement: iris-rec frame 0 missing expected content"
    echo "iris payload:"
    xxd -g 1 "$iris_payload" | head -5
    return 1
  fi

  # Payloads should match byte-for-byte (same input → same recorded bytes)
  if ! cmp -s "$ovh_payload" "$iris_payload"; then
    echo "FAIL cross-tool-agreement: frame 0 payloads differ between recorders"
    echo "ovh payload ($(wc -c < "$ovh_payload" | tr -d ' ') bytes):"
    xxd -g 1 "$ovh_payload" | head -5
    echo "iris payload ($(wc -c < "$iris_payload" | tr -d ' ') bytes):"
    xxd -g 1 "$iris_payload" | head -5
    return 1
  fi

  echo "PASS cross-tool-agreement (ovh_frames=$ovh_iris_frames iris_frames=$iris_iris_frames payload_match=yes)"
  return 0
}

# --- Main ---
main() {
  tmp_dir="$(mktemp -d /tmp/iris-recording-cross-product.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local failures=0

  case "$selected_test" in
    "")
      run_ovh_to_iris_replay "$tmp_dir" || failures=$((failures + 1))
      run_ovh_to_ipbt "$tmp_dir" || failures=$((failures + 1))
      run_iris_rec_to_ipbt "$tmp_dir" || failures=$((failures + 1))
      run_cross_tool_agreement "$tmp_dir" || failures=$((failures + 1))
      ;;
    "ovh-to-iris-replay")
      run_ovh_to_iris_replay "$tmp_dir" || failures=$((failures + 1))
      ;;
    "ovh-to-ipbt")
      run_ovh_to_ipbt "$tmp_dir" || failures=$((failures + 1))
      ;;
    "iris-rec-to-ipbt")
      run_iris_rec_to_ipbt "$tmp_dir" || failures=$((failures + 1))
      ;;
    "cross-tool-agreement")
      run_cross_tool_agreement "$tmp_dir" || failures=$((failures + 1))
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
