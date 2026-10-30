# Todo Wallpaper · Native iOS

> 交接文档（当前代码现状）：[AGENTS.md](AGENTS.md) · [ARCHITECTURE.md](ARCHITECTURE.md) · [FILE_MAP.md](FILE_MAP.md) · [KNOWN_ISSUES.md](KNOWN_ISSUES.md)

**当前版本：0.6.1** — 实际构建号见交付包 status.json（1000 + CI run_number）。第1～4组已通过各自完整门禁；本版本最终编译/检查结论以生成包内证据为准。Windows 签名安装与本轮真机验收仍未验证。

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
| 裁剪/透明度/主题后重算与自动数值刷新 | 已通过第2组实际 CG 与 iOS 调度回归；约 0.5 秒体验需真机 |
| 相册全部分析、crop 后全部失效、换日选图对应统计 | 已通过第2组纯 CG 批次与实际比例检查，跨日系统 Widget 刷新需真机 |
| Widget 缓存清理、缺失请求与冷进程 entry | 已通过第2组文件双实例、清内存与快照检查；实际跨进程通知和系统调度需真机 |
| 现有 native 门禁 | 原门禁完整保留并追加新 runner，第2组完整 CI 已通过；不将源码检查视为真机验收 |

第2组的 CI 首次运行通过 86 项真实 CG 分析检查及原有 macOS 检查，但 SwiftUI 编辑页过长的修饰链超过编译器类型推断时限；已把原链分为私有子视图属性，让编译器分段检查，保留控件顺序、行为和所有既有断言。

## 第3组：相册与存储

3.1 已修复：PhotoKit 改用 requestImage 的 1536×1536 aspectFit 高质量目标请求并允许 iCloud 网络，返回后仍经 ImageIO 保证最终最长边 1536。一次只处理一张；单张失败计数跳过，全部失败或超过一半失败、取消均回滚本次写入；恰好一半可提交。文件名有原子事务日志。父编辑器保存外观成功后才结束事务，之后取消不会误删已引用的照片；部分成功显示“N 张读取失败，已跳过”。进程被系统终止时未提交文件可在超过保护期且无引用后由后续 GC 回收，日志可用于追查。

3.2 已修复：启动、相册提交、移除照片后在共享 actor 回收 WidgetPhotos/MarkerImages。保留集合包含当前外观全部引用、所有任务标记、两个编辑器的撤销 current/before/after、可恢复备份与归档。导入活跃、任一权威文件/归档不可读时整体跳过；最近 10 分钟及符号链接不删。宁可少删，备份与撤销尚引用的旧相册不会立刻释放。同步清理分析全部变体和孤立键。

3.3 已修复：迁移和 ready 路径返回仓库与已验证文档快照，App reload/Provider 不再第二次 load；不引入长期缓存、不改变锁顺序和幂等回执。新增迁移快照回归。

检查变更原因：追加 PhotoAssetMaintenanceChecks 原生失败阈值与真实目录保留/失败关闭检查，NativeUIProbe 执行生产 actor 的事务日志、回滚、提交后取消保护和导入时禁止 GC，并验证编辑器历史引用回调。结构门禁追加实际生产入口约束，未删除旧断言。受保护的存储/迁移文件与 TodoStore 因新增这些调用而更新审查哈希；壁纸渲染完成态与 TextLegibility 未改变。所有 Photos 权限/iCloud 网络和内存峰值体验仍需真机，不以测试替代。

## 第4组：日期、手势与微调

4.1 已修复：TodoSchedule.label 原先每次创建 DateFormatter；现在缓存日期/日期时间两种短格式，NSLock 内使用，locale/calendar 为 autoupdatingCurrent，时区沿用旧格式器的应用默认值；地区/时区通知在缓存对象生命周期注册并失效。日期组件、date()/validate() 与 JSON 不变，回归逐字比较旧实现并覆盖时区/地区通知。

4.2 已修复：检索 PhotoMotionView、MEDIA-MOTION-050 与既有 Tests，没有“任一取消就全回滚”的产品依据。改为只在所有已开始识别器都取消/失败时回滚，任一个正常结束即保留当前值；最后一个结束只提交一次，重复结束忽略。真实 UIKit 层会话回归覆盖两种混合顺序、全取消、全成功和单手取消，保留逐帧零提交约束。

4.3 已修复撤销合并：微调显式使用 interaction.begin/end，500ms 内同键点按合为一组；切工具、离开、撤销或下一种手势会结束旧组，旧定时器不会截断新手势。步进已确认无需修改：仍是一个导出像素；抽出原公式供生产和检查共用，没有凭猜测加大。生产布局在 2048/4096 输出、三种面板宽、九个中心/边界与四方向共216例检查可见移动不超过1像素；未在这些几何场景复现跳变，Windows环境无法作iPhone触摸视觉复现，仍需真机。

4.4 旧 setShadow 绘制与界面控件已确认无需修改（源码中已不存在）；删除 drawText 遗留的未使用 shadow 参数及过时注释，旧持久化字段仍兼容。TextLegibility.readable 与静态壁纸完成态按要求不动。另把 WallpaperLiveCanvas 未变更的 x/y 改为 let，清除已有两条编译警告。

检查变更原因：新增日期旧文本比较、原生UIKit组合手势和真实撤销上下文、生产布局微调回归及结构约束；没有放宽既有像素断言。WallpaperGeometry 受保护哈希的变化来自同公式微调函数和删除过时阴影注释，原有 glyphKey 完成态约束完整保留。

