# ARCHITECTURE

本文只描述当前代码现状，所有条目均可追溯到源码。

## a. 模块总览

**待办数据（Core/TodoItem, TodoRepository, TodoStore）**
`TodoItem` / `TodoDocument` 是值类型模型；`TodoRepository` 负责 `todos-v1.json` 的加锁读写、备份与校验；`TodoStore`（`@MainActor` 观察者）持有内存状态并在变更后 `reloadTimelines`。入口：`TodoListView`、`SetTodoCompletionIntent`。

**外观模型（Core/TodoAppearance, Core/ReadableModels）**
`TodoAppearance` 是根结构，含 `defaultMarker`、`markerStyle`、`widget: WidgetAppearance`；`ReadableSettings` 由 `WidgetAppearance.readable` 组装。被 `WidgetAppearanceEditor`、`WallpaperEditorView`、小组件渲染共同读取。

**可读性层（Shared/ReadableLayer, Shared/TodoWidgetContent, Shared/WidgetBackgroundView）**
`ReadableTone` 统一算文字色/深浅/蒙层色/是否启用；`ScrimView` 画蒙层（在背景层）；`TextStyleModifier` 给文字加阴影；`TodoWidgetContent` 排内容。

**小组件（Widget/TodoWallpaperWidget, Shared/SetTodoCompletionIntent）**
`TodoWidgetProvider` 读 App Group 数据并预生成背景位图；`TodoWidgetView` 组合内容层与 `containerBackground`；点击走 AppIntent 直接改共享文件再 `reloadTimelines`。

**照片与相册（App/WidgetPhotoStore, App/WidgetAlbumPicker, Core/PhotoComposition）**
`WidgetPhotoStore` 把 Photos 数据缩到 1536px（照片）/512px（标记）写进 App Group；`AlbumReader.prepare` 用 PhotoKit 请求约 1536px、允许 iCloud 网络的目标图，逐张写入共享 actor 的有记录事务；单张失败跳过，全部或超过半数失败/取消整体回滚，外观落盘后才提交相册；`WidgetAlbumRotation.photo(at:)` 决定当天用哪张。照片提交后由 `TodoStore` 统一调度 `PhotoAnalysisService`，不在选图 MainActor 解码原图作分析。

