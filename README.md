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

锁屏 family 的像素检查通过内容/背景的生产参数注入：真实 Widget 从系统读取 family 后传入同一参数，测试显式传入 family。原因是 `EnvironmentValues.widgetFamily` 为只读键，不能通过 `.environment` 伪造；模式仍使用公开可写的 `widgetRenderingMode` 环境键。检查未删除锁屏效果禁用的像素断言，也不把此注入等同于真实锁屏安装验收。

## 第2组：图片分析管线

原先选图只分析未裁剪的原图，透明度与主题改变后没有重算，且 `Task` 继承 MainActor。现在生产入口统一由 `TodoStore` 调度：交互期间取消旧 generation，结束后 400ms 去抖；`PhotoAnalysisService` 在单一 utility 串行队列读取已导入的 1536px 文件，用 ImageIO 降到最大边 128px，再按实际 crop、画布比例、透明度与白/0.09 深色底色合成一次 32×32 位图，从同一缓冲区计算三锚点。没有 `UIImage(data:)` 原图分析，也没有每图片 detached 并发。

相册先处理今天图片，其次当前预览图片及当前比例，再逐张处理余下图片；crop、透明度和有效底色改变会使整个相册失效重算。完全不透明时明暗共用上下文。每个完成上下文发布 `analysisRevision`，全命中磁盘的批次也发布最终 revision，使“自动：0.xx”在冷启动暖缓存后刷新；Widget 刷新合并为今天图片完成和批次结束两次。400ms 是开始分析前的去抖时间，实际更新还取决于后台排队、文件读取和系统调度，尚不能用编译结果保证真机固定 0.5 秒。

缓存键包含图片名、zoom/pan、opacity、有效底色和实际 canvasAspect。生产结果为 App Group `AnalysisCache/<上下文>.json`，版本化封套原子写入三锚点原始统计；旧 defaults 的图片名+锚点结果不再复用。缺失请求写入 `AnalysisRequests/<上下文>.json` 后才发送公开 Darwin 通知，App 启动、回到前台及存活期间事件都会补算，避免 defaults 异步可见性造成漏请求。运行中的同参数批次收到晚到请求只记补扫，不反复取消并清空整个相册。

Widget 每次 Provider 开始清空分析内存缓存，按真实 displaySize 比例读取并登记缺失，绝不在 Widget 分析；entry 携带分析快照，避免另一尺寸 Provider 清内存后使已准备的 entry 回退。App 和 Widget 的 body 仅读热内存或快照。缓存使用短 NSLock 保护内存、独立后台文件锁保护 IO，并以图片删除版本和源文件存在检查防止旧结果复活；坏/未来结果封套安全回退。移除照片异步清理全部变体，后续回收通过 `cachedPhotoNames()` / `cleanOrphanAnalysis(existing:)` 使用同一接口。

检查变更原因：新增独立 `check-photo-analysis.sh` 并接入原 `check-native.sh`，直接编译生产纯 CG 服务，从 MainActor 提交真实上下/左右色块验证方向、crop/zoom、alpha、0.09 底色、实际比例、128px 解码、后台执行、取消、原子文件后端、旧键隔离、跨实例刷新、整相册失效与今天优先。iOS probe 另执行生产 TodoStore 的交互结束去抖、取消旧 generation、晚到真实比例请求、observable 刷新以及 entry 快照回归。新增结构约束固定这些调用边界；没有删除、放宽既有像素或状态断言。生产调用链变更涉及受保护文件，内容哈希须审查后更新。

| 本组验收项 | 当前证据范围 |
| --- | --- |
| 裁剪/透明度/主题后重算与自动数值刷新 | 已加入实际 CG 与 iOS 调度回归，待本组 macOS CI 执行；约 0.5 秒体验需真机 |
| 相册全部分析、crop 后全部失效、换日选图对应统计 | 已加入纯 CG 批次与实际比例检查，跨日系统 Widget 刷新需真机 |
| Widget 缓存清理、缺失请求与冷进程 entry | 已加入文件双实例、清内存与快照检查；实际跨进程通知和系统调度需真机 |
| 现有 native 门禁 | 原门禁完整保留并追加新 runner，待本组完整 CI；不将源码检查视为真机验收 |

第2组的 CI 首次运行通过 86 项真实 CG 分析检查及原有 macOS 检查，但 SwiftUI 编辑页过长的修饰链超过编译器类型推断时限；已把原链分为私有子视图属性，让编译器分段检查，保留控件顺序、行为和所有既有断言。
