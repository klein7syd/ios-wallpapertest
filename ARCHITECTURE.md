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
`WidgetPhotoStore` 把 Photos 数据缩到 1536px（照片）/512px（标记）写进 App Group；`AlbumReader.prepare` 批量导入相册；`WidgetAlbumRotation.photo(at:)` 决定当天用哪张。

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

UserDefaults（App Group）：`readable.analysis.<图片名>.<锚点>` 存 `ImageAnalysis` 的 JSON Data；`ReadableSettingsMigration` 会一次性读取并删除旧键 `readable.anchor` / `readable.intensity` / `readable.scrimOverride` / `readable.shadowPreset` / `readable.scrimHeightRatio`。

字段表（只列已从源码确认的字段；完整默认值以源码为准）：

`TodoAppearance`：`schemaVersion = 1`、`defaultMarker: TodoMarker`、`markerStyle: MarkerStyle`、`widget: WidgetAppearance`。
`WidgetAppearance`：`theme`、`backdrop`、`panelColor`、`followsSystemText`、`textColor`、`font`、`weight`、`fontSize`(12…20)、`markerOverride: TodoMarker?`、`markerStyle`、`spacing`(-10…40)、`compact`、`maximumItems`(1…10)、`completed`、`completedTextStyle`、`completedTextColor`、`showsSeparators`、`header: WidgetHeaderAppearance?`、`backgroundPhotoName`、`backgroundCrop`、`backgroundPhotoOpacity`(0…1)、`photoRotation`、`systemMaterial`、`showsFooter`、`maximumTitleLines`(1…2)、`unifiedMarkers`、`hidesCompletedTasks`、`readableAnchor`、`readableIntensity`、`readableScrimOverride`(0…0.8)、`readableHeightRatio`(0.25…0.7)、`readableShadowPreset`、`readableEdgeInset`(-40…40)。
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

**改一个参数**：编辑页控件 → `widget.wrappedValue.xxx = …` → `TodoStore.setAppearance` → `validate()` → 内存赋值 → `appearanceDirty = true` → `scheduleAppearanceSave()`（800ms 去抖）→ `saveAppearance` → `AppearanceRepository.save` → `WidgetCenter.reloadTimelines`。拖动期间 `PreciseSlider` 调用 `editorInteraction.begin/end`，`TodoStore.beginAppearanceInteraction` 会 `defersAppearanceSave = true`，松手才落盘。

**选照片**：`PhotosPicker` → `selection.loadTransferable(Data)` → `WidgetPhotoStore.importPhoto`（缩到 1536、写 App Group）→ 若在选图处则 `ImageAnalyzer.analyzeAllAnchors` → `AppearanceStore.setAnalysis` → `widget.wrappedValue = next` → 落盘 + 刷新。相册：`AlbumReader.prepare`（逐张 `importPhoto`，当前也会算分析）。

**Provider**：`getSnapshot` 读仓库与外观后 `WidgetPhotoCache.prepared`；`getTimeline` 在相册开启时生成今天/明天两个 entry，`policy = .after(明天)`，否则单 entry `.never`。

**点按完成**：Widget 行的 `Button(intent: SetTodoCompletionIntent(taskID:completed:))` → `perform()` → `TodoSharedStorage.widgetRepository().setCompleted` → `defer` 里 `reloadTimelines`。

**渲染管线**：`containerBackground` → `WidgetBackgroundView`（照片 → 裁剪框 `photoCrop.frame(source:canvas:)` → 不透明度 → `ScrimView` 蒙层）→ `TodoWidgetContent`（`WidgetLayoutMetrics` 度量 → `header` → 行 `task` → `title` 内文字与日期加 `.readableText`）→ 底部说明。编辑页预览复用同样的 `WidgetBackgroundView` + `TodoWidgetContent`。

**相册每日轮换**：`WidgetAppearance.photoName(at:)`，若 `photoRotation.enabled` 用 `album.photo(at: date)`，否则 `backgroundPhotoName`。

## d. 可读性层

