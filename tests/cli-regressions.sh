#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REC_BIN="${IRIS_REC_BIN:-$ROOT_DIR/iris-rec/build/exec/iris-rec}"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"

usage() {
  cat <<'EOF'
Usage: tests/cli-regressions.sh [--test replay-byte-safety|record-byte-safety|record-timestamps|search-output|info-output|raw-byte-roundtrip|exit-codes]
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
require_cmd grep

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

run_replay_byte_safety() {
  local tmp_dir="$1"
  local payload_file="$tmp_dir/replay-input.bin"
  local ttyrec_file="$tmp_dir/replay-single-frame.ttyrec"
  local replay_file="$tmp_dir/replay-output.bin"

  # Deliberately include non-ASCII bytes and NUL.
  printf '\200\377\000A\177\n' > "$payload_file"
  make_single_frame_ttyrec "$payload_file" "$ttyrec_file" 17 420

  "$IRIS_REPLAY_BIN" replay "$ttyrec_file" > "$replay_file"

  if cmp -s "$payload_file" "$replay_file"; then
    echo "PASS replay-byte-safety"
    return 0
  fi

  echo "FAIL replay-byte-safety"
  echo "expected:"
  xxd -g 1 "$payload_file"
  echo "actual:"
  xxd -g 1 "$replay_file"
  return 1
}

run_record_byte_safety() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/record-input.bin"
  local ttyrec_file="$tmp_dir/record-output.ttyrec"
  local payload_file="$tmp_dir/record-payload.bin"

  # Deliberately include non-ASCII bytes and NUL.
  printf '\200\377\000A\177\n' > "$input_file"

  cat "$input_file" | "$IRIS_REC_BIN" record "$ttyrec_file" >/dev/null
  dd if="$ttyrec_file" of="$payload_file" bs=1 skip=12 2>/dev/null

  if cmp -s "$input_file" "$payload_file"; then
    echo "PASS record-byte-safety"
    return 0
  fi

  echo "FAIL record-byte-safety"
  echo "expected payload:"
  xxd -g 1 "$input_file"
  echo "actual payload:"
  xxd -g 1 "$payload_file"
  return 1
}

