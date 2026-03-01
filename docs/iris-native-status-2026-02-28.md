# iris-native status — 2026-02-28T13:25:00-08:00

## What the 28-commit plan actually delivered

The plan was titled "Cross-backend test infrastructure + iris-native usability" — it delivered **test infrastructure** and **foundational plumbing**, not a working terminal multiplexer. All 28 commits are done and pushed to `cross-backend-redo` / `tmux-iris`.

## What works

### Test infrastructure (commits 1-16)
- `tests/recording-cross-product.sh` — 4 tests, all pass
- `tests/cross-backend.sh` — 5 scenarios × 2 backends, full cross-product validation (20/20)
- Baseline management with three-way comparison (PASS/BASELINE/REGRESSION)

### Single-pane raw passthrough (commits 17-20)
- Raw byte pump (`stdinToFd`/`fdToStdout`) bypasses Idris String/lines corruption
- iris-native launches, forks $SHELL, passes bytes through
- You can type commands and see output — it "works" as a dumb terminal passthrough

### Signal handling (commits 21-24)
- SIGWINCH → PTY resize
- SIGCHLD → waitpidNohang → mark panes closed → exit when all closed
- SIGTERM/SIGINT → graceful shutdown

### Lifecycle (commits 25-28)
- Alt screen buffer (enter/exit)
- FIFO control pipe (`echo quit > /tmp/iris-$PID.ctl`)
- Control pipe polled in both single-pane and multi-pane loops

## What's still broken / missing

### Native baselines still don't match tmux (all 5 scenarios = BASELINE)
Three concrete issues visible in the hex diffs:

1. **PS1 not applied** — native shows `bash-3.2$`, tmux shows `$ `. The Rust `iris_forkpty` does `execvp($SHELL)` with no `--rcfile`. The cross-backend test sets `PS1='$ '` in the env, but bash ignores env PS1 when reading ~/.bash_profile. Fix: pass `--rcfile` to the shell exec, or use `BASH_ENV`.

2. **`\x1b[?1034h` escape spam** — bash 3.2 emits "set meta key sends ESC" on startup. tmux strips this; iris-native passes it through. Fix: either strip it in the passthrough, or set `TERM=dumb` during shell init, or use `--norc` + explicit rcfile.

3. **Alt screen escapes in recording** — `\x1b[?1049h`, `\x1b[2J`, `\x1b[?1049l`, `\x1b[?25h` appear at start/end of native recording because ttyrec records everything iris-native writes. tmux baselines don't have this because ttyrec records inside the tmux pane (after tmux's own processing). Fix: either don't enter alt screen in single-pane mode, or strip iris-native's framing from the recording in the test.

### Multi-pane mux is not functional
- `SplitH`/`SplitV` commands are parsed but do nothing (`pure ()`)
- Multi-pane loop uses `String`/`lines`/`appendOutput`/`renderDirtyPanes` — the old broken path that destroys escape sequences
- No pane creation (no second `forkPty` call)
- No layout management (no `flattenLayout` integration)
- `Render.idr` has `renderPane`/`renderBorders`/`renderDirtyPanes` but they do naive line-buffer rendering, not VT100 screen emulation

### No keybind/prefix handling
- No way to switch panes, split, or do anything mux-like from the keyboard
- No prefix key (like tmux's Ctrl-b)
- stdin goes straight to the active pane's PTY

### No session persistence / detach-reattach
- No socket/server architecture
- No detach/reattach (the whole point of a terminal multiplexer)
- Single process, dies when you close the terminal

### No VT100/terminal emulation
- The multi-pane renderer needs to parse VT100 escape sequences to know where the cursor is, what colors are active, etc.
- Current `appendOutput` just splits on `\n` and dumps raw lines — unusable for anything with color or cursor movement
- This is the single hardest piece and it's completely unstarted

## Summary

iris-native is a **working single-pane terminal passthrough** with proper signal handling and a control pipe. It is **not** a terminal multiplexer. The gap between "passthrough" and "multiplexer" is enormous — it needs VT100 emulation, layout management, pane creation, keybind handling, and session persistence. The test infrastructure is solid and ready to validate progress.
