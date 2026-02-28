#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tests/run-tier.sh [--tier N]

Tier config:
  1 -> 5 files,   N=10 property rounds,   budget 1s (default, runs always)
  2 -> 20 files,  N=50 property rounds,   budget 10s (on commit)
  3 -> 100 files, N=200 property rounds,  budget 60s (on demand)
  4 -> all files in ~/.ttyrec, N=1000 property rounds (occasional)
EOF
}

tier="1"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      tier="${2:-}"
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

case "$tier" in
  1)
    file_target=5
    property_rounds=10
    budget_seconds=1
    ;;
  2)
    file_target=20
    property_rounds=50
    budget_seconds=10
    ;;
  3)
    file_target=100
    property_rounds=200
    budget_seconds=60
    ;;
  4)
    file_target=0
    property_rounds=1000
    budget_seconds=0
    ;;
  *)
    echo "unsupported tier: $tier" >&2
    usage
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IRIS_REPLAY_BIN="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"
IRIS_TESTS_BIN="${IRIS_TESTS_BIN:-$ROOT_DIR/tests/build/exec/iris-tests}"

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing required command: $cmd" >&2
    exit 1
  fi
}

require_cmd lzip
require_cmd ttyplay
require_cmd ttytime
require_cmd ipbt-dump
require_cmd awk
require_cmd find

if [[ ! -x "$IRIS_REPLAY_BIN" ]]; then
  echo "missing iris-replay binary at $IRIS_REPLAY_BIN" >&2
  echo "build first: idris2 --build iris-replay/iris-replay.ipkg" >&2
  exit 1
fi

if [[ ! -x "$IRIS_TESTS_BIN" ]]; then
  echo "missing iris-tests binary at $IRIS_TESTS_BIN" >&2
  echo "build first: idris2 --build tests/tests.ipkg" >&2
  exit 1
fi

archives=()
while IFS= read -r archive; do
  base_name="$(basename "$archive")"
  if [[ "$base_name" =~ ^[0-9a-fA-F-]+\.lz$ ]]; then
    archives+=("$archive")
  fi
done < <(
  find "$HOME/.ttyrec" -maxdepth 1 -type f -name '*.lz' | while IFS= read -r path; do
    printf '%s\t%s\n' "$(wc -c < "$path")" "$path"
  done | sort -n | awk -F'\t' '{ print $2 }'
)
if [[ ${#archives[@]} -eq 0 ]]; then
  echo "no .lz recordings found in $HOME/.ttyrec" >&2
  exit 1
fi

if [[ "$tier" != "4" ]]; then
  if (( ${#archives[@]} < file_target )); then
    echo "tier $tier requires $file_target files; found ${#archives[@]}" >&2
    exit 1
  fi
  archives=( "${archives[@]:0:file_target}" )
fi

if [[ "$tier" == "4" && ${#archives[@]} -ne 1550 ]]; then
  echo "tier 4 note: expected 1550 files, found ${#archives[@]}" >&2
fi

# Dedicated temp dir — isolates our files from other /tmp users
TIER_TMPDIR="$(mktemp -d "/tmp/iris-tier-${tier}.XXXXXX")"

# Layer 1: trap cleans up on any exit (success, failure, signal)
cleanup() {
  rm -rf "$TIER_TMPDIR"
}
trap cleanup EXIT

# Layer 2: clean up stale runs from previous invocations
for stale in /tmp/iris-tier-*.??????; do
  [[ -d "$stale" ]] && [[ "$stale" != "$TIER_TMPDIR" ]] && rm -rf "$stale"
done

echo "tier=$tier files=${#archives[@]} property_rounds=$property_rounds budget=${budget_seconds}s"

failures=0
start_seconds=$SECONDS

for archive in "${archives[@]}"; do
  base="$(basename "$archive" .lz)"
  tmp_file="${TIER_TMPDIR}/${base}.ttyrec"

  if ! lzip -d -c "$archive" > "$tmp_file"; then
    echo "FAIL parse/decompress $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  info_out="$("$IRIS_REPLAY_BIN" info "$tmp_file" 2>&1 || true)"
  frames="$(printf '%s\n' "$info_out" | awk '/^frames: [0-9]+$/ { print $2; exit }')"
  if [[ -z "${frames:-}" ]]; then
    if [[ "$tier" == "4" ]] && printf '%s\n' "$info_out" | grep -q "truncated ttyrec payload"; then
      echo "SKIP truncated $archive :: $info_out"
      rm -f "$tmp_file"
      continue
    fi
    echo "FAIL parse/info $archive :: $info_out"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if (( frames <= 0 )); then
    echo "FAIL parse/non-empty $archive :: frames=$frames"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! ttyplay -n "$tmp_file" >/dev/null 2>&1; then
    echo "FAIL ovh/ttyplay $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! ttytime "$tmp_file" >/dev/null 2>&1; then
    echo "FAIL ovh/ttytime $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  ipbt_count="$(ipbt-dump -T -H "$tmp_file" 2>/dev/null | awk -F: '/:offset / { c += 1 } END { print c + 0 }')"
  if [[ -z "${ipbt_count:-}" ]]; then
    echo "FAIL ipbt/empty $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if (( ipbt_count != frames )); then
    echo "FAIL cross-validate $archive :: iris=$frames ipbt=$ipbt_count"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! "$IRIS_REPLAY_BIN" replay "$tmp_file" >/dev/null 2>&1; then
    echo "FAIL iris/replay $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! "$IRIS_REPLAY_BIN" dump "$tmp_file" >/dev/null 2>&1; then
    echo "FAIL iris/dump $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! "$IRIS_REPLAY_BIN" raw-dump "$tmp_file" 0 >/dev/null 2>&1; then
    echo "FAIL iris/raw-dump $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  if ! "$IRIS_REPLAY_BIN" search "$tmp_file" "a" >/dev/null 2>&1; then
    echo "FAIL iris/search $archive"
    rm -f "$tmp_file"
    failures=$((failures + 1))
    continue
  fi

  # Layer 3: delete each file immediately after processing
  rm -f "$tmp_file"
done

if ! "$IRIS_TESTS_BIN" property-roundtrip "$property_rounds"; then
  echo "FAIL property/roundtrip-$property_rounds"
  failures=$((failures + 1))
fi

elapsed=$((SECONDS - start_seconds))
if (( budget_seconds > 0 && elapsed > budget_seconds )); then
  echo "FAIL budget tier=$tier :: elapsed=${elapsed}s budget=${budget_seconds}s"
  failures=$((failures + 1))
fi

echo "summary: tier=$tier elapsed=${elapsed}s failures=$failures"
if (( failures == 0 )); then
  echo "PASS tier=$tier"
else
  exit 1
fi
