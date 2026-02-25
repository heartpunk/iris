#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDRIS2_PREFIX="${IDRIS2_PREFIX:-$ROOT_DIR/.idris2}"

if ! command -v tmux >/dev/null 2>&1; then
  echo "missing required command: tmux" >&2
  exit 1
fi

nix develop --no-write-lock-file -c env IDRIS2_PREFIX="$IDRIS2_PREFIX" idris2 --build "$ROOT_DIR/iris-tmux/iris-tmux.ipkg"
nix develop --no-write-lock-file -c env IDRIS2_PREFIX="$IDRIS2_PREFIX" idris2 --install "$ROOT_DIR/iris-tmux/iris-tmux.ipkg"

(
  cd "$ROOT_DIR/tests"
  nix develop --no-write-lock-file ..#default -c env IDRIS2_PREFIX="$IDRIS2_PREFIX" idris2 --build iris-tmux-tests.ipkg
)

"$ROOT_DIR/tests/build/exec/iris-tmux-tests"
