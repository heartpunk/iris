# tmux Command Frequency Data

Mined from two sources on 2026-02-28.

## Sources

- **atuin** — 31 manually-typed tmux commands (user's own shell history)
- **ttyrec recordings** — 28,141 tmux commands from agent sessions (programmatic usage)

## Already implemented in iris-tmux

| Subcommand | atuin | ttyrec |
|------------|-------|--------|
| `new-session` | 3 | 2,779 |
| `new-window` | 0 | 67 |
| `split-window` | 0 | 30 |
| `capture-pane` | 0 | 9,543 |
| `send-keys` | 7 | 12,770 |

## Priority 1 — atuin commands (user-typed)

| Subcommand | atuin | ttyrec |
|------------|-------|--------|
| `list-sessions` | 2 | 364 |
| `attach` | 8 | 885 |
| `kill-server` | 1 | 128 |
| `list-clients` | 1 | 36 |
| `select-layout` | 2 | 286 |

## Priority 2 — high-frequency programmatic

| Subcommand | atuin | ttyrec |
|------------|-------|--------|
| `list-panes` | 0 | 797 |
| `display-message` | 0 | 503 |
| `list-windows` | 0 | 247 |
| `kill-session` | 0 | 26 |
| `has-session` | 0 | 97 |
| `select-pane` | 0 | 101 |
