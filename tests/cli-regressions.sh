#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REC_BIN="${IRIS_REC_BIN:-$ROOT_DIR/iris-rec/build/exec/iris-rec}"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"

usage() {
  cat <<'EOF'
Usage: tests/cli-regressions.sh [--test raw-byte-roundtrip|exit-codes]
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

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd xxd
require_cmd wc
require_cmd cmp

if [[ ! -x "$IRIS_REC_BIN" ]]; then
  echo "missing binary: $IRIS_REC_BIN" >&2
  exit 1
fi

if [[ ! -x "$IRIS_REPLAY_BIN" ]]; then
  echo "missing binary: $IRIS_REPLAY_BIN" >&2
  exit 1
fi

u32le_hex() {
  local n="$1"
  printf '%02x%02x%02x%02x' \
    "$((n & 255))" \
    "$(((n >> 8) & 255))" \
    "$(((n >> 16) & 255))" \
    "$(((n >> 24) & 255))"
}

make_single_frame_ttyrec() {
  local payload_file="$1"
  local output_file="$2"
  local sec="$3"
  local usec="$4"
  local payload_len
  local payload_hex

  payload_len="$(wc -c < "$payload_file" | tr -d ' ')"
  payload_hex="$(xxd -p -c 1000000 "$payload_file" | tr -d '\n')"

  printf '%s%s%s%s' \
    "$(u32le_hex "$sec")" \
    "$(u32le_hex "$usec")" \
    "$(u32le_hex "$payload_len")" \
    "$payload_hex" | xxd -r -p > "$output_file"
}

run_raw_byte_roundtrip() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/input.bin"
  local ttyrec_file="$tmp_dir/roundtrip.ttyrec"
  local replay_file="$tmp_dir/replay.bin"

  # Deliberately include non-ASCII bytes and NUL.
  printf '\200\377\000A\177\n' > "$input_file"

  cat "$input_file" | "$IRIS_REC_BIN" record "$ttyrec_file" >/dev/null
  "$IRIS_REPLAY_BIN" replay "$ttyrec_file" > "$replay_file"

  if cmp -s "$input_file" "$replay_file"; then
    echo "PASS raw-byte-roundtrip"
    return 0
  fi

  echo "FAIL raw-byte-roundtrip"
  echo "expected:"
  xxd -g 1 "$input_file"
  echo "actual:"
  xxd -g 1 "$replay_file"
  return 1
}

run_exit_codes() {
  local tmp_dir="$1"
  local failures=0

  set +e
  "$IRIS_REPLAY_BIN" info "$tmp_dir/does-not-exist.ttyrec" >/dev/null 2>&1
  local replay_status=$?
  "$IRIS_REC_BIN" >/dev/null 2>&1
  local rec_status=$?
  set -e

  if [[ "$replay_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-info-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-info-missing-file"
  fi

  if [[ "$rec_status" -eq 0 ]]; then
    echo "FAIL exit-codes rec-no-args returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes rec-no-args"
  fi

  return "$failures"
}

main() {
  local tmp_dir
  tmp_dir="$(mktemp -d /tmp/iris-cli-regressions.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local failures=0

  case "$selected_test" in
    "")
      run_raw_byte_roundtrip "$tmp_dir" || failures=$((failures + 1))
      run_exit_codes "$tmp_dir" || failures=$((failures + 1))
      ;;
    "raw-byte-roundtrip")
      run_raw_byte_roundtrip "$tmp_dir" || failures=$((failures + 1))
      ;;
    "exit-codes")
      run_exit_codes "$tmp_dir" || failures=$((failures + 1))
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
