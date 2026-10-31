# FILE_MAP

所有路径相对 `TodoWallpaper/`。`tools/check_handoff.sh` 严格检查文件、实际声明与所有 Swift 登记覆盖，逐项输出非零计数；其负向回归也在 CI 执行。主要类型不是文件内所有私有声明的清单。

| 路径 | Target | 职责 | 主要类型 |
| --- | --- | --- | --- |
| App/CalendarImportView.swift | App | 日历/提醒事项导入 | CalendarSource, CalendarImportError, CalendarReader |
| App/EditorUndoState.swift | App | 编辑页撤销栈与 interaction 上下文 | EditorInteractionContext, EditorInteractionKey, EditorUndoState |
| App/ImageAnalyzer.swift | App | 仅可读性调试页的 UIKit 分析兼容入口，生产照片走统一后台服务 | ImageAnalyzer |
| App/PhotoAnalysisService.swift | App + macOS检查 | utility 串行 ImageIO/CG 分析、整批缓存更新与公开请求通知观察 | PhotoAnalysisService, PhotoAnalysisOutput, PhotoAnalysisRequestObserver |
| App/InspectorComponents.swift | App | 共享工具选择器与可滚动参数容器 | EditorToolPicker, InspectorViewport, InspectorGroupTitle |
| App/MarkerEditors.swift | App | 标记编辑控件、PreciseSlider、StyleColorControl | MarkerChoiceEditor, EmojiEntry, PreciseSlider |
| App/PhotoMotionView.swift | App | 保留图层裁剪与组合手势，全部取消才回滚 | PhotoMotionView, WidgetPhotoMotionSurface |
| App/ReadableLayerDebugView.swift | App | 可读性调试页（5 张测试图） | TestImageFactory, Sample, ReadableLayerDebugView |
| App/ShadowCompareView.swift | App | 阴影配方对比页 | ShadowCompareView |
| App/SmoothValueSlider.swift | App | UISlider 包装，按显示帧合并回写 | SmoothValueSlider, Coordinator, FrameProxy |
| App/TodoStore.swift | App | 待办/外观快照、去抖保存、后台分析调度与图片保留/回收入口 | TodoStore |
| App/TodoWallpaperApp.swift | App | App 入口、五页 TabView、关于页（含 #if DEBUG 调试入口） | TodoWallpaperApp, EditorRequest, DisplayError |
| App/WidgetAlbumPicker.swift | App | PhotoKit目标尺寸逐张导入、失败计数、取消与事务提交 | PhotoAlbumRow, AlbumError, AlbumImageRequest, PreparedAlbum, AlbumReader |
| App/WidgetAppearanceEditor.swift | App | 小组件编辑页：主题/标题/文字/标记/内容 五个工具页 | WidgetEditorTool, TaskMarkerState, WidgetEditState, WidgetAppearanceEditor |
| App/WidgetPhotoStore.swift | App | 共享actor缩图写入、相册名称事务日志与保守回收 | WidgetPhotoStore |
| Core/AppearanceRepository.swift | App + Widget | appearance-v1.json 读写与备份 | AppearanceRepository |
| Core/EditorHistory.swift | App + Widget | 分组撤销、图片引用快照与标准点吸附 | EditorHistory, Step, EditorStandards |
| Core/EditorUIState.swift | App + Widget | 五页导航、编辑工具、预览与检查器空间分配 | AppPage, WallpaperTool, AppNavigationState |
| Core/MarkerDrawing.swift | App + Widget | 标记位图绘制 | MarkerDrawing |
| Core/MarkerImageReference.swift | App + Widget | 标记图片命名与读取 | MarkerImageReference |
| Core/NativeTypography.swift | App + Widget | CTFont 构造与字体家族 | NativeTypography, FontBox |
| Core/PhotoAssetMaintenance.swift | App + Widget | 导入失败阈值、引用集合、保守孤立图片回收 | PhotoAssetReferences, PhotoImportProgress, PhotoAssetGarbageCollector |
| Core/PhotoComposition.swift | App + Widget | PhotoCrop、相册轮换、每日时间线 | PhotoCrop, WidgetAlbumRotation, WidgetDayTimeline |
| Core/PhotoAnalysisRequest.swift | App + Widget | 完整分析上下文、稳定缓存标识与不透明底色归一 | PhotoAnalysisRequest |
| Core/ReadableModels.swift | App + Widget | 可读性规则、动态偏移边界、强度、阴影配方、原始图片分析 | TextAnchor, ReadableRules, ReadableContentGeometry, ImageAnalysis |
| Core/TextLegibility.swift | App + Widget | 亮度、对比度、可读色（壁纸仍在用） | TextLegibility |
| Core/TodoAppearance.swift | App + Widget | TodoAppearance / WidgetAppearance / 标记与颜色模型 | MarkerKind, TodoMarker, EmojiInput, TodoAppearance, WidgetAppearance |
| Core/TodoImport.swift | App + Widget | 导入候选与稳定来源身份 | TodoImportCandidate, TodoImportIdentity |
| Core/TodoItem.swift | App + Widget | TodoItem / TodoDocument / 排序规则 | TodoItem, TodoDocument, TodoDataError |
| Core/TodoRepository.swift | App + Widget | 加锁校验、备份、迁移快照与可恢复图片引用 | TodoRepository, Header |
| Core/TodoSchedule.swift | App + Widget | 浮动日期组件、兼容校验及两种短格式缓存 | TodoSchedule, ScheduleLabelFormatters |
| Core/TodoSharedStorage.swift | App + Widget | App Group目录、迁移锁/回执、仓库及已校验文档快照 | TodoWidgetConstants, TodoSharedStorage, TodoRepositorySnapshot, TodoMigrationReceipt, TodoMigration |
| Core/VisualTypes.swift | App + Widget | 共享颜色、字体、字重与对齐枚举 | WallpaperColor, WallpaperFont, WallpaperWeight |
| Core/WidgetHeaderLayout.swift | App + Widget | 标题栏度量 | WidgetHeaderLayout |
| Core/WidgetLayout.swift | App + Widget | 小组件行高、容量、间距计算 | WidgetLayoutMetrics, WidgetRowMetrics, WidgetTitleMeasure, WidgetPreviewState |
| Core/WidgetPhotoReference.swift | App + Widget | 小组件照片命名与读取 | WidgetPhotoReference |
| Shared/AppearanceStore.swift | App + Widget | 原子分析封套/请求、短内存锁与后台文件锁、清理接口、旧设置迁移 | AppearanceStore, Key, AppGroup |
| Shared/ReadableLayer.swift | App + Widget | 蒙层、文字/标记阴影、色调、模式门禁与内容几何偏好 | ScrimView, TextStyleModifier, ReadableTone, ReadableGeometryPreference |
| Shared/SetTodoCompletionIntent.swift | App + Widget | 小组件点按完成的 AppIntent | SetTodoCompletionIntent |
| Shared/TodoMarkerView.swift | App + Widget | 标记视图与位图缓存 | TodoMarkerView, MarkerBitmapCache |
| Shared/TodoWidgetContent.swift | App + Widget | 小组件内容层与共享自然高度：标题栏、行、阴影、锚点对齐 | TodoWidgetContent, WidgetContentLayout, WidgetMeasureCache |
| Shared/WidgetBackgroundView.swift | App + Widget | 背景层：照片、裁剪、不透明度、蒙层、准备缓存 | WidgetBackgroundView, WidgetPhotoCache, WidgetGlassBackground |
| Tests/D34Checks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | D34Checks |
| Tests/EditorRefinementChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | EditorRefinementChecks |
| Tests/FeedbackRepairChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | FeedbackRepairChecks |
| Tests/FeedbackRepairRenderChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | FeedbackRepairRenderChecks |
| Tests/MediaInteractionChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | MediaInteractionChecks |
| Tests/MigrationChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | MigrationChecks |
| Tests/NativeUIProbe.swift | App（Simulator Debug + TODO_UI_CHECKS） | 模拟器原生像素、实际交互/撤销和App界面检查 | NativeUIProbe, ProbeTrackingSlider |
| Tests/PhotoAssetMaintenanceChecks.swift | 独立 macOS 原生检查 | 导入阈值、回收与撤销/备份保留回归 | PhotoAssetMaintenanceChecks |
| Tests/PhotoRepairChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | PhotoRepairChecks |
| Tests/PhotoAnalysisChecks.swift | 独立 macOS 原生检查 | 实际CG分析、文件后端、取消与相册批次可执行回归 | PhotoAnalysisChecks |
| Tests/PhotoRepairRenderChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | PhotoRepairRenderChecks |
| Tests/RepositoryChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | RepositoryChecks |
| Tests/UIStateChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | UIStateChecks |
| Tests/WallpaperRenderChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | WallpaperRenderChecks |
| Tests/WidgetFeedbackChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | WidgetFeedbackChecks |
| Tests/WidgetFeedbackRenderChecks.swift | 独立 macOS 原生检查 | 由原生检查脚本执行的生产状态/渲染回归 | WidgetFeedbackRenderChecks |
| Wallpaper/WallpaperDraftStore.swift | App | 壁纸草稿存取与清理 | WallpaperLoadedDraft, WallpaperDraftStore |
| Wallpaper/WallpaperEditorModel.swift | App | 壁纸编辑器状态机 | WallpaperShareFile, WallpaperEditorModel |
| Wallpaper/WallpaperEditorView.swift | App | 壁纸编辑、撤销引用保留与连续微调分组 | WallpaperEditState, WallpaperEditorView, WallpaperFullPreview |
| Wallpaper/WallpaperGeometry.swift | App | 画布比例、导出尺寸、静态字形缓存键与单像素微调 | WallpaperAspect, WallpaperQuality |
| Wallpaper/WallpaperLiveCanvas.swift | App | 实时画布与面板拖动 | WallpaperLiveCanvas, WallpaperLayerSurface, WallpaperLayerView |
| Wallpaper/WallpaperRenderer.swift | App | 壁纸合成渲染 | WallpaperPhotoInfo, WallpaperTextBlock, WallpaperRow, WallpaperLayout, WallpaperRendered, WallpaperRenderer |
| Wallpaper/WallpaperSettings.swift | App | 壁纸设置与尺寸 | WallpaperSize, WallpaperSettings, WallpaperDraft |
| Widget/TodoWallpaperWidget.swift | Widget | Widget bundle：Provider、View、Timeline 策略 | TodoWidgetEntry, TodoWidgetProvider, TodoWidgetView |
| App/LianxinService.swift | App + macOS检查 | 连心资料、可替换 AI 协议与 HTTPS 请求/解码 | LianxinProfile, AIServiceProtocol, LianxinAPIService, MockLianxinService, LianxinWritingRules |
| App/LianxinModel.swift | App | 连心状态、钥匙串密钥与私有目录持久化 | LianxinKeychain, LianxinStorage, LianxinModel, LianxinSystemCredentials |
| App/LianxinView.swift | App | 连心底图话语卡片及 API/提示词设置 | LianxinView |
| App/LianxinWallpaperView.swift | App | 独立连心壁纸预览、调节与相册导出 | LianxinWallpaperRequest, LianxinWallpaperView |
| Core/LianxinPublication.swift | App + Widget | 用户明确发布的文案与底图原子快照 | LianxinPublication |
| Widget/LianxinWidget.swift | Widget | 连心组件五种尺寸及双组件 Bundle | LianxinEntry, LianxinProvider, LianxinWidgetView, LianxinWidget, TodoWallpaperWidgetBundle |
| Tests/LianxinChecks.swift | 独立 macOS 原生检查 | 请求校验、错误处理、发布和凭证隔离 | LianxinChecks |
| Tests/WidgetWrappingChecks.swift | 独立 macOS 原生检查 | 逐项多行、容量与旧数据兼容检查 | WidgetWrappingChecks |
| App/LianxinProvider.swift | App + macOS检查 | 官方服务商预设、输入清洗与凭证迁移策略 | LianxinProviderPreset, LianxinSetupRules, LianxinCredentialStore, LianxinCredentialMigration, LianxinConnectionService, MockLianxinConnection |
| App/LianxinSetupView.swift | App | 服务商、密钥粘贴、连接测试与模型向导 | LianxinSetupView |
| Tests/LianxinWizardChecks.swift | 独立 macOS 原生检查 | 官方预设完整性、清洗、迁移和离线体验 | LianxinWizardChecks |
| Core/ContentMode.swift | App + Widget | 内容模式持久化与样式槽位 | ContentMode |
| Shared/LianxinWidgetContent.swift | App + Widget | 连心共用正文、署名与强制标注 | LianxinWidgetContent |
