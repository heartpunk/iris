#!/usr/bin/env bash
set -euo pipefail

# tmux-commands.sh — Extract tmux command invocations from ttyrec recordings
# into a SQLite database for frequency analysis.
#
# Usage:
#   ./scripts/tmux-commands.sh [--db PATH] [--days N]        # extract mode
#   ./scripts/tmux-commands.sh --query [--db PATH]           # query mode
#   ./scripts/tmux-commands.sh --help

DB="./tmux-commands.db"
DAYS=14
MODE=extract
TTYREC_DIR="$HOME/.ttyrec"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
IRIS_REPLAY="${IRIS_REPLAY_BIN:-$ROOT_DIR/iris-replay/build/exec/iris-replay}"

# --- Known tmux subcommands (for false-positive filtering) ---
KNOWN_SUBCOMMANDS=(
  attach-session bind-key break-pane capture-pane choose-buffer choose-client
  choose-tree clear-history clock-mode command-prompt confirm-before
  copy-mode customize-mode delete-buffer detach-client display-menu
  display-message display-panes display-popup find-window has-session
  if-shell join-pane kill-pane kill-server kill-session kill-window
  last-pane last-window link-window list-buffers list-clients list-commands
  list-keys list-panes list-sessions list-windows load-buffer lock-client
  lock-server lock-session menu move-pane move-window new-session new-window
  next-layout next-window paste-buffer pipe-pane previous-layout
  previous-window refresh-client rename-session rename-window resize-pane
  resize-window respawn-pane respawn-window rotate-window run-shell
  save-buffer select-layout select-pane select-window send-keys send-prefix
  server-access server-info set-buffer set-environment set-hook set-option
  set-window-option show-buffer show-environment show-hooks show-messages
  show-options show-window-options source-file split-window start-server
  suspend-client swap-pane swap-window switch-client unbind-key unlink-window
  wait-for
  # Short aliases
  attach a bind breakp capturep chooset clearhist clockmode
  confirm copymode deleteb detach displaym displayp findw
  has ifsh joinp killp killserver killsess killw lastp lastw
  linkw lsb lsc lscm lsk lsp ls lsw loadb lockc locks
  lockserver movep movew new neww nextl nextp pasteb pipep
  prevl prev refresh renamec renamew resizep resizew respawnp
  respawnw rotatew run saveb selectl selectp selectw send
  sendprefix setb setenv setw sete show showb showenv showmsgs
  showw source splitw start suspendc swapp swapw switchc unbind
  unlinkw wait
)

usage() {
  cat <<'EOF'
Usage: tmux-commands.sh [OPTIONS]

Extract tmux commands from ttyrec recordings into a SQLite database.

Options:
  --db PATH     Database path (default: ./tmux-commands.db)
  --days N      Look back N days (default: 14)
  --query       Run frequency queries instead of extracting
  --help        Show this help
EOF
  exit 0
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)    DB="$2"; shift 2 ;;
    --days)  DAYS="$2"; shift 2 ;;
    --query) MODE=query; shift ;;
    --help)  usage ;;
    *)       echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Query mode ---
run_query() {
  if [[ ! -f "$DB" ]]; then
    echo "database not found: $DB" >&2
    exit 1
  fi

  echo "=== Subcommand frequency ==="
  sqlite3 -column -header "$DB" "
    SELECT subcommand, COUNT(*) AS count
    FROM tmux_commands
    GROUP BY subcommand
    ORDER BY count DESC;
  "

  echo ""
  echo "=== Full subcommand frequency (top 30) ==="
  sqlite3 -column -header "$DB" "
    SELECT full_subcommand, COUNT(*) AS count
    FROM tmux_commands
    GROUP BY full_subcommand
    ORDER BY count DESC
    LIMIT 30;
  "

  echo ""
  echo "=== Commands per file (top 20) ==="
  sqlite3 -column -header "$DB" "
    SELECT file, COUNT(*) AS count
    FROM tmux_commands
    GROUP BY file
    ORDER BY count DESC
    LIMIT 20;
  "

  echo ""
  echo "=== Summary ==="
  sqlite3 -column -header "$DB" "
    SELECT
      COUNT(DISTINCT subcommand)  AS unique_subcommands,
      COUNT(*)                    AS total_commands,
      COUNT(DISTINCT file)        AS files_with_tmux
    FROM tmux_commands;
  "
  exit 0
}

[[ "$MODE" == "query" ]] && run_query

# --- Extract mode ---

if [[ ! -x "$IRIS_REPLAY" ]]; then
  echo "iris-replay binary not found at $IRIS_REPLAY" >&2
  echo "build first: idris2 --build iris-replay/iris-replay.ipkg" >&2
  echo "or set IRIS_REPLAY_BIN=/path/to/iris-replay" >&2
  exit 1
fi

# Build subcommand lookup file (bash 3 compatible, avoids associative arrays)
SUBCMD_FILE="${TMPDIR:-/tmp}/tmux-commands-subcmds.$$"
TSV_BATCH_FILE="${TMPDIR:-/tmp}/tmux-commands-batch.$$.tsv"
trap 'rm -f "$SUBCMD_FILE" "$TSV_BATCH_FILE" "${TMPDIR:-/tmp}/tmux-commands-err.$$"' EXIT
printf '%s\n' "${KNOWN_SUBCOMMANDS[@]}" > "$SUBCMD_FILE"

is_known_subcmd() {
  grep -qFx "$1" "$SUBCMD_FILE"
}