**壁纸（Wallpaper/*）**
`WallpaperEditorModel` 状态机 + `WallpaperLiveCanvas`（实时 UIKit 层）+ `WallpaperRenderer`（CoreGraphics 合成）+ `WallpaperDraftStore`（草稿）。

**日历/提醒导入（App/CalendarImportView）**
`CalendarReader` 读取 EventKit，转成 `TodoImportCandidate`。

**共享存储与迁移（Core/TodoSharedStorage）**
提供 App Group 目录、迁移锁与迁移回执。

**撤销与编辑页（App/EditorUndoState, Core/EditorHistory）**
`EditorUndoState` 保存快照式撤销栈；`EditorInteractionContext` 把连续手势合并为一次撤销。

## b. 持久化与数据格式

App Group 容器下（`TodoSharedStorage.sharedDirectory()` 返回 `<group>/TodoWallpaper`）：

| 文件 | 写入者 | 读取者 | 格式 | 备注 |
| --- | --- | --- | --- | --- |
| `todos-v1.json` | App / AppIntent | App / Widget | JSON，`schemaVersion = 1` | 有 `.backup.json` 与 `.lock` |
| `appearance-v1.json` | App | App / Widget | JSON，`schemaVersion = 1` | 有 `.backup.json` 与 `.lock` |
| `migration-ready-v1.json` | App | App / Widget | JSON 回执 | 迁移完成标记 |
| `appgroup-migration-v1.json` | App | App | JSON 回执 | 旧目录迁移确认 |
| `WidgetPhotos/widget-photo-<UUID>.jpg` | App | Widget | JPEG | 最长边 1536 |
| `MarkerImages/marker-image-<UUID>.png` | App | App / Widget | PNG | 最长边 512 |
| `AnalysisCache/<完整上下文>.json` | App utility 批次 | App / Widget Provider | schemaVersion=1，request + 三锚点原始统计 | 单封套原子写入 |
| `AnalysisRequests/<完整上下文>.json` | Widget Provider | App utility 批次 | PhotoAnalysisRequest | 原子发布后发公开 Darwin 通知 |

UserDefaults（实际签名后的 App Group suite）：旧 `readable.analysis.<图片名>.<锚点>` 不包含裁剪/底色/比例，生产不再复用，只保留清理兼容。`ReadableSettingsMigration` 会一次性读取并删除旧键 `readable.anchor` / `readable.intensity` / `readable.scrimOverride` / `readable.shadowPreset` / `readable.scrimHeightRatio`。`AppearanceStore` 可注入独立 defaults 后端供旧键兼容检查；实际生产读写上述原子文件。

字段表（只列已从源码确认的字段；完整默认值以源码为准）：

`TodoAppearance`：`schemaVersion = 1`、`defaultMarker: TodoMarker`、`markerStyle: MarkerStyle`、`widget: WidgetAppearance`。
`WidgetAppearance`：`theme`、`backdrop`、`panelColor`、`followsSystemText`、`textColor`、`font`、`weight`、`fontSize`(12…20)、`markerOverride: TodoMarker?`、`markerStyle`、`spacing`(-10…40)、`compact`、`maximumItems`(1…10)、`completed`、`completedTextStyle`、`completedTextColor`、`showsSeparators`、`header: WidgetHeaderAppearance?`、`backgroundPhotoName`、`backgroundCrop`、`backgroundPhotoOpacity`(0…1)、`photoRotation`、`systemMaterial`、`showsFooter`、`maximumTitleLines`(1…2)、`unifiedMarkers`、`hidesCompletedTasks`、`readableAnchor`、`readableIntensity`、`readableScrimOverride`(0…0.8)、`readableHeightRatio`(0.25…0.7)、`readableShadowPreset`、`readableEdgeInset`（居中存储允许有限值；顶部/底部兼容旧 -40…40，编辑与渲染夹取到 -12…40）。
`WidgetHeaderAppearance`：`text`(≤40 无换行)、`fontSize`(12…32)、`color`、`followsTextColor`、`showsTitle`、`showsSummary`、`horizontalPosition`(0…1)、`topInset`(0…24，已不参与布局)。
`ReadableSettings`：`anchor`、`intensity`、`scrimOverride: Double?`、`heightRatio`、`shadowPreset`、`edgeInset`。
`WidgetAlbumRotation`：`title`(≤100)、`photos`(1…60)、`anchor: Date`、`enabled`。
`MarkerStyle`（`Core/TodoAppearance.swift`）：`size`(8…48, 18)、`emojiSize`(8…48, 22)、`gap`(0…32, 10)、
`verticalOffset`(-16…16, 0)、`lineWidth`(0.3…6, 1.5)、`followsTextColor`(Bool, true)、`fill`/`stroke`(WallpaperColor)、
`completedColor`(默认绿 0.2/0.75/0.4)、`completion`(MarkerCompletion, .checkShapes)、`completionEmoji`(默认 ✅，需 EmojiInput 校验)。
全部字段非可选；`validate()` 逐项检查上述范围与颜色合法性。

`PhotoCrop`（`Core/PhotoComposition.swift`）：`zoom`(1…4, 1)、`panX`(-1…1, 0)、`panY`(-1…1, 0)；
三个字段都要求 `isFinite`；非可选。裁剪框由 `frame(source:canvas:)` 计算。

`WallpaperSettings`（`Wallpaper/WallpaperSettings.swift`）：`size`(WallpaperSize, 1890×4096)、`canvasAspect`(Double?, 9/19.5)、
`backgroundZoom`(1…4, 1)、`backgroundPanX`/`backgroundPanY`(-1…1, 0)、`customPosition`(false)、`panelX`/`panelY`(0…1, 0.5)、
`panelWidth`(0.3…0.96, 0.88)、`automaticHeight`(true)、`panelHeight`(0.12…0.94, 0.38)、`cornerRadius`(0…80, 24)、
`glassOpacity`(0…0.85, 0.22)、`darkGlass`(true)、`blurRadius`(0…45, 22)、`borderOpacity`(0…1, 0.25)、`highlight`(0…0.6, 0.12)、
`padding`(8…48, 20)、`includeCompleted`(false)、`maximumItems`(Int, 8)、`fontSize`(Double, 18)、`font`/`weight`/`textColor`、
`lineSpacing`(4)、`itemSpacing`(12)、`alignment`(.leading)、`completionStyle`(.strikeAndDim)。
`validated()` 先把 `aspectRatio` 限制在 0.25…2，其余越界值按上表 `c(...)` 夹取（不抛错，除尺寸非法）。

迁移：`ReadableSettingsMigration.take()` 主 App 启动时执行一次并删除旧键；`TodoMigration` 负责旧目录 → App Group 的一次性迁移，用 `migration-ready-v1.json` 与文件锁保证幂等。

## c. 关键调用链

**改一个参数**：编辑页控件 → `widget.wrappedValue.xxx = …` → `TodoStore.setAppearance` → `validate()`（失败则 `clampedForEditing()` 规范化数值并重试；语义错误仍拒绝）→ 成功立即清除校验错误，返回 Bool → 内存赋值 → `appearanceDirty = true` → `scheduleAppearanceSave()`（800ms 去抖）→ `saveAppearance` → `AppearanceRepository.save` → `WidgetCenter.reloadTimelines`。存储错误单独保留，实际 IO 成功才清除，避免同值 setter 隐藏损坏/未来版本文件保护。拖动期间 `PreciseSlider` 调用 `editorInteraction.begin/end`，`TodoStore.beginAppearanceInteraction` 会 `defersAppearanceSave = true`，松手才落盘。撤销检查接收结果，失败保留可重试历史。

**选照片**：`PhotosPicker` → `selection.loadTransferable(Data)` → `WidgetPhotoStore.importPhoto`（缩到 1536、写 App Group）→ 更新外观 → `TodoStore` 结束交互后 400ms 去抖 → utility 串行服务读取已落盘照片并分析 → 原子写结果 → MainActor 发布 `analysisRevision`。相册提交后同一路径，今天图片先算，再逐张分析所有照片；crop/opacity/有效明暗变化使整个相册旧变体失效并重算。旧 generation 取消后不发布 UI 结果；删除版本拒绝在途回写。

**Provider**：`getSnapshot` / `getTimeline` 起始先 `AppearanceStore.clearMemoryCache()`。按 `context.displaySize` 的真实比例读取结果，缺失则登记原子请求文件；系统明暗且照片半透明时登记两种底色。entry 携实际比例和两个底色所需分析快照，防止另一尺寸 Provider 清缓存或冷进程渲染导致回退。`WidgetPhotoCache.prepared` 仍只预生成背景位图；Widget 不计算图片统计。相册生成今天/明天两个 entry，`policy = .after(明天)`，否则单 entry `.never`。

**点按完成**：Widget 行的 `Button(intent: SetTodoCompletionIntent(taskID:completed:))` → `perform()` → `TodoSharedStorage.widgetRepository().setCompleted` → `defer` 里 `reloadTimelines`。

**渲染管线**：`containerBackground` → `WidgetBackgroundView`（照片 → 裁剪框 `photoCrop.frame(source:canvas:)` → 不透明度 → `ScrimView` 蒙层）→ `TodoWidgetContent`（`WidgetLayoutMetrics` 度量 → `header` → 行 `task` → `title` 内文字与日期加 `.readableText`）→ 底部说明。编辑页预览复用同样的 `WidgetBackgroundView` + `TodoWidgetContent`。

**相册每日轮换**：`WidgetAppearance.photoName(at:)`，若 `photoRotation.enabled` 用 `album.photo(at: date)`，否则 `backgroundPhotoName`。

## d. 可读性层

- `ScrimView`：底部/顶部用 `LinearGradient`，三个 stop（1.0 / 0.45 / 0 倍强度），高度 = `min(高度, 高度 × heightRatio + max(0, extraInset))`；居中用 `RadialGradient`（中心 `.center`，`endRadius = 高度 × 0.55`，按有符号的 `extraInset` 偏移）。
- `TextStyleModifier`：按 `ReadabilityIntensity` 取 `shadowOpacityMultiplier`（0.5/0.8/1.1）与 `shadowRadiusScale`（0.7/0.85/1.0）；配方来自 `ShadowRecipes`，默认 `lightTextRecipe = I`、`darkTextRecipe = J`。
- 套了阴影的：标题栏文字、任务标题、日期、"N 未完成"、底部说明、标记视图；摘要只套一次。行分隔线画在行 overlay，不参与阴影链。文字、标记与背景使用同一 `ReadableRules.permitsEffects` 策略，实际着色模式以及锁屏 family 都禁用阴影和蒙层。
- 颜色判断：`ReadableTone.resolve` 用线性亮度阈值 **0.179** 判定深浅并给出 `scrimColor`；`TodoWidgetContent.foreground` 与 `ReadableResolver.scrim` 都走它。第三处历史实现 `TextLegibility.readable` 仍在壁纸渲染中使用（未统一）。
- 强度与 Scrim 优先级：`scrimOverride`（手动）> `autoScrim(analysis:isLightText:)`；后者根据原始亮度/对比度与当前文字深浅算基础值，再乘强度并夹取到 0…0.8。无分析时基础值为 0.4，弱/标准/强最终为 0.28/0.4/0.52。
- `edgeInset`：顶部/底部锚点作为该方向的 padding（可为负）；居中锚点作为 `offset(y:)`。与 `header.topInset` 无耦合，后者已不参与布局。
- `PhotoAnalysisService`：从已导入的 1536px 文件用 ImageIO 取最大边 128px 缩略图（含方向变换），纯 CoreGraphics 按实际 crop、画布比例、透明度与白/0.09 深色底色合成一次 32×32 位图，再分别统计 top 前 40%、center 中间 40%、bottom 后 40%。luma = 0.2126R+0.7152G+0.0722B（sRGB 近似），contrast = min(1, 标准差/0.35)。`ReadableRules.scrim` 继续运行时按当前文字深浅执行黑/白映射；新结果只存 meanLuma/contrast，旧 suggestedScrim 仅解码兼容。`ImageAnalyzer` 只服务 UIKit 调试页，生产入口不调用。
- `StyleColorControl` 与标记颜色解算先用 CoreGraphics 转为 sRGB，再夹取 0…1，保留 alpha；不直接把 Display P3 数值解释为 sRGB。

## e. 布局与测量

`WidgetLayoutMetrics.make`：行高 = `max(标记高度, 行高×行数 + 日期高) + padding`；`padding = min(4, spacing×0.8)`（负 spacing 时为 0）；容量 = `(行空间 + spacing) / (行高 + spacing)` 向下取整，再与 `maximumItems` 取小。`WidgetHeaderLayout.make`：`titleY = 0`、标题高度与摘要高度参与 header 高度。CoreText 测量结果按「字体:字重:字号:前 10 条标题」缓存到 `WidgetMeasureCache.heights`（`NSCache`，上限 96）。

## f. 编辑页与撤销

`EditorUndoState` 用 `WidgetEditState`（style + 每个任务的标记）做快照；`EditorInteractionContext` 把一次连续手势合并成一个撤销步。`PreciseSlider`：`SmoothValueSlider`（UISlider + CADisplayLink 每帧 flush）+ `StandardDetent`（吸附半径 = 每点单位 ×4，已吸附时 ×7）+ 数字输入框与"标准"按钮。撤销可恢复外观与任务标记；两个编辑器把全部 current/before/after 快照的图片名交给 TodoStore 保留，GC 不删除这些文件。已导出的 PNG 不随撤销恢复。

## g. 壁纸子系统

`WallpaperSettings`（尺寸、字号、行距、导出质量）→ `WallpaperEditorModel` 驱动 → `WallpaperLiveCanvas` 实时层（面板拖动、手势）→ `WallpaperRenderer` 用 CoreGraphics 合成 → `WallpaperDraftStore` 存草稿（含 `cleanExpired`）。导出通过 `WallpaperShareFile` 写临时文件后分享。

## h. 日历/提醒导入

`CalendarReader`（`EKEventStore`）分别调用 `requestFullAccessToEvents()` 与 `requestFullAccessToReminders()`，任一被拒抛 `CalendarImportError.permission`；不申请写入权限，也不读取 `EKAuthorizationStatus` 数值，只用返回的 Bool。事件按 90 天窗口过滤，转 `TodoImportCandidate`；提醒事项用 `dueDateComponents` 还原日期（缺 calendar 时补当前日历）。

## i. 常量与阈值

| 名称 | 值 | 所在文件:函数 | 含义 |
| --- | --- | --- | --- |
| 亮度阈值 | 0.179 | `Shared/ReadableLayer.swift:ReadableTone.resolve` | 深浅文字分界 |
| 默认 scrim | 0.4 | `Core/ReadableModels.swift:ReadableDefaults` | 无分析时回退 |
| 渐变比例 | 0.45 | `Core/ReadableModels.swift:ReadableDefaults` | 蒙层覆盖高度 |
| Scrim 范围 | 0…0.8 | `Core/ReadableModels.swift:ReadableDefaults` | 手动滑条 |
| 高度比范围 | 0.25…0.7 | `Core/ReadableModels.swift:ReadableDefaults` | 渐变范围滑条 |
| edgeInset | 顶/底 -12…40；居中 ±max(40, (画布高-自然文字高)/2) | `Core/ReadableModels.swift:ReadableRules.insetRange` | 位置偏移 |
| 强度倍率 | 0.7/1.0/1.3 | `Core/ReadableModels.swift:ReadabilityIntensity` | 蒙层 |
| 阴影不透明度倍率 | 0.5/0.8/1.1 | `Core/ReadableModels.swift:ReadabilityIntensity` | 阴影 |
| 阴影半径缩放 | 0.7/0.85/1.0 | `Core/ReadableModels.swift:ReadabilityIntensity` | 阴影 |
| 分析缩图 | 128px 解码 / 32×32 合成 | `App/PhotoAnalysisService.swift:PhotoAnalysisService` | 后台采样尺寸 |
| 对比度归一 | 0.35 | `App/ImageAnalyzer.swift:ImageAnalyzer` | 标准差基准 |
| 照片最长边 | 1536 | `App/WidgetPhotoStore.swift:WidgetPhotoStore` | 导入缩放 |
| 标记图最长边 | 512 | `App/WidgetPhotoStore.swift:WidgetPhotoStore` | 导入缩放 |
| 背景缓存最长边 | 1024 / 768 | `Shared/WidgetBackgroundView.swift:WidgetPhotoCache` | 解码与预生成 |
| 照片上传上限 | 80 MB | `App/WidgetPhotoStore.swift:WidgetPhotoStore` | 数据保护 |
| 外观去抖 | 800 ms | `App/TodoStore.swift:TodoStore` | 保存延迟 |
| 吸附半径 | 4pt（已吸附 7pt） | `Core/EditorHistory.swift:StandardDetent` | PreciseSlider |
| 相册上限 | 60 张 | `Core/PhotoComposition.swift:WidgetAlbumRotation` | 轮换数量 |
| 日历窗口 | 90 天 | `App/CalendarImportView.swift:CalendarReader` | 导入范围 |
| 最大行数 | 10 | `Core/TodoAppearance.swift:WidgetAppearance` | 小组件行数 |

### 阴影配方表（`Core/ReadableModels.swift` → `ShadowRecipes`）

| 编号 | 名称 | 层数 | 各层 radius / y / 不透明度 | 颜色 | 用途 |
| --- | --- | --- | --- | --- | --- |
| A | 单层 | 1 | 2.5 / 1.0 / 0.35 | 黑 | 浅色文字候选 |
| B | 双层 | 2 | 1.0 / 0.5 / 0.45；3.0 / 1.0 / 0.25 | 黑 | 浅色文字候选 |
| C | 宽柔 | 2 | 2.0 / 1.0 / 0.40；8.0 / 2.0 / 0.25 | 黑 | 浅色文字候选 |
| D | 无阴影 | 0 | — | — | 浅色文字候选 |
| I | 当前默认 | 2 | 0.8 / 0.5 / 0.30；2.0 / 1.0 / 0.18 | 黑 | **`ReadableDefaults.lightTextRecipe`** |
| E | 当前 | 1 | 1.0 / 0.5 / 0.35 | 白 | 深色文字候选 |
| F | 细光晕 | 2 | 1.5 / 0.5 / 0.60；4.0 / 1.0 / 0.35 | 白 | 深色文字候选 |
| G | 宽光晕 | 2 | 2.0 / 1.0 / 0.50；8.0 / 2.0 / 0.40 | 白 | 深色文字候选 |
| H | 无阴影 | 0 | — | — | 深色文字候选 |
| J | 当前默认 | 1 | 1.0 / 0.5 / 0.40 | 白 | **`ReadableDefaults.darkTextRecipe`** |

实际生效前还会乘强度：不透明度 × `shadowOpacityMultiplier`（0.5 / 0.8 / 1.1），半径 × `shadowRadiusScale`（0.7 / 0.85 / 1.0）。
定义位置：`Core/ReadableModels.swift` 的 `ShadowRecipes.light` / `ShadowRecipes.dark`，默认值在 `ReadableDefaults`。

### edgeInset 规则

- 存储：`WidgetAppearance.readableEdgeInset: Double?`；居中校验要求有限值，顶部/底部保留旧 -40…40 文件的解码校验兼容（`Core/TodoAppearance.swift`）。
- 统一边界：`ReadableRules.insetRange` 顶部/底部返回 -12…40，居中返回 `±max(40, (canvasHeight-textHeight)/2)`；`ReadableRules.inset` 同时处理夹取和非有限值。
- 滑条范围、数值 setter、切换锚点、几何改变后的夹取以及真实渲染都调用上述规则。`TodoWidgetContent` 对居中使用未扣除偏移的自然内容高度，利用 `ReadableGeometryPreference` 回传编辑器；不会在 `body` 直接改业务状态。
- 作用位置：顶部锚点 = `padding(.top, edgeInset)`；底部锚点 = `padding(.bottom, edgeInset)`；居中锚点 = `offset(y: edgeInset)`，均作用在 `TodoWidgetContent.body` 的整个文字块上（含标题栏、列表与底部说明）。
- 与蒙层的关系：`WidgetBackgroundView` 把 `edgeInset` 作为 `scrimExtraInset` 传给 `ScrimView`；顶部/底部覆盖高度的负增量按 0 计，居中径向蒙层保留偏移方向。
- 中心蒙层必须与文字使用相同有效偏移：预览传入 Preference 几何，Widget 背景按真实 `widgetContentMargins` 换算内容区域并复用 `WidgetContentLayout.make`，不会直接沿用另一尺寸保存的中心偏移。
- 与 `header.topInset` 的关系：后者已不参与布局（`WidgetHeaderLayout.titleY = 0`），仅保留解码兼容。

## j. 线程与并发

主线程只提交/取消请求、管理交互状态与 400ms 结束去抖、按 generation 接收 revision 通知，正文读取已暖内存或 entry 快照。`PhotoAnalysisService` actor 的单一 utility 串行队列负责缓存枚举/批次失效、请求组装、ImageIO 128px 解码、CG 32×32 合成与三锚点分析、结果原子写入。今天图片与批次结束各合并一次 Widget 刷新；命中已有文件的批次也发布最终 analysisRevision，确保冷启动自动数值更新。取消 token 的 NSLock 只保护布尔值，不跨 IO；`AppearanceStore` 内存 NSLock 只保护 cache/revision/imageVersion，独立文件锁串行化 IO。锁外读后复核 memoryRevision，写入校验删除版本并检查源文件仍存在，避免旧任务复活已删除图片。`TodoRepository`、`AppearanceRepository`、`TodoMigration` 原有 O_EXLOCK 不变。

### 图片分析请求与事件闭环

- `PhotoAnalysisRequest` 的稳定标识包括图片名、zoom/panX/panY、opacity、实际 canvasAspect 与有效底色；opacity=1 时明暗归一。三种预览比例和 Widget 登记的实际比例都参与分析，改变相册参数前先保存实际比例再失效。
- `AnalysisRequests` 原子文件先可见，再通过公开 Darwin 通知提示 App。观察者由生产 TodoStore 生命周期持有；注入测试 store 不注册系统观察者。启动、回到前台和存活期间请求事件都会补算，body 无登记/分析/通知注册副作用。
- 同参数批次进行中收到晚到请求只标记 rescan，不取消或重复清理当前相册；批末清任务与失效标记后补扫，避免“今天刷新→明天缺失→反复全清”的循环。实际参数改变仍立即取消旧 generation，并在交互结束后重新计时 400ms。
- 编辑页通过事件提交当前预览图与比例优先级；服务顺序为今天图片、当前预览图片、剩余相册，且当前比例先算。主线程不执行文件扫描或失效；400ms 后所有批次 IO 均在 utility 队列。
- `removeAnalysis(for:)` 删除旧 defaults、所有文件变体与待算请求；`cachedPhotoNames()` 和 `cleanOrphanAnalysis(existing:)` 为后续图片回收提供统一接口，不要求调用方猜缓存路径。
- 生产纯 CG 分析由 `native-tools/check-photo-analysis.sh` 独立编译执行；上下/左右色块验证方向、裁剪、透明度、底色、实际比例、后台执行、取消、文件后端与相册重算，iOS probe 另验证交互去抖和 observable 刷新。

## 第3组：导入事务、回收与读取快照

`WidgetPhotoStore.shared` 是 App 内所有照片/标记导入的共同 actor。相册先写 `PhotoImports/<UUID>.json` 名称日志；串行请求/编码一张后再处理下一张，高质量非 degraded 回调只消费一次，取消同时取消 PhotoKit 请求。成功数大于零且失败不超过一半才允许发布，部分成功提示跳过数。父编辑器先同步原子保存外观，再结束事务；发布后到达的取消不得删除已被引用的图。异常回滚只删除本事务 UUID 文件，不触碰其他导入。

回收在启动、相册提交后、移除照片后进入同一 actor，导入活跃时跳过。`PhotoAssetGarbageCollector` 先验证 todos、appearance 及可恢复备份/恢复归档，再收集全部候选，任一读取失败不删除。保留当前全部引用（含禁用相册）、所有任务标记、两个编辑器撤销快照及备份；只处理正确目录中的规范 UUID 普通文件，拒绝符号链接，创建或修改不足 10 分钟均保留。删除失败留待后续重试。回收后通过 AppearanceStore 同步失效所有已删照片变体并清理无源分析键。损坏的历史恢复归档也会使回收跳过，优先数据可恢复性。

迁移提供 `TodoRepositorySnapshot(repository, document)`；App reload、Provider read 直接使用已校验 document，既有 prepare/readyRepository 包装继续供 Intent 等使用。未增加跨事务缓存，迁移锁顺序、回执发布和每次事务文件锁不变。existingSnapshot 的 JSON 与原始 bytes 也来自同一次读取。

## 第4组：日期缓存与交互结束语义

TodoSchedule.label 由私有 ScheduleLabelFormatters 缓存两种短格式，在 NSLock 下使用，autoupdatingCurrent 的地区、日历与时区配合系统通知失效；格式化不改浮动日期组件或JSON。PhotoMotionView 的组合会话最后一个结束才提交，有任何正常结束便保留当前状态，全取消才回滚。微调走 EditorUndoState.coalescingContext 的显式 begin/end，500ms 同键连点一组，其他交互/页面结束会取消旧定时器；WallpaperSettings.nudged 复用既有一个导出像素的计算公式。壁纸 drawText 不再保留死 shadow 参数，没有旧阴影控件或绘制；TextLegibility.readable 及静态完成态设计保留。
