# iris-rec

Capture stdin as a ttyrec recording.

## Usage

```sh
iris-rec record <output-path>
```

Reads stdin in 4096-byte chunks, timestamps each chunk with UTC clock time (seconds + microseconds), and writes the result as a ttyrec file.

Each chunk becomes one frame. Timestamps use `System.Clock.UTC` — seconds from epoch and nanoseconds divided down to microseconds.

## Encoding

Frames are encoded as ttyrec format:

```
[4 bytes: sec (u32 LE)] [4 bytes: usec (u32 LE)] [4 bytes: len (u32 LE)] [len bytes: payload]
```

`encodeU32LE` rejects values exceeding 2^32-1 with a `Left` error rather than silently truncating.

## Byte Safety

All 256 byte values survive the recording roundtrip, including NUL (0x00) and high bytes (0x80-0xFF). This is verified by the `record-byte-safety` and `raw-byte-roundtrip` CLI regression tests.

## API

```idris
-- Encode a single U32 as 4 little-endian bytes
encodeU32LE : Nat -> Either String (List Bits8)

-- Encode a single frame (header + payload)
encodeFrame : Frame -> Either String (List Bits8)

-- Encode a list of frames
encodeFrames : List Frame -> Either String (List Bits8)

-- Write frames to a file
writeTtyrec : String -> List Frame -> IO (Either String ())
```

## Exit Codes

- `0` — success
- `1` — error (missing output path, allocation failure, write failure, bad args)
