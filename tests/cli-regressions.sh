#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REC_BIN="${IRIS_REC_BIN:-$ROOT_DIR/iris-rec/build/exec/iris-rec}"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"

usage() {
  cat <<'EOF'
Usage: tests/cli-regressions.sh [--test replay-byte-safety|record-byte-safety|record-timestamps|search-output|search-zero-matches|info-output|dump-output|raw-dump-output|empty-file|raw-byte-roundtrip|exit-codes|help-flags|compressed-roundtrip|compression-mismatch]
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
require_cmd lzip

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

  if ! grep -q "ts=10.000100" "$output_file"; then
    echo "FAIL search-output missing timestamp for first match"
    cat "$output_file"
    return 1
  fi

  if ! grep -q "ts=12.000300" "$output_file"; then
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

run_search_zero_matches() {
  local tmp_dir="$1"
  local payload_file="$tmp_dir/search-zero-payload.txt"
  local ttyrec_file="$tmp_dir/search-zero-input.ttyrec"
  local output_file="$tmp_dir/search-zero-output.txt"
  local line_count

  printf 'hello world\n' > "$payload_file"
  make_single_frame_ttyrec "$payload_file" "$ttyrec_file" 21 42

  set +e
  "$IRIS_REPLAY_BIN" search "$ttyrec_file" "xyzzy" > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL search-zero-matches command exited with $status"
    cat "$output_file"
    return 1
  fi

  if ! grep -qx "matches: 0" "$output_file"; then
    echo "FAIL search-zero-matches expected exact matches: 0 line"
    cat "$output_file"
    return 1
  fi

  line_count="$(wc -l < "$output_file" | tr -d ' ')"
  if [[ "$line_count" -ne 1 ]]; then
    echo "FAIL search-zero-matches expected no additional match lines"
    cat "$output_file"
    return 1
  fi

  echo "PASS search-zero-matches"
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

  if ! grep -q "^timestamp-range: 10.000100..13.000600$" "$output_file"; then
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

run_dump_output() {
  local tmp_dir="$1"
  local payload0="$tmp_dir/dump-payload-0.txt"
  local payload1="$tmp_dir/dump-payload-1.txt"
  local payload2="$tmp_dir/dump-payload-2.txt"
  local frame0="$tmp_dir/dump-frame-0.ttyrec"
  local frame1="$tmp_dir/dump-frame-1.ttyrec"
  local frame2="$tmp_dir/dump-frame-2.ttyrec"
  local ttyrec_file="$tmp_dir/dump-input.ttyrec"
  local output_file="$tmp_dir/dump-output.txt"

  printf 'hello world\n' > "$payload0"
  printf 'line\ttwo\there\n' > "$payload1"
  printf 'third frame\n' > "$payload2"

  make_single_frame_ttyrec "$payload0" "$frame0" 10 100
  make_single_frame_ttyrec "$payload1" "$frame1" 10 500200
  make_single_frame_ttyrec "$payload2" "$frame2" 12 300

  cat "$frame0" "$frame1" "$frame2" > "$ttyrec_file"

  set +e
  "$IRIS_REPLAY_BIN" dump "$ttyrec_file" > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL dump-output command exited with $status"
    cat "$output_file"
    return 1
  fi

  local line_count
  line_count="$(wc -l < "$output_file" | tr -d ' ')"
  if [[ "$line_count" -ne 3 ]]; then
    echo "FAIL dump-output expected 3 lines, got $line_count"
    cat "$output_file"
    return 1
  fi

  # Frame 0: index=0, ts=10.000100, len=12, payload with sanitized newline
  if ! sed -n '1p' "$output_file" | grep -q "^frame=0 "; then
    echo "FAIL dump-output line 1 missing frame=0"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '1p' "$output_file" | grep -q "ts=10.000100"; then
    echo "FAIL dump-output line 1 wrong timestamp"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '1p' "$output_file" | grep -q "len=12"; then
    echo "FAIL dump-output line 1 wrong payload length"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '1p' "$output_file" | grep -q "payload=hello world"; then
    echo "FAIL dump-output line 1 wrong payload content"
    cat "$output_file"
    return 1
  fi

  # Frame 1: index=1, ts=10.500200, tabs sanitized to spaces
  if ! sed -n '2p' "$output_file" | grep -q "^frame=1 "; then
    echo "FAIL dump-output line 2 missing frame=1"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '2p' "$output_file" | grep -q "ts=10.500200"; then
    echo "FAIL dump-output line 2 wrong timestamp"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '2p' "$output_file" | grep -q "len=14"; then
    echo "FAIL dump-output line 2 wrong payload length"
    cat "$output_file"
    return 1
  fi

  # Tabs should be sanitized to spaces
  if ! sed -n '2p' "$output_file" | grep -q "payload=line two here"; then
    echo "FAIL dump-output line 2 tabs not sanitized"
    cat "$output_file"
    return 1
  fi

  # Frame 2: index=2, ts=12.000300
  if ! sed -n '3p' "$output_file" | grep -q "^frame=2 "; then
    echo "FAIL dump-output line 3 missing frame=2"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '3p' "$output_file" | grep -q "ts=12.000300"; then
    echo "FAIL dump-output line 3 wrong timestamp"
    cat "$output_file"
    return 1
  fi

  if ! sed -n '3p' "$output_file" | grep -q "len=12"; then
    echo "FAIL dump-output line 3 wrong payload length"
    cat "$output_file"
    return 1
  fi

  echo "PASS dump-output"
  return 0
}

run_raw_dump_output() {
  local tmp_dir="$1"
  local payload0="$tmp_dir/raw-dump-payload-0.bin"
  local payload1="$tmp_dir/raw-dump-payload-1.bin"
  local frame0="$tmp_dir/raw-dump-frame-0.ttyrec"
  local frame1="$tmp_dir/raw-dump-frame-1.ttyrec"
  local ttyrec_file="$tmp_dir/raw-dump-input.ttyrec"
  local output_file="$tmp_dir/raw-dump-output.bin"
  local oob_output="$tmp_dir/raw-dump-oob-output.txt"

  # Frame 0: some ASCII bytes; Frame 1: full non-ASCII range (0x80-0xFF).
  # The two payloads are intentionally different so we can verify selection.
  printf 'frame zero bytes\n' > "$payload0"
  printf '%02x' $(seq 128 255) | xxd -r -p > "$payload1"

  make_single_frame_ttyrec "$payload0" "$frame0" 1 0
  make_single_frame_ttyrec "$payload1" "$frame1" 2 0
  cat "$frame0" "$frame1" > "$ttyrec_file"

  # Requesting frame 1 should return only payload1, not payload0
  set +e
  "$IRIS_REPLAY_BIN" raw-dump "$ttyrec_file" 1 > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL raw-dump-output frame 1 command exited with $status"
    xxd -g 1 "$output_file" | head -5
    return 1
  fi

  if ! cmp -s "$payload1" "$output_file"; then
    echo "FAIL raw-dump-output frame 1 output does not match payload1"
    echo "expected size: $(wc -c < "$payload1" | tr -d ' ') bytes"
    echo "actual size:   $(wc -c < "$output_file" | tr -d ' ') bytes"
    echo "expected (first 32 bytes):"
    xxd -g 1 "$payload1" | head -2
    echo "actual (first 32 bytes):"
    xxd -g 1 "$output_file" | head -2
    return 1
  fi

  # Requesting frame 0 should return only payload0
  set +e
  "$IRIS_REPLAY_BIN" raw-dump "$ttyrec_file" 0 > "$output_file" 2>&1
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL raw-dump-output frame 0 command exited with $status"
    return 1
  fi

  if ! cmp -s "$payload0" "$output_file"; then
    echo "FAIL raw-dump-output frame 0 output does not match payload0"
    echo "expected size: $(wc -c < "$payload0" | tr -d ' ') bytes"
    echo "actual size:   $(wc -c < "$output_file" | tr -d ' ') bytes"
    return 1
  fi

  # Out-of-bounds index should exit non-zero
  set +e
  "$IRIS_REPLAY_BIN" raw-dump "$ttyrec_file" 2 > "$oob_output" 2>&1
  local oob_status=$?
  set -e

  if [[ "$oob_status" -eq 0 ]]; then
    echo "FAIL raw-dump-output out-of-bounds index should exit non-zero"
    cat "$oob_output"
    return 1
  fi

  echo "PASS raw-dump-output"
  return 0
}

run_empty_file() {
  local tmp_dir="$1"
  local empty_file="$tmp_dir/empty.ttyrec"
  local replay_output="$tmp_dir/empty-replay-output.bin"
  local search_output="$tmp_dir/empty-search-output.txt"
  local info_output="$tmp_dir/empty-info-output.txt"
  local dump_output="$tmp_dir/empty-dump-output.txt"
  local raw_dump_output="$tmp_dir/empty-raw-dump-output.bin"
  local replay_status
  local search_status
  local info_status
  local dump_status
  local raw_dump_status
  local replay_size

  : > "$empty_file"

  set +e
  "$IRIS_REPLAY_BIN" replay "$empty_file" > "$replay_output" 2>&1
  replay_status=$?
  "$IRIS_REPLAY_BIN" search "$empty_file" "anything" > "$search_output" 2>&1
  search_status=$?
  "$IRIS_REPLAY_BIN" info "$empty_file" > "$info_output" 2>&1
  info_status=$?
  "$IRIS_REPLAY_BIN" dump "$empty_file" > "$dump_output" 2>&1
  dump_status=$?
  "$IRIS_REPLAY_BIN" raw-dump "$empty_file" 0 > "$raw_dump_output" 2>&1
  raw_dump_status=$?
  set -e

  if [[ "$replay_status" -ne 0 ]]; then
    echo "FAIL empty-file replay exited with $replay_status"
    return 1
  fi

  replay_size="$(wc -c < "$replay_output" | tr -d ' ')"
  if [[ "$replay_size" -ne 0 ]]; then
    echo "FAIL empty-file replay produced output"
    xxd -g 1 "$replay_output"
    return 1
  fi

  if [[ "$search_status" -ne 0 ]]; then
    echo "FAIL empty-file search exited with $search_status"
    cat "$search_output"
    return 1
  fi

  if ! grep -qx "matches: 0" "$search_output"; then
    echo "FAIL empty-file search missing matches: 0"
    cat "$search_output"
    return 1
  fi

  if [[ "$info_status" -ne 0 ]]; then
    echo "FAIL empty-file info exited with $info_status"
    cat "$info_output"
    return 1
  fi

  if ! grep -q "^frames: 0$" "$info_output"; then
    echo "FAIL empty-file info missing frames: 0"
    cat "$info_output"
    return 1
  fi

  if ! grep -q "^timestamp-range: n/a$" "$info_output"; then
    echo "FAIL empty-file info missing timestamp-range: n/a"
    cat "$info_output"
    return 1
  fi

  if [[ "$dump_status" -ne 0 ]]; then
    echo "FAIL empty-file dump exited with $dump_status"
    cat "$dump_output"
    return 1
  fi

  local dump_size
  dump_size="$(wc -c < "$dump_output" | tr -d ' ')"
  if [[ "$dump_size" -ne 0 ]]; then
    echo "FAIL empty-file dump produced output"
    cat "$dump_output"
    return 1
  fi

  # raw-dump on an empty file (frame index 0 out of bounds) must exit non-zero
  if [[ "$raw_dump_status" -eq 0 ]]; then
    echo "FAIL empty-file raw-dump should exit non-zero (frame 0 out of bounds on empty file)"
    return 1
  fi

  echo "PASS empty-file"
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
  "$IRIS_REPLAY_BIN" dump "$tmp_dir/does-not-exist.ttyrec" >/dev/null 2>&1
  local replay_dump_status=$?
  "$IRIS_REPLAY_BIN" raw-dump "$tmp_dir/does-not-exist.ttyrec" 0 >/dev/null 2>&1
  local replay_raw_dump_status=$?
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

  if [[ "$replay_dump_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-dump-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-dump-missing-file"
  fi

  if [[ "$replay_raw_dump_status" -eq 0 ]]; then
    echo "FAIL exit-codes replay-raw-dump-missing-file returned 0"
    failures=$((failures + 1))
  else
    echo "PASS exit-codes replay-raw-dump-missing-file"
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

run_help_flags() {
  local failures=0

  set +e
  "$IRIS_REPLAY_BIN" --help >/dev/null 2>&1
  local replay_help_status=$?
  "$IRIS_REC_BIN" --help >/dev/null 2>&1
  local rec_help_status=$?
  set -e

  if [[ "$replay_help_status" -eq 0 ]]; then
    echo "PASS help-flags replay---help"
  else
    echo "FAIL help-flags replay---help returned $replay_help_status"
    failures=$((failures + 1))
  fi

  if [[ "$rec_help_status" -eq 0 ]]; then
    echo "PASS help-flags rec---help"
  else
    echo "FAIL help-flags rec---help returned $rec_help_status"
    failures=$((failures + 1))
  fi

  return "$failures"
}

run_compressed_roundtrip() {
  local tmp_dir="$1"
  local payload_file="$tmp_dir/comp-payload.txt"
  local ttyrec_file="$tmp_dir/comp-input.ttyrec"
  local lz_file="$tmp_dir/comp-input.ttyrec.lz"
  local replay_raw="$tmp_dir/comp-replay-raw.bin"
  local replay_lz="$tmp_dir/comp-replay-lz.bin"
  local search_raw="$tmp_dir/comp-search-raw.txt"
  local search_lz="$tmp_dir/comp-search-lz.txt"
  local info_raw="$tmp_dir/comp-info-raw.txt"
  local info_lz="$tmp_dir/comp-info-lz.txt"
  local dump_raw="$tmp_dir/comp-dump-raw.txt"
  local dump_lz="$tmp_dir/comp-dump-lz.txt"
  local raw_dump_raw="$tmp_dir/comp-raw-dump-raw.bin"
  local raw_dump_lz="$tmp_dir/comp-raw-dump-lz.bin"

  printf 'hello needle world\n' > "$payload_file"
  make_single_frame_ttyrec "$payload_file" "$ttyrec_file" 17 420

  lzip -k "$ttyrec_file"

  "$IRIS_REPLAY_BIN" replay "$ttyrec_file" > "$replay_raw"
  "$IRIS_REPLAY_BIN" search "$ttyrec_file" "needle" > "$search_raw"
  "$IRIS_REPLAY_BIN" info "$ttyrec_file" > "$info_raw"
  "$IRIS_REPLAY_BIN" dump "$ttyrec_file" > "$dump_raw"
  "$IRIS_REPLAY_BIN" raw-dump "$ttyrec_file" 0 > "$raw_dump_raw"

  "$IRIS_REPLAY_BIN" replay "$lz_file" > "$replay_lz"
  "$IRIS_REPLAY_BIN" search "$lz_file" "needle" > "$search_lz"
  "$IRIS_REPLAY_BIN" info "$lz_file" > "$info_lz"
  "$IRIS_REPLAY_BIN" dump "$lz_file" > "$dump_lz"
  "$IRIS_REPLAY_BIN" raw-dump "$lz_file" 0 > "$raw_dump_lz"

  if ! cmp -s "$replay_raw" "$replay_lz"; then
    echo "FAIL compressed-roundtrip replay output differs"
    return 1
  fi

  if ! cmp -s "$search_raw" "$search_lz"; then
    echo "FAIL compressed-roundtrip search output differs"
    return 1
  fi

  if ! cmp -s "$info_raw" "$info_lz"; then
    echo "FAIL compressed-roundtrip info output differs"
    return 1
  fi

  if ! cmp -s "$dump_raw" "$dump_lz"; then
    echo "FAIL compressed-roundtrip dump output differs"
    return 1
  fi

  if ! cmp -s "$raw_dump_raw" "$raw_dump_lz"; then
    echo "FAIL compressed-roundtrip raw-dump output differs"
    return 1
  fi

  echo "PASS compressed-roundtrip"
  return 0
}

run_compression_mismatch() {
  local tmp_dir="$1"
  local payload_file="$tmp_dir/mismatch-payload.txt"
  local ttyrec_file="$tmp_dir/mismatch-input.ttyrec"
  local fake_lz="$tmp_dir/mismatch-input.lz"
  local output_file="$tmp_dir/mismatch-output.txt"
  local replay_output="$tmp_dir/mismatch-replay.bin"
  local raw_replay="$tmp_dir/mismatch-raw-replay.bin"

  printf 'mismatch test data\n' > "$payload_file"
  make_single_frame_ttyrec "$payload_file" "$ttyrec_file" 17 420

  cp "$ttyrec_file" "$fake_lz"

  set +e
  "$IRIS_REPLAY_BIN" replay "$fake_lz" > "$output_file" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "FAIL compression-mismatch should have failed but succeeded"
    return 1
  fi

  if ! grep -q "cowardly refuse" "$output_file"; then
    echo "FAIL compression-mismatch missing 'cowardly refuse' message"
    cat "$output_file"
    return 1
  fi

  set +e
  "$IRIS_REPLAY_BIN" --force-decompression=none replay "$fake_lz" > "$replay_output" 2>&1
  status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    echo "FAIL compression-mismatch --force-decompression=none should succeed"
    cat "$replay_output"
    return 1
  fi

  "$IRIS_REPLAY_BIN" replay "$ttyrec_file" > "$raw_replay"

  if ! cmp -s "$raw_replay" "$replay_output"; then
    echo "FAIL compression-mismatch --force-decompression=none output differs"
    return 1
  fi

  echo "PASS compression-mismatch"
  return 0
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
      run_search_zero_matches "$tmp_dir" || failures=$((failures + 1))
      run_info_output "$tmp_dir" || failures=$((failures + 1))
      run_dump_output "$tmp_dir" || failures=$((failures + 1))
      run_raw_dump_output "$tmp_dir" || failures=$((failures + 1))
      run_empty_file "$tmp_dir" || failures=$((failures + 1))
      run_raw_byte_roundtrip "$tmp_dir" || failures=$((failures + 1))
      run_exit_codes "$tmp_dir" || failures=$((failures + 1))
      run_help_flags || failures=$((failures + 1))
      run_compressed_roundtrip "$tmp_dir" || failures=$((failures + 1))
      run_compression_mismatch "$tmp_dir" || failures=$((failures + 1))
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
    "search-zero-matches")
      run_search_zero_matches "$tmp_dir" || failures=$((failures + 1))
      ;;
    "info-output")
      run_info_output "$tmp_dir" || failures=$((failures + 1))
      ;;
    "dump-output")
      run_dump_output "$tmp_dir" || failures=$((failures + 1))
      ;;
    "raw-dump-output")
      run_raw_dump_output "$tmp_dir" || failures=$((failures + 1))
      ;;
    "empty-file")
      run_empty_file "$tmp_dir" || failures=$((failures + 1))
      ;;
    "raw-byte-roundtrip")
      run_raw_byte_roundtrip "$tmp_dir" || failures=$((failures + 1))
      ;;
    "exit-codes")
      run_exit_codes "$tmp_dir" || failures=$((failures + 1))
      ;;
    "help-flags")
      run_help_flags || failures=$((failures + 1))
      ;;
    "compressed-roundtrip")
      run_compressed_roundtrip "$tmp_dir" || failures=$((failures + 1))
      ;;
    "compression-mismatch")
      run_compression_mismatch "$tmp_dir" || failures=$((failures + 1))
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
