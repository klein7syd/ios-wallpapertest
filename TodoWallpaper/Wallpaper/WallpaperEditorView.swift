import SwiftUI
import PhotosUI
import UIKit

private enum WallpaperTool: String, CaseIterable {
    case background = "背景", panel = "面板", text = "文字", marker = "标记", output = "导出"
    var icon: String {
        switch self { case .background: return "photo"; case .panel: return "rectangle.center.inset.filled"
        case .text: return "textformat"; case .marker: return "face.smiling"; case .output: return "square.and.arrow.up" }
    }
}
struct WallpaperEditorView: View {
    @ObservedObject var store: TodoStore
    @StateObject private var model = WallpaperEditorModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var tool = WallpaperTool.background
    @State private var expanded = true
    @State private var fullScreen = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var resetConfirmation = false
    @State private var aspect = WallpaperAspect.modern
    @State private var quality = WallpaperQuality.high
    @State private var ratioWidth = "9", ratioHeight = "19.5"
    @State private var pixelWidth = "1890", pixelHeight = "4096"
    private var dataReady: Bool { store.hasLoaded && store.loadError == nil }
    private var canExport: Bool { dataReady && model.ready && !model.busy && !model.draftBlocked && store.appearanceError == nil && model.previewError == nil }
    private var appearance: Binding<TodoAppearance> {
        Binding(get: { store.appearance }, set: { store.setAppearance($0) })
    }
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                if dataReady {
                    WallpaperLiveCanvas(model: model, editsBackground: tool == .background)
                        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, expanded ? 132 : 64)
                } else {
                    ContentUnavailableView("请先读取待办", systemImage: "checklist", description: Text(store.loadError ?? "正在读取"))
                }
                inspector.padding(.horizontal, 10).padding(.bottom, 6)
            }
            .navigationTitle("壁纸").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { fullScreen = true } label: { Label("全屏预览", systemImage: "arrow.up.left.and.arrow.down.right") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("重新读取待办", systemImage: "arrow.clockwise") { store.flushAppearance(); store.reload() }
                        Button("恢复壁纸默认排版", systemImage: "arrow.counterclockwise") { resetConfirmation = true }
                    } label: { Label("更多", systemImage: "ellipsis.circle") }.disabled(model.busy)
                }
            }
            .task { await model.start(items: store.items, appearance: store.appearance); syncOutputFields() }
            .onChange(of: store.items) { _, items in model.updateItems(items) }
            .onChange(of: store.appearance) { _, value in model.updateAppearance(value) }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                Task { await model.importPhoto(selection); selectedPhoto = nil }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { Task { await model.saveNow() } } }
            .onDisappear { store.flushAppearance(); Task { await model.saveNow() } }
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
    }
    private var inspector: some View {
        VStack(spacing: 10) {
            HStack {
                Text(model.settings.size.label + " px").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(tool == .background ? "拖动背景 · 双指缩放" : "拖动面板 · 靠近中心可对齐")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                }.accessibilityLabel(expanded ? "收起参数" : "展开参数")
            }
            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.draftBlocked { Text("草稿已保留，请用右上角菜单确认恢复默认。").font(.caption).foregroundStyle(.red) }
                        if let error = store.appearanceError { Text(error).font(.caption).foregroundStyle(.red) }
                        switch tool {
                        case .background: backgroundControls
                        case .panel: panelControls
                        case .text: textControls
                        case .marker: markerControls
                        case .output: outputControls
                        }
                    }.padding(.horizontal, 4).padding(.vertical, 4)
                }
                .frame(height: 184).scrollDismissesKeyboard(.interactively)
                .disabled(!model.ready || model.busy || model.draftBlocked)
            }
            HStack(spacing: 0) {
                ForEach(WallpaperTool.allCases, id: \.self) { item in
                    Button { tool = item; expanded = true } label: {
                        VStack(spacing: 3) { Image(systemName: item.icon); Text(item.rawValue).font(.caption2) }
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .foregroundStyle(tool == item ? Color.accentColor : Color.secondary)
                    }.buttonStyle(.plain).accessibilityAddTraits(tool == item ? .isSelected : [])
                }
            }
        }
        .padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.primary.opacity(0.06), lineWidth: 0.5))
    }
    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.12).ignoresSafeArea()
            ProgressView(model.isImporting ? "正在读取照片…" : "正在生成 \(model.settings.size.label) PNG…")
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
    @ViewBuilder private var backgroundControls: some View {
        let title = model.hasPhoto ? "更换背景照片" : "选择背景照片"
        PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
            Label(title, systemImage: "photo")
        }.buttonStyle(.bordered)
        if model.hasPhoto {
            PreciseSlider(title: "等比例缩放", value: $model.settings.backgroundZoom, range: 1...4)
            DisclosureGroup("精确偏移") {
                VStack(spacing: 12) {
                    PreciseSlider(title: "水平", value: $model.settings.backgroundPanX, range: -1...1)
                    PreciseSlider(title: "垂直", value: $model.settings.backgroundPanY, range: -1...1)
                    Button("重置裁剪") { model.settings.backgroundZoom = 1; model.settings.backgroundPanX = 0; model.settings.backgroundPanY = 0 }
                    Button("使用默认背景") { model.removePhoto() }
                }.padding(.top, 10)
            }
            if let info = model.livePhoto?.info { Text("原图 \(info.label)").font(.caption).foregroundStyle(.secondary) }
            if model.sourceIsSoft { Text("原图或当前裁剪的有效像素不足，放大不能补出细节。").font(.caption).foregroundStyle(.secondary) }
        }
        Text("照片留在本机，预览不会添加相册图片。").font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private var panelControls: some View {
        PreciseSlider(title: "宽度比例", value: $model.settings.panelWidth, range: 0.3...0.96)
        Toggle("自动高度", isOn: $model.settings.automaticHeight)
        if !model.settings.automaticHeight { PreciseSlider(title: "高度比例", value: $model.settings.panelHeight, range: 0.12...0.94) }
        Toggle("自定义位置（也可直接拖动）", isOn: $model.settings.customPosition)
        if model.settings.customPosition {
            PreciseSlider(title: "水平中心", value: $model.settings.panelX, range: 0...1)
            PreciseSlider(title: "垂直中心", value: $model.settings.panelY, range: 0...1)
            HStack {
                nudge("arrow.left", dx: -1, dy: 0); nudge("arrow.right", dx: 1, dy: 0)
                nudge("arrow.up", dx: 0, dy: -1); nudge("arrow.down", dx: 0, dy: 1)
                Spacer(); Button("居中") { model.settings.panelX = 0.5; model.settings.panelY = 0.5 }
            }
            Text("箭头每次移动 1 个输出像素；切换分辨率仍保留相对构图。").font(.caption).foregroundStyle(.secondary)
        }
        PreciseSlider(title: "玻璃不透明度", value: $model.settings.glassOpacity, range: 0...0.85)
        PreciseSlider(title: "模糊程度", value: $model.settings.blurRadius, range: 0...45)
        Toggle("深色底色", isOn: $model.settings.darkGlass)
        DisclosureGroup("圆角、边框与间距") {
            VStack(spacing: 12) {
                PreciseSlider(title: "圆角", value: $model.settings.cornerRadius, range: 0...80)
                PreciseSlider(title: "边框", value: $model.settings.borderOpacity, range: 0...1)
                PreciseSlider(title: "高光", value: $model.settings.highlight, range: 0...0.6)
                PreciseSlider(title: "内边距", value: $model.settings.padding, range: 8...48)
            }.padding(.top, 10)
        }
    }
    private func nudge(_ icon: String, dx: Double, dy: Double) -> some View {
        Button {
            guard let layout = model.layout?.positioned(using: model.settings) else { return }
            model.settings.panelX = min(1, max(0, Double(layout.panel.midX / 390) + dx / Double(model.settings.size.width)))
            model.settings.panelY = min(1, max(0, Double(layout.panel.midY / layout.canvas.height) + dy / Double(model.settings.size.height)))
        } label: { Image(systemName: icon) }.buttonStyle(.bordered).accessibilityLabel("面板移动一个像素 \(icon)")
    }
    @ViewBuilder private var textControls: some View {
        StyleColorControl(title: "文字颜色", value: $model.settings.textColor)
        PreciseSlider(title: "字号", value: $model.settings.fontSize, range: 10...38)
        Picker("字重", selection: $model.settings.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        Picker("字体", selection: $model.settings.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }
        Toggle("包含已完成事项", isOn: $model.settings.includeCompleted)
        Stepper("最多 \(model.settings.maximumItems) 项", value: $model.settings.maximumItems, in: 1...20)
        DisclosureGroup("排版细节") {
            VStack(spacing: 12) {
                Picker("对齐", selection: $model.settings.alignment) { ForEach(WallpaperAlignment.allCases) { Text($0.title).tag($0) } }
                PreciseSlider(title: "行间距", value: $model.settings.lineSpacing, range: 0...20)
                PreciseSlider(title: "事项间距", value: $model.settings.itemSpacing, range: 0...36)
                Stepper("每项最多 \(model.settings.maximumLines) 行", value: $model.settings.maximumLines, in: 1...8)
                Picker("完成文字", selection: $model.settings.completionStyle) { ForEach(WallpaperCompletionStyle.allCases) { Text($0.title).tag($0) } }
            }.padding(.top, 10)
        }
    }
    @ViewBuilder private var markerControls: some View {
        Text("全局默认标记 · 单项覆盖可在待办编辑页设置").font(.caption).foregroundStyle(.secondary)
        MarkerChoiceEditor(choice: appearance.defaultMarker)
        MarkerStyleEditor(style: appearance.markerStyle)
        Button("将壁纸样式应用到小组件") { applyWidgetStyle() }.buttonStyle(.bordered)
        NavigationLink("独立编辑小组件外观") { WidgetAppearanceEditor(store: store) }
    }
    @ViewBuilder private var outputControls: some View {
        Picker("画布比例", selection: Binding(get: { aspect }, set: { chooseAspect($0) })) {
            ForEach(WallpaperAspect.allCases) { Text($0.title).tag($0) }
        }
        if aspect == .custom {
            HStack { Text("宽:高"); TextField("宽", text: $ratioWidth); Text(":"); TextField("高", text: $ratioHeight); Button("应用") { applyRatio() } }
                .keyboardType(.decimalPad)
        }
        Text("19.5:9 为通用近似，实际屏幕可能有微小裁剪。图片保持比例，重要内容请留在安全边距内。")
            .font(.caption).foregroundStyle(.secondary)
        Picker("输出分辨率", selection: Binding(get: { quality }, set: { chooseQuality($0) })) {
            ForEach(WallpaperQuality.allCases) { Text($0.title).tag($0) }
        }
        if quality == .custom {
            HStack { TextField("宽 px", text: $pixelWidth); Text("×"); TextField("高 px", text: $pixelHeight); Button("应用") { applyPixels() } }.keyboardType(.numberPad)
        }
        Text("输出 \(model.settings.size.label) · 相册保存前会校验实际 PNG 像素尺寸").font(.caption)
        HStack {
            Button { Task { await model.export(saveToPhotos: true) } } label: { Label("保存相册", systemImage: "square.and.arrow.down") }
            Button { Task { await model.export(saveToPhotos: false) } } label: { Label("系统分享", systemImage: "square.and.arrow.up") }
        }.buttonStyle(.borderedProminent).disabled(!canExport)
        if let size = model.lastExportSize { Text("最近成品已校验：\(size) px").font(.caption) }
        Button("将壁纸样式应用到小组件") { applyWidgetStyle() }
        Button("清理导出缓存") { Task { await model.clearCache() } }
        Text("导出为静态 SDR PNG，需手动设置系统壁纸。全屏的“精确预览”可检查稳定后的原生渲染结果。")
            .font(.caption).foregroundStyle(.secondary)
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
        var next = store.appearance
        next.widget.font = model.settings.font; next.widget.weight = model.settings.weight
        next.widget.textColor = model.settings.textColor; next.widget.followsSystemText = false
        next.widget.theme = model.settings.darkGlass ? .dark : .light; next.widget.backdrop = .solid
        let gray = model.settings.darkGlass ? 0.12 : 0.93
        next.widget.panelColor = WallpaperColor(red: gray, green: gray, blue: gray)
        next.widget.markerStyle = next.markerStyle; next.widget.markerOverride = next.defaultMarker
        store.setAppearance(next); store.flushAppearance()
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
        }
    }
}
private struct WallpaperShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
