# Todo Wallpaper · Native iOS

> 交接文档（当前代码现状）：[AGENTS.md](AGENTS.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [FILE_MAP.md](FILE_MAP.md) · [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

**Current delivery: 0.6.0 / 1069** — 原生 App + Widget 编译、原生 PNG 渲染检查与模拟器检查通过；Windows 签名安装与全部真机项仍未验证。

Public source-only personal project. Windows+iPhone, free Apple Account, macOS GitHub Actions compilation, Windows iPASide/R1 local signing. No credentials, signed packages, profiles or device identities are committed; no automatic public Releases.

- Proven R1 validation baseline: `native-validation/`, original ID `org.todowallpaper.nativeinstallprobe`, frozen baseline branch. [Provenance](docs/R1-BASELINE.md).
- Formal IDs unchanged: `org.todowallpaper.app`, `org.todowallpaper.app.widget`, `group.org.todowallpaper.app`.
- A/B/C passed user device acceptance. D1+D2 0.3.0/1005 received first real-device feedback.
- Previous 0.4.0: D3+D4 native large-canvas editor, direct layer movement, true weighted fonts, arbitrary/global/per-task Emoji markers, independent Widget appearance, ratio-first 4096px-high output. No PWA, WebView, AI, translation or cloud sync.

[Current photo/editor repairs](docs/PHOTO-EDITOR-REPAIRS-051.md) · [Previous media/motion update](docs/MEDIA-MOTION-050.md) · [Previous feedback repairs](docs/FEEDBACK-REPAIR-044.md) · [Previous editor refinement](docs/EDITOR-REFINEMENT.md) · [0.4.2 feedback revision](docs/WIDGET-FEEDBACK.md) · [Previous UI revision](docs/UI-REVISION.md) · [Rendering and compatibility](docs/STAGE-D3-D4.md) · [Real validation status](docs/VALIDATION.json) · [Windows/iPhone test checklist](TodoWallpaper/DEVICE-TEST.md) · [Product workflow](https://github.com/klein7syd/ios-wallpapertest/actions/workflows/todo-wallpaper.yml)

CI executes actual production native rendering and persistence checks, packages unsigned ARM64 App+Widget IPA with unchanged R1 scripts. Compilation, signing, installation and device acceptance remain separate. The UI feedback revision awaits actual iPhone acceptance; compilation and source/state checks cannot prove the scrolling fix. Docs-only evidence commits use `[skip ci]`.

The native TabView has four root pages; The 0.4.3 refinement keeps the system Tab Bar visible during wallpaper editing and retires the circular Dock. Source published while Public may be copied/cached even if made Private later.
