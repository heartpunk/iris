# Iris — Agent Instructions

## What This Is

**Iris** is a formally-specified terminal multiplexer written in Idris 2. Part of the **preternatural suite** — a collection of tools built with dependent types for provably correct behavior.

The name: Iris was the messenger goddess who carried between realms. Also close to Idris. Also the aperture of the eye.

## Architecture

Iris uses a **swappable backend** design. `iris-core` defines the abstract interface; backends implement it. This enables:

1. **Phase 1 (now):** `iris-tmux` backend — dispatches to real tmux. Gives us observability and a working dev environment immediately.
2. **Phase 2 (later):** `iris-native` backend — pure Idris implementation replacing tmux. Built *using* Phase 1 as the dev environment.
3. **Testing:** ttyrec recordings from Phase 1 are the test oracle for Phase 2. Feature parity = same outputs for same inputs.

It's self-hosting: the wrapper tests its own replacement.

## Package Structure

```
iris-core/    — Session/Window/Pane types + abstract Backend interface
iris-tmux/    — Phase 1: dispatches to tmux CLI
iris-rec/     — Typed recording writer (ttyrec format)
iris-replay/  — Read, replay, search, dump ttyrec recordings
iris-iterm/   — iTerm2 DCS control sequence layer
iris-native/  — Phase 2: native Idris implementation (stub)
tests/        — Unit, property, integration, CLI regression tests
```

## Core Types (iris-core)

The key insight: dependent types let us encode terminal layout invariants in the type system — panes tile exactly, no overlap, fill the window.

```idris
-- A Session contains named Windows (existentially quantified dimensions)
record Session where
  constructor MkSession
  name    : String
  windows : List (w : Nat ** h : Nat ** Window w h)

-- A Window has a Layout of statically known dimensions
record Window (width : Nat) (height : Nat) where
  constructor MkWindow
  name   : String
  layout : Layout width height

-- Layout encodes tiling constraints dependently
data Layout : (width : Nat) -> (height : Nat) -> Type where
  Single : Pane w h -> Layout w h
  HSplit : Layout w h1 -> Layout w h2 -> Layout w (h1 + h2)
  VSplit : Layout w1 h -> Layout w2 h -> Layout (w1 + w2) h

-- Abstract backend interface
interface Backend b where
  newSession   : b -> String -> IO (Either IrisError Session)
  newWindow    : b -> Session -> String -> (w : Nat) -> (h : Nat)
                -> IO (Either IrisError (Window w h))
  splitPane    : b -> Session -> String -> Direction
                -> IO (Either IrisError Session)
  capturePane  : b -> Nat -> IO (Either IrisError String)
  sendKeys     : b -> Nat -> String -> IO (Either IrisError ())
  listSessions : b -> IO (Either IrisError (List Session))
```

## iris-tmux Dispatch

The `iris-tmux` backend is a thin, boring dispatch layer. 17 wrappers covering session management, window/pane operations, querying, and content capture. Currently stringly typed — not yet wired through `iris-core` types.

## iTerm Integration

iTerm2's tmux integration uses DCS (Device Control String) sequences. Iris implements this so sessions appear native in iTerm. Package declared, not yet implemented.

## Recording (iris-rec / iris-replay)

`iris-rec` captures stdin as ttyrec frames. `iris-replay` reads, replays, searches, and inspects recordings with transparent decompression (lzip, gzip, zstd, xz, bzip2). Both are working.

## Development Notes

- **Language:** Idris 2 (Chez Scheme backend)
- **VCS:** `jj commit` (not `git commit`) — colocated jj repo
- **Build:** Nix dev shell provides idris2 + tools. See `docs/building.md`.
- The iris-tmux backend should be a thin, boring dispatch layer. No cleverness there.
- All cleverness goes in iris-core types.

## Testing

Three test suites:

1. **Unit/property tests** (`tests/tests.ipkg`) — frame encoding roundtrips, U32 bounds, binary transparency, LCG-based property tests
2. **Tiered integration** (`tests/run-tier.sh`) — cross-validates against OVH ttyrec tools on real recordings
3. **CLI regressions** (`tests/cli-regressions.sh`) — byte safety, timestamps, search output, exit codes, compression

iris-tmux dispatch tests (`tests/iris-tmux-tests.ipkg`):
- **Unit tests** use a fake tmux script — safe to run anywhere
- **Integration tests** run inside a NixOS QEMU VM with sentinel isolation — never touch real tmux

See `tests/README.md` and `docs/` for details.

## Current Status

- `iris-core` — types defined, Backend interface specified
- `iris-tmux` — 17 dispatch wrappers implemented and tested
- `iris-rec` — stdin capture working
- `iris-replay` — replay, search, info, dump, raw-dump working
- `iris-iterm` — package declared, not yet implemented
- `iris-native` — stub, awaiting Phase 2

## Relation to Preternatural Suite

Iris is one piece. The suite includes tools sharing the philosophy: dependent types, formally specified behavior, self-hosting where possible.
