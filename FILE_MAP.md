# FILE_MAP

所有路径相对 `TodoWallpaper/`。脚本 `tools/check_handoff.sh` 会校验本表。

| 路径 | Target | 职责 | 主要类型 |
| --- | --- | --- | --- |
| App/CalendarImportView.swift | App | 日历/提醒事项导入 | CalendarSource, CalendarImportError, CalendarReader |
| App/EditorUndoState.swift | App | 编辑页撤销栈与 interaction 上下文 | EditorInteractionContext, EditorInteractionKey, EditorUndoState |
| App/ImageAnalyzer.swift | App | 仅可读性调试页的 UIKit 分析兼容入口，生产照片走统一后台服务 | ImageAnalyzer |
| App/PhotoAnalysisService.swift | App + macOS检查 | utility 串行 ImageIO/CG 分析、整批缓存更新与公开请求通知观察 | PhotoAnalysisService, PhotoAnalysisOutput, PhotoAnalysisRequestObserver |
| App/InspectorComponents.swift | App | 见主要类型（职责待补充） | EditorToolPicker, InspectorViewport |
| App/MarkerEditors.swift | App | 标记编辑控件、PreciseSlider、StyleColorControl | MarkerChoiceEditor, EmojiEntry, PreciseSlider |
| App/PhotoMotionView.swift | App | 照片裁剪手势 | PhotoMotionView, WidgetPhotoMotionSurface |
| App/ReadableLayerDebugView.swift | App | 可读性调试页（5 张测试图） | TestImageFactory, Sample, ReadableLayerDebugView |
| App/ShadowCompareView.swift | App | 阴影配方对比页 | ShadowCompareView |
| App/SmoothValueSlider.swift | App | UISlider 包装，按显示帧合并回写 | SmoothValueSlider, Coordinator, FrameProxy |
| App/TodoStore.swift | App | 外观与待办的内存状态、去抖保存、reloadTimelines | TodoStore |
| App/TodoWallpaperApp.swift | App | App 入口、四页 TabView、关于页（含 #if DEBUG 调试入口） | TodoWallpaperApp, EditorRequest, DisplayError |
| App/WidgetAlbumPicker.swift | App | 相册选择与批量导入（AlbumReader） | PhotoAlbumRow, AlbumError, AlbumReader |
| App/WidgetAppearanceEditor.swift | App | 小组件编辑页：主题/标题/文字/标记/内容 五个工具页 | WidgetEditorTool, TaskMarkerState, WidgetEditState |
| App/WidgetPhotoStore.swift | App | 把 Photos 数据缩到 512/1536 写入 App Group | WidgetPhotoStore |
| Core/AppearanceRepository.swift | App + Widget | appearance-v1.json 读写与备份 | AppearanceRepository |
| Core/EditorHistory.swift | App + Widget | 撤销历史与 StandardDetent 吸附 | EditorHistory, Step, EditorStandards |
| Core/EditorUIState.swift | App + Widget | 见主要类型（职责待补充） | AppPage, WallpaperTool, AppNavigationState |
| Core/MarkerDrawing.swift | App + Widget | 标记位图绘制 | MarkerDrawing |
| Core/MarkerImageReference.swift | App + Widget | 标记图片命名与读取 | MarkerImageReference |
| Core/NativeTypography.swift | App + Widget | CTFont 构造与字体家族 | NativeTypography, FontBox |
| Core/PhotoComposition.swift | App + Widget | PhotoCrop、相册轮换、每日时间线 | PhotoCrop, WidgetAlbumRotation, WidgetDayTimeline |
| Core/PhotoAnalysisRequest.swift | App + Widget | 完整分析上下文、稳定缓存标识与不透明底色归一 | PhotoAnalysisRequest |
| Core/ReadableModels.swift | App + Widget | 可读性规则、动态偏移边界、强度、阴影配方、原始图片分析 | TextAnchor, ReadableRules, ReadableContentGeometry, ImageAnalysis |
| Core/TextLegibility.swift | App + Widget | 亮度、对比度、可读色（壁纸仍在用） | TextLegibility |
| Core/TodoAppearance.swift | App + Widget | TodoAppearance / WidgetAppearance / 标记与颜色模型 | MarkerKind, TodoMarker, EmojiInput |
| Core/TodoImport.swift | App + Widget | 见主要类型（职责待补充） | TodoImportCandidate, TodoImportIdentity |
| Core/TodoItem.swift | App + Widget | TodoItem / TodoDocument / 排序规则 | TodoItem, TodoDocument, TodoDataError |
| Core/TodoRepository.swift | App + Widget | todos-v1.json 读写与校验 | TodoRepository, Header |
| Core/TodoSchedule.swift | App + Widget | 见主要类型（职责待补充） | TodoSchedule |
| Core/TodoSharedStorage.swift | App + Widget | App Group 路径、迁移与锁 | TodoWidgetConstants, TodoSharedStorage, TodoMigrationReceipt |
| Core/VisualTypes.swift | App + Widget | 见主要类型（职责待补充） | WallpaperColor, WallpaperFont, WallpaperWeight |
| Core/WidgetHeaderLayout.swift | App + Widget | 标题栏度量 | WidgetHeaderLayout |
| Core/WidgetLayout.swift | App + Widget | 小组件行高、容量、间距计算 | WidgetLayoutMetrics, WidgetPreviewState |
| Core/WidgetPhotoReference.swift | App + Widget | 小组件照片命名与读取 | WidgetPhotoReference |
| Shared/AppearanceStore.swift | App + Widget | 原子分析封套/请求、短内存锁与后台文件锁、清理接口、旧设置迁移 | AppearanceStore, Key, AppGroup |
| Shared/ReadableLayer.swift | App + Widget | 蒙层、文字/标记阴影、色调、模式门禁与内容几何偏好 | ScrimView, TextStyleModifier, ReadableTone, ReadableGeometryPreference |
| Shared/SetTodoCompletionIntent.swift | App + Widget | 小组件点按完成的 AppIntent | SetTodoCompletionIntent |
| Shared/TodoMarkerView.swift | App + Widget | 标记视图与位图缓存 | TodoMarkerView, MarkerBitmapCache |
| Shared/TodoWidgetContent.swift | App + Widget | 小组件内容层与共享自然高度：标题栏、行、阴影、锚点对齐 | TodoWidgetContent, WidgetContentLayout, WidgetMeasureCache |
| Shared/WidgetBackgroundView.swift | App + Widget | 背景层：照片、裁剪、不透明度、蒙层、准备缓存 | WidgetBackgroundView, WidgetPhotoCache, WidgetGlassBackground |
| Tests/D34Checks.swift | App(Debug) | 见主要类型（职责待补充） | D34Checks |
| Tests/EditorRefinementChecks.swift | App(Debug) | 见主要类型（职责待补充） | EditorRefinementChecks |
| Tests/FeedbackRepairChecks.swift | App(Debug) | 见主要类型（职责待补充） | FeedbackRepairChecks |
| Tests/FeedbackRepairRenderChecks.swift | App(Debug) | 见主要类型（职责待补充） | FeedbackRepairRenderChecks |
| Tests/MediaInteractionChecks.swift | App(Debug) | 见主要类型（职责待补充） | MediaInteractionChecks |
| Tests/MigrationChecks.swift | App(Debug) | 见主要类型（职责待补充） | MigrationChecks |
| Tests/NativeUIProbe.swift | App(Debug) | 见主要类型（职责待补充） | NativeUIProbe, ProbeTrackingSlider |
| Tests/PhotoRepairChecks.swift | App(Debug) | 见主要类型（职责待补充） | PhotoRepairChecks |
| Tests/PhotoAnalysisChecks.swift | 独立macOS检查 | 实际CG分析、文件后端、取消与相册批次可执行回归 | PhotoAnalysisChecks |
| Tests/PhotoRepairRenderChecks.swift | App(Debug) | 见主要类型（职责待补充） | PhotoRepairRenderChecks |
| Tests/RepositoryChecks.swift | App(Debug) | 见主要类型（职责待补充） | RepositoryChecks |
| Tests/UIStateChecks.swift | App(Debug) | 见主要类型（职责待补充） | UIStateChecks |
| Tests/WallpaperRenderChecks.swift | App(Debug) | 见主要类型（职责待补充） | WallpaperRenderChecks |
| Tests/WidgetFeedbackChecks.swift | App(Debug) | 见主要类型（职责待补充） | WidgetFeedbackChecks |
| Tests/WidgetFeedbackRenderChecks.swift | App(Debug) | 见主要类型（职责待补充） | WidgetFeedbackRenderChecks |
| Wallpaper/WallpaperDraftStore.swift | App | 壁纸草稿存取与清理 | WallpaperLoadedDraft, WallpaperDraftStore |
| Wallpaper/WallpaperEditorModel.swift | App | 壁纸编辑器状态机 | WallpaperShareFile, WallpaperEditorModel |
| Wallpaper/WallpaperEditorView.swift | App | 壁纸编辑页 | WallpaperEditState, WallpaperEditorView, WallpaperFullPreview |
| Wallpaper/WallpaperGeometry.swift | App | 画布比例与导出尺寸 | WallpaperAspect, WallpaperQuality |
| Wallpaper/WallpaperLiveCanvas.swift | App | 实时画布与面板拖动 | WallpaperLiveCanvas, WallpaperLayerSurface, WallpaperLayerView |
| Wallpaper/WallpaperRenderer.swift | App | 壁纸合成渲染 | WallpaperPhotoInfo, WallpaperTextBlock, WallpaperRow |
| Wallpaper/WallpaperSettings.swift | App | 壁纸设置与尺寸 | WallpaperSize, WallpaperSettings, WallpaperDraft |
| Widget/TodoWallpaperWidget.swift | Widget | Widget bundle：Provider、View、Timeline 策略 | TodoWidgetEntry, TodoWidgetProvider, TodoWidgetView |
