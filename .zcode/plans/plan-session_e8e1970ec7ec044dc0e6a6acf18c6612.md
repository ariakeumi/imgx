# IMGo 架构收敛：移除 Web UI 与 Tauri，改为 macOS 原生应用（SwiftUI + AppKit）

## 目标终态

仓库收敛为：**Rust 压缩核心 + Swift 原生 macOS 应用 + CLI**。

```
imgx/
├── crates/
│   ├── minifier/          # 保留不动（压缩核心）
│   ├── minifier-utils/    # 保留
│   ├── shared/            # 保留，清理 tsify/ts-rs/wasm-bindgen 等纯 TS 生成依赖
│   ├── minifier-cli/      # 保留（benchmark 依赖它）
│   ├── minifier-js/       # 删除（纯 Web WASM）
│   ├── shared-js/         # 删除（TS 类型/WASM 桥）
│   └── minifier-ffi/      # 新增：C ABI staticlib，供 Swift 调用
├── macos/                 # 新增：原生应用
│   ├── build-core.sh      # cargo 构建静态库 + 拷贝头文件（默认当前架构，--universal 双架构）
│   ├── Vendor/            # libminifier_ffi.a + minifier.h（gitignore）
│   ├── IMGo.xcodeproj/    # 手写精简 pbxproj（Xcode 16+ 文件系统同步组，单一 app target）
│   └── IMGo/              # Swift 源码 + 资源
├── deps/ benchmark/ docs/ # 保留
├── app/ website/ packaging/  # 整体删除
└── .github/workflows/     # 重写为 macOS-only
```

## Phase A — 抢救 + 移除

**先抢救再删除**（拷入 `macos/IMGo/Resources/`）：
- `app/src/i18n/`（前端全部 UI 文案，含 13 语言）和 `app/src-tauri/i18n/*.json`（菜单/弹窗文案）→ 合并为 Swift i18n 资源，回退链沿用 `完整locale → 主语言 → en`
- `app/src-tauri/icons/` → AppIcon（iconutil 转 .icns）
- 需要移植的逻辑参考（实施时读后删）：`constants/format-options.ts`、`constants/simplified-quality.ts`、`store/mutations.ts`（缩略图参数、skip-save 规则）、`lib/migrate-app-options.ts`

**删除**：`app/`、`website/`、`packaging/`、`crates/minifier-js/`、`crates/shared-js/`、根目录全部 JS 工具链（package.json、pnpm-workspace.yaml、pnpm-lock.yaml、tsconfig.json、.oxlintrc.json、.prettierrc、.prettierignore）。

**修改**：
- 根 `Cargo.toml`：members 收敛为 `[deps/libheif-sys, deps/jpegxl-rs/jpegxl-src, crates/minifier, crates/minifier-utils, crates/minifier-cli, crates/shared, crates/minifier-ffi]`；删 minifier-js/shared-js 的 release profile；`[patch.crates-io]` 保留（minifier 仍依赖）
- 原 `package.json` 的 `init:src`（submodule 打补丁）改写为 `scripts/init-deps.sh` 纯 shell 脚本
- `benchmark/quality-calibration.mjs`：确认无 npm 依赖后保留（纯 node 直接跑）；若有依赖则删或改 Rust，实施时定
- `imgo-shared`：删除 wasm-bindgen/tsify/ts-rs/console_error_panic_hook 依赖及派生宏，只留 serde/image/anyhow
- `.gitignore`：删 minifier-js 条目，加 `macos/Vendor/`、xcuserdata 等

## Phase B — FFI 层（crates/minifier-ffi）

staticlib crate，头文件手写（约 50 行，不引入 cbindgen）：

```c
typedef struct { uint8_t *data; size_t len; char *meta_json; } imgo_result;
int  imgo_optimize(const uint8_t *input, size_t len,
                   const char *request_json,   // {"outputFormat":"WebP","options":{...}}，serde 解析
                   imgo_result *out);          // 成功 0；meta_json 含格式/分辨率
void imgo_result_free(imgo_result *r);
const char *imgo_last_error(void);             // thread_local 错误信息
```

- `optimize_image` 是纯函数（decode→resize→encode），可多线程并发调用；文件缓存、哈希命名、并发限流全部留在 Swift 侧，FFI 只做 bytes→bytes
- 实施时先核对 `OptimizeOptions`/`ImageFormat` 的 serde JSON 表示（枚举命名风格），Swift Codable 严格对齐
- 测试：cargo test 增加 FFI 往返用例（PNG 输入→PNG 输出验证魔数、错误路径）

