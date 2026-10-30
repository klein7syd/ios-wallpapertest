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

## 第1组：可读性、颜色与编辑状态修复

负边距曾通过绝对值扩大照片蒙层；现在顶部/底部只计正增量。标记补上与文字相同的阴影，摘要删除重复阴影，并让真实着色模式与锁屏 family 同时禁用阴影和蒙层。位图标记缓存、任务完成行为与静态壁纸完成逻辑保持原有职责。

旧分析把黑蒙层建议值与图片绑定，切换文字深浅后不适用。现在缓存仅写原始亮度与对比度，黑/白蒙层通过 Core 纯函数按当前文字颜色运行时计算；旧 `suggestedScrim` 只用于兼容解码。系统取色先通过 CoreGraphics 转换到 sRGB，再夹取分量并保留透明度。

居中偏移不再固定在 ±40：以未扣除偏移的自然内容高度计算 `±max(40, (画布高-文字高)/2)`，预览通过 Preference 回传几何，滑条、setter、锚点切换和渲染共用边界。持久化仍接收旧顶部/底部 -40 值，避免历史合法文件被拒读。样式校验失败会规范化数值并重试，成功立即清除校验错误；存储和未来版本保护错误只在实际 IO 成功后清除。撤销检查接收结果，防止失败后误吞历史。

检查变更原因：在已有 `WidgetFeedbackChecks` 加入蒙层方向、负边距、动态范围与历史 JSON 检查，在 `NativeUIProbe` 加入 P3 转换色值、真实背景/标记像素、存储错误保护和撤销检查，并在 `check-ui-structure.py` 固化共享规则及模式门禁。上述文件改变的是实际生产调用链，因此受保护源码清单需要审查后更新内容哈希，不能绕过或删除保护检查。当前组的 iOS 编译、原生检查与真机结果应分别以本次实际运行证据为准。
