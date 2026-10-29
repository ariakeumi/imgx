# Architecture

IMGo is a Rust-first image optimization and transcoding monorepo. One core
processing stack powers a native macOS app built with SwiftUI + AppKit.

## Repository Layout

- `crates/minifier` - core image optimization and transcoding logic for PNG, JPEG, WebP, AVIF, HEIC, JXL, and related formats
- `crates/minifier-ffi` - C ABI (`staticlib`) over the core, linked into the macOS app
- `crates/minifier-utils` / `crates/shared` - shared Rust data structures and helpers
- `macos` - SwiftUI application, Xcode project, and the `build-core.sh` staging script
- `deps` - vendored third-party sources managed as Git submodules, plus local patches

## Runtime Model

The macOS app links `crates/minifier-ffi` as a static library:

- Swift calls `imgo_optimize` (bytes in, bytes + JSON metadata out) through the `CMinifier` module defined in `macos/Bridge`.
- Concurrency limiting (`max(cores - 1, 2)`), in-flight request deduplication, thumbnail generation, output caching (`~/Library/Caches/com.meowtec.imgo/oss/`), and settings persistence (`~/Library/Application Support/com.meowtec.imgo/options.json`) all live on the Swift side.
- `./macos/build-core.sh` stages `libminifier_ffi.a` and the C header for the Xcode project; `--universal` produces an arm64 + x86_64 slice via `lipo`.

## Format Support

| Format           | Native decode | Native encode | Notes                                                    |
| ---------------- | ------------- | ------------- | -------------------------------------------------------- |
| PNG / APNG       | Yes           | Yes           | Animated PNG is supported for decode and encode.         |
| JPEG             | Yes           | Yes           | Encoding is single-frame; alpha is flattened onto white. |
| GIF              | Yes           | Yes           | Animated GIF is supported for decode and encode.         |
| WebP             | Yes           | Yes           | Animated WebP is supported for decode and encode.        |
| AVIF             | Yes           | Yes           | Animated AVIF is supported by the core pipeline.         |
| HEIC / HEIF      | Yes           | Yes           | Single-frame only.                                       |
| JXL              | Yes           | Yes           | Single-frame only; lossless JPEG transcoding available.  |
| BMP              | Yes           | Yes           | Single-frame only.                                       |
| TIFF             | Yes           | Yes           | Single-frame only.                                       |
| PNM              | Yes           | Yes           | Single-frame only.                                       |
| TGA              | No            | Yes           | Input detection does not currently recognize TGA.        |
| ICO              | Yes           | Yes           | Single-frame only.                                       |
| HDR              | Yes           | Yes           | Single-frame only.                                       |
| OpenEXR          | Yes           | Yes           | Single-frame only.                                       |
| Farbfeld (`.ff`) | Yes           | Yes           | Single-frame only.                                       |
| QOI              | Yes           | Yes           | Single-frame only.                                       |

macOS preview notes: animated formats render their first frame in the UI
today; JXL source files have no system image decoder and show a placeholder
until converted.