run_record_timestamps() {
  local tmp_dir="$1"
  local input_file="$tmp_dir/timestamp-input.bin"
  local ttyrec_file="$tmp_dir/timestamp-output.ttyrec"
  local sec_hex
  local usec_hex
  local sec_val
  local usec_val

  printf 'timestamp-check\n' > "$input_file"
  cat "$input_file" | "$IRIS_REC_BIN" record "$ttyrec_file" >/dev/null

  sec_hex="$(dd if="$ttyrec_file" bs=1 count=4 2>/dev/null | xxd -p -c 1000000)"
  usec_hex="$(dd if="$ttyrec_file" bs=1 skip=4 count=4 2>/dev/null | xxd -p -c 1000000)"

  sec_val=$((16#${sec_hex:6:2}${sec_hex:4:2}${sec_hex:2:2}${sec_hex:0:2}))
  usec_val=$((16#${usec_hex:6:2}${usec_hex:4:2}${usec_hex:2:2}${usec_hex:0:2}))

  if [[ "$sec_val" -eq 0 && "$usec_val" -eq 0 ]]; then
    echo "FAIL record-timestamps frame timestamp is 0/0"
    return 1
  fi

  echo "PASS record-timestamps"
  return 0
}

run_search_output() {
  local tmp_dir="$1"
  local payload0="$tmp_dir/search-payload-0.txt"
  local payload1="$tmp_dir/search-payload-1.txt"
  local payload2="$tmp_dir/search-payload-2.txt"
  local frame0="$tmp_dir/search-frame-0.ttyrec"
  local frame1="$tmp_dir/search-frame-1.ttyrec"
  local frame2="$tmp_dir/search-frame-2.ttyrec"
  local ttyrec_file="$tmp_dir/search-input.ttyrec"
  local output_file="$tmp_dir/search-output.txt"

  printf 'prefix needle one\n' > "$payload0"
  printf 'skip frame\n' > "$payload1"
  printf 'needle two suffix\n' > "$payload2"

  make_single_frame_ttyrec "$payload0" "$frame0" 10 100
  make_single_frame_ttyrec "$payload1" "$frame1" 11 200
  make_single_frame_ttyrec "$payload2" "$frame2" 12 300
  cat "$frame0" "$frame1" "$frame2" > "$ttyrec_file"

  set +e
  "$IRIS_REPLAY_BIN" search "$ttyrec_file" "needle" > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL search-output command exited with $status"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "frame=0" "$output_file"; then
    echo "FAIL search-output missing frame index for first match"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "frame=2" "$output_file"; then
    echo "FAIL search-output missing frame index for second match"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "ts=10.100" "$output_file"; then
    echo "FAIL search-output missing timestamp for first match"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "ts=12.300" "$output_file"; then
    echo "FAIL search-output missing timestamp for second match"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "snippet=" "$output_file"; then
    echo "FAIL search-output missing snippet field"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "needle one" "$output_file"; then
    echo "FAIL search-output missing first snippet content"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "needle two" "$output_file"; then
    echo "FAIL search-output missing second snippet content"
    cat "$output_file"
    return 1
  fi

  echo "PASS search-output"
  return 0
}

run_info_output() {
  local tmp_dir="$1"
  local payload0="$tmp_dir/info-payload-0.txt"
  local payload1="$tmp_dir/info-payload-1.txt"
  local frame0="$tmp_dir/info-frame-0.ttyrec"
  local frame1="$tmp_dir/info-frame-1.ttyrec"
  local ttyrec_file="$tmp_dir/info-input.ttyrec"
  local output_file="$tmp_dir/info-output.txt"
  local expected_size

  printf 'alpha\n' > "$payload0"
  printf 'beta\n' > "$payload1"

  make_single_frame_ttyrec "$payload0" "$frame0" 10 100
  make_single_frame_ttyrec "$payload1" "$frame1" 13 600
  cat "$frame0" "$frame1" > "$ttyrec_file"
  expected_size="$(wc -c < "$ttyrec_file" | tr -d ' ')"

  set +e
  "$IRIS_REPLAY_BIN" info "$ttyrec_file" > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL info-output command exited with $status"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "^frames: 2$" "$output_file"; then
    echo "FAIL info-output missing frame count"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "^file-size: $expected_size$" "$output_file"; then
    echo "FAIL info-output missing or wrong file-size"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "^timestamp-range: 10.100..13.600$" "$output_file"; then
    echo "FAIL info-output missing or wrong timestamp-range"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "^duration-us: 3000500$" "$output_file"; then
    echo "FAIL info-output missing or wrong duration-us"
    cat "$output_file"
    return 1
  fi

  echo "PASS info-output"
  return 0
}

run_exit_codes() {
  local tmp_dir="$1"
  local failures=0

  set +e
  "$IRIS_REPLAY_BIN" >/dev/null 2>&1
  local replay_usage_status=$?
  "$IRIS_REPLAY_BIN" replay "$tmp_dir/does-not-exist.ttyrec" >/dev/null 2>&1
  local replay_replay_status=$?
  "$IRIS_REPLAY_BIN" search "$tmp_dir/does-not-exist.ttyrec" "needle" >/dev/null 2>&1
  local replay_search_status=$?
  "$IRIS_REPLAY_BIN" info "$tmp_dir/does-not-exist.ttyrec" >/dev/null 2>&1
  local replay_info_status=$?
  "$IRIS_REC_BIN" >/dev/null 2>&1
  local rec_usage_status=$?
  "$IRIS_REC_BIN" record >/dev/null 2>&1
  local rec_record_args_status=$?
  set -e

  if [[ "$replay_usage_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-usage returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-usage"
  fi

  if [[ "$replay_replay_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-replay-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-replay-missing-file"
  fi

  if [[ "$replay_search_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-search-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-search-missing-file"
  fi

  if [[ "$replay_info_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-info-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-info-missing-file"
  fi

  if [[ "$rec_usage_status" -eq 0 ]]; then
    echo "FAIL exit-codes rec-no-args returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes rec-no-args"
  fi

  if [[ "$rec_record_args_status" -eq 0 ]]; then
    echo "FAIL exit-codes rec-record-missing-output returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes rec-record-missing-output"
  fi

  return "$failures"
}

main() {
  tmp_dir="$(mktemp -d /tmp/iris-cli-regressions.XXXXXX)"
  trap 'rm -rf "$tmp_dir"' EXIT

  local failures=0

  case "$selected_test" in
    "")
      run_replay_byte_safety "$tmp_dir" || failures=$((failures + 1))
      run_record_byte_safety "$tmp_dir" || failures=$((failures + 1))
      run_record_timestamps "$tmp_dir" || failures=$((failures + 1))
      run_search_output "$tmp_dir" || failures=$((failures + 1))
      run_info_output "$tmp_dir" || failures=$((failures + 1))
      run_raw_byte_roundtrip "$tmp_dir" || failures=$((failures + 1))
      run_exit_codes "$tmp_dir" || failures=$((failures + 1))
      ;;
    "replay-byte-safety")
      run_replay_byte_safety "$tmp_dir" || failures=$((failures + 1))
      ;;
    "record-byte-safety")
      run_record_byte_safety "$tmp_dir" || failures=$((failures + 1))
      ;;
    "record-timestamps")
      run_record_timestamps "$tmp_dir" || failures=$((failures + 1))
      ;;
    "search-output")
      run_search_output "$tmp_dir" || failures=$((failures + 1))
      ;;
    "info-output")
      run_info_output "$tmp_dir" || failures=$((failures + 1))
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
