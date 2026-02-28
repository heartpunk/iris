# iris-replay

Read, replay, search, and inspect ttyrec terminal recordings.

## Commands

### replay

```sh
iris-replay replay <path>
```

Writes concatenated frame payloads to stdout. Uncompressed — all frames emitted back-to-back without timing delays. Byte-exact: non-ASCII bytes, NUL, and 0xFF survive the roundtrip.

### search

```sh
iris-replay search <path> <query>
```

Searches frame payloads for a substring. Output format:

```
matches: N
frame=0 ts=1234567890.000100 snippet=...matching content...
frame=5 ts=1234567891.000200 snippet=...more matches...
```

Snippets are sanitized (newlines, tabs, carriage returns replaced with spaces) and truncated to 80 characters.

### info

```sh
iris-replay info <path>
```

Output:

```
frames: 42
file-size: 12345
timestamp-range: 1234567890.000000..1234567892.500000
duration-us: 2500000
```

### dump

```sh
iris-replay dump <path>
```

One line per frame:

```
frame=0 ts=1234567890.000100 len=45 payload=sanitized content here
```

Payloads are sanitized (control chars replaced with spaces).

### raw-dump

```sh
iris-replay raw-dump <path> <frame-index>
```

Emits raw bytes of a single frame (0-indexed) to stdout. Non-zero exit if the index is out of bounds.

## Compression

Transparent decompression for five formats, detected by both file extension and magic bytes:

| Extension | Format | Detection |
|-----------|--------|-----------|
| `.lz` | lzip | `LZIP` magic (4C 5A 49 50) |
| `.gz` | gzip | 1F 8B magic |
| `.zst` | zstd | 28 B5 2F FD magic |
| `.xz` | xz | FD 37 7A 58 5A 00 magic |
| `.bz2` | bzip2 | `BZh` magic (42 5A 68) |

If extension and magic bytes disagree, iris-replay refuses to proceed with a diagnostic message. Override with:

```sh
iris-replay --force-decompression=<alg> <command> <path>
```

Where `<alg>` is one of: `lzip`, `gzip`, `zstd`, `xz`, `bzip2`, `none`.

## ttyrec Format

Each frame:

```
offset  size  field
0       4     sec   (uint32 LE) — seconds since epoch
4       4     usec  (uint32 LE) — microseconds
8       4     len   (uint32 LE) — payload byte count
12      len   payload
```

Frames are concatenated with no separator or footer. An empty file is valid (zero frames).

## Parsing

Two code paths:

- **Buffer-based** (`parseBufferAt`): reads from a `Buffer` with explicit offset tracking. Used for file I/O.
- **Byte-list** (`parseBytes`): parses from `List Bits8`. Used in property tests for encode/decode roundtrips.

Both produce `Either ParseError (List Frame)` where `ParseError` carries the byte offset and a diagnostic message.

## Exit Codes

- `0` — success
- `1` — error (missing file, parse failure, out-of-bounds index, bad args)

Usage errors (no args, unknown subcommand) also exit `1` and print the usage string.
