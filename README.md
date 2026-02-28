# Iris

A formally-specified terminal multiplexer written in Idris 2. Part of the **preternatural suite** — tools built with dependent types for provably correct behavior.

The name: Iris was the messenger goddess who carried between realms. Also close to Idris. Also the aperture of the eye.

## Architecture

Iris uses a **swappable backend** design. `iris-core` defines the abstract interface; backends implement it.

1. **Phase 1 (now):** `iris-tmux` — dispatches to real tmux. Gives us a working dev environment immediately.
2. **Phase 2 (later):** `iris-native` — pure Idris implementation replacing tmux, built *using* Phase 1 as the dev environment.
3. **Testing bridge:** ttyrec recordings from Phase 1 are the test oracle for Phase 2. Feature parity = same outputs for same inputs.

It's self-hosting: the wrapper tests its own replacement.

## Packages

```
iris-core/    Session/Window/Pane types + abstract Backend interface
iris-tmux/    Phase 1: dispatches to tmux CLI
iris-rec/     Typed terminal recording writer (ttyrec format)
iris-replay/  Read, replay, search, and dump ttyrec recordings
iris-iterm/   iTerm2 DCS control sequence layer
iris-native/  Phase 2: native Idris implementation (stub)
```

## The Key Idea

Dependent types encode terminal layout invariants in the type system — panes tile exactly, no overlap, fill the window:

```idris
data Layout : (width : Nat) -> (height : Nat) -> Type where
  Single : Pane w h -> Layout w h
  HSplit : Layout w h1 -> Layout w h2 -> Layout w (h1 + h2)
  VSplit : Layout w1 h -> Layout w2 h -> Layout (w1 + w2) h
```

An `HSplit` proves both halves share the same width. A `VSplit` proves both halves share the same height. The type system enforces that layouts tile perfectly — if your code compiles, your layout math is correct.

## Building

Requires [Idris 2](https://idris2.readthedocs.io/) 0.8.0+. A Nix dev shell is provided:

```sh
nix develop
```

Build individual packages:

```sh
idris2 --build iris-core/iris-core.ipkg
idris2 --build iris-tmux/iris-tmux.ipkg
idris2 --build iris-rec/iris-rec.ipkg
idris2 --build iris-replay/iris-replay.ipkg
```

Build and install (for dependent packages):

```sh
idris2 --install iris-core/iris-core.ipkg
```

## CLI Tools

### iris-rec

Capture stdin as a ttyrec recording:

```sh
iris-rec record output.ttyrec
```

### iris-replay

Read, replay, search, and inspect ttyrec recordings. Handles lzip, gzip, zstd, xz, and bzip2 compression transparently.

```sh
iris-replay replay recording.ttyrec       # replay to stdout
iris-replay search recording.ttyrec.lz "query"  # search frame content
iris-replay info recording.ttyrec         # frame count, file size, duration
iris-replay dump recording.ttyrec         # dump all frames with metadata
iris-replay raw-dump recording.ttyrec 0   # emit raw bytes of frame N
```

Override auto-detected compression:

```sh
iris-replay --force-decompression=none replay misnamed.lz
```

## Testing

Tests are split across three suites. See [tests/README.md](tests/README.md) for full details.

### Unit and property tests

```sh
idris2 --build tests/tests.ipkg
./tests/build/exec/iris-tests
```

Covers: frame roundtrip encoding, U32 bounds, timestamp formatting, parse error handling, binary transparency. Includes LCG-based property tests with configurable seeds.

### Tiered integration tests

Cross-validates against OVH ttyrec tools (`ttyplay`, `ttytime`) and IPBT:

```sh
tests/run-tier.sh              # tier 1: 5 files, 10 property rounds, <1s
tests/run-tier.sh --tier 2     # 20 files, 50 rounds, <10s
tests/run-tier.sh --tier 3     # 100 files, 200 rounds, <60s
tests/run-tier.sh --tier 4     # full corpus (~1550 files), 1000 rounds
```

### CLI regression tests

Byte safety, timestamp correctness, search output, exit codes, compression handling:

```sh
tests/cli-regressions.sh
tests/cli-regressions.sh --test replay-byte-safety
```

### iris-tmux dispatch tests

Unit tests use a fake tmux script (no real tmux needed). Integration tests run inside a NixOS VM with sentinel-based isolation:

```sh
# Build
idris2 --build iris-tmux/iris-tmux.ipkg
idris2 --install iris-tmux/iris-tmux.ipkg
cd tests && idris2 --build iris-tmux-tests.ipkg && cd ..

# Unit tests (safe to run anywhere)
./tests/build/exec/iris-tmux-tests unit

# Integration tests (NixOS VM only — requires nix on Linux)
nix build .#checks.x86_64-linux.integration
```

## Development

- **Language:** Idris 2 (Chez Scheme backend)
- **VCS:** jj (colocated with git) — use `jj commit`, not `git commit`
- **Build:** Nix dev shell provides idris2 + ttyrec tools
- **CI:** `nix flake check` runs integration tests in isolated QEMU VMs

## License

GPL-3.0-or-later. Copyright 2026 Sophie Smithburg.
