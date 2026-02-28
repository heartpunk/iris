# Building

## Prerequisites

- **Idris 2** 0.8.0+ (Chez Scheme backend)
- **Nix** (optional, but provides everything automatically)

## Nix Dev Shell

The easiest way to get started:

```sh
nix develop
```

This provides: `idris2`, `ovh-ttyrec` (`ttyplay`, `ttytime`), `ipbt`, `lzip`.

## Building Packages

Packages must be built in dependency order. `iris-core` has no dependencies beyond `base`; everything else depends on it.

```sh
# Core types (required by everything)
idris2 --build iris-core/iris-core.ipkg
idris2 --install iris-core/iris-core.ipkg

# Phase 1 backend (no core dependency yet — stringly typed)
idris2 --build iris-tmux/iris-tmux.ipkg

# Recording writer
idris2 --build iris-rec/iris-rec.ipkg

# Recording reader/player
idris2 --build iris-replay/iris-replay.ipkg
```

Executables land in `<package>/build/exec/`:

```
iris-rec/build/exec/iris-rec
iris-replay/build/exec/iris-replay
```

## Building Tests

### Main test suite

```sh
idris2 --install iris-core/iris-core.ipkg
idris2 --install iris-rec/iris-rec.ipkg
idris2 --install iris-replay/iris-replay.ipkg
idris2 --build tests/tests.ipkg
```

### iris-tmux tests

```sh
idris2 --build iris-tmux/iris-tmux.ipkg
idris2 --install iris-tmux/iris-tmux.ipkg
cd tests
idris2 --build iris-tmux-tests.ipkg
cd ..
```

## Nix Builds

Build the test package as a Nix derivation (any platform):

```sh
nix build .#iris-tmux-tests
```

Run integration tests in a NixOS VM (Linux only):

```sh
nix build .#checks.x86_64-linux.integration
```

Full flake check:

```sh
nix flake check
```

## Clean Rebuild

Build artifacts are in `build/` directories (gitignored). To start fresh:

```sh
rm -rf iris-core/build iris-tmux/build iris-rec/build iris-replay/build tests/build
```

## VCS

This project uses **jj** (Jujutsu) colocated with git:

```sh
jj commit -m "description"     # not git commit
jj git push                    # pushes to git remote
```
