"""Requirement-level architecture guards, not a simulator or device visual test."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
read = lambda path: (root / path).read_text(encoding='utf-8')
checks = []

def require(condition, description):
    if not condition:
        raise AssertionError(description)
    checks.append(description)

app = read('TodoWallpaper/App/TodoWallpaperApp.swift')
wallpaper = read('TodoWallpaper/Wallpaper/WallpaperEditorView.swift')
widget = read('TodoWallpaper/App/WidgetAppearanceEditor.swift')
marker = read('TodoWallpaper/App/MarkerEditors.swift')
viewport = read('TodoWallpaper/App/InspectorComponents.swift')
extension = read('TodoWallpaper/Widget/TodoWallpaperWidget.swift')
shared = read('TodoWallpaper/Shared/TodoWidgetContent.swift')
require(all(f'.tag(AppPage.{page})' in app for page in ['todos','wallpaper','widget','lianxin','about']), 'Five selectable native TabView root pages including Lianxin')
require('TabView(selection:' in app and 'NavigationStack { WidgetAppearanceEditor(store: store) }' in app, 'Widget editor is real root-tab content')
require('WidgetAppearanceEditor' not in app[app.index('struct AboutView:'):] and 'WidgetAppearanceEditor' not in wallpaper, 'No duplicate pushed Widget-editor entrances')
require('if navigation.isEditing {' not in app and 'primaryTabs' in app and '@StateObject private var wallpaperModel' in app, 'System TabView stays mounted while editing; cached model remains stable')
require('CircularDock' not in wallpaper + viewport and 'toolDock(' not in wallpaper, 'Obsolete circular navigation Dock removed')
require('EditorToolPicker(' in wallpaper and 'EditorToolPicker(' in widget and 'pickerStyle(.segmented)' in viewport, 'Wallpaper and Widget share one system animated tool selector')
require('editor.advancedControls.v1' in read('TodoWallpaper/Core/EditorHistory.swift') and 'Toggle("高级编辑选项"' in app and 'AppStorage(EditorStandards.advancedKey)' in wallpaper + widget, 'About owns the persistent advanced-control switch for both editors')
require('EditorUndoState<' in wallpaper and 'EditorUndoState<' in widget and 'wallpaper.undo' in wallpaper and 'widget.undo' in widget, 'Both editors expose scoped undo actions')
require('onEditingChanged:' in marker and 'editorInteraction' in marker and 'interaction.begin("canvas")' in read('TodoWallpaper/Wallpaper/WallpaperLiveCanvas.swift'), 'Continuous slider and canvas gestures use grouped history')
require('let standard: Double' in marker and '标准节点' in marker and 'Button("标准")' in marker, 'Every slider requires a standard value, visible node and restore action')
for source in [wallpaper,widget,marker]:
    for line in source.splitlines():
        if 'PreciseSlider(' in line:
            require('standard:' in line, 'Slider call declares a standard: ' + line.strip())
require('ZStack(alignment: .bottom)' not in wallpaper and 'inspector(height:' in wallpaper, 'Canvas and inspector receive separate layout space, not overlapping overlays')
require('InspectorViewport' in wallpaper and 'InspectorViewport' in widget, 'Both editors use the same bounded settings viewport')
require('.scrollClipDisabled(false)' in viewport and viewport.count('.clipped()') >= 2, 'Scroll descendants explicitly clipped at viewport boundaries')
require('.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))' in wallpaper, 'Inspector material has an actual continuous clipping shape')
require(all('DisclosureGroup' not in source for source in [wallpaper,widget,marker]), 'Editor controls replace detail pages instead of nesting expanding scroll groups')
require('onChange(of: pageID)' in viewport and 'scrollTo("inspector-top"' in viewport, 'Tool/detail replacement resets its own content anchor, not on slider edits')
require('fixedPreview(height:' in widget and widget.index('fixedPreview(height:') < widget.index('InspectorViewport(') and 'Form {' not in widget, 'Fixed Widget preview is outside the independent settings scroll surface')
require('ForEach(WidgetPreviewFamily.allCases)' in widget and 'family.scale(' in widget, 'Three Widget preview ratios fit their fixed space without distortion')
require('TodoWidgetContent(' in widget and 'TodoWidgetContent(' in extension and 'interactive: false' in widget, 'Preview and real Widget share native content with separate action routing')
require('Button(intent: SetTodoCompletionIntent(' in shared and '.invalidatableContent()' in shared, 'Real Widget retains direct App Intent completion and restore')
require('onPreviewToggle' in shared and 'onPreviewMarker' in shared and 'WidgetPreviewState()' in widget and 'setCompleted(' not in widget, 'Preview trial completion is local; marker taps select editing')
require('editGlobalMarker' not in widget and '全局默认' not in widget and '继承壁纸标记' in widget, 'Widget has no global/wallpaper editor masquerading as its own setting')
require('showsCompletion: false' in wallpaper, 'Wallpaper marker editor excludes completion interaction controls')
require('@ScaledMetric' in shared and 'WidgetLayoutMetrics.make(' in shared, 'System text scaling drives actual Widget row budgeting')
require('maximumSize: family' not in shared and 'min(12, style.markerStyle.gap)' not in shared, 'No hidden 20/24 point marker or 12 point gap caps')
require('widget.markerStyle.gap' in widget and 'appearance.markerStyle.gap' in wallpaper, 'Text settings expose the same marker-gap storage as marker settings')
require('TodoMarkerView(marker: TodoMarker(kind: kind' in marker and 'Picker("标记类型"' not in marker, 'Reusable marker choices show native shape/Emoji samples')
require('MarkerControlVisibility(kind: kind)' in marker and 'if controls.visible' in marker and 'if controls.emoji' in marker, 'Marker parameters use explicit selected-kind capabilities')
require('if !style.followsTextColor' in marker and 'if controls.fill' in marker and 'if controls.stroke' in marker, 'Independent shape colors appear only for active capabilities')
require('if model.hasPhoto' in wallpaper and 'if model.settings.customPosition' in wallpaper and 'if !model.settings.automaticHeight' in wallpaper, 'Inactive photo, position and manual-height controls are absent')
require('DisclosureGroup' not in marker and '精细 RGB' not in marker and 'ColorPicker(' in marker, 'Color editing uses native picker plus swatches without extra RGB disclosure trees')
for forbidden in ['UITabBar.appearance', 'setValue(', 'WebView', 'WKWebView']:
    require(all(forbidden not in source for source in [app,wallpaper,widget,marker]), f'No {forbidden} workaround in edited UI')
require('Picker("完成文字"' not in wallpaper and 'strike: row.item.isCompleted' not in read('TodoWallpaper/Wallpaper/WallpaperRenderer.swift'), 'Static wallpaper has no completed-text interaction controls or rendering')
require('rowPlacement(' in read('TodoWallpaper/Wallpaper/WallpaperRenderer.swift') and '标记与文字间距' in wallpaper + widget + marker, 'Marker and text group alignment shares the explicitly named gap')
require('toggleInspector()' in wallpaper and 'value: navigation.inspectorExpanded' in wallpaper and '.transaction { $0.animation = nil }' not in read('TodoWallpaper/Wallpaper/WallpaperLiveCanvas.swift'), 'Inspector entry points share animation; canvas does not blanket-disable it')
require('editor.wallpaperPreviewScale.v1' in read('TodoWallpaper/Core/EditorHistory.swift') and 'if advanced { PreciseSlider(title: "编辑预览大小"' in wallpaper, 'Editor preview-size preference is advanced-only, separate from exported composition')
require('StandardDetent()' in marker and 'UISelectionFeedbackGenerator().selectionChanged()' in marker and 'value: sliding' in marker, 'Sliders capture the standard node with selection feedback, separate from numeric entry')
require('wallpaperMarkerChoice' in wallpaper and 'usesTaskMarkers = false' in wallpaper and 'model.updateAppearance(editingAppearance)' in wallpaper and 'root.lianxin = value.widget' in wallpaper, 'Uniform wallpaper marker changes reach its own live model despite task overrides')
require('WidgetHeaderAppearance' in read('TodoWallpaper/Core/TodoAppearance.swift') and 'headerControls' in widget and 'heading.showsSummary' in widget and 'Text("待办").font' not in shared, 'Widget title and summary are configurable in shared actual content')
require('WidgetBackgroundView' in widget + extension and 'PhotosPicker(' in widget and 'WidgetPhotoStore' in widget, 'Widget preview and extension share the selected local photo background')
require('CalendarImportView(store: store)' in app and 'requestFullAccessToEvents()' in read('TodoWallpaper/App/CalendarImportView.swift') and 'requestFullAccessToReminders()' in read('TodoWallpaper/App/CalendarImportView.swift'), 'Explicit Calendar/Reminders import uses native EventKit full-access APIs')
require('func importItems(' in read('TodoWallpaper/Core/TodoRepository.swift') and 'func updateMarkers(' in read('TodoWallpaper/Core/TodoRepository.swift'), 'Import and marker undo use existing process-locked repository transactions')
model = read('TodoWallpaper/Wallpaper/WallpaperEditorModel.swift')
require('guard wantsExactPreview else' in model and model.index('if name == photoName {') < model.index('saveTask?.cancel()', model.index('func restoreEditorState')), 'Ordinary undo applies live settings before any photo I/O; whole bitmap previews are on demand')
require('.frame(maxWidth: .infinity, alignment: .topLeading)\n        .frame(height: layout.height, alignment: .topLeading)' in shared, 'Custom Widget header fills its position coordinate space before clipping')
require('MarkerEditorTarget.selected' in wallpaper and 'ForEach(markerTasks)' in wallpaper, 'Wallpaper marker editor targets only actually visible canvas rows')
require('wallpaperInspectorHeight(' in wallpaper and 'previewScale: previewScale' in wallpaper, 'Preview-size control reallocates inspector height')
require('PhotoMotionView' in read('TodoWallpaper/Wallpaper/WallpaperLiveCanvas.swift') and 'UIPanGestureRecognizer' in read('TodoWallpaper/App/PhotoMotionView.swift'), 'Interactive photos use retained UIKit/CA gesture layers')
require('WidgetPhotoMotionSurface' in widget and '照片不透明度' in widget, 'Widget photo supports direct crop and alpha controls')
require('显示左下角说明' in widget and 'style.footerVisible' in read('TodoWallpaper/Core/WidgetLayout.swift'), 'Footer switch changes both content and space budget')
require('Text("点按后效果")' in widget, 'Text completion menu has a visible label')
require('isExplicitlyDark' in shared and 'systemScheme' in read('TodoWallpaper/Shared/WidgetBackgroundView.swift'), 'Widget colors resolve explicit theme instead of inheriting system-light background')
require('WidgetDayTimeline.dates' in extension and 'entry.date' in extension and '.after(dates[1])' in extension, 'Daily image uses actual Widget timeline entries')
require('WidgetAlbumPicker' in widget and 'PHAssetCollection.fetchAssetCollections' in read('TodoWallpaper/App/WidgetAlbumPicker.swift'), 'Album selector uses native PhotoKit with explicit access')
require('指定日期' in app and '指定时间' in app and 'schedule' in read('TodoWallpaper/Core/TodoItem.swift'), 'Optional schedule has real shared task persistence')
require('systemMaterial' in widget and '.ultraThinMaterial' in read('TodoWallpaper/Shared/WidgetBackgroundView.swift'), 'Experimental glass requests public Liquid Glass with material fallback')
require('Text("标记点按后效果")' in marker and 'case hollow, filled, thin, bordered, square, emoji, image, none' in read('TodoWallpaper/Core/TodoAppearance.swift'), 'Visible marker-effect heading and image marker kind')
require('PhotosPicker(selection: $selection' in marker and 'importMarker(' in marker, 'Every reused marker chooser supports real native photo input')
require('preparedOnly: true' in extension and 'count: rotating ? 2 : 1' in extension and 'kCGImageSourceThumbnailMaxPixelSize: 1024' in read('TodoWallpaper/Shared/WidgetBackgroundView.swift'), 'Extension archives bounded prepared photos and limits future image entries')
require('SmoothValueSlider(value: sliding' in marker and 'CADisplayLink' in read('TodoWallpaper/App/SmoothValueSlider.swift'), 'Native slider tracks immediately with frame-coalesced model publication')
require('@Published private var history' not in read('TodoWallpaper/App/EditorUndoState.swift'), 'History does not republish the entire editor for every grouped sample')
text_section = widget[widget.index('@ViewBuilder private var textControls'):widget.index('@ViewBuilder private var markerControls')]
content_section = widget[widget.index('@ViewBuilder private var contentControls'):widget.index('private var help:')]
require('PreciseSlider(title: "行距"' in text_section and 'range: -10...40' in text_section and 'showsSummary' in content_section, 'Text owns expanded row spacing; content owns the count switch')
require(widget.index('Toggle("玻璃背景') > widget.index('Picker("明暗"') and 'title: "实验选项"' in widget, 'Experimental glass follows everyday theme settings in a labeled section')
require('ReadableTone.resolve' in shared and 'layout.titleY' in shared, 'Widget uses explicit text contrast protection and bounded title insets')
readable_rules = read('TodoWallpaper/Core/ReadableModels.swift')
readable_layer = read('TodoWallpaper/Shared/ReadableLayer.swift')
background = read('TodoWallpaper/Shared/WidgetBackgroundView.swift')
store = read('TodoWallpaper/App/TodoStore.swift')
require('import UIKit' not in readable_rules and 'enum ReadableRules' in readable_rules,
    '可读性数值规则保持纯 Core，可由 macOS 原生检查直接运行')
require('ReadableRules.coverHeight' in readable_layer and 'max(0, extraInset)' in readable_rules,
    '负边距不会增加照片蒙层覆盖高度')
mark_section = shared[shared.index('private func mark('):shared.index('private func title(')]
require('.readableText(' in mark_section and 'enabled: tone.enabled' in mark_section,
    '实际标记与文字共用阴影及效果门禁，保留位图缓存')
header_section = shared[shared.index('private func header('):shared.index('@ViewBuilder private func task(')]
require(header_section.count('.readableText(') == 2,
    '标题和摘要各套一次文字阴影，不叠加重复摘要阴影')
require('family.isReadableAccessory' in readable_layer and 'widgetRenderingMode' in background
    and 'permitsEffects' in background and 'renderingMode: renderingMode, family: family' in extension,
    '真实着色模式和锁屏 family 同时禁用背景蒙层与内容阴影')
require(extension.count('effectsFamily: family') == 2 and 'effectsFamily ?? hostFamily' in shared
    and 'effectsFamily ?? family' in background and '.environment(\\.widgetFamily,' not in read('TodoWallpaper/Tests/NativeUIProbe.swift'),
    '系统family通过生产参数传入内容和背景，像素测试使用同一入口而不写只读环境键')
require('ReadableRules.insetRange' in widget and 'ReadableRules.inset(' in widget + shared
    and 'ReadableGeometryPreference' in widget + shared and 'settings.anchor == .center ? 0' in shared,
    '居中偏移以自然内容高度计算，滑条、切换锚点和渲染共用边界')
require('WidgetContentLayout.make' in shared + background and 'contentGeometry: readableGeometry' in widget
    and 'widgetContentMargins' in extension and 'contentDocument: entry.document' in extension,
    '中心蒙层与文字共用实际内容几何和有效偏移，跨尺寸不沿用旧画布偏移')
require('WallpaperColor.sRGB(UIColor(next))' in marker
    and 'converted(to: space' in read('TodoWallpaper/Shared/TodoMarkerView.swift'),
    '系统取色先转换 sRGB 再规范化，不重新解释 Display P3 分量')
require('value.clampedForEditing()' in store and 'func setAppearance(_ value: TodoAppearance) -> Bool' in store
    and store.index('appearanceError = appearanceStorageError', store.index('func setAppearance')) < store.index('guard accepted != appearance'),
    '样式校验可修复数值且成功立即清校验错误，存储保护错误只在实际IO成功后清除')
analysis_service = read('TodoWallpaper/App/PhotoAnalysisService.swift')
analysis_cache = read('TodoWallpaper/Shared/AppearanceStore.swift')
analysis_request = read('TodoWallpaper/Core/PhotoAnalysisRequest.swift')
require('import UIKit' not in analysis_service and 'CGImageSourceCreateThumbnailAtIndex' in analysis_service
    and 'kCGImageSourceThumbnailMaxPixelSize: 128' in analysis_service and 'let side = 32' in analysis_service
    and 'qos: .utility' in analysis_service and 'Task.detached' not in analysis_service,
    '统一分析服务使用后台utility串行ImageIO128缩图与一次CG32合成，不解码UIKit原图或并发分图')
require('UIImage(data:' not in widget and 'analyzeAllAnchors' not in widget
    and 'analyzeAllAnchors' not in read('TodoWallpaper/App/WidgetAlbumPicker.swift'),
    '单图和相册提交统一管线，不在选图MainActor或相册导入中分析原图')
require('canvasAspect' in analysis_request and 'opacity == 1 ? false' in analysis_request
    and all(value in analysis_request for value in ['crop.zoom', 'crop.panX', 'crop.panY', 'opacity, canvasAspect']),
    '分析请求包含实际裁剪、透明度、底色与画布比例，完全不透明时明暗共用')
require(extension.count('AppearanceStore.shared.clearMemoryCache()') == 2
    and 'registerMissing(request)' in extension and 'preparedAnalyses: entry.analyses' in extension
    and 'PhotoAnalysisService' not in extension and 'ImageAnalyzer' not in extension,
    'Provider每次起始清内存并登记真实比例缺失，entry携分析快照，Widget不执行分析')
require('cachedAnalysis(for:' in readable_layer and 'cachedAnalysis(for:' in widget
    and 'registerMissing' not in readable_layer and 'PhotoAnalysisService' not in readable_layer,
    '真实内容与自动数值只读取已暖缓存或entry快照，body没有分析、写队列或磁盘读取')
require('AnalysisRequests' in analysis_cache and 'AnalysisCache' in analysis_cache and '.atomic' in analysis_cache
    and 'schemaVersion == 1' in analysis_cache and 'expectedVersion' in analysis_cache
    and 'private let fileLock = NSLock()' in analysis_cache and 'memoryRevision' in analysis_cache,
    '跨进程请求和三anchor结果均原子发布，短内存锁与后台IO锁分离并防删除后复活')
require('PhotoAnalysisRequestObserver' in store and 'if usesSharedStorage {' in store
    and 'rescanAnalysisPending = true; return' in store and '.milliseconds(400)' in store
    and 'if succeeded { self.analysisNeedsInvalidation = false; self.analysisRevision += 1 }' in store
    and 'runBatch(style:' in store and 'knownRequests()' not in store,
    'App生命周期接请求事件，同批次晚到请求不重入取消，交互结束去抖并发布缓存命中结果')
require('bash native-tools/check-photo-analysis.sh' in read('native-tools/check-native.sh')
    and 'ranOnMainThread' in read('TodoWallpaper/Tests/PhotoAnalysisChecks.swift')
    and 'photo_analysis_interaction_debounce_generation_and_actual_aspect' in read('TodoWallpaper/Tests/NativeUIProbe.swift'),
    '完整native门禁执行独立CG分析和iOS生产交互调度回归，不仅检查源码')
album = read('TodoWallpaper/App/WidgetAlbumPicker.swift')
photo_store = read('TodoWallpaper/App/WidgetPhotoStore.swift')
asset_gc = read('TodoWallpaper/Core/PhotoAssetMaintenance.swift')
require('requestImageDataAndOrientation' not in album and 'targetSize: CGSize(width: 1536, height: 1536)' in album
    and 'isNetworkAccessAllowed = true' in album and 'cancelImageRequest' in album and 'PHImageResultIsDegradedKey' in album,
    '相册逐张请求目标图并处理取消和重复降级回调，不读取原图Data')
require('PhotoImportProgress' in album and 'validateResult()' in album and 'rollbackBatch' in album
    and 'published = true' in album and 'if !published' in album and 'PhotoImports' in photo_store,
    '相册跳过单张失败并按阈值回滚，持久化发布后取消不删除照片，名称事务有日志')
require('WidgetPhotoStore().import' not in widget + marker + album and 'transactions.isEmpty' in photo_store and 'now.timeIntervalSince(max(created, modified)) >= 600' in asset_gc
    and 'isSymbolicLink' in asset_gc and 'todo.assetReferences()' in asset_gc and 'look.assetReferences()' in asset_gc
    and 'cleanOrphanAnalysis' in photo_store,
    '回收保护导入、十分钟新文件、权威数据和备份，并清除孤立分析')
require('retainedValuesChanged' in widget and 'retainedValuesChanged' in wallpaper and 'steps.flatMap' in read('TodoWallpaper/Core/EditorHistory.swift')
    and 'owner: "widget"' in widget and 'owner: "wallpaper"' in wallpaper and 'store.collectPhotoAssets()' in widget,
    '两个编辑器所有撤销快照都进入保留集合，相册和移除照片后触发回收')
require('TodoSharedStorage.appSnapshot()' in store and 'accept(snapshot.document)' in store
    and 'TodoSharedStorage.widgetSnapshot().document' in extension and 'existingSnapshot' in read('TodoWallpaper/Core/TodoRepository.swift'),
    'App和Provider复用同一次加锁校验的迁移快照，不重复load或长期缓存')
require('PhotoAssetMaintenanceChecks.swift' in read('native-tools/check-native.sh')
    and 'album_transaction_rollback_commit_busy_and_undo_retention' in read('TodoWallpaper/Tests/NativeUIProbe.swift'),
    '门禁执行真实文件回收、导入事务和编辑器保留回归')
schedule = read('TodoWallpaper/Core/TodoSchedule.swift')
motion = read('TodoWallpaper/App/PhotoMotionView.swift')
renderer = read('TodoWallpaper/Wallpaper/WallpaperRenderer.swift')
require('ScheduleLabelFormatters.shared.string' in schedule and 'formatter.locale = .autoupdatingCurrent' in schedule
    and 'formatter.calendar = .autoupdatingCurrent' in schedule and 'currentLocaleDidChangeNotification' in schedule
    and 'private let lock = NSLock()' in schedule,
    '日期短格式双缓存跟随系统设置并加锁，label不反复创建格式器')
require('hasSuccessfulEnd = hasSuccessfulEnd || !cancelled' in motion and 'if !hasSuccessfulEnd' in motion
    and 'guard active.remove(ObjectIdentifier(gesture)) != nil' in motion,
    '组合照片手势全取消才回滚，正常结束保留当前值且重复回调不二次提交')
require('interaction.begin("wallpaper.panel.nudge")' in wallpaper and 'defer { interaction.end() }' in wallpaper
    and 'coalescingContext' in wallpaper and 'func nudged(in layout:' in read('TodoWallpaper/Wallpaper/WallpaperGeometry.swift')
    and 'dx / Double(size.width)' in read('TodoWallpaper/Wallpaper/WallpaperGeometry.swift'),
    '微调显式begin/end合并点按并保留一个导出像素步进')
require('setShadow(' not in renderer and 'shadow: CGColor?' not in renderer and 'TextLegibility.readable' in renderer,
    '壁纸删除旧阴影绘制和死参数，保留规定的可读色调用')
require('mixed_gesture_endings_and_all_cancel_rollback' in read('TodoWallpaper/Tests/NativeUIProbe.swift')
    and 'nudge_begin_end_coalescing_and_later_gesture_isolation' in read('TodoWallpaper/Tests/NativeUIProbe.swift')
    and 'production nudge edge/center cases' in read('TodoWallpaper/Tests/PhotoRepairRenderChecks.swift'),
    '实际原生门禁验证组合结束顺序、撤销合并与生产几何边界')
handoff = read('tools/check_handoff.py')
handoff_tests = read('tools/test_check_handoff.py')
require('if count == 0:' in handoff and '检查了 {count} 条' in handoff and 'has_symbol' in handoff
    and 'is_relative_to' in handoff and '未登记源码' in handoff,
    '交接检查逐项实际计数并拒绝零条、缺声明、未登记和越界路径')
require(all(name in handoff_tests for name in ['test_empty_map', 'test_empty_symbols', 'test_empty_source', 'test_empty_constants', 'test_counts_follow_added_file'])
    and 'python3 tools/test_check_handoff.py' in read('native-tools/check-native.sh')
    and 'bash tools/check_handoff.sh' in read('native-tools/check-native.sh'),
    '完整native门禁执行交接空输入负向及动态计数回归，不硬编码成功数')
require('steps.product.outputs.version' in read('.github/workflows/todo-wallpaper.yml')
    and 'Todo Wallpaper $PRODUCT_VERSION ($PRODUCT_BUILD)' in read('native-tools/build-product.sh')
    and 'CURRENT_PROJECT_VERSION="$UI_PRODUCT_BUILD"' in read('native-tools/check-ios-ui.sh'),
    '版本和产物摘要读取元数据，模拟器与设备使用同次构建号')
protected = json.loads(read('docs/UI-PROTECTED-SOURCES.json'))
require(all('__pycache__' not in path and Path(path).suffix in {'.swift','.py','.cmd','.ps1','.plist','.entitlements'} for path in protected),
    'Protected manifest contains source/config only, no generated caches')
for path, expected in protected.items():
    # Git may check text files out as CRLF on Windows (core.autocrlf=true).
    # Normalize before hashing so the guard measures content, not line endings.
    data = (root/path).read_bytes().replace(b'\r\n', b'\n')
    require(hashlib.sha256(data).hexdigest() == expected, f'Protected source matches reviewed manifest: {path}')
out = root/'TodoWallpaper/out'
out.mkdir(exist_ok=True)
(out/'ui-structure-checks.json').write_text(json.dumps({'result':'passed','checks':checks,
    'evidence_scope':'Source architecture only. Native compilation and executable state checks are separate. No iPhone scrolling, animation, keyboard, safe-area or signing result is implied.'},ensure_ascii=False,indent=2))
print(f'PASS: {len(checks)} UI architecture/protected-source guards; no device visual assertion.')
