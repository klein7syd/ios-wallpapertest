"""Requirement-level architecture guards, not a simulator or device visual test."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
read = lambda path: (root / path).read_text()
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
require(all(f'.tag(AppPage.{page})' in app for page in ['todos','wallpaper','widget','about']), 'Four selectable native TabView root pages')
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
require('wallpaperMarkerChoice' in wallpaper and 'usesTaskMarkers = false' in wallpaper and 'model.updateAppearance(store.appearance)' in wallpaper, 'Uniform wallpaper marker changes reach its own live model despite task overrides')
require('WidgetHeaderAppearance' in read('TodoWallpaper/Core/TodoAppearance.swift') and 'headerControls' in widget and 'heading.showsSummary' in widget and 'Text("待办").font' not in shared, 'Widget title and summary are configurable in shared actual content')
require('WidgetBackgroundView' in widget + extension and 'PhotosPicker(' in widget and 'WidgetPhotoStore' in widget, 'Widget preview and extension share the selected local photo background')
require('CalendarImportView(store: store)' in app and 'requestFullAccessToEvents()' in read('TodoWallpaper/App/CalendarImportView.swift') and 'requestFullAccessToReminders()' in read('TodoWallpaper/App/CalendarImportView.swift'), 'Explicit Calendar/Reminders import uses native EventKit full-access APIs')
require('func importItems(' in read('TodoWallpaper/Core/TodoRepository.swift') and 'func updateMarkers(' in read('TodoWallpaper/Core/TodoRepository.swift'), 'Import and marker undo use existing process-locked repository transactions')
model = read('TodoWallpaper/Wallpaper/WallpaperEditorModel.swift')
require('guard wantsExactPreview else' in model and model.index('if name == photoName {') < model.index('saveTask?.cancel()', model.index('func restoreEditorState')), 'Ordinary undo applies live settings before any photo I/O; whole bitmap previews are on demand')
require('.frame(maxWidth: .infinity, alignment: .topLeading)\n        .frame(height: layout.height)' in shared, 'Custom Widget header fills its position coordinate space before clipping')
protected = json.loads(read('docs/UI-PROTECTED-SOURCES.json'))
require(all('__pycache__' not in path and Path(path).suffix in {'.swift','.py','.cmd','.ps1','.plist','.entitlements'} for path in protected),
    'Protected manifest contains source/config only, no generated caches')
for path, expected in protected.items():
    # Git intentionally checks Windows text scripts out as CRLF; signing code is unchanged.
    data = (root/path).read_bytes()
    if path.endswith(('.cmd','.ps1')):
        data = data.replace(b'\r\n', b'\n')
    require(hashlib.sha256(data).hexdigest() == expected, f'Protected source matches reviewed manifest: {path}')
out = root/'TodoWallpaper/out'
out.mkdir(exist_ok=True)
(out/'ui-structure-checks.json').write_text(json.dumps({'result':'passed','checks':checks,
    'evidence_scope':'Source architecture only. Native compilation and executable state checks are separate. No iPhone scrolling, animation, keyboard, safe-area or signing result is implied.'},ensure_ascii=False,indent=2))
print(f'PASS: {len(checks)} UI architecture/protected-source guards; no device visual assertion.')