# Initialize database
sqlite3 "$DB" "
  CREATE TABLE IF NOT EXISTS tmux_commands (
    file            TEXT    NOT NULL,
    frame_number    INTEGER NOT NULL,
    timestamp       TEXT    NOT NULL,
    full_command    TEXT    NOT NULL,
    subcommand      TEXT    NOT NULL,
    full_subcommand TEXT    NOT NULL,
    PRIMARY KEY (file, frame_number, full_command)
  );
  CREATE INDEX IF NOT EXISTS idx_subcommand ON tmux_commands(subcommand);
"

# Discover files
files=()
while IFS= read -r f; do
  base="$(basename "$f")"
  # Match UUID pattern: hex-hex-hex-hex-hex with optional .lz extension
  if [[ "$base" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(\.lz)?$ ]]; then
    files+=("$f")
  fi
done < <(find "$TTYREC_DIR" -maxdepth 1 -type f -mtime "-${DAYS}")

echo "Found ${#files[@]} ttyrec files from the last ${DAYS} days"

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files to process."
  exit 0
fi

total=${#files[@]}
processed=0
total_matches=0
failures=0

for file in "${files[@]}"; do
  processed=$((processed + 1))
  base="$(basename "$file")"
  file_matches=0

  # Clear batch file for this recording
  : > "$TSV_BATCH_FILE"

  # Dump frames, capturing stderr to detect failures
  dump_err="${TMPDIR:-/tmp}/tmux-commands-err.$$"
  while IFS= read -r line; do
    # Parse: frame=N ts=T len=L payload=P
    if [[ ! "$line" =~ ^frame=([0-9]+)\ ts=([^ ]+)\ len=[0-9]+\ payload=(.*)$ ]]; then
      continue
    fi
    frame_num="${BASH_REMATCH[1]}"
    ts="${BASH_REMATCH[2]}"
    payload="${BASH_REMATCH[3]}"

    # Replace ANSI escapes with spaces (preserves word boundaries from cursor positioning)
    payload="$(printf '%s' "$payload" | sed $'s/\x1b\\[[0-9;?]*[A-Za-z]/ /g')"
    # Replace literal \033 sequences with spaces
    payload="$(printf '%s' "$payload" | sed 's/\\033\[[0-9;?]*[A-Za-z]/ /g')"
    # Collapse multiple spaces
    payload="$(printf '%s' "$payload" | sed 's/  */ /g')"

    # Extract tmux commands from payload
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue

      # Parse subcommand: first word after "tmux" (skip flags)
      rest="${cmd#tmux }"
      # Skip leading flags like -u, -2, -L name, -S path, -f file, -CC
      while [[ "$rest" =~ ^-[A-Za-z0-9] ]]; do
        # Consume the flag token
        flag="${rest%% *}"
        rest="${rest#"$flag"}"
        rest="${rest# }"  # trim one space
        # If it was a single-char flag like -L, the next token might be its argument
        if [[ ${#flag} -eq 2 && -n "$rest" && ! "$rest" =~ ^-[A-Za-z] ]]; then
          arg="${rest%% *}"
          # Skip the argument if it doesn't look like a subcommand
          if ! is_known_subcmd "$arg"; then
            rest="${rest#"$arg"}"
            rest="${rest# }"
          fi
        fi
      done

      # Extract subcommand (first remaining word)
      subcmd="${rest%% *}"
      [[ -z "$subcmd" ]] && continue

      # Validate against known subcommands
      if ! is_known_subcmd "$subcmd"; then
        continue
      fi

      # full_subcommand = subcommand + remaining args
      full_sub="$rest"
      # Trim trailing whitespace
      full_sub="${full_sub%"${full_sub##*[^ ]}"}"

      # Write as tab-separated values (avoids SQL escaping issues)
      # Replace any tabs in values with spaces to avoid TSV corruption
      tsv_cmd="${cmd//$'\t'/ }"
      tsv_fullsub="${full_sub//$'\t'/ }"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$base" "$frame_num" "$ts" "$tsv_cmd" "$subcmd" "$tsv_fullsub" >> "$TSV_BATCH_FILE"

      file_matches=$((file_matches + 1))
    done < <(printf '%s' "$payload" | grep -oE '(^|[^a-zA-Z])tmux( +-[A-Za-z0-9]+)*( +[a-z][-a-z]*)( +-[A-Za-z]+ +[^ ]+| +-[A-Za-z]+| +[a-zA-Z][-a-zA-Z./~_]*)*' | sed 's/^[^t]*//' || true)

  done < <("$IRIS_REPLAY" dump "$file" 2>"$dump_err" | grep -i 'tmux' || true)

  # Count failures from iris-replay stderr
  if [[ -s "$dump_err" ]]; then
    failures=$((failures + 1))
  fi
  rm -f "$dump_err"

  # Batch import for this file via staging table (avoids SQL escaping issues)
  if [[ -s "$TSV_BATCH_FILE" ]]; then
    sqlite3 "$DB" <<EOSQL
CREATE TEMP TABLE staging (
  file TEXT, frame_number INTEGER, timestamp TEXT,
  full_command TEXT, subcommand TEXT, full_subcommand TEXT
);
.mode tabs
.import '$TSV_BATCH_FILE' staging
INSERT OR IGNORE INTO tmux_commands SELECT * FROM staging;
DROP TABLE staging;
EOSQL
  fi

  total_matches=$((total_matches + file_matches))
  printf '[%d/%d] %s — %d matches\n' "$processed" "$total" "$base" "$file_matches"
done

echo ""
echo "Done. ${total_matches} total tmux commands extracted from ${processed} files (${failures} failures)."
echo "Database: ${DB}"
