# Iris — Agent Instructions

## What This Is

**Iris** is a formally-specified terminal multiplexer written in Idris 2. Part of the **preternatural suite** — a collection of tools built with dependent types for provably correct behavior.

The name: Iris was the messenger goddess who carried between realms. Also close to Idris. Also the aperture of the eye.

## Architecture

Iris uses a **swappable backend** design. `iris-core` defines the abstract interface; backends implement it. This enables:

1. **Phase 1 (now):** `iris-tmux` backend — dispatches to real tmux + ttyrec. Gives us observability and a working dev environment immediately.
2. **Phase 2 (later):** `iris-native` backend — pure Idris implementation replacing tmux. Built *using* Phase 1 as the dev environment.
3. **Testing:** ttyrec recordings from Phase 1 are the test oracle for Phase 2. Feature parity = same outputs for same inputs.

It's self-hosting: the wrapper tests its own replacement.

## Package Structure

```
iris-core/    — Session/Window/Pane types + abstract Backend interface
iris-tmux/    — Phase 1: dispatches to tmux + ttyrec
iris-iterm/   — iTerm2 DCS control sequence layer
iris-rec/     — Typed recording/playback (ttyrec successor)
iris-native/  — Phase 2: native Idris implementation (stub for now)
tests/        — ttyrec-based parity tests
```

## Core Types (iris-core)

The key insight: dependent types let us encode terminal layout invariants in the type system — panes tile exactly, no overlap, fill the window.

```idris
-- A Session contains named Windows
record Session where
  constructor MkSession
  name    : String
  windows : List Window

-- A Window has a Layout of Panes
record Window where
  constructor MkWindow
  name   : String
  layout : Layout

-- Layout encodes tiling constraints dependently
-- Panes tile exactly: no overlap, full coverage
data Layout : (width : Nat) -> (height : Nat) -> Type where
  Single : (p : Pane w h) -> Layout w h
  HSplit : Layout w h1 -> Layout w h2 -> Layout w (h1 + h2)
  VSplit : Layout w1 h -> Layout w2 h -> Layout (w1 + w2) h

-- Abstract backend interface — both iris-tmux and iris-native implement this
interface Backend b where
  newSession  : b -> String -> IO (Either Error Session)
  newWindow   : b -> Session -> String -> IO (Either Error Window)
  splitPane   : b -> Window -> Direction -> IO (Either Error Window)
  capturePane : b -> Pane -> IO (Either Error String)
  sendKeys    : b -> Pane -> String -> IO (Either Error ())
```

## iTerm Integration

iTerm2's tmux integration uses DCS (Device Control String) sequences. Iris implements this so sessions appear native in iTerm. The dependent types are great here — control sequences have complex invariants that the type system enforces.

## Recording (iris-rec)

Typed terminal event stream replacing raw ttyrec format. Each event is typed: write, resize, focus, etc. Enables:
- Structured playback with seeking
- Diff between recordings (for parity testing)
- Metadata annotations

## Development Notes

- Language: Idris 2
- VCS: jj (colocated with git)
- Build: pack (Idris package manager)
- Phase 1 first — get something working, then replace the backend
- The iris-tmux backend should be a thin, boring dispatch layer. No cleverness there.
- All cleverness goes in iris-core types.

## Tooling

- Language: Idris 2
- VCS: `jj commit` (not `git commit`) — colocated jj repo
- Build: pack (Idris 2 package manager)

## Current Status

Scaffolded. Not yet implemented. Start with:
1. `iris-core` — get the types right first
2. `iris-tmux` — thin dispatch over `tmux` CLI + ttyrec
3. Wire them together with a basic CLI

## Relation to Preternatural Suite

Iris is one piece. The suite includes tools sharing the philosophy: dependent types, formally specified behavior, self-hosting where possible. More TBD.
