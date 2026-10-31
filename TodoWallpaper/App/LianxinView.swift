// Target Membership：仅 App。
import SwiftUI
import PhotosUI

struct LianxinView: View {
    @ObservedObject var model: LianxinModel
    @ObservedObject var store: TodoStore
    @ObservedObject var wallpaper: WallpaperEditorModel
    @Binding var navigation: AppNavigationState
    @State private var family = WidgetPreviewFamily.small
    @State private var lastPreviewPhoto: String?
    @AppStorage("editor.contentMode") private var contentMode = "todo"
    @State private var showsSettings = false
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var outputText = ""
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.loaded { Button("重新读取连心资料") { Task { await model.load() } } }
                    if model.connected {
                        Button("已连接：\(model.provider.name)") { openSettings() }.font(.caption)
                    } else if !model.exampleMode {
                        HStack {
                            Button("连接 AI（约 1 分钟）") { openSettings() }
                            Button("先体验") { model.exampleMode = true; model.generate() }
                        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if model.exampleMode {
                        Label("体验模式：示例内容，非 AI 生成", systemImage: "sparkles").font(.footnote)
                        Button("连接我自己的AI") { model.exampleMode = false }
                    }
                    previews
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("你的称呼（最多100字）", text: limited(\.userName, 100))
                        TextField("IDOL 名字（最多100字）", text: limited(\.idolName, 100))
                        TextField("提示词（最多12000字）", text: limited(\.prompt, 12000), axis: .vertical).lineLimit(4...10)
                    }.textFieldStyle(.roundedBorder).disabled(model.busy)
                    actions
                    Text(model.profile.exampleContent == true ? "示例内容，非 AI 生成。连接自己的AI后，语气与情境由你的提示词决定。" : "由你的提示词决定语气与情境。这里的话语是 AI 创作，不代表本人真实言论。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !model.profile.message.isEmpty {
                        outputControls
                        HStack {
                            Button { UIPasteboard.general.string = model.profile.message; model.notice = "已复制话语" } label: {
                                Label("复制", systemImage: "doc.on.doc").frame(minHeight: 44)
                            }
                            Spacer()
                            ShareLink(item: "\(model.profile.messageIdol) · \(model.profile.exampleContent == true ? "示例内容，非 AI 生成" : "AI 创作")\n\(model.profile.message)") {
                                Label("分享文字", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                            }
                        }
                    }
                    if model.photo != nil {
                        Button("移除底图", role: .destructive) { Task { await model.setPhoto(nil) } }
                            .frame(minHeight: 44).disabled(model.busy || loadingPhoto)
                    }
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }.padding(20)
            }
            .navigationTitle("连心")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openSettings() } label: { Label("连心设置", systemImage: "gearshape") }
                        .disabled(!model.loaded || model.busy || loadingPhoto)
                }
            }

            .task { await model.load(); await model.prepareStyle(store); outputText = model.profile.message }
            .sheet(isPresented: $showsSettings) { settings }
            .sheet(item: $model.wallpaperRequest) { LianxinWallpaperView(request: $0) }
            .onChange(of: model.profile.message) { _, value in outputText = value }
            .onChange(of: outputText) { _, value in if value.count <= 200 && value != model.profile.message { model.profile.message = value } }
            .alert("连心", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .onDisappear { model.cancel(); Task { await model.saveInputsNow() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
            .task(id: model.profile.message + (model.profile.photoName ?? "")) { await syncPreview() }
            .task(id: selection) { await importSelection() }
        }
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("放到每天看得见的地方").font(.headline)
            TextField("编辑用于小组件和壁纸的话语", text: $outputText, axis: .vertical)
                .lineLimit(3...8).textFieldStyle(.roundedBorder)
            Text("\(outputText.count)/200 字 · 可以编辑后再发布；小号组件可能只展示部分文字。")
                .font(.caption).foregroundStyle(.secondary)
            Button { Task { await model.output(text: outputText, wallpaper: false) } } label: {
                Label("发布到连心小组件", systemImage: "square.grid.2x2").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(!canOutput)
            Button { openEditor(.wallpaper) } label: {
                Label("去调整壁纸样式", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(!canOutput)
            Button("去调整小组件样式") { openEditor(.widget) }.frame(minHeight: 44)
        }.disabled(model.busy || loadingPhoto)
    }

    private var canOutput: Bool { !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && outputText.count <= 200 }

    private func limited(_ path: WritableKeyPath<LianxinProfile, String>, _ limit: Int) -> Binding<String> {
        Binding(get: { model.profile[keyPath: path] }, set: { model.profile[keyPath: path] = String($0.prefix(limit)) })
    }
    private func openEditor(_ page: AppPage) { contentMode = "lianxin"; navigation.selectPage(page) }
    private var previews: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { wallpaperPreview.frame(width: 140); widgetPreview.frame(width: 170) }
            VStack(spacing: 16) { wallpaperPreview; widgetPreview }
        }
    }
    private var wallpaperPreview: some View {
        VStack {
            Text("壁纸预览").font(.headline)
            WallpaperLiveCanvas(model: wallpaper, editsBackground: false, editable: false).frame(height: 280)
                .onTapGesture { openEditor(.wallpaper) }
            Button("调整壁纸") { openEditor(.wallpaper) }
        }
    }
    private var widgetPreview: some View {
        VStack {
            Menu("小组件 · " + family.title) {
                ForEach(WidgetPreviewFamily.allCases) { size in Button(size.title) { family = size } }
            }
            LianxinWidgetContent(content: model.publication, style: store.appearance.style(in: .lianxin), family: family)
                .padding(12).frame(width: 170, height: family == .large ? 280 : 170)
                .background { if let image = model.photo { Image(uiImage: image).resizable().scaledToFill() } }
                .clipped().clipShape(RoundedRectangle(cornerRadius: 22)).allowsHitTesting(false)
                .overlay { Color.clear.contentShape(Rectangle()).onTapGesture { openEditor(.widget) } }
            Button("调整小组件") { openEditor(.widget) }
        }
    }
    private var previewItems: [TodoItem] {
        [TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
                  title: model.profile.message.isEmpty ? "写下提示词，生成一句话。" : model.profile.message,
                  marker: TodoMarker(kind: .none), isCompleted: false, createdAt: .distantPast, updatedAt: .distantPast)]
    }
    private var previewAppearance: TodoAppearance {
        var value = store.appearance; value.defaultMarker = TodoMarker(kind: .none)
        value.widget.header = WidgetHeaderAppearance(text: model.profile.idolName.isEmpty ? "连心" : String(model.profile.idolName.prefix(40)))
        return value
    }
    private func syncPreview() async {
        do {
            try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation()
            await wallpaper.start(items: previewItems, appearance: previewAppearance)
            if model.profile.photoName != lastPreviewPhoto {
                if let data = try await model.wallpaperPhotoData() { try await wallpaper.importPhotoData(data) }
                else { wallpaper.removePhoto() }
                lastPreviewPhoto = model.profile.photoName
            }
        } catch is CancellationError { }
        catch { model.notice = "壁纸预览暂未更新，请重试。" }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if model.busy || loadingPhoto { ProgressView(loadingPhoto ? "正在导入底图" : "正在处理") }
            HStack {
                PhotosPicker(selection: $selection, matching: .images) {
                    Label("底图", systemImage: "photo").frame(minHeight: 44)
                }.buttonStyle(.bordered).disabled(!model.loaded || model.busy || loadingPhoto)
                Button { model.generate() } label: {
                    Label(model.profile.message.isEmpty ? "生成话语" : "再生成一句", systemImage: "heart.text.clipboard")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(!model.loaded || model.busy || loadingPhoto)
                if model.busy { Button("取消") { model.cancel() }.frame(minHeight: 44) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("连接AI向导") { LianxinSetupView(model: model) }

            }
            .disabled(model.busy)
            .navigationTitle("连心设置").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { if await model.saveSettings() { showsSettings = false } } }.disabled(model.busy)
                }
            }
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        showsSettings = false
                    }.disabled(model.busy)
                }
            }
        }
    }

    private func openSettings() {
        showsSettings = true
    }

    private func importSelection() async {
        guard let selection else { return }
        loadingPhoto = true
        defer { loadingPhoto = false; self.selection = nil }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else { throw LianxinError.storage }
            try Task.checkCancellation()
            await model.setPhoto(data)
        } catch is CancellationError { }
        catch { model.error = "照片读取失败，请检查相册或 iCloud 网络后重试。" }
    }
}
