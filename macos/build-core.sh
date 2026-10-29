#!/bin/sh
# Build the Rust minifier core and stage it for the Xcode project.
#
#   ./build-core.sh            build for the current architecture
#   ./build-core.sh --universal  build arm64 + x86_64 and lipo them together
set -e

cd "$(dirname "$0")/.."

if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi

command -v cargo >/dev/null || {
  echo "cargo not found; install Rust via https://rustup.rs" >&2
  exit 1
}

UNIVERSAL=0
[ "${1:-}" = "--universal" ] && UNIVERSAL=1

mkdir -p macos/Vendor macos/Bridge
cp crates/minifier-ffi/include/imgo_minifier.h macos/Bridge/

build() {
  echo "==> cargo build --release -p minifier-ffi --target $1"
  cargo build --release -p minifier-ffi --target "$1"
}

if [ "$UNIVERSAL" -eq 1 ]; then
  build aarch64-apple-darwin
  build x86_64-apple-darwin
  mkdir -p target/universal-apple-darwin/release
  lipo -create \
    target/aarch64-apple-darwin/release/libminifier_ffi.a \
    target/x86_64-apple-darwin/release/libminifier_ffi.a \
    -output target/universal-apple-darwin/release/libminifier_ffi.a
  SOURCE="target/universal-apple-darwin/release/libminifier_ffi.a"
else
  cargo build --release -p minifier-ffi
  SOURCE="target/release/libminifier_ffi.a"
fi

cp "$SOURCE" macos/Vendor/libminifier_ffi.a
echo "==> staged macos/Vendor/libminifier_ffi.a ($(lipo -archs macos/Vendor/libminifier_ffi.a))"