## 第5组：文档、检查与版本

5.1 已修复：原 Bash 在 IFS 分列后继续判断分隔符，导致前两项跳过所有真实行也 PASS。现在 Bash 只选择可运行的 Python 3.9+ 并转交标准库检查器（支持 Windows python3 商店占位回退，UTF-8 输出）；严格解析表格、检查文件/实际声明、所有 Swift 登记及常量引用，每项输出实际计数，任一零条失败。18个正/负向夹具覆盖空表/空源/空符号/空常量、漏行/文件/符号、注释伪声明、重复、畸形、路径越界和动态计数，已接 CI。检查仅验证引用，不宣称自动证明所有常量值语义一致。

5.2 已修复：KNOWN_ISSUES 统一按四段记录历史，静态壁纸完成态改列有意设计，不恢复旧效果；微调视觉跳变未在216个生产几何场景复现，保留真机待验。已纠正测试 Target、旧目录回执、非法壁纸比例抛错、日历默认7天/最大90天及主要类型遗漏，ARCHITECTURE/FILE_MAP 同步新线程、事务、回收与快照流程。

5.3 已修复：版本提升0.6.1，实际构建仍为1000+CI序号；Artifact名、构建摘要取元数据，Simulator与设备使用同次构建号。版本和最终CI提交以包内 status.json 为准。

检查变更原因：仅追加严格交接门禁和工具回归，保留所有既有 native/结构/像素断言；没有通过固定成功数或放宽原检查获得通过。当前源码在Windows的完整交接输出如下（CI会再次运行同一脚本）：

```text
== 1. FILE_MAP 文件存在 ==
检查了 66 条
== 2. FILE_MAP 符号声明 ==
检查了 144 条
== 3. Swift 源码登记覆盖 ==
检查了 66 条
== 4. ARCHITECTURE 常量引用 ==
检查了 20 条
== 5. 交接文档齐全 ==
检查了 5 条
PASS: 交接引用与源码登记检查通过（不代替编译、常量值语义审查或真机验证）
```

### 本轮九项自测（证据分层）

| 自测项 | 状态与范围 |
| --- | --- |
| 1 黑/白/粉字、蒙层色和阴影色一致，白蒙层暗强亮弱 | 已验证规则与模拟器像素；全部真实照片观感需真机 |
| 2 标记阴影，着色/锁屏规格不加效果 | 已验证共享规则与模拟器像素；真实系统模式需真机；当前未新增锁屏组件 |
| 3 裁剪/拖动/透明度后自动刷新、大图不卡 | 已验证后台分析、400ms结束去抖与revision通知；约0.5秒体验、内存与帧率需真机 |
| 4 相册逐张分析、crop全部重算、跨日对应图片 | 已验证原生串行批次和日期状态；系统跨日刷新需真机 |
| 5 单张失败跳过、过半失败回滚 | 已验证阈值和生产文件事务；Photos真实iCloud请求/取消入口仅编译检查，需真机 |
| 6 孤立图回收、撤销引用保护 | 已验证真实文件目录、当前/任务/备份/撤销/最近导入保留及加载失败不删；长期真实图库流程需真机 |
| 7 鲜艳颜色立即生效 | 已验证sRGB转换、状态接收和撤销；屏幕真实观感需真机 |
| 8 日期文本与旧版一致 | 已验证三种时区下与旧DateFormatter逐字比较及通知失效；系统设置切换体验需真机 |
| 9 现有native门禁 | 第1～4组完整CI已验证；第5组执行本源码后，最终结果见包内status.json及交付README.txt |

### 分组验证记录

- 第1组 `4b423ce`：[完整CI #71](https://github.com/klein7syd/ios-wallpapertest/actions/runs/41051835229) 通过。
- 第2组 `2a0e283`：[完整CI #74](https://github.com/klein7syd/ios-wallpapertest/actions/runs/41072835683) 通过，含86项实际CG分析回归。
- 第3组 `1973efa`：[完整CI #77](https://github.com/klein7syd/ios-wallpapertest/actions/runs/41089037457) 通过，含事务、回收和快照回归。
- 第4组 `dee27d4`：[完整CI #79](https://github.com/klein7syd/ios-wallpapertest/actions/runs/41092594042) 通过，含日期、组合手势、撤销与216例微调几何；已清除旧x/y警告。
- 第5组最终提交、实际构建、IPA校验和及完整检查结果由本源码CI生成到交付包，避免在源码文档里自引用提交号。

## 操作布局优化

新增待办移至列表底部安全区；编辑器类别切换移至参数区下方，保持四页系统Tab和独立预览。常用参数按素材、布局、质感、导出顺序分组；小组件实验玻璃移至常用设置之后，移除照片与调节控件分隔。微调/收起/导出按钮增加44pt点击区域，导出纵向排列以适应窄屏和大字体。依据Apple HIG按钮指南；真实单手握持舒适度仍需真机。未改变渲染、数据保存和撤销逻辑。

结构检查同步原因：旧检查强制实验玻璃排在主题第一项，与本次常用操作优先的布局要求冲突；改为检查它位于明暗控件之后且有实验分组标签，保留检查而非跳过。TodoStore等数据文件未修改；App入口保护哈希仅因新增待办按钮下移更新。
