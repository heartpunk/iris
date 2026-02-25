# Iris Tests

## Parity Testing Strategy

ttyrec recordings from `iris-tmux` (Phase 1) are the test oracle for `iris-native` (Phase 2).

Feature parity = same outputs for same inputs, verified via `iris-rec diff`.

## Test Structure

- `phase1/` — recordings captured via iris-tmux backend
- `parity/`  — parity tests: run same scenario against iris-native, diff with phase1 recording
- `unit/`    — unit tests for iris-core types

## Running Tests

TBD — depends on pack test setup.