- `ScrimView`：底部/顶部用 `LinearGradient`，三个 stop（1.0 / 0.45 / 0 倍强度），高度 = `高度 × heightRatio + |extraInset|`；居中用 `RadialGradient`（中心 `.center`，`endRadius = 高度 × 0.55`，按 `extraInset` 偏移）。
- `TextStyleModifier`：按 `ReadabilityIntensity` 取 `shadowOpacityMultiplier`（0.5/0.8/1.1）与 `shadowRadiusScale`（0.7/0.85/1.0）；配方来自 `ShadowRecipes`，默认 `lightTextRecipe = I`、`darkTextRecipe = J`。
- 套了阴影的：标题栏文字、任务标题、日期、"N 未完成"、底部说明。未套的：行分隔线（画在行 overlay，不参与阴影链）、标记视图（`TodoMarkerView` 调用处没有加 `readableText`）。
- 颜色判断：`ReadableTone.resolve` 用线性亮度阈值 **0.179** 判定深浅并给出 `scrimColor`；`TodoWidgetContent.foreground` 与 `ReadableResolver.scrim` 都走它。第三处历史实现 `TextLegibility.readable` 仍在壁纸渲染中使用（未统一）。
- 强度与 Scrim 优先级：`scrimOverride`（手动）> `autoScrim(analysis:) = suggestedScrim × 强度倍率`（clamp 0…0.8）> 无分析时 `ReadableDefaults.scrim = 0.4`。
- `edgeInset`：顶部/底部锚点作为该方向的 padding（可为负）；居中锚点作为 `offset(y:)`。与 `header.topInset` 无耦合，后者已不参与布局。
- `ImageAnalyzer`：缩到 32×32；取样行区间 bottom = 后 40%、top = 前 40%、center = 中间 40%（缓冲区第 0 行是顶部）；luma = 0.2126R+0.7152G+0.0722B（sRGB 近似，不转线性）；contrast = min(1, 标准差 / 0.35)；`suggestedScrim = 0.25 + 0.25×min(1, mean/0.8) + 0.10×contrast`，`mean < 0.25` 时取 ≤0.15，最终 clamp 0.2…0.55（**只对黑蒙层成立**，白蒙层尚未区分）。缓存：`AppearanceStore` 内存字典 + `NSLock`，键 `readable.analysis.<图片名>.<锚点>`，写入/删除时失效；Widget 进程不主动失效。

## e. 布局与测量

`WidgetLayoutMetrics.make`：行高 = `max(标记高度, 行高×行数 + 日期高) + padding`；`padding = min(4, spacing×0.8)`（负 spacing 时为 0）；容量 = `(行空间 + spacing) / (行高 + spacing)` 向下取整，再与 `maximumItems` 取小。`WidgetHeaderLayout.make`：`titleY = 0`、标题高度与摘要高度参与 header 高度。CoreText 测量结果按「字体:字重:字号:前 10 条标题」缓存到 `WidgetMeasureCache.heights`（`NSCache`，上限 96）。

## f. 编辑页与撤销

`EditorUndoState` 用 `WidgetEditState`（style + 每个任务的标记）做快照；`EditorInteractionContext` 把一次连续手势合并成一个撤销步。`PreciseSlider`：`SmoothValueSlider`（UISlider + CADisplayLink 每帧 flush）+ `StandardDetent`（吸附半径 = 每点单位 ×4，已吸附时 ×7）+ 数字输入框与"标准"按钮。撤销可恢复外观与任务标记；**不能**恢复已写入 App Group 的图片文件或已导出的 PNG。

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
| edgeInset | -40…40 | `Core/ReadableModels.swift:ReadableDefaults` | 位置偏移 |
| 强度倍率 | 0.7/1.0/1.3 | `Core/ReadableModels.swift:ReadabilityIntensity` | 蒙层 |
| 阴影不透明度倍率 | 0.5/0.8/1.1 | `Core/ReadableModels.swift:ReadabilityIntensity` | 阴影 |
| 阴影半径缩放 | 0.7/0.85/1.0 | `Core/ReadableModels.swift:ReadabilityIntensity` | 阴影 |
| 分析缩图 | 32×32 | `App/ImageAnalyzer.swift:ImageAnalyzer` | 采样尺寸 |
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

## j. 线程与并发

主线程：所有 SwiftUI 视图、`TodoStore`、编辑页、`WallpaperEditorViewModel`。后台：`WidgetPhotoStore.importMarker/importPhoto` 是 `actor`；`AlbumReader.prepare` 是 async；`ImageAnalyzer` 在调用方线程执行（选图处目前在 Task 内）。锁：`TodoRepository`、`AppearanceRepository`、`TodoMigration` 用 `O_EXLOCK` 文件锁；`AppearanceStore` 缓存用 `NSLock`；`MarkerBitmapCache` / `WidgetPhotoCache` 用 `NSCache`（线程安全）。
