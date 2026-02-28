# iris-tmux

Phase 1 backend: a thin dispatch layer over the `tmux` CLI.

## Design

Every function shells out to `tmux` via `popen`, captures stdout, and returns `Either String result`. Arguments are single-quote escaped to prevent injection. The dispatch layer is intentionally boring — it's just arg construction and process invocation.

Two return patterns:

- **`Either String String`** — commands that produce output (list-sessions, capture-pane, etc.)
- **`Either String ()`** — commands that only need success/failure (new-session, send-keys, etc.)

One exception: `tmuxHasSession` returns `IO Bool` (success = True, any failure = False).

## API Reference

### Core

```idris
runTmux : List String -> IO (Either String String)
```

Low-level dispatch. Builds `tmux arg1 arg2 ...` with single-quoted escaping, runs via `popen`, returns stdout on exit 0 or error message on non-zero exit.

### Session Management

```idris
tmuxNewSession    : (name : String) -> IO (Either String ())
tmuxAttachSession : (name : String) -> IO (Either String ())
tmuxKillSession   : (name : String) -> IO (Either String ())
tmuxHasSession    : (name : String) -> IO Bool
tmuxListSessions  : IO (Either String String)
tmuxKillServer    : IO (Either String ())
```

### Window and Pane Management

```idris
tmuxNewWindow    : (session : String) -> (name : String) -> IO (Either String ())
tmuxSplitWindow  : (target : String) -> IO (Either String String)  -- returns pane ID
tmuxSelectPane   : (target : String) -> IO (Either String ())
tmuxSelectLayout : (target : String) -> (layout : String) -> IO (Either String ())
```

### Querying

```idris
tmuxListWindows    : (target : String) -> IO (Either String String)
tmuxListPanes      : (target : String) -> IO (Either String String)
tmuxListClients    : IO (Either String String)
tmuxDisplayMessage : (target : String) -> (format : String) -> IO (Either String String)
```

### Content

```idris
data CaptureDepth = VisibleOnly | Lines Int | FullHistory

tmuxCapturePane : (target : String) -> (depth : CaptureDepth) -> IO (Either String String)
tmuxSendKeys    : (target : String) -> (keys : String) -> IO (Either String ())
```

`CaptureDepth` controls how much scrollback to capture:

- `VisibleOnly` — just the visible pane content
- `Lines n` — last `n` lines of scrollback (passes `-S -n`)
- `FullHistory` — entire scrollback buffer (passes `-S -`)

## tmux Subcommand Mapping

| Wrapper | tmux subcommand | Key flags |
|---------|-----------------|-----------|
| `tmuxNewSession` | `new-session` | `-d -s <name>` |
| `tmuxAttachSession` | `attach-session` | `-t <name>` |
| `tmuxKillSession` | `kill-session` | `-t <name>` |
| `tmuxHasSession` | `has-session` | `-t <name>` |
| `tmuxListSessions` | `list-sessions` | |
| `tmuxKillServer` | `kill-server` | |
| `tmuxNewWindow` | `new-window` | `-t <session> -n <name>` |
| `tmuxSplitWindow` | `split-window` | `-t <target> -P -F #{pane_id}` |
| `tmuxSelectPane` | `select-pane` | `-t <target>` |
| `tmuxSelectLayout` | `select-layout` | `-t <target> <layout>` |
| `tmuxListWindows` | `list-windows` | `-t <target>` |
| `tmuxListPanes` | `list-panes` | `-t <target>` |
| `tmuxListClients` | `list-clients` | |
| `tmuxDisplayMessage` | `display-message` | `-t <target> -p <format>` |
| `tmuxCapturePane` | `capture-pane` | `-t <target> -p [-S ...]` |
| `tmuxSendKeys` | `send-keys` | `-t <target> <keys>` |

## Command Priority

Wrappers were implemented based on real usage frequency. See [tmux-command-frequency.md](tmux-command-frequency.md) for the data — mined from shell history (atuin) and ttyrec recordings of agent sessions.

## Testing

Unit tests use a fake `tmux` script that echoes its arguments, verifying correct dispatch without running real tmux. Integration tests run inside a NixOS QEMU VM with sentinel-based isolation.

```sh
# Unit tests (safe anywhere)
./tests/build/exec/iris-tmux-tests unit

# Integration tests (Linux, via nix)
nix build .#checks.x86_64-linux.integration
```

See [tests/README.md](../tests/README.md) for full details.