## Phase C — Swift 应用 MVP（macOS 14+，SwiftUI 生命周期 + NSApplicationDelegateAdaptor）

**核心模型/服务**：
- `AppStore`（@Observable）：任务列表、加载态、全局选项，对应原 Zustand store
- `OptimizeEngine`：并发上限 `max(核心数-1, 2)`、进行中同参数请求去重（SHA-512 缓存键，沿用原公式：请求参数 + 源路径，取前 16 字节 hex）
- `CacheStore`：`~/Library/Caches/com.meowtec.imgo/oss/`，启动/退出时清空，`thumb/` 子目录，`hash.ext` 命名
- `ConfigStore`：`~/Library/Application Support/com.meowtec.imgo/options.json`，字段与现格式逐一对齐（skipSaveType、skipSaveMinRatio、newFileNameSuffix、globalDefaultOptions、appTheme、confirmOnClose），tmp+rename 原子写，天然兼容老配置
- `SaveService`：四模式复刻——SAVE_AS（单张、预填文件名并修正扩展名）、OVERRIDE（写回原路径）、AUTO_NEW_NAME（stem+后缀+`name(N)` 找不冲突名）、SAVE_TO_DIR（选目录批量）；含 skip-save 规则（按类型/压缩率跳过）
- `ImportService`：NSOpenPanel（9 种扩展名过滤）、文件夹递归（跳 `.` 开头）、拖放、`application(_:openFiles:)`、pending 缓冲

**视图**：
- 主窗口 1140×800 / min 640×360，空态提示拖入图片
- `TaskListView`（LazyVGrid 虚拟滚动）+ `TaskCardView`（缩略图、原始→压缩尺寸/大小、格式徽标、状态/错误）
- `CompareView`：分割线拖动对比 + 滚轮/捏合缩放 + 拖拽平移（SwiftUI 手势），统计栏
- `OptionsPanel`：输出格式（含"保持原格式"）、质量滑块、无损、缩放输入、元数据开关；`SettingsSheet`：主题 light/dark/system、关闭确认、skip-save、默认格式规则
- 菜单：File → Open(⌘O) / Open Folder / Save(⌘S) / Save as New File / Save to Directory，About；关闭确认 NSAlert（i18n 文案沿用）
- Info.plist：CFBundleDocumentTypes 关联 png/jpg/jpeg/gif/webp/avif/heic/heif/jxl；bundle id `com.meowtec.imgo`
- 动图（APNG/GIF/动图 WebP/AVIF）MVP 阶段显示首帧，动画播放列为后续跟进

**工程生成**：手写 Xcode 16+ 精简 pbxproj（文件系统同步组、单 target、无资产目录，图标用 .icns + CFBundleIconFile）；若 pbxproj 受阻则回退 SPM executable + 手工 .app 打包脚本。

## Phase D — CI 与文档

- `ci.yml`：删全部 wasm/web/emscripten 步骤 → cargo fmt --check + clippy + test（minifier/shared/ffi）+ build minifier-cli + macOS runner 上 build-core + `xcodebuild build`
- `release.yml`：仅 macOS——校验 tag、submodule+补丁、universal 静态库、`xcodebuild archive` 出 arm64/x86_64 DMG（保持不签名），删 Windows/Linux/Flatpak/AppImage 全部矩阵
- README / README.zh-CN / docs（architecture.md、development.md）：重写为 macOS 原生架构，下载指向 GitHub Releases

## 实施前置（第 0 步）

仓库是新克隆，需先：`git submodule update --init --recursive` + `scripts/init-deps.sh` 打补丁；核对 rustc/Xcode/cmake/nasm 工具链（计划模式下无法验证，实施时确认；缺什么装什么）。

## 验证关口

1. `cargo test -p minifier -p imgo-shared -p minifier-ffi` 通过
2. `cargo build --release -p minifier-cli` 可跑（验证编解码器 submodule 链路完好）
3. `macos/build-core.sh` 产出静态库；`xcodebuild build` 通过
4. 手动冒烟：启动 app → 拖入 PNG/JPEG/HEIC → 批量压缩 → 对比视图 → 三种保存模式 → 关闭确认弹窗 → 重启后配置保留

## 后续跟进（本次不做）

动图动画预览、拖出导出、完整快捷键、自动更新、签名与公证、i18n RTL 打磨。