import SwiftUI
import UIKit
import PhotosUI
import WidgetKit

private enum WidgetEditorTool: String, CaseIterable, Identifiable {
    case theme = "主题", header = "标题", text = "文字", marker = "标记", content = "内容"
    var id: String { rawValue }
}
private struct TaskMarkerState: Equatable {
    let id: UUID
    let marker: TodoMarker?
}
private struct WidgetEditState: Equatable {
    let style: WidgetAppearance
    let markers: [TaskMarkerState]
}
struct WidgetAppearanceEditor: View {
    @ObservedObject var store: TodoStore
    @State private var error: String?
    @State private var isVisible = false
    @State private var tool = WidgetEditorTool.theme
    @State private var family = WidgetPreviewFamily.medium
    @AppStorage(EditorStandards.advancedKey) private var advanced = false
    @StateObject private var edits = EditorUndoState<WidgetEditState>()
    @State private var selectedTaskID: UUID?
    @State private var preview = WidgetPreviewState()
    @State private var showHelp = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importingPhoto = false
    @State private var cropPhoto = false
    @State private var chooseAlbum = false
    @State private var previewDay = 0
    private let photos = WidgetPhotoStore.shared
    @State private var previousWidgetMarker: TodoMarker?
    @State private var readableGeometry = ReadableContentGeometry(canvasHeight: 138, textHeight: 138)
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var widget: Binding<WidgetAppearance> {
        Binding(get: { store.appearance.widget }, set: { var next = store.appearance; next.widget = $0; store.setAppearance(next) })
    }
    private var photoCrop: Binding<PhotoCrop> {
        Binding(get: { store.appearance.widget.photoCrop }, set: { widget.wrappedValue.backgroundCrop = $0 })
    }
    private var photoDate: Date { Calendar.current.date(byAdding: .day, value: previewDay, to: .now) ?? .now }
    private var heading: Binding<WidgetHeaderAppearance> {
        Binding(get: { store.appearance.widget.heading }, set: { widget.wrappedValue.header = $0 })
    }
    private var scheme: ColorScheme {
        let theme = store.appearance.widget.theme
        return theme == .system ? systemScheme : theme == .dark ? .dark : .light
    }
    private var editState: WidgetEditState {
        WidgetEditState(style: store.appearance.widget,
            markers: store.items.map { TaskMarkerState(id: $0.id, marker: $0.marker) }.sorted { $0.id.uuidString < $1.id.uuidString })
    }
    private var layoutScale: Binding<Double> {
        Binding(get: { store.appearance.widget.fontSize / 15 },
            set: { widget.wrappedValue = EditorStandards.widget(store.appearance.widget, scale: $0) })
    }
    private var editorInteraction: EditorInteractionContext {
        let base = edits.context(read: { editState })
        return EditorInteractionContext(begin: { key in store.beginAppearanceInteraction(); base.begin(key) },
            end: { base.end(); store.endAppearanceInteraction() }, pulse: base.pulse)
    }
    var body: some View {
        presentedEditor.environment(\.editorInteraction, editorInteraction)
    }
    // 分段约束 SwiftUI 泛型推断，保持原有修饰顺序与事件行为。
    private var editingObservers: some View {
        configuredEditor
            .onChange(of: tool) { _, next in edits.finish(editState); if next != .theme { cropPhoto = false } }
            .onChange(of: store.appearance.widget.backdrop) { _, _ in cropPhoto = false }
            .onChange(of: advanced) { _, _ in edits.finish(editState) }
            .onChange(of: previousWidgetMarker) { _, value in store.retainPhotoAssets(PhotoAssetReferences.marker(value), owner: "widget.previousMarker") }
    }
    private var analysisObservers: some View {
        editingObservers
            .onChange(of: systemScheme) { _, value in store.updateAnalysisSystemTheme(dark: value == .dark) }
            .onChange(of: previewDay) { _, _ in updateAnalysisPriority() }
            .onChange(of: family) { _, _ in updateAnalysisPriority() }
            .onChange(of: currentAnalysisPhotoName) { _, _ in updateAnalysisPriority() }
    }
    private var lifecycleEditor: some View {
        analysisObservers
            .onChange(of: currentTaskIDs) { _, ids in
                if let selectedTaskID, !ids.contains(selectedTaskID) { self.selectedTaskID = nil }
            }
            .onDisappear { edits.finish(editState); isVisible = false; store.flushAppearance() }
    }
    private var presentedEditor: some View {
        lifecycleEditor
            .sheet(isPresented: $showHelp) { help }
            .sheet(isPresented: $chooseAlbum) { albumPicker }
            .alert("样式", isPresented: errorPresented) {
                Button("好", role: .cancel) { }
            } message: { Text(error ?? "") }
    }
    private var errorPresented: Binding<Bool> {
        Binding<Bool>(get: { self.error != nil }, set: { presented in
            if !presented { self.error = nil }
        })
    }
    private var currentTaskIDs: [UUID] { store.items.map(\.id) }
    private var currentAnalysisPhotoName: String? { store.appearance.widget.photoName(at: photoDate) }
    private var albumPicker: some View {
        WidgetAlbumPicker(onSelect: acceptAlbum, onCommitted: { store.collectPhotoAssets() })
    }
    private func acceptAlbum(_ rotation: WidgetAlbumRotation, skipped: Int) throws {
        var next = store.appearance.widget
        next.photoRotation = rotation; next.backgroundPhotoName = rotation.photos.first
        next.backdrop = .photo; next.systemMaterial = false; next.backgroundCrop = PhotoCrop()
        var root = store.appearance; root.widget = next
        try store.saveAppearance(root.clampedForEditing()); previewDay = 0
        if skipped > 0 { error = "\(skipped) 张读取失败，已跳过" }
    }
    private var editorSurface: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                fixedPreview(height: EditorSizing.widgetPreviewHeight(available: geometry.size.height, family: family))
                InspectorViewport(pageID: tool.id + (advanced ? ".advanced" : ".basic") + (selectedTaskID?.uuidString ?? ".default")) {
                    if let message = store.appearanceError {
                        Text(message).font(.caption).foregroundStyle(.red)
                        Button("重试") { store.reloadAppearance() }
                        Button("恢复有效样式备份") {
                            do { try store.recoverAppearance() } catch { self.error = error.localizedDescription }
                        }
                    }
                    switch tool {
                    case .theme: themeControls
                    case .header: headerControls
                    case .text: textControls
                    case .marker: markerControls
                    case .content: contentControls
                    }
                }
                .frame(maxHeight: .infinity).accessibilityIdentifier("widget.settings")
                EditorToolPicker(choices: WidgetEditorTool.allCases, selection: $tool,
                    title: { $0.rawValue }, compact: geometry.size.height < 320)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .accessibilityIdentifier("widget.tools")
            }
            .clipped()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("小组件").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { undoEdit() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                    .disabled(!edits.canUndo || store.loadError != nil || store.appearanceError != nil || importingPhoto)
                    .accessibilityIdentifier("widget.undo")
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("小组件帮助")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
    }
    private var configuredEditor: some View {
        editorSurface
        .onAppear {
            isVisible = true
            configureAssetRetention()
            updateAnalysisPriority()
            store.updateAnalysisSystemTheme(dark: systemScheme == .dark)
            store.resumePhotoAnalysis()
            edits.synchronize(editState)
            #if TODO_UI_CHECKS
            if ProcessInfo.processInfo.arguments.contains("--native-widget-text") { tool = .text }
            if ProcessInfo.processInfo.arguments.contains("--native-widget-header") { tool = .header }
            #endif
        }
        .onChange(of: editState) { previous, next in
            guard isVisible else { return }
            if previous.markers.map(\.id) != next.markers.map(\.id) { edits.synchronize(next) }
            else { edits.observe(next) }
        }
        .onChange(of: selectedPhoto) { _, selection in
            guard let selection else { return }
            importingPhoto = true
            Task {
                defer { importingPhoto = false; selectedPhoto = nil }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw WallpaperError.unreadablePhoto }
                    let name = try await photos.importPhoto(data)
                    var next = store.appearance.widget
                    next.backgroundPhotoName = name; next.backdrop = .photo; next.systemMaterial = false; next.backgroundCrop = PhotoCrop(); next.photoRotation?.enabled = false; previewDay = 0
                    widget.wrappedValue = next; store.flushAppearance()
                } catch { self.error = error.localizedDescription }
            }
        }
        .task {
            if let legacy = ReadableSettingsMigration.take() {
                var next = store.appearance.widget
                if next.readableAnchor == nil { next.readableAnchor = legacy.anchor }
                if next.readableIntensity == nil { next.readableIntensity = legacy.intensity }
                if next.readableShadowPreset == nil { next.readableShadowPreset = legacy.shadowPreset }
                if next.readableHeightRatio == nil { next.readableHeightRatio = legacy.heightRatio }
                if next.readableScrimOverride == nil { next.readableScrimOverride = legacy.scrimOverride }
                if next.readableEdgeInset == nil, var header = next.header, header.topInset > 0,
                   next.readableAnchor == .top || (next.readableAnchor == nil && legacy.anchor == .top) {
                    next.readableEdgeInset = header.topInset
                    header.topInset = 0
                    next.header = header
                }
                widget.wrappedValue = next
                store.flushAppearance()
            }
        }
    }
    private func configureAssetRetention() {
        edits.retainedValuesChanged = { values in
            let names = values.reduce(into: Set<String>()) { result, value in
                result.formUnion(PhotoAssetReferences.widget(value.style))
                for item in value.markers { result.formUnion(PhotoAssetReferences.marker(item.marker)) }
            }
            store.retainPhotoAssets(names, owner: "widget")
        }
        edits.retainedValuesChanged(edits.retainedValues)
    }
    private func undoEdit() {
        Task {
            do {
                try await edits.undo(read: { editState }) { previous, expected in
                    var restored = store.appearance
                    restored.widget = previous.style
                    restored = restored.clampedForEditing()
                    try restored.validate()
                    let changed = previous.markers.filter { old in
                        expected.markers.first(where: { $0.id == old.id })?.marker != old.marker
                    }
                    // Only restore the marker field. Never restore stale titles,
                    // completion, task order, or a task removed in another surface.
                    for old in changed {
                        guard let item = store.items.first(where: { $0.id == old.id }),
                              item.marker == expected.markers.first(where: { $0.id == old.id })?.marker else {
                            throw NSError(domain: "EditorUndo", code: 1, userInfo: [NSLocalizedDescriptionKey: "任务已发生变化，保留当前数据。"])
                        }
                    }
                    try store.updateMarkers(changed.map { old in
                        TodoMarkerUpdate(id: old.id, expected: expected.markers.first(where: { $0.id == old.id })?.marker, marker: old.marker)
                    })
                    if previous.style != expected.style, !store.setAppearance(restored) {
                        throw AppearanceError.invalidStyle
                    }
                }
            } catch { self.error = "未能撤销：\(error.localizedDescription)" }
        }
    }
    private func fixedPreview(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(WidgetPreviewFamily.allCases) { size in Button(size.title) { family = size } }
                } label: {
                    Group {
                        if typeSize.isAccessibilitySize { Text(family.title).lineLimit(1).fixedSize(horizontal: true, vertical: false) }
                        else { Label(family.title, systemImage: "rectangle.3.group") }
                    }.font(.subheadline)
                }.accessibilityLabel("预览尺寸：\(family.title)")
                Spacer(minLength: 0)
                if !typeSize.isAccessibilitySize {
                    Text("点标记编辑 · 点文字试完成").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                }
                Button { preview.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 20)).frame(width: 44, height: 44) }
                    .accessibilityLabel("重置预览完成状态，不修改真实待办")
            }
            GeometryReader { proxy in
                let scale = family.scale(availableWidth: proxy.size.width - 32, availableHeight: proxy.size.height - 8)
                TodoWidgetContent(document: store.hasLoaded && store.loadError == nil ? TodoDocument(items: preview.items(store.items)) : nil,
                    appearance: store.appearance, error: store.loadError, family: family, interactive: false,
                    onPreviewToggle: { id in if let item = store.items.first(where: { $0.id == id }) { preview.toggle(item) } },
                    onPreviewMarker: { id in selectedTaskID = id; tool = .marker }, selectedTaskID: selectedTaskID, onPreviewHeader: { tool = .header })
                    .onPreferenceChange(ReadableGeometryPreference.self) { geometry in
                        readableGeometry = geometry
                        clampReadableInset(geometry: geometry)
                    }
                    .padding(16)
                    .frame(width: family.width, height: family.height)
                    .allowsHitTesting(!cropPhoto)
                    .background {
                        if cropPhoto && store.appearance.widget.backdrop == .photo && !store.appearance.widget.materialEnabled, let image = WidgetPhotoCache.image(named: store.appearance.widget.photoName(at: photoDate)) {
                            WidgetPhotoMotionSurface(image: image, crop: photoCrop, opacity: store.appearance.widget.photoOpacity,
                                background: scheme == .dark ? UIColor(white: 0.09, alpha: 1) : .white)
                        } else {
                            let readable = ReadableResolver.scrim(style: store.appearance.widget, date: photoDate, scheme: scheme,
                                canvasAspect: family.width / family.height)
                            WidgetBackgroundView(style: store.appearance.widget, date: photoDate,
                                                 scrim: readable.value, scrimAnchor: store.appearance.widget.readable.anchor,
                                                 scrimHeightRatio: store.appearance.widget.readable.heightRatio,
                                                 scrimColor: readable.color, scrimExtraInset: store.appearance.widget.readable.edgeInset,
                                                 contentGeometry: readableGeometry)
                        }
                    }
                    .environment(\.colorScheme, scheme)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .scaleEffect(scale)
                    .frame(width: family.width * scale, height: family.height * scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .background(TransparencyGrid())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(height: height).padding(.horizontal, 16).padding(.top, 6)
        .accessibilityElement(children: .contain).accessibilityLabel("\(family.title)小组件外观预览，使用真实待办")
        .accessibilityIdentifier("widget.fixedPreview")
    }
    @ViewBuilder private var themeControls: some View {
        InspectorGroupTitle(title: "背景与照片", detail: "先选背景，再调整照片构图与明暗。")
        Picker("明暗", selection: widget.theme) { ForEach(WidgetTheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        if store.appearance.widget.materialEnabled {
            Text("请求原生 Liquid Glass。默认图标模式能否透出桌面壁纸，仍需实机确认；系统透明模式由 iOS 控制。")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Picker("背景", selection: widget.backdrop) { ForEach(WidgetBackdrop.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if store.appearance.widget.backdrop == .solid { StyleColorControl(title: "面板底色", value: widget.panelColor) }
            if store.appearance.widget.backdrop == .photo {
                PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                    Label("选择或更换照片", systemImage: "photo")
                }.buttonStyle(.bordered).disabled(importingPhoto)
                Button("选择相册，每天换一张", systemImage: "photo.stack") { chooseAlbum = true }
                if importingPhoto { ProgressView("正在处理照片…") }
                if let rotation = store.appearance.widget.photoRotation {
                    Toggle("每日轮换 · \(rotation.title)", isOn: Binding(get: { store.appearance.widget.photoRotation?.enabled ?? false }, set: {
                        widget.wrappedValue.photoRotation?.enabled = $0; previewDay = 0
                    }))
                    if rotation.enabled {
                        Button("预览下一张") { previewDay += 1 }
                        Text("\(rotation.photos.count) 张；裁剪与透明度用于整个相册。相册变动后重新选择同步。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if store.appearance.widget.photoName(at: photoDate) != nil {
                    Toggle("手指调整照片", isOn: $cropPhoto)
                    PreciseSlider(title: "照片缩放", value: photoCrop.zoom, range: 1...4, standard: 1, precision: 2)
                    PreciseSlider(title: "照片不透明度", value: Binding(get: { store.appearance.widget.photoOpacity }, set: { widget.wrappedValue.backgroundPhotoOpacity = $0 }), range: 0...1, standard: 1, precision: 2)
                    if advanced {
                        PreciseSlider(title: "照片水平位置", value: photoCrop.panX, range: -1...1, standard: 0, precision: 2)
                        PreciseSlider(title: "照片垂直位置", value: photoCrop.panY, range: -1...1, standard: 0, precision: 2)
                    }
                    Button("恢复照片构图") { photoCrop.wrappedValue = PhotoCrop() }
                    Divider()
                    Button("移除照片", role: .destructive) {
                        if let photos = store.appearance.widget.photoRotation?.photos {
                            store.forgetPhotoAnalysis(photos)
                        }
                        if let current = store.appearance.widget.backgroundPhotoName {
                            store.forgetPhotoAnalysis([current])
                        }
                        var next = store.appearance.widget; next.backgroundPhotoName = nil; next.photoRotation = nil; next.backdrop = .system
                        widget.wrappedValue = next; cropPhoto = false; store.flushAppearance(); store.collectPhotoAssets()
                    }
                }
            }
        }
        InspectorGroupTitle(title: "实验选项", detail: "系统玻璃效果受 iOS 模式影响，可按需开启。")
        Toggle("玻璃背景（实验）", isOn: Binding(get: { store.appearance.widget.materialEnabled }, set: {
            widget.wrappedValue.systemMaterial = $0; cropPhoto = false
        }))
        if advanced {
            Text("网格不会出现在主屏幕。系统外观会影响实际小组件背景。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var headerControls: some View {
        InspectorGroupTitle(title: "标题与位置", detail: "标题内容与整块文字的位置在这里调整。")
        PreciseSlider(title: edgeLabel, value: edgeBinding, range: edgeRange, standard: 0)
        Toggle("显示标题", isOn: heading.showsTitle)
        if store.appearance.widget.heading.showsTitle {
            TextField("标题内容", text: Binding(get: { store.appearance.widget.heading.text }, set: { text in
                edits.context(read: { editState }).pulse("widget.title")
                heading.wrappedValue.text = String(text.filter { !$0.isNewline }.prefix(40))
            })).textInputAutocapitalization(.never).submitLabel(.done)
            Toggle("标题颜色跟随文字", isOn: heading.followsTextColor)
            StyleColorControl(title: "标题颜色", value: heading.color)
            .disabled(store.appearance.widget.heading.followsTextColor)
            Picker("标题位置", selection: Binding(get: { store.appearance.widget.heading.horizontalPosition < 0.25 ? 0 : store.appearance.widget.heading.horizontalPosition > 0.75 ? 2 : 1 }, set: {
                heading.wrappedValue.horizontalPosition = Double($0) / 2
            })) {
                Text("左").tag(0); Text("中").tag(1); Text("右").tag(2)
            }.pickerStyle(.segmented)
            Picker("标题字体", selection: heading.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("标题字重", selection: heading.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if advanced {
                PreciseSlider(title: "标题大小", value: heading.fontSize, range: 12...32, standard: 17)
                PreciseSlider(title: "标题水平位置", value: heading.horizontalPosition, range: 0...1, standard: 0, precision: 2)
            }
        }
    }
    @ViewBuilder private var textControls: some View {
        InspectorGroupTitle(title: "文字与可读性", detail: "先选位置与颜色，再细调字体和护字效果。")
        Picker("文字位置", selection: readableAnchor) {
            ForEach(TextAnchor.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
        Picker("可读性强度", selection: readableIntensity) {
            ForEach(ReadabilityIntensity.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented)
        Toggle("文字跟随系统", isOn: widget.followsSystemText)
        StyleColorControl(title: "文字色", value: widget.textColor)
            .disabled(store.appearance.widget.followsSystemText)
        if advanced {
            PreciseSlider(title: "字号", value: widget.fontSize, range: 12...20, standard: 15)
            if hasVisibleMarker { PreciseSlider(title: "标记与文字间距", value: widget.markerStyle.gap, range: 0...32, standard: 10) }
        } else {
            PreciseSlider(title: "排版缩放", value: layoutScale, range: EditorStandards.widgetScale, standard: 1, precision: 2)
        }
        Picker("字重", selection: widget.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Picker("字体", selection: widget.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        if advanced {
            PreciseSlider(title: "行距", value: widget.spacing, range: -10...40, standard: 5)
        }
        Toggle("紧凑布局", isOn: widget.compact)
        Picker("每项文字行数", selection: Binding(get: { store.appearance.widget.maximumTitleLines ?? 0 }, set: { widget.wrappedValue.maximumTitleLines = $0 == 0 ? nil : $0 })) {
            Text("自动").tag(0); Text("单行").tag(1); Text("最多两行").tag(2)
        }.pickerStyle(.menu)
        Text("点按后效果").font(.subheadline)
        Picker("点按后效果", selection: Binding(get: { store.appearance.widget.textCompletion }, set: { widget.wrappedValue.completedTextStyle = $0 })) {
            ForEach(WidgetTextCompletion.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.menu)
        if store.appearance.widget.textCompletion == .color {
            StyleColorControl(title: "完成文字色", value: Binding(get: { store.appearance.widget.completionColor }, set: { widget.wrappedValue.completedTextColor = $0 }))
        }
        if advanced {
            PreciseSlider(title: "Scrim 强度", value: scrimBinding, range: 0...0.8, standard: autoScrim, precision: 2)
            Text(settings.scrimOverride == nil
                 ? String(format: "自动：%.2f", autoScrim)
                 : String(format: "手动：%.2f", settings.scrimOverride ?? 0))
                .font(.caption).foregroundStyle(.secondary)
            PreciseSlider(title: "渐变范围", value: heightBinding, range: 0.25...0.7, standard: ReadableDefaults.scrimHeightRatio, precision: 2)
            Button("全部恢复标准") { resetReadable() }
        } else if settings != ReadableSettings() {
            Text("已使用自定义参数").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var settings: ReadableSettings { store.appearance.widget.readable }
    /// 当前图片在当前锚点上的自动值，滑条的蓝点
    private var autoScrim: Double {
        let id = store.appearance.widget.photoName(at: photoDate)
        let analysis = id.flatMap { name in
            AppearanceStore.shared.cachedAnalysis(for: store.appearance.widget.analysisRequest(photoName: name,
                canvasAspect: family.width / family.height, darkBackground: scheme == .dark), anchor: settings.anchor)
        }
        let tone = ReadableTone.resolve(style: store.appearance.widget, scheme: scheme, renderingMode: .fullColor)
        return settings.autoScrim(analysis: analysis, isLightText: tone.isLightText)
    }
    private func updateAnalysisPriority() {
        store.prioritizePhotoAnalysis(photoName: store.appearance.widget.photoName(at: photoDate), canvasAspect: family.width / family.height)
    }
    private var readableAnchor: Binding<TextAnchor> {
        Binding(get: { settings.anchor }, set: { next in
            var value = widget.wrappedValue
            value.readableAnchor = next
            value.readableEdgeInset = ReadableRules.inset(value.readable.edgeInset, anchor: next,
                canvasHeight: readableGeometry.canvasHeight, textHeight: readableGeometry.textHeight)
            widget.wrappedValue = value
        })
    }
    private var readableIntensity: Binding<ReadabilityIntensity> {
        Binding(get: { settings.intensity }, set: { next in
            widget.wrappedValue.readableIntensity = next
            // 手动 Scrim 会盖住强度，这里一并清掉让强度立刻生效
            widget.wrappedValue.readableScrimOverride = nil
        })
    }
    /// 拖到蓝点附近 = 清除手动覆盖，回到自动
    private var scrimBinding: Binding<Double> {
        Binding(get: { settings.scrim(auto: autoScrim) },
                set: { newValue in
                    if abs(newValue - autoScrim) < 0.02 {
                        widget.wrappedValue.readableScrimOverride = nil
                    } else {
                        widget.wrappedValue.readableScrimOverride = newValue
                    }
                })
    }
    private var heightBinding: Binding<Double> {
        Binding(get: { settings.heightRatio }, set: { widget.wrappedValue.readableHeightRatio = $0 })
    }
    private var edgeLabel: String {
        switch settings.anchor {
        case .top: return "顶部留白"
        case .center: return "垂直偏移"
        case .bottom: return "底部留白"
        }
    }
    private var edgeRange: ClosedRange<Double> {
        ReadableRules.insetRange(anchor: settings.anchor, canvasHeight: readableGeometry.canvasHeight, textHeight: readableGeometry.textHeight)
    }
    private var edgeBinding: Binding<Double> {
        Binding(get: { ReadableRules.inset(settings.edgeInset, anchor: settings.anchor,
                    canvasHeight: readableGeometry.canvasHeight, textHeight: readableGeometry.textHeight) },
                set: { widget.wrappedValue.readableEdgeInset = ReadableRules.inset($0, anchor: settings.anchor,
                    canvasHeight: readableGeometry.canvasHeight, textHeight: readableGeometry.textHeight) })
    }
    private func clampReadableInset(geometry: ReadableContentGeometry) {
        let clamped = ReadableRules.inset(settings.edgeInset, anchor: settings.anchor,
            canvasHeight: geometry.canvasHeight, textHeight: geometry.textHeight)
        if clamped != settings.edgeInset { widget.wrappedValue.readableEdgeInset = clamped }
    }
    private func reloadWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
    }
    private func resetReadable() {
        widget.wrappedValue.readableAnchor = nil
        widget.wrappedValue.readableIntensity = .standard
        widget.wrappedValue.readableScrimOverride = nil
        widget.wrappedValue.readableHeightRatio = nil
        widget.wrappedValue.readableShadowPreset = nil
        widget.wrappedValue.readableEdgeInset = nil
        reloadWidget()
    }
    @ViewBuilder private var markerControls: some View {
        Toggle("统一标记（对所有待办生效）", isOn: Binding(
            get: { store.appearance.widget.unifiedMarkers ?? false },
            set: { widget.wrappedValue.unifiedMarkers = $0 }))
        Menu {
            Button("小组件默认") { selectedTaskID = nil }
            ForEach(store.items) { item in Button(item.title) { selectedTaskID = item.id } }
        } label: { Label(selectedTask?.title ?? "小组件默认", systemImage: selectedTask == nil ? "square.grid.2x2" : "pencil.circle").lineLimit(2) }
        if let item = selectedTask {
            Group {
                MarkerChoiceEditor(choice: Binding(get: { store.appearance.marker(for: item, widgetContext: true) }, set: { setTaskMarker($0, id: item.id) }))
                if item.marker != nil { Button("恢复小组件默认") { setTaskMarker(nil, id: item.id) } }
            }
            MarkerStyleEditor(style: widget.markerStyle, kind: store.appearance.marker(for: item, widgetContext: true).kind, advanced: advanced)
            Text("此项标记单独保存；尺寸与完成效果用于整个小组件。").font(.caption).foregroundStyle(.secondary)
        } else {
            Group {
                Toggle("继承壁纸标记", isOn: Binding(get: { store.appearance.widget.markerOverride == nil }, set: { inherit in
                    var next = store.appearance
                    if inherit { previousWidgetMarker = next.widget.markerOverride; next.widget.markerOverride = nil }
                    else { next.widget.markerOverride = previousWidgetMarker ?? next.defaultMarker }
                    store.setAppearance(next)
                }))
                if store.appearance.widget.markerOverride != nil {
                    MarkerChoiceEditor(choice: Binding(get: { store.appearance.widget.markerOverride ?? store.appearance.defaultMarker }, set: { value in
                        var next = store.appearance; next.widget.markerOverride = value; store.setAppearance(next)
                    }))
                }
            }
            MarkerStyleEditor(style: widget.markerStyle,
                kind: (store.appearance.widget.markerOverride ?? store.appearance.defaultMarker).kind, advanced: advanced)
        }
        if advanced {
            Text("继承壁纸的标记类型与 Emoji；大小、间距和完成效果在这里独立设置。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var selectedTask: TodoItem? { store.items.first { $0.id == selectedTaskID } }
    private var hasVisibleMarker: Bool {
        (store.appearance.widget.markerOverride ?? store.appearance.defaultMarker).kind != .none ||
        store.items.contains { store.appearance.marker(for: $0, widgetContext: true).kind != .none }
    }
    private func setTaskMarker(_ marker: TodoMarker?, id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        do { try store.edit(id: id, title: item.title, marker: marker) }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private var contentControls: some View {
        InspectorGroupTitle(title: "显示内容", detail: "控制数量、筛选和辅助说明。")
        Toggle("显示左下角说明", isOn: Binding(get: { store.appearance.widget.footerVisible }, set: { widget.wrappedValue.showsFooter = $0 }))
        Toggle("显示未完成数量", isOn: heading.showsSummary)
        Toggle("显示行分隔线", isOn: Binding(get: { store.appearance.widget.separatesRows }, set: { widget.wrappedValue.showsSeparators = $0 }))
        Stepper("最多 \(store.appearance.widget.maximumItems) 项", value: widget.maximumItems, in: 1...10)
        Picker("完成事项", selection: widget.completed) { ForEach(WidgetCompleted.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
        Button("请求更新小组件") { store.flushAppearance(); store.reload() }
    }
    private var help: some View {
        NavigationStack {
            List {
                Section("添加与操作") {
                    Text("长按主屏幕，添加 Todo Wallpaper 小组件。点击任务可直接完成或恢复。")
                    Text("点预览标记可编辑该任务的 Emoji；点文字试完成或恢复。试点状态只留在预览，重置按钮可清除。单项标记修改会保存到真实任务。")
                    Text("预览遵守完成事项筛选。若试完成后该项隐藏，可重置预览，或选择显示全部事项来比较效果。")
                    Text("小组件字体随系统文字大小调整。较大的标记或字体会减少可显示行数，不会让滑块后半段失效。")
                }
                Section("背景与透明度") {
                    Text("不透明度 0 表示不绘制自定义底色，1 表示完全实色。它不控制系统为小组件合成的背景材质。")
                    Text("可选本地照片作为背景；这是组件自己的照片，不是让主屏幕壁纸透过。系统可能在着色模式下调整最终效果。")
                }
                Section("标记") { Text("单项标记优先于小组件默认，再到壁纸标记。壁纸标记只作静态装饰，小组件的完成效果独立设置。") }
            }
            .navigationTitle("小组件帮助").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHelp = false } } }
        }
    }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(uiColor: .secondarySystemGroupedBackground)))
            let step: CGFloat = 14
            for y in 0...Int(size.height / step) {
                for x in 0...Int(size.width / step) where (x + y).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(x) * step, y: CGFloat(y) * step, width: step, height: step)),
                        with: .color(.secondary.opacity(0.07)))
                }
            }
        }.accessibilityHidden(true)
    }
}
