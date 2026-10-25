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
require('navigation.isEditing ? .hidden : .visible, for: .tabBar' in wallpaper, 'Public SwiftUI toolbar visibility replaces Tab Bar only during editing')
require('ForEach(AppPage.allCases)' in wallpaper and 'navigation.selectPage(page)' in wallpaper and 'navigation.exitEditing()' in wallpaper, 'Circular Dock menu can switch every root page or restore full tabs')
require('ZStack(alignment: .bottom)' not in wallpaper and 'inspector(height:' in wallpaper, 'Canvas and inspector receive separate layout space, not overlapping overlays')
require('InspectorViewport' in wallpaper and 'InspectorViewport' in widget, 'Both editors use the same bounded settings viewport')
require('.scrollClipDisabled(false)' in viewport and viewport.count('.clipped()') >= 2, 'Scroll descendants explicitly clipped at viewport boundaries')
require('.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))' in wallpaper, 'Inspector material has an actual continuous clipping shape')
require(all('DisclosureGroup' not in source for source in [wallpaper,widget,marker]), 'Editor controls replace detail pages instead of nesting expanding scroll groups')
require('onChange(of: pageID)' in viewport and 'scrollTo("inspector-top"' in viewport, 'Tool/detail replacement resets its own content anchor, not on slider edits')
require('fixedPreview(height:' in widget and widget.index('fixedPreview(height:') < widget.index('InspectorViewport(') and 'Form {' not in widget, 'Fixed Widget preview is outside the independent settings scroll surface')
require('ForEach(WidgetPreviewFamily.allCases)' in widget and 'family.scale(' in widget, 'Three Widget preview ratios fit their fixed space without distortion')
require('TodoWidgetContent(' in widget and 'TodoWidgetContent(' in extension and 'interactive: false' in widget, 'Preview and real Widget share content; preview cannot toggle tasks')
require('Button(intent: SetTodoCompletionIntent(' in shared and '.invalidatableContent()' in shared, 'Real Widget retains direct App Intent completion and restore')
require('TodoMarkerView(marker: TodoMarker(kind: kind' in marker and 'Picker("标记类型"' not in marker, 'Reusable marker choices show native shape/Emoji samples')
require('MarkerControlVisibility(kind: kind)' in marker and 'if controls.visible' in marker and 'if controls.emoji' in marker, 'Marker parameters use explicit selected-kind capabilities')
require('if !style.followsTextColor' in marker and 'if controls.fill' in marker and 'if controls.stroke' in marker, 'Independent shape colors appear only for active capabilities')
require('if model.hasPhoto' in wallpaper and 'if model.settings.customPosition' in wallpaper and 'if !model.settings.automaticHeight' in wallpaper, 'Inactive photo, position and manual-height controls are absent')
require('DisclosureGroup' not in marker and '精细 RGB' not in marker and 'ColorPicker(' in marker, 'Color editing uses native picker plus swatches without extra RGB disclosure trees')
for forbidden in ['UITabBar.appearance', 'setValue(', 'WebView', 'WKWebView']:
    require(all(forbidden not in source for source in [app,wallpaper,widget,marker]), f'No {forbidden} workaround in edited UI')
protected = json.loads(read('docs/UI-PROTECTED-SOURCES.json'))
require(all('__pycache__' not in path and Path(path).suffix in {'.swift','.py','.cmd','.ps1','.plist','.entitlements'} for path in protected),
    'Protected manifest contains source/config only, no generated caches')
for path, expected in protected.items():
    # Git intentionally checks Windows text scripts out as CRLF; signing code is unchanged.
    data = (root/path).read_bytes()
    if path.endswith(('.cmd','.ps1')):
        data = data.replace(b'\r\n', b'\n')
    require(hashlib.sha256(data).hexdigest() == expected, f'Protected source unchanged: {path}')
out = root/'TodoWallpaper/out'
out.mkdir(exist_ok=True)
(out/'ui-structure-checks.json').write_text(json.dumps({'result':'passed','checks':checks,
    'evidence_scope':'Source architecture only. Native compilation and executable state checks are separate. No iPhone scrolling, animation, keyboard, safe-area or signing result is implied.'},ensure_ascii=False,indent=2))
print(f'PASS: {len(checks)} UI architecture/protected-source guards; no device visual assertion.')
