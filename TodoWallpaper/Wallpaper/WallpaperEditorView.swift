import SwiftUI
import PhotosUI
import UIKit

private struct WallpaperEditState: Equatable {
    var settings: WallpaperSettings
    var photoName: String?
    var previewScale: Double
    var marker: TodoMarker
    var markerStyle: MarkerStyle
    var taskMarkers: [UUID: TodoMarker]
    var widgetStyle: WidgetAppearance
}

struct WallpaperEditorView: View {
    @ObservedObject var store: TodoStore
    @EnvironmentObject private var lianxinModel: LianxinModel
    @AppStorage(ContentMode.key) private var contentMode = "todo"
    @State private var hasSyncedPhoto = false
    @State private var appliedSharedPhoto: String?
    private var isLianxin: Bool { contentMode == "lianxin" }
    private var contentItems: [TodoItem] { isLianxin ? WallpaperContentSource.lianxin(lianxinModel.publication).items : store.items }
    private var editingAppearance: TodoAppearance {
        var root = store.appearance
        if isLianxin { root.widget = root.style(in: .lianxin); root.defaultMarker = TodoMarker(kind: .none) }
        return root
    }
    @discardableResult private func setEditingAppearance(_ value: TodoAppearance) -> Bool {
        var root = store.appearance
        if isLianxin { root.lianxin = value.widget } else { root = value }
        return store.setAppearance(root)
    }
    private var textFits: Bool { !isLianxin || (model.layout?.hiddenCount == 0 && model.layout?.rows.isEmpty == false && model.layout?.rows.allSatisfy { !$0.block.truncated } == true && !lianxinModel.profile.message.isEmpty && lianxinModel.profile.message.count <= 200) }
    private func syncPhoto() async {
        guard isLianxin, model.ready, !model.busy else { return }
        let name = store.appearance.lianxin?.photoName(at: .now)
        guard !hasSyncedPhoto || name != appliedSharedPhoto else { return }
        do {
            if let data = try await lianxinModel.wallpaperPhotoData() { try await model.importPhotoData(data) }
            else { model.removePhoto() }
            appliedSharedPhoto = name; hasSyncedPhoto = true
        } catch { model.message = "连心底图暂未更新，请重试。" }
    }
    private func removeBackdrop() {
        model.removePhoto()
        if isLianxin { Task { await lianxinModel.setPhoto(nil) } }
    }
    @Binding var navigation: AppNavigationState
    @ObservedObject var model: WallpaperEditorModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(EditorStandards.advancedKey) private var advanced = false
    @StateObject private var edits = EditorUndoState<WallpaperEditState>()
    @AppStorage(EditorStandards.previewScaleKey) private var previewScale = 1.0
    @State private var markerTaskID: UUID?
    @State private var fullScreen = false
    @State private var isVisible = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var resetConfirmation = false
    @State private var aspect = WallpaperAspect.modern
    @State private var quality = WallpaperQuality.high
    @State private var ratioWidth = "9"
    @State private var ratioHeight = "19.5"
    @State private var pixelWidth = "1890"
    @State private var pixelHeight = "4096"
    private var tool: WallpaperTool { navigation.wallpaperTool }
    private var dataReady: Bool { store.hasLoaded && store.loadError == nil }
    private var canExport: Bool { dataReady && model.ready && !model.busy && !model.draftBlocked && store.appearanceError == nil && model.previewError == nil && textFits }
    private var appearance: Binding<TodoAppearance> {
        Binding(get: { editingAppearance }, set: { setEditingAppearance($0); model.updateAppearance(editingAppearance) })
    }
    private var editState: WallpaperEditState {
        WallpaperEditState(settings: model.settings, photoName: model.photoName, previewScale: previewScale,
            marker: editingAppearance.defaultMarker, markerStyle: editingAppearance.markerStyle,
            taskMarkers: Dictionary(uniqueKeysWithValues: contentItems.compactMap { item in item.marker.map { (item.id, $0) } }),
            widgetStyle: editingAppearance.widget)
    }
    private var layoutScale: Binding<Double> {
        Binding(get: { model.settings.fontSize / 18 }, set: { scale in
            model.settings = model.settings.withStandardScale(scale)
            var next = editingAppearance
            next.markerStyle = EditorStandards.marker(next.markerStyle, scale: scale)
            setEditingAppearance(next); model.updateAppearance(editingAppearance)
        })
    }
    private var editorInteraction: EditorInteractionContext {
        let base = edits.context(read: { editState })
        return EditorInteractionContext(begin: { key in store.beginAppearanceInteraction(); base.begin(key) },
            end: { base.end(); store.endAppearanceInteraction() }, pulse: base.pulse)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 8) {
                    if dataReady {
                        WallpaperLiveCanvas(model: model, editsBackground: tool == .background,
                            editable: navigation.isEditing)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped().accessibilityIdentifier("wallpaper.canvas")
                    } else {
                        ContentUnavailableView("请先读取待办", systemImage: "checklist", description: Text(store.loadError ?? "正在读取"))
                    }
                    inspector(height: EditorSizing.wallpaperInspectorHeight(available: geometry.size.height,
                        expanded: navigation.inspectorExpanded, advanced: advanced, previewScale: previewScale))
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: navigation.inspectorExpanded)
                .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 6)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("壁纸").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isLianxin ? "切换回待办" : "切换到连心") { contentMode = isLianxin ? "todo" : "lianxin" }.disabled(model.busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { undoEdit() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                        .disabled(!edits.canUndo || model.busy || model.draftBlocked)
                        .accessibilityIdentifier("wallpaper.undo")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { fullScreen = true } label: { Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("重新读取待办", systemImage: "arrow.clockwise") { store.flushAppearance(); store.reload() }
                        Button("恢复壁纸默认排版", systemImage: "arrow.counterclockwise") { resetConfirmation = true }
                        Button(navigation.inspectorExpanded ? "收起设置" : "展开设置", systemImage: "slider.horizontal.3") { toggleInspector() }
                    } label: { Label("更多", systemImage: "ellipsis.circle") }.disabled(model.busy)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .task {
                if isLianxin { await lianxinModel.load(); await lianxinModel.prepareStyle(store) }
                await model.start(items: contentItems, appearance: editingAppearance)
                if isLianxin {
                    model.settings.usesTaskMarkers = true
                    if navigation.wallpaperTool == .marker { navigation.selectTool(.text) }
                    await syncPhoto()
                }
                syncOutputFields()
            }
            .onChange(of: model.busy) { _, busy in if !busy { Task { await syncPhoto() } } }
            .onChange(of: store.appearance.lianxin?.photoName(at: .now)) { _, _ in Task { await syncPhoto() } }
            .onChange(of: model.ready) { _, ready in
                if ready { syncOutputFields(); edits.synchronize(editState) }
            }
            .onAppear { isVisible = true; configureAssetRetention(); if model.ready { edits.synchronize(editState) } }
            .onChange(of: editState) { _, state in if model.ready && isVisible { edits.observe(state) } }
            .onChange(of: advanced) { _, _ in edits.finish(editState) }
            .onChange(of: contentItems) { _, items in model.updateItems(items) }
            .onChange(of: editingAppearance) { _, value in model.updateAppearance(value) }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                Task {
                    if isLianxin {
                        do {
                            guard let data = try await selection.loadTransferable(type: Data.self) else { throw WallpaperError.unreadablePhoto }
                            await lianxinModel.setPhoto(data); await syncPhoto()
                        } catch { model.message = error.localizedDescription }
                    } else { await model.importPhoto(selection) }
                    selectedPhoto = nil
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.saveNow() } } }
            .onDisappear { edits.finish(editState); isVisible = false; store.flushAppearance(); Task { await model.saveNow() } }
            .fullScreenCover(isPresented: $fullScreen) { WallpaperFullPreview(model: model, editsBackground: tool == .background) }
            .sheet(item: $model.shareFile) { WallpaperShareSheet(url: $0.url) }
            .overlay { if model.busy { busyOverlay } }
            .alert("壁纸", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                if model.needsPhotoPermission {
                    Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                }
                Button("好", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .confirmationDialog("恢复默认排版？", isPresented: $resetConfirmation, titleVisibility: .visible) {
                Button("恢复默认") { Task { await model.resetLayout() } }
            } message: { Text("保留照片、画布比例和输出尺寸。待办与单项 Emoji 不变。") }
        }
        .environment(\.editorInteraction, editorInteraction)
    }
    private func toggleInspector() {
        edits.finish(editState)
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { navigation.toggleInspector() }
    }
    private func configureAssetRetention() {
        edits.retainedValuesChanged = { values in
            let names = values.reduce(into: Set<String>()) { result, value in
                result.formUnion(PhotoAssetReferences.marker(value.marker))
                result.formUnion(PhotoAssetReferences.widget(value.widgetStyle))
                for marker in value.taskMarkers.values { result.formUnion(PhotoAssetReferences.marker(marker)) }
            }
            store.retainPhotoAssets(names, owner: "wallpaper")
        }
        edits.retainedValuesChanged(edits.retainedValues)
    }
    private func undoEdit() {
        Task {
            do {
                try await edits.undo(read: { editState }) { previous, expected in
                    var next = editingAppearance
                    if previous.marker != expected.marker { next.defaultMarker = previous.marker }
                    if previous.markerStyle != expected.markerStyle { next.markerStyle = previous.markerStyle }
                    if previous.widgetStyle != expected.widgetStyle { next.widget = previous.widgetStyle }
                    try next.validate()
                    if model.settings != previous.settings || model.photoName != previous.photoName {
                        try await model.restoreEditorState(settings: previous.settings, photoName: previous.photoName)
                    }
                    let ids = Set(previous.taskMarkers.keys).union(expected.taskMarkers.keys)
                    let changes = ids.filter { previous.taskMarkers[$0] != expected.taskMarkers[$0] }.map {
                        TodoMarkerUpdate(id: $0, expected: expected.taskMarkers[$0], marker: previous.taskMarkers[$0])
                    }
                    try store.updateMarkers(changes)
                    if previous.previewScale != expected.previewScale { previewScale = previous.previewScale }
                    if next != editingAppearance { setEditingAppearance(next); model.updateAppearance(editingAppearance) }
                    model.updateItems(contentItems)
                }
                syncOutputFields()
            } catch { model.message = "未能撤销：\(error.localizedDescription)" }
        }
    }
    private func inspector(height: Double) -> some View {
        VStack(spacing: 8) {
            if !textFits { Text("请将话语缩至200字以内，并调整字号/面板宽度使全部文字及创作标注完整显示。").font(.caption).foregroundStyle(.red) }
            if navigation.inspectorExpanded {
                InspectorViewport(pageID: tool.id + (advanced ? ".advanced" : ".basic") +
                    (tool == .marker ? (selectedMarkerTask?.id.uuidString ?? ".uniform") : "")) {
                    if model.draftBlocked { Text("草稿已保留，请用右上角菜单确认恢复默认。").font(.caption).foregroundStyle(.red) }
                    if let error = store.appearanceError { Text(error).font(.caption).foregroundStyle(.red) }
                    switch tool {
                    case .background: backgroundControls
                    case .panel: panelControls
                    case .text: textControls
                    case .marker: markerControls
                    case .output: outputControls
                    }
                }
                .frame(maxHeight: .infinity)
                .padding(.top, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .disabled(!model.ready || model.busy || model.draftBlocked)
            }
            toolSelector.frame(height: 44)
        }
        .frame(height: height)
        .accessibilityIdentifier("wallpaper.inspector")
    }
    private var toolSelector: some View {
        HStack(spacing: 6) {
            EditorToolPicker(choices: WallpaperTool.allCases.filter { !isLianxin || $0 != .marker },
                selection: Binding(get: { tool }, set: { next in
                    edits.finish(editState)
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) { navigation.selectTool(next) }
                }), title: { $0.title })
            Button {
                toggleInspector()
            } label: {
                Image(systemName: navigation.inspectorExpanded ? "chevron.down" : "chevron.up")
                    .font(.subheadline).frame(width: 44, height: 44)
            }.buttonStyle(.plain)
                .accessibilityLabel(navigation.inspectorExpanded ? "收起参数" : "展开参数")
        }
        .padding(.horizontal, 6)
        .accessibilityIdentifier("wallpaper.tools")
    }
    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView(model.isImporting ? "正在读取照片…" : "正在生成 \(model.settings.size.label) PNG…")
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    @ViewBuilder private var backgroundControls: some View {
        let photoTitle = model.hasPhoto ? "更换背景照片" : "选择背景照片"
        InspectorGroupTitle(title: "背景素材", detail: "先选照片，再在上方预览中调整构图。")
        PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
            Label(photoTitle, systemImage: "photo")
        }.buttonStyle(.bordered)
        if model.hasPhoto {
            PreciseSlider(title: "等比例缩放", value: $model.settings.backgroundZoom, range: 1...4, standard: 1, precision: 2)
            if advanced {
                PreciseSlider(title: "水平偏移", value: $model.settings.backgroundPanX, range: -1...1, standard: 0, precision: 2)
                PreciseSlider(title: "垂直偏移", value: $model.settings.backgroundPanY, range: -1...1, standard: 0, precision: 2)
            }
            HStack {
                Button("重置裁剪") { model.settings.backgroundZoom = 1; model.settings.backgroundPanX = 0; model.settings.backgroundPanY = 0 }
                Spacer()
                Button("默认背景") { removeBackdrop() }
            }
            if model.sourceIsSoft { Text("原图或当前裁剪的有效像素不足。").font(.caption).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private var panelControls: some View {
        InspectorGroupTitle(title: "面板布局", detail: "先调整大小和位置，再调整玻璃质感。")
        if !advanced {
            PreciseSlider(title: "排版缩放", value: layoutScale, range: EditorStandards.wallpaperScale, standard: 1, precision: 2)
        } else {
            PreciseSlider(title: "宽度比例", value: $model.settings.panelWidth, range: 0.3...0.96, standard: 0.88, precision: 2)
            Toggle("自动高度", isOn: $model.settings.automaticHeight)
            if !model.settings.automaticHeight {
                PreciseSlider(title: "高度比例", value: $model.settings.panelHeight, range: 0.12...0.94, standard: 0.38, precision: 2)
            }
            Toggle("自定义位置", isOn: $model.settings.customPosition)
            if model.settings.customPosition {
                PreciseSlider(title: "水平中心", value: $model.settings.panelX, range: 0...1, standard: 0.5, precision: 2)
                PreciseSlider(title: "垂直中心", value: $model.settings.panelY, range: 0...1, standard: 0.5, precision: 2)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        nudge("arrow.left", dx: -1, dy: 0); nudge("arrow.right", dx: 1, dy: 0)
                        Spacer()
                        Text("水平微调").font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        nudge("arrow.up", dx: 0, dy: -1); nudge("arrow.down", dx: 0, dy: 1)
                        Spacer()
                        Text("垂直微调").font(.caption).foregroundStyle(.secondary)
                    }
                    Button("居中") { model.settings.panelX = 0.5; model.settings.panelY = 0.5 }
                        .frame(minHeight: 44)
                }
            }
            PreciseSlider(title: "圆角", value: $model.settings.cornerRadius, range: 0...80, standard: 24)
            PreciseSlider(title: "内边距", value: $model.settings.padding, range: 8...48, standard: 20)
        }
        InspectorGroupTitle(title: "玻璃质感", detail: "透明度、模糊和底色共同决定面板效果。")
        PreciseSlider(title: "玻璃不透明度", value: $model.settings.glassOpacity, range: 0...0.85, standard: 0.22, precision: 2)
        PreciseSlider(title: "模糊程度", value: $model.settings.blurRadius, range: 0...45, standard: 22)
        Toggle("深色底色", isOn: $model.settings.darkGlass)
        if advanced {
            PreciseSlider(title: "边框不透明度", value: $model.settings.borderOpacity, range: 0...1, standard: 0.25, precision: 2)
            PreciseSlider(title: "高光", value: $model.settings.highlight, range: 0...0.6, standard: 0.12, precision: 2)
        }
    }
    private func nudge(_ icon: String, dx: Double, dy: Double) -> some View {
        Button {
            guard let layout = model.layout else { return }
            let interaction = edits.coalescingContext(read: { editState })
            interaction.begin("wallpaper.panel.nudge")
            defer { interaction.end() }
            model.settings = model.settings.nudged(in: layout, dx: dx, dy: dy)
        } label: { Image(systemName: icon).frame(minWidth: 44, minHeight: 44) }.buttonStyle(.bordered).accessibilityLabel("面板移动一个像素 \(icon)")
    }
    @ViewBuilder private var textControls: some View {
        InspectorGroupTitle(title: "文字排版", detail: "先调字号与颜色，再选择显示哪些事项。")
        StyleColorControl(title: "文字颜色", value: $model.settings.textColor)
        if advanced {
            PreciseSlider(title: "字号", value: $model.settings.fontSize, range: 10...38, standard: 18)
            if model.settings.filtered(contentItems).contains(where: { model.settings.marker(for: $0, appearance: editingAppearance).kind != .none }) {
                PreciseSlider(title: "标记与文字间距", value: appearance.markerStyle.gap, range: 0...32, standard: 10)
            }
        } else {
            PreciseSlider(title: "排版缩放", value: layoutScale, range: EditorStandards.wallpaperScale, standard: 1, precision: 2)
        }
        Picker("字重", selection: $model.settings.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Picker("字体", selection: $model.settings.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Toggle("包含已完成事项", isOn: $model.settings.includeCompleted)
        Stepper("最多 \(model.settings.maximumItems) 项", value: $model.settings.maximumItems, in: 1...20)
        if advanced {
            Picker("对齐", selection: $model.settings.alignment) { ForEach(WallpaperAlignment.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            PreciseSlider(title: "行间距", value: $model.settings.lineSpacing, range: 0...20, standard: 4)
            PreciseSlider(title: "事项间距", value: $model.settings.itemSpacing, range: 0...36, standard: 12)
            Stepper("每项最多 \(model.settings.maximumLines) 行", value: $model.settings.maximumLines, in: 1...8)
        }
    }
    private var markerTasks: [TodoItem] {
        let ids = model.layout?.rows.map { $0.item.id } ??
            Array(model.settings.filtered(contentItems).prefix(model.settings.maximumItems)).map(\.id)
        return ids.compactMap { id in contentItems.first { $0.id == id } }
    }
    private var selectedMarkerTask: TodoItem? {
        guard model.settings.inheritsTaskMarkers else { return nil }
        return MarkerEditorTarget.selected(items: contentItems, visibleIDs: markerTasks.map(\.id), preferredID: markerTaskID)
    }
    private var wallpaperMarkerChoice: Binding<TodoMarker> {
        Binding(get: {
            if let task = selectedMarkerTask { return model.settings.marker(for: task, appearance: editingAppearance) }
            return editingAppearance.defaultMarker
        }, set: { value in
            if let task = selectedMarkerTask {
                do { try store.edit(id: task.id, title: task.title, marker: value); model.updateItems(contentItems) }
                catch { model.message = error.localizedDescription }
            } else {
                // Choosing a uniform wallpaper marker must visibly change the canvas,
                // even when every task already owns a Widget/Todo Emoji override.
                model.settings.usesTaskMarkers = false
                appearance.defaultMarker.wrappedValue = value
            }
        })
    }
    @ViewBuilder private var markerControls: some View {
        Toggle("使用待办的单项标记", isOn: Binding(get: { model.settings.inheritsTaskMarkers }, set: {
            model.settings.usesTaskMarkers = $0; markerTaskID = nil
        }))
        if model.settings.inheritsTaskMarkers {
            Menu {
                Button("壁纸统一标记") { markerTaskID = nil; model.settings.usesTaskMarkers = false }
                ForEach(markerTasks) { item in Button(item.title) { markerTaskID = item.id } }
            } label: { Label(selectedMarkerTask?.title ?? "默认标记", systemImage: "pencil.circle").lineLimit(2) }
        }
        MarkerChoiceEditor(choice: wallpaperMarkerChoice)
        if markerTasks.isEmpty {
            Text("当前没有可显示的事项。可添加待办，或在文字设置中包含已完成事项。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if let task = selectedMarkerTask, task.marker != nil {
            Button("恢复默认标记") {
                do { try store.edit(id: task.id, title: task.title, marker: nil); model.updateItems(contentItems) }
                catch { model.message = error.localizedDescription }
            }
        }
        MarkerStyleEditor(style: appearance.markerStyle, kind: wallpaperMarkerChoice.wrappedValue.kind, advanced: advanced, showsCompletion: false)
        if model.settings.inheritsTaskMarkers && selectedMarkerTask == nil {
            Text("修改默认样式后，壁纸会统一使用该标记；任务原有 Emoji 仍保留。")
                .font(.caption).foregroundStyle(.secondary)
        }
        if advanced { Button("将壁纸样式应用到小组件") { applyWidgetStyle() }.buttonStyle(.bordered) }
    }
    @ViewBuilder private var outputControls: some View {
        InspectorGroupTitle(title: "成品设置", detail: "确认比例和清晰度后，保存或分享。")
        if advanced { PreciseSlider(title: "编辑预览大小", value: $previewScale, range: 0.55...1, standard: 1, precision: 2) }
        Picker("画布比例", selection: Binding(get: { aspect }, set: { chooseAspect($0) })) {
            ForEach(WallpaperAspect.allCases) { Text($0.title).tag($0) }
        }
        if aspect == .custom {
            HStack { Text("宽:高"); TextField("宽", text: $ratioWidth); Text(":"); TextField("高", text: $ratioHeight); Button("应用") { applyRatio() } }
                .keyboardType(.decimalPad)
        }
        Picker("输出分辨率", selection: Binding(get: { quality }, set: { chooseQuality($0) })) {
            ForEach(WallpaperQuality.allCases) { Text($0.title).tag($0) }
        }
        if quality == .custom {
            HStack { TextField("宽 px", text: $pixelWidth); Text("×"); TextField("高 px", text: $pixelHeight); Button("应用") { applyPixels() } }.keyboardType(.numberPad)
        }
        Text("输出 \(model.settings.size.label) · 相册保存前会校验实际 PNG 像素尺寸").font(.caption)
        VStack(spacing: 12) {
            Button { Task { await model.export(saveToPhotos: true) } } label: { Label("保存相册", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44) }
            Button { Task { await model.export(saveToPhotos: false) } } label: { Label("系统分享", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44) }
        }.buttonStyle(.borderedProminent).disabled(!canExport)
        if let size = model.lastExportSize { Text("最近成品已校验：\(size) px").font(.caption) }
        if advanced {
            Button("将壁纸样式应用到小组件") { applyWidgetStyle() }
            Button("清理导出缓存") { Task { await model.clearCache() } }
            Text("19.5:9 是通用近似比例。照片等比裁剪，重要内容请保留安全边距。")
                .font(.caption).foregroundStyle(.secondary)
            Text("按目标像素重新绘制 SDR PNG。预览不写入相册；静态壁纸需手动设置。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func chooseAspect(_ value: WallpaperAspect) {
        if let ratio = value.ratio { setRatio(ratio) }
        aspect = value
    }
    private func setRatio(_ ratio: Double) {
        do {
            var next = model.settings; next.canvasAspect = ratio
            next = try next.withOutputHeight(quality.height ?? next.size.height)
            model.settings = next; pixelWidth = "\(next.size.width)"; pixelHeight = "\(next.size.height)"
        } catch { model.message = error.localizedDescription }
    }
    private func chooseQuality(_ value: WallpaperQuality) {
        do { if let height = value.height { model.settings = try model.settings.withOutputHeight(height) }; quality = value; syncPixels() }
        catch { model.message = error.localizedDescription }
    }
    private func applyRatio() {
        guard let w = Double(ratioWidth), let h = Double(ratioHeight), w.isFinite, h.isFinite, w > 0, h > 0 else { model.message = WallpaperError.invalidSize.localizedDescription; return }
        setRatio(w / h)
    }
    private func applyPixels() {
        guard let w = Int(pixelWidth), let h = Int(pixelHeight) else { model.message = WallpaperError.invalidSize.localizedDescription; return }
        do { model.settings = try model.settings.withOutputSize(WallpaperSize(width: w, height: h)) }
        catch { model.message = error.localizedDescription }
    }
    private func syncPixels() { pixelWidth = "\(model.settings.size.width)"; pixelHeight = "\(model.settings.size.height)" }
    private func syncOutputFields() {
        let ratio = model.settings.aspectRatio
        aspect = abs(ratio - 9 / 19.5) < 0.001 ? .modern : abs(ratio - 9 / 16) < 0.001 ? .classic : .custom
        quality = model.settings.size.height == 4096 ? .high : model.settings.size.height == 2048 ? .medium : .custom
        ratioWidth = "\(model.settings.size.width)"; ratioHeight = "\(model.settings.size.height)"; syncPixels()
    }
    private func applyWidgetStyle() {
        var next = editingAppearance
        next.widget.font = model.settings.font; next.widget.weight = model.settings.weight
        next.widget.textColor = model.settings.textColor; next.widget.followsSystemText = false
        next.widget.theme = model.settings.darkGlass ? .dark : .light; next.widget.backdrop = .solid
        let gray = model.settings.darkGlass ? 0.12 : 0.93
        next.widget.panelColor = WallpaperColor(red: gray, green: gray, blue: gray)
        let completion = next.widget.markerStyle.completion
        let completionEmoji = next.widget.markerStyle.completionEmoji
        let completionColor = next.widget.markerStyle.completedColor
        next.widget.markerStyle = next.markerStyle; next.widget.markerOverride = next.defaultMarker
        next.widget.markerStyle.completion = completion
        next.widget.markerStyle.completionEmoji = completionEmoji
        next.widget.markerStyle.completedColor = completionColor
        setEditingAppearance(next); store.flushAppearance()
        model.message = store.appearanceError ?? "已将文字、字体、标记与主题应用到小组件，并请求系统刷新。单项 Emoji 保持优先。"
    }
}
private struct WallpaperFullPreview: View {
    @ObservedObject var model: WallpaperEditorModel
    let editsBackground: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var exact = false
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if exact, let preview = model.preview, !model.isRendering {
                    Image(decorative: preview.image, scale: 1).resizable().scaledToFit()
                } else { WallpaperLiveCanvas(model: model, editsBackground: editsBackground, editable: !exact) }
                if exact && model.isRendering { ProgressView("正在生成精确预览…").padding().background(.regularMaterial, in: Capsule()) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回编辑") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Toggle("精确预览", isOn: $exact).font(.caption) }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: exact) { _, value in model.requestExactPreview(value) }
            .onDisappear { model.requestExactPreview(false) }
        }
    }
}
private struct WallpaperShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
