#!/bin/sh
set -e

cd "$(dirname "$0")"

# Build Rust support library
echo "--- Building Rust support crate ---"
cargo build --manifest-path support/Cargo.toml "$@"

# Build Idris executable
echo "--- Building Idris iris-native ---"
idris2 --build iris-native.ipkg

# Copy dylib into the app directory so the generated wrapper finds it
APPDIR=build/exec/iris-native_app
if [ "$(uname)" = Darwin ]; then
  cp support/target/debug/libiris_native_support.dylib "$APPDIR/"
else
  cp support/target/debug/libiris_native_support.so "$APPDIR/"
fi

echo "--- Done: ./build/exec/iris-native ---"
