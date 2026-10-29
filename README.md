# IMGX

[English](./README.md) | [简体中文](./README.zh-CN.md)

IMGX (short for "image optimizer") is a private batch image compression and conversion tool for macOS. Process multiple images at once, adjust quality and dimensions, and convert between common formats without uploading your files.

IMGX is the next-generation rewrite of the original [meowtec/Imagine](https://github.com/meowtec/Imagine). It is now a fully native app: a SwiftUI interface over a Rust compression core, with no embedded browser.

![IMGX batch processing view](./docs/images/imgo.webp)

## Features

- Batch image compression and conversion
- Local processing: images stay on your device
- Quality, lossless, resize, and metadata controls
- Support for animated PNG, GIF, WebP, and AVIF
- Native macOS app (Apple Silicon and Intel)
- Drag & drop, Finder integration, and folder import

## Output Formats

JPEG, PNG, GIF, WebP, AVIF, HEIC, JPEG XL (JXL)

Animated PNG, GIF, WebP, and AVIF output is supported.

## Download

Download the latest DMG from [GitHub Releases](https://github.com/meowtec/imgo/releases).

The universal DMG runs on Apple Silicon and Intel Macs (macOS 14 or newer).

The app is not notarized. The first time you open it, macOS may display a
security warning. If macOS prevents IMGX from opening, move `IMGX.app` to the
Applications folder, open Terminal, and run:

```bash
xattr -cr "/Applications/IMGX.app"
```

Then open IMGX again.

## Development

See [docs/development.md](./docs/development.md). In short:

```bash
./scripts/init-deps.sh   # submodules + native patches
./macos/build-core.sh    # stage the Rust static library
cd macos && xcodebuild -project IMGo.xcodeproj -scheme IMGo build
```

## License

MIT
