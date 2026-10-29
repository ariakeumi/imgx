# IMGX

[English](./README.md) | [简体中文](./README.zh-CN.md)

IMGX（image optimizer）是一个本地批量图片压缩与格式转换工具。一次处理多张图片，自由调整画质与尺寸，在各种常见格式之间转换，全程不上传你的文件。

IMGX 是 [meowtec/Imagine](https://github.com/meowtec/Imagine) 的重写版。它现在是一个完全原生的应用：SwiftUI 界面 + Rust 压缩核心，不内嵌任何浏览器。

![IMGX 批量处理界面](./docs/images/imgo.webp)

## 功能

- 批量图片压缩与格式转换
- 本地处理：图片不出设备
- 画质、无损、缩放、元数据控制
- 支持动图 PNG、GIF、WebP、AVIF
- macOS 原生应用（Apple Silicon 与 Intel）
- 拖拽导入、Finder 文件关联、文件夹导入

## 输出格式

JPEG、PNG、GIF、WebP、AVIF、HEIC、JPEG XL（JXL）

支持动图 PNG、GIF、WebP、AVIF 输出。

## 下载

从 [GitHub Releases](https://github.com/meowtec/imgo/releases) 下载最新的 DMG。

通用 DMG 同时支持 Apple Silicon 与 Intel 芯片（macOS 14 及以上）。

应用未做公证，首次打开时 macOS 可能弹出安全提示。如果系统阻止打开
IMGX，请先把 `IMGX.app` 移到「应用程序」文件夹，再在终端执行：

```bash
xattr -cr "/Applications/IMGX.app"
```

然后重新打开 IMGX。

## 开发

见 [docs/development.md](./docs/development.md)。简要步骤：

```bash
./scripts/init-deps.sh   # 初始化 submodule 并应用补丁
./macos/build-core.sh    # 构建 Rust 静态库
cd macos && xcodebuild -project IMGo.xcodeproj -scheme IMGo build
```

## 许可

MIT
