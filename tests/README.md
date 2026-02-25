# Iris Tests

## Parity Testing Strategy

ttyrec recordings from `iris-tmux` (Phase 1) are the test oracle for `iris-native` (Phase 2).

Feature parity = same outputs for same inputs, verified via `iris-rec diff`.

## Test Structure

- `phase1/` — recordings captured via iris-tmux backend
- `parity/`  — parity tests: run same scenario against iris-native, diff with phase1 recording
- `unit/`    — unit tests for iris-core types

## Running Tests

Build test binaries:

```sh
idris2 --build iris-core/iris-core.ipkg
idris2 --build iris-replay/iris-replay.ipkg
idris2 --build tests/tests.ipkg
```

Run tiered suites (default `--tier 1`):

```sh
tests/run-tier.sh
tests/run-tier.sh --tier 2
tests/run-tier.sh --tier 3
tests/run-tier.sh --tier 4
```

Tier matrix:

- Tier 1: 5 real `~/.ttyrec/*.lz` files, `N=10` property rounds, target under 1s
- Tier 2: 20 files, `N=50`, target under 10s
- Tier 3: 100 files, `N=200`, target under 60s
- Tier 4: all files (expected 1550), `N=1000`, occasional full sweep

Each tier runs the same shape:

- Real file parsing via `iris-replay info`
- Cross-validation with OVH ttyrec tools (`ttyplay`, `ttytime`)
- IPBT sanity + frame-count check (`ipbt-dump -T -H`)
- Property roundtrip checks from `tests/Tests/Main.idr`

## Iris-Rec Design Notes (Not Implemented)

- U32 bounds contract for writer inputs (`clamp`/`wrap`/`reject`) is TBD.
- Dedicated cross-tool verification suite against `ipbt-dump` output is tracked separately.
- Explicit determinism assertion (`encodeFrames fs` stable across repeated evaluation) is tracked separately.
