# Todo Wallpaper · Native iOS

**Current work: native UI feedback revision 0.4.1** — four root tabs, editor navigation Dock, conditional visual marker controls and fixed Widget preview. Compilation and device validation are recorded separately below.

Public source-only personal project. Windows+iPhone, free Apple Account, macOS GitHub Actions compilation, Windows iPASide/R1 local signing. No credentials, signed packages, profiles or device identities are committed; no automatic public Releases.

- Proven R1 validation baseline: `native-validation/`, original ID `org.todowallpaper.nativeinstallprobe`, frozen baseline branch. [Provenance](docs/R1-BASELINE.md).
- Formal IDs unchanged: `org.todowallpaper.app`, `org.todowallpaper.app.widget`, `group.org.todowallpaper.app`.
- A/B/C passed user device acceptance. D1+D2 0.3.0/1005 received first real-device feedback.
- Previous 0.4.0: D3+D4 native large-canvas editor, direct layer movement, true weighted fonts, arbitrary/global/per-task Emoji markers, independent Widget appearance, ratio-first 4096px-high output. No PWA, WebView, AI, translation or cloud sync.

[UI revision](docs/UI-REVISION.md) · [Rendering and compatibility](docs/STAGE-D3-D4.md) · [Real validation status](docs/VALIDATION.json) · [Windows/iPhone test checklist](TodoWallpaper/DEVICE-TEST.md) · [Product workflow](https://github.com/klein7syd/ios-wallpapertest/actions/workflows/todo-wallpaper.yml)

CI executes actual production native rendering and persistence checks, packages unsigned ARM64 App+Widget IPA with unchanged R1 scripts. Compilation, signing, installation and device acceptance remain separate. D3+D4 iPhone acceptance is pending until actual feedback. Docs-only evidence commits use `[skip ci]`.

The native TabView has four root pages; Wallpaper uses an explicit editing Dock while its system Tab Bar is hidden. Source published while Public may be copied/cached even if made Private later.
