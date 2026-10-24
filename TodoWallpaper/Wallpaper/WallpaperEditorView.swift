import SwiftUI
import PhotosUI
import UIKit

private enum WallpaperControlSection: String, CaseIterable {
    case background = "背景", panel = "面板", text = "文字", output = "导出"
}

struct WallpaperEditorView: View {
    @ObservedObject var store: TodoStore
    @StateObject private var model = WallpaperEditorModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var section = WallpaperControlSection.background
    @State private var showControls = true
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var resetConfirmation = false
    @State private var preset = WallpaperPreset.iPhone13Pro
    @State private var customWidth = "1170"
    @State private var customHeight = "2532"
    @State private var dragStart: CGPoint?
    @State private var zoomStart: Double?

    private var dataReady: Bool { store.hasLoaded && store.loadError == nil }
    private var canExport: Bool { dataReady && model.ready && !model.busy && !model.draftBlocked && model.previewError == nil }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    canvas
                        .frame(height: showControls ? min(geometry.size.height * 0.46, 370) : max(100, geometry.size.height - 38))
                        .padding(.horizontal, 16).padding(.top, 8)
                    HStack {
                        Text(model.settings.size.label + " px")
                        Spacer()
                        if model.isRendering { ProgressView().controlSize(.mini) }
                        else if let preview = model.preview {
                            Text("\(preview.layout.rows.count) 项" + (preview.layout.hiddenCount > 0 ? " · 另有 \(preview.layout.hiddenCount) 项" : ""))
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 6)
                    if showControls {
                        Picker("编辑分类", selection: $section) {
                            ForEach(WallpaperControlSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 4)
                        Form {
                            if model.draftBlocked {
                                Section { Text("草稿文件已保留，请从右上角菜单确认恢复默认。待办和小组件不受影响。").foregroundStyle(.secondary) }
                            }
                            switch section {
                            case .background: backgroundControls
                            case .panel: panelControls
                            case .text: textControls
                            case .output: outputControls
                            }
                        }
                        .disabled(!model.ready || model.busy || model.draftBlocked)
                        .scrollDismissesKeyboard(.interactively)
                    }
                }
            }
            .navigationTitle("壁纸")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { withAnimation(.snappy) { showControls.toggle() } } label: {
                        Label(showControls ? "完整预览" : "显示编辑选项", systemImage: showControls ? "arrow.up.left.and.arrow.down.right" : "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("重新读取待办", systemImage: "arrow.clockwise") { store.reload() }
                        Button("恢复排版默认值", systemImage: "arrow.counterclockwise") { resetConfirmation = true }
                    } label: { Label("更多", systemImage: "ellipsis.circle") }
                    .disabled(model.busy)
                }
            }
            .overlay {
                if model.busy {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                        ProgressView(model.isImporting ? "正在读取照片…" : "正在生成 \(model.settings.size.label) PNG…")
                            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                }
            }
            .task {
                await model.start(items: store.items)
                syncSizeFields()
            }
            .onChange(of: store.items) { _, items in model.updateItems(items) }
            .onChange(of: selectedPhoto) { _, selection in
                guard let selection else { return }
                Task { await model.importPhoto(selection); selectedPhoto = nil }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { Task { await model.saveNow() } }
            }
            .onDisappear { Task { await model.saveNow() } }
            .sheet(item: $model.shareFile) { file in WallpaperShareSheet(url: file.url) }
            .alert("壁纸", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                if model.needsPhotoPermission {
                    Button("打开系统设置") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                Button("好", role: .cancel) { model.message = nil }
            } message: { Text(model.message ?? "") }
            .confirmationDialog("恢复壁纸排版默认值？", isPresented: $resetConfirmation, titleVisibility: .visible) {
                Button("恢复默认") { Task { await model.resetLayout() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("保留目标分辨率和已选背景。若草稿损坏，会先另存原文件再新建草稿。待办数据不受影响。")
            }
        }
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, geometry.size.height * model.settings.size.aspectRatio)
            let height = width / model.settings.size.aspectRatio
            ZStack {
                if !dataReady {
                    ContentUnavailableView("请先读取待办", systemImage: "checklist",
                        description: Text(store.loadError ?? "正在等待待办数据"))
                } else if let error = model.previewError {
                    ContentUnavailableView("预览未完成", systemImage: "exclamationmark.triangle", description: Text(error))
                } else if let preview = model.preview {
                    Image(decorative: preview.image, scale: 1)
                        .resizable().interpolation(.high)
                        .accessibilityLabel("壁纸预览，显示当前真实待办")
                } else { ProgressView("正在生成预览") }
            }
            .frame(width: max(1, width), height: max(1, height))
            .background(Color(white: 0.12))
            .clipped()
            .contentShape(Rectangle())
            .gesture(backgroundDrag(previewWidth: width))
            .simultaneousGesture(backgroundMagnification)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func backgroundDrag(previewWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard section == .background, !model.busy, let info = model.preview?.sourceInfo else { return }
                if dragStart == nil {
                    dragStart = CGPoint(x: model.settings.backgroundPanX, y: model.settings.backgroundPanY)
                }
                guard let start = dragStart, previewWidth > 0 else { return }
                let canvas = CGSize(width: 390, height: model.settings.size.logicalHeight)
                let rect = WallpaperRenderer.backgroundRect(source: CGSize(width: info.width, height: info.height),
                    canvas: canvas, settings: model.settings)
                let factor = 390 / previewWidth
                if rect.width > canvas.width + 0.01 {
                    model.settings.backgroundPanX = min(1, max(-1, start.x + value.translation.width * factor / ((rect.width - canvas.width) / 2)))
                }
                if rect.height > canvas.height + 0.01 {
                    model.settings.backgroundPanY = min(1, max(-1, start.y + value.translation.height * factor / ((rect.height - canvas.height) / 2)))
                }
            }
            .onEnded { _ in dragStart = nil }
    }

    private var backgroundMagnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard section == .background, model.hasPhoto, !model.busy else { return }
                if zoomStart == nil { zoomStart = model.settings.backgroundZoom }
                model.settings.backgroundZoom = min(4, max(1, (zoomStart ?? 1) * Double(value)))
            }
            .onEnded { _ in zoomStart = nil }
    }

    @ViewBuilder private var backgroundControls: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images, preferredItemEncoding: .current) {
                Label(model.hasPhoto ? "更换背景照片" : "选择背景照片", systemImage: "photo")
            }
            if model.hasPhoto {
                WallpaperSlider(title: "等比例缩放", value: $model.settings.backgroundZoom, range: 1...4)
                Text("可在上方预览中拖动、双指缩放。拖动到边缘会停止，不露出空白。").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("精细裁剪") {
                    WallpaperSlider(title: "水平偏移", value: $model.settings.backgroundPanX, range: -1...1)
                    WallpaperSlider(title: "垂直偏移", value: $model.settings.backgroundPanY, range: -1...1)
                    Button("重置裁剪") {
                        model.settings.backgroundZoom = 1
                        model.settings.backgroundPanX = 0; model.settings.backgroundPanY = 0
                    }
                    Button("使用默认背景") { model.removePhoto() }
                }
            }
        } footer: { Text("照片仅在本机处理。选择、预览与调节不会新增相册图片。") }
        if let info = model.preview?.sourceInfo {
            Section("原始照片") {
                LabeledContent("像素尺寸", value: info.label)
                if model.preview?.sourceIsSoft == true {
                    Text("当前裁剪或放大可能超出照片的有效清晰度。可降低缩放或换用更高分辨率照片。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var panelControls: some View {
        Section("尺寸与位置") {
            WallpaperSlider(title: "面板宽度（画布比例）", value: $model.settings.panelWidth, range: 0.3...0.96)
            Toggle("自动适应内容高度", isOn: $model.settings.automaticHeight)
            if !model.settings.automaticHeight {
                WallpaperSlider(title: "面板高度（画布比例）", value: $model.settings.panelHeight, range: 0.12...0.94)
            }
            Toggle("自定义位置", isOn: $model.settings.customPosition)
            if model.settings.customPosition {
                WallpaperSlider(title: "水平中心（0 左 · 1 右）", value: $model.settings.panelX, range: 0...1)
                WallpaperSlider(title: "垂直中心（0 上 · 1 下）", value: $model.settings.panelY, range: 0...1)
                Button("回到正中") { model.settings.panelX = 0.5; model.settings.panelY = 0.5 }
            }
        } footer: { Text("默认水平、垂直居中。靠近画布边缘时会自动约束面板，防止超出。") }
        Section("玻璃") {
            WallpaperSlider(title: "玻璃底色不透明度", value: $model.settings.glassOpacity, range: 0...0.85)
            WallpaperSlider(title: "背景模糊", value: $model.settings.blurRadius, range: 0...45)
            Toggle("深色玻璃底色", isOn: $model.settings.darkGlass)
            DisclosureGroup("面板细节") {
                WallpaperSlider(title: "圆角", value: $model.settings.cornerRadius, range: 0...80)
                WallpaperSlider(title: "边框不透明度", value: $model.settings.borderOpacity, range: 0...1)
                WallpaperSlider(title: "中性高光", value: $model.settings.highlight, range: 0...0.6)
                WallpaperSlider(title: "内边距", value: $model.settings.padding, range: 8...48)
            }
        }
    }

    @ViewBuilder private var textControls: some View {
        Section("显示内容") {
            Toggle("包含已完成待办", isOn: $model.settings.includeCompleted)
            Stepper("最多显示 \(model.settings.maximumItems) 项", value: $model.settings.maximumItems, in: 1...20)
            Text("沿用待办页的真实内容和排序。超出空间或数量限制会显示剩余数量。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("字体与排版") {
            WallpaperSlider(title: "字号", value: $model.settings.fontSize, range: 10...38)
            Picker("字体", selection: $model.settings.font) {
                ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) }
            }
            Picker("字重", selection: $model.settings.weight) {
                ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) }
            }
            ColorPicker("文字颜色与透明度", selection: textColor, supportsOpacity: true)
            Picker("对齐方式", selection: $model.settings.alignment) {
                ForEach(WallpaperAlignment.allCases) { Text($0.title).tag($0) }
            }
            DisclosureGroup("文字细节") {
                WallpaperSlider(title: "行间距", value: $model.settings.lineSpacing, range: 0...20)
                WallpaperSlider(title: "事项间距", value: $model.settings.itemSpacing, range: 0...36)
                Stepper("每项最多 \(model.settings.maximumLines) 行", value: $model.settings.maximumLines, in: 1...8)
                Picker("完成事项样式", selection: $model.settings.completionStyle) {
                    ForEach(WallpaperCompletionStyle.allCases) { Text($0.title).tag($0) }
                }
                Text("长标题自动换行；超过每项行数时使用省略号。字体和间距使用 390 单位画布，导出按目标比例绘制。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var textColor: Binding<Color> {
        Binding {
            let color = model.settings.textColor
            return Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
        } set: { color in
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
            if UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) {
                model.settings.textColor = WallpaperColor(red: r, green: g, blue: b, alpha: a)
            }
        }
    }

    @ViewBuilder private var outputControls: some View {
        Section("目标像素尺寸") {
            Picker("设备预设", selection: $preset) {
                ForEach(WallpaperPreset.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: preset) { _, value in
                if let size = value.size { model.settings.size = size; customWidth = "\(size.width)"; customHeight = "\(size.height)" }
            }
            if preset == .custom {
                HStack {
                    TextField("宽度", text: $customWidth).keyboardType(.numberPad)
                    Text("×").foregroundStyle(.secondary)
                    TextField("高度", text: $customHeight).keyboardType(.numberPad)
                    Button("应用") { applyCustomSize() }
                }
            }
            LabeledContent("将导出", value: model.settings.size.label + " px")
        } footer: { Text("默认适配 iPhone 13 Pro：1170 × 2532。自定义宽高各 480–4096，总像素最多 1200 万。") }
        Section("PNG 成品") {
            Button { Task { await model.export(saveToPhotos: true) } } label: { Label("保存到相册", systemImage: "square.and.arrow.down") }
                .disabled(!canExport)
            Button { Task { await model.export(saveToPhotos: false) } } label: { Label("系统分享", systemImage: "square.and.arrow.up") }
                .disabled(!canExport)
            if let size = model.lastExportSize { LabeledContent("最近成品已校验", value: size + " px") }
            Text("按实际像素重新渲染背景、文字与玻璃效果。不是预览截图放大。")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            Button("清理导出缓存") { Task { await model.clearCache() } }
            Text("壁纸是导出时的静态快照。请在系统照片或设置中手动设置壁纸；待办变化后需重新导出。")
                .font(.caption).foregroundStyle(.secondary)
            Text("壁纸玻璃使用独立的 Core Image 渲染，与预览共用绘制逻辑；不是系统实时 Liquid Glass 的离屏复制。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func applyCustomSize() {
        guard let w = Int(customWidth), let h = Int(customHeight) else {
            model.message = WallpaperError.invalidSize.localizedDescription; return
        }
        let size = WallpaperSize(width: w, height: h)
        guard size.isValid else { model.message = WallpaperError.invalidSize.localizedDescription; return }
        model.settings.size = size
    }

    private func syncSizeFields() {
        let size = model.settings.size
        preset = WallpaperPreset.allCases.first { $0.size == size } ?? .custom
        customWidth = "\(size.width)"; customHeight = "\(size.height)"
    }
}

private struct WallpaperSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    private var bounded: Binding<Double> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, value)) },
                set: { value = $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0)) : range.lowerBound })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer(minLength: 8)
                TextField(title, value: bounded, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    .monospacedDigit().frame(width: 68).foregroundStyle(.secondary)
            }
            Slider(value: bounded, in: range).accessibilityLabel(title)
        }
        .padding(.vertical, 2)
    }
}

private struct WallpaperShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
