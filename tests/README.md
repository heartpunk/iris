# Iris Tests

Three test suites cover different aspects of correctness.

## 1. Unit and Property Tests (`tests/tests.ipkg`)

Built from `Tests/Main.idr`. Run with:

```sh
idris2 --build tests/tests.ipkg
./build/exec/iris-tests
```

### What's covered

**Unit tests** — deterministic, boundary-value checks:

- Fixed-frame encoding/decoding roundtrip
- Empty payload frames
- Max U32 field values (sec, usec, length at 2^32-1)
- Truncated header and payload detection
- Multi-frame sequences
- Timestamp formatting (`formatTimestampMicros`)

**Property-based tests** — LCG pseudo-random generation with configurable seeds:

- Frame count preservation through encode/decode
- U32 roundtrip (`encodeU32LE` then parse back)
- Frame ordering preservation
- Payload integrity (bytes survive roundtrip)
- Header field validation (sec, usec, length correct after roundtrip)
- Size laws (encoded byte count = sum of 12-byte headers + payload lengths)
- Concatenation laws (encoding list = concatenating individual encodings)
- Binary transparency (non-ASCII bytes, NUL, 0xFF survive roundtrip)
- Payload collection (`collectPayloads` = concatenation of all payloads)

Run with specific round counts:

```sh
./build/exec/iris-tests property-roundtrip 100
```

**Proofs** — compile-time verified:

- `frameAt` index correctness
- `parseNat` computation proofs (verified with `Refl`)

## 2. Tiered Integration Tests (`tests/run-tier.sh`)

Cross-validates iris-replay against real `.ttyrec.lz` recordings and external tools.

```sh
tests/run-tier.sh              # tier 1 (default)
tests/run-tier.sh --tier 2
tests/run-tier.sh --tier 3
tests/run-tier.sh --tier 4
```

| Tier | Files | Property Rounds | Budget | When |
|------|-------|-----------------|--------|------|
| 1 | 5 | 10 | <1s | Every run |
| 2 | 20 | 50 | <10s | Pre-commit |
| 3 | 100 | 200 | <60s | CI / thorough check |
| 4 | all (~1550) | 1000 | unlimited | Occasional full sweep |

Each tier runs the same checks per file:

1. Decompress `.lz` recording
2. `iris-replay info` — parse and count frames
3. `ttyplay -n` — OVH ttyrec tool validates format
4. `ttytime` — OVH ttyrec timestamp validation
5. `ipbt-dump -T -H` — frame count cross-validation
6. `iris-replay replay` — full playback
7. `iris-replay dump` — structured frame dump
8. `iris-replay raw-dump` — raw byte extraction
9. `iris-replay search` — content search

Recordings live in `~/.ttyrec/` as UUID-named `.lz` files.

## 3. CLI Regression Tests (`tests/cli-regressions.sh`)

Targeted regression tests for CLI behavior:

```sh
tests/cli-regressions.sh
tests/cli-regressions.sh --test <name>
```

| Test | What it checks |
|------|----------------|
| `replay-byte-safety` | Non-ASCII bytes and NUL survive replay |
| `record-byte-safety` | Non-ASCII bytes and NUL survive recording |
| `record-timestamps` | Recorded timestamps are non-zero |
| `search-output` | Frame index, timestamp, snippet in search results |
| `search-zero-matches` | Zero-match case outputs `matches: 0` only |
| `info-output` | Frame count, file size, timestamp range, duration |
| `dump-output` | Frame indices, timestamps, lengths, sanitized payloads |
| `raw-dump-output` | Correct frame selection, byte-exact output, OOB error |
| `empty-file` | All commands handle zero-frame files gracefully |
| `raw-byte-roundtrip` | stdin -> iris-rec -> iris-replay -> exact match |
| `exit-codes` | Non-zero exit on bad args and missing files |
| `help-flags` | `--help` exits zero for both tools |
| `compressed-roundtrip` | `.ttyrec` and `.ttyrec.lz` produce identical output |
| `compression-mismatch` | Extension/magic mismatch detected, `--force-decompression` overrides |

## 4. iris-tmux Dispatch Tests (`tests/iris-tmux-tests.ipkg`)

Built from `Tmux/Main.idr`. Two phases:

### Unit tests (fake tmux)

Use a fake `tmux` script at `fixtures/fake-tmux-bin/tmux` that echoes its arguments. Tests verify each wrapper dispatches the correct subcommand and arguments. Safe to run anywhere.

```sh
./build/exec/iris-tmux-tests unit
```

Covers all 17 dispatch wrappers: `list-sessions`, `list-clients`, `list-panes`, `display-message`, `list-windows`, `split-window`, `capture-pane` (3 depth variants), `new-session`, `new-window`, `send-keys`, `select-layout`, `attach-session`, `kill-server`, `kill-session`, `select-pane`, `has-session`.

### Integration tests (NixOS VM)

Run real tmux inside an isolated QEMU VM. A sentinel file (`/etc/iris-test-vm`) with a high-entropy token prevents accidental execution outside the VM.

```sh
# Run via nix (boots VM, runs tests, tears down)
nix build .#checks.x86_64-linux.integration
```

Covers multi-step flows: send-keys + capture-pane, has-session lifecycle, kill-session verification.

## Parity Testing Strategy

ttyrec recordings from `iris-tmux` (Phase 1) will become the test oracle for `iris-native` (Phase 2). Feature parity = same outputs for same inputs, verified via recording diffs.

Planned directories (not yet populated):

- `phase1/` — recordings captured via iris-tmux backend
- `parity/` — parity tests: run same scenario against iris-native, diff with phase1 recording

## Requirements

The Nix dev shell provides everything:

```sh
nix develop
```

External tools used by the test suites:

- `idris2` — builds test binaries
- `lzip` — decompresses `.lz` recordings
- `ttyplay`, `ttytime` — OVH ttyrec tools for cross-validation
- `ipbt-dump` — IPBT frame counting
- `tmux` — integration tests only (inside VM)
- Standard Unix: `xxd`, `wc`, `cmp`, `grep`, `mktemp`
