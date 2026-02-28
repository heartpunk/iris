# Architecture

## Swappable Backend Design

Iris separates the abstract terminal model (`iris-core`) from its implementation. The `Backend` interface defines the operations any backend must support:

```idris
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

Two backends are planned:

### Phase 1: iris-tmux

A thin dispatch layer over the `tmux` CLI. Each wrapper function shells out to `tmux <subcommand>` with appropriate arguments. Intentionally boring — no cleverness here.

This gives us a working dev environment immediately. All cleverness goes in `iris-core` types.

### Phase 2: iris-native

A pure Idris implementation replacing tmux entirely. Built *using* Phase 1 as the dev environment. Not yet implemented — `iris-tmux` must reach feature parity first.

The testing bridge: ttyrec recordings from Phase 1 become the test oracle for Phase 2.

## Package Dependency Graph

```
iris-core  (no dependencies beyond base)
  |
  +-- iris-tmux     (core types not yet wired — dispatch is stringly typed)
  +-- iris-rec      (depends on Frame from core)
  +-- iris-replay   (depends on Frame from core)
  +-- iris-iterm    (depends on core types)
  +-- iris-native   (depends on core types — stub)
```

## Core Type System

### Layout Invariants

The `Layout` GADT encodes tiling constraints at the type level:

```idris
data Layout : (width : Nat) -> (height : Nat) -> Type where
  Single : Pane w h -> Layout w h
  HSplit : Layout w h1 -> Layout w h2 -> Layout w (h1 + h2)
  VSplit : Layout w1 h -> Layout w2 h -> Layout (w1 + w2) h
```

- `HSplit` stacks two layouts vertically. Both must share the same width `w`. Heights add.
- `VSplit` places two layouts side by side. Both must share the same height `h`. Widths add.
- `Single` fills the entire area with one pane.

This makes malformed layouts unrepresentable. If your layout code compiles, the panes tile exactly with no overlap and full coverage.

### Existentially Quantified Windows

Sessions contain windows with different dimensions:

```idris
record Session where
  constructor MkSession
  name    : String
  windows : List (w : Nat ** h : Nat ** Window w h)
```

The dependent pair `(w : Nat ** h : Nat ** Window w h)` lets each window have its own dimensions while still carrying the proof that its layout is correct for those dimensions.

### Error Types

```idris
data IrisError
  = SessionNotFound String
  | WindowNotFound String
  | PaneNotFound Nat
  | BackendError String
  | RecordingError String
  | ProtocolError String
```

## iTerm2 Integration

iTerm2's tmux integration uses DCS (Device Control String) sequences to make tmux sessions appear as native iTerm tabs/splits. The `iris-iterm` package implements this protocol layer. Dependent types enforce the control sequence invariants.

## Recording Format

Iris uses the [ttyrec](https://en.wikipedia.org/wiki/Ttyrec) format for terminal recordings. Each frame is:

```
[4 bytes: sec (u32 LE)] [4 bytes: usec (u32 LE)] [4 bytes: len (u32 LE)] [len bytes: payload]
```

`iris-rec` writes this format from stdin. `iris-replay` reads, replays, searches, and inspects it. Transparent decompression handles lzip, gzip, zstd, xz, and bzip2.

## Current Status

- `iris-core` — types defined, Backend interface specified
- `iris-tmux` — 17 dispatch wrappers implemented, fully tested
- `iris-rec` — stdin capture working
- `iris-replay` — replay, search, info, dump, raw-dump all working
- `iris-iterm` — package declared, modules listed, not yet implemented
- `iris-native` — stub

The dispatch layer (`iris-tmux`) is currently stringly typed — it doesn't yet wire through the `iris-core` types. That wiring is part of the path toward Phase 2.
