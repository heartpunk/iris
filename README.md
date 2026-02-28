# Iris

Terminal session recording and tmux dispatch tools in Idris 2, working towards becoming a formally-specified terminal multiplexer. Currently stringly typed.

## Packages

- **iris-core** — session, window, pane types and abstract backend interface
- **iris-tmux** — tmux dispatch backend
- **iris-rec** — typed terminal recording (ttyrec format)
- **iris-replay** — read, replay, search, and dump ttyrec recordings

## Testing

Tests are organized into tiers by scope and duration:

| Tier | Seeds | Budget | Purpose |
|------|-------|--------|---------|
| 1 | 10 | <1s | Fast feedback during development |
| 2 | 50 | <10s | Pre-commit verification |
| 3 | 200 | <60s | CI / thorough check |
| 4 | 1000 | — | Full sweep against private recording corpus |

```sh
tests/run-tier.sh --tier 1
tests/cli-regressions.sh
```

Coverage includes:

- **Property-based tests** — roundtrip parse/encode, frame ordering, binary transparency, size laws
- **Unit tests** — boundary values, error cases, timestamp formatting
- **Integration tests** — real ttyrec file parsing, CLI subcommand output verification
- **CLI regression tests** — byte safety, timestamp correctness, search output, exit codes

## Building

Requires [Idris 2](https://idris2.readthedocs.io/). A Nix dev shell is provided:

```sh
nix develop
```

## License

GPL-3.0-or-later
