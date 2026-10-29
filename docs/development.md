# Development

See [Architecture](./architecture.md) for the repository structure, runtime
boundaries, and codec support matrix.

## Requirements

- Rust through `rustup`
- Xcode (a full installation, selected via `xcode-select` or the
  `DEVELOPER_DIR` environment variable)
- CMake, Meson, Ninja, and NASM (`brew install cmake ninja meson nasm`)

## Initial Setup

For a clean checkout:

```bash
./scripts/init-deps.sh
```

The script initializes all Git submodules, then resets the working trees of
`deps/libheif-sys`, `deps/libde265`, `deps/libheif`, and `deps/jpegxl-rs`
before applying the repository patches. Do not run it when those submodules
contain local changes that must be preserved.

## Development Commands

Run the Rust test suite:

```bash
cargo test -p imgo-shared -p minifier -p minifier-ffi
```

Stage the Rust core for the Xcode project (required before the first app
build):

```bash
./macos/build-core.sh
```

Build the macOS app:

```bash
cd macos
xcodebuild -project IMGo.xcodeproj -scheme IMGo -configuration Debug build
```

Or open `macos/IMGo.xcodeproj` in Xcode and run the IMGo scheme directly.

Format and lint:

```bash
cargo fmt --all
cargo clippy -p minifier-ffi -p imgo-shared
```

## Release

Tagging `vX.Y.Z` triggers `.github/workflows/release.yml`, which:

1. Validates the tag against `MARKETING_VERSION` in the Xcode project.
2. Builds a universal (arm64 + x86_64) `libminifier_ffi.a`.
3. Builds the Release app and packages an unsigned universal DMG.
