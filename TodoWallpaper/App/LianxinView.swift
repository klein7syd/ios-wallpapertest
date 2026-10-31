// Target Membership：仅 App。
import SwiftUI
import PhotosUI

struct LianxinView: View {
    @StateObject private var model = LianxinModel()
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
                    if !model.configurationComplete && !model.exampleMode {
                        LianxinSetupView(model: model)
                    }
                    if model.exampleMode {
                        Label("体验模式：示例内容，非 AI 生成", systemImage: "sparkles").font(.footnote)
                        Button("连接我自己的AI") { model.exampleMode = false }
                    }
                    card
                    Text(model.profile.exampleContent == true ? "示例内容，非 AI 生成。连接自己的AI后，语气与情境由你的提示词决定。" : "由你的提示词决定语气与情境。这里的话语是 AI 创作，不代表本人真实言论。")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.profile.prompt.isEmpty {
                        Button("先填写名字、提示词和 API") { openSettings() }
                            .buttonStyle(.bordered).frame(minHeight: 44).disabled(!model.loaded || model.busy)
                    }
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
            .safeAreaInset(edge: .bottom) { actions }
            .task { await model.load(); outputText = model.profile.message }
            .sheet(isPresented: $showsSettings) { settings }
            .sheet(item: $model.wallpaperRequest) { LianxinWallpaperView(request: $0) }
            .onChange(of: model.profile.message) { _, value in outputText = value }
            .alert("连心", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .onDisappear { model.cancel() }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } }
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
            Button { Task { await model.output(text: outputText, wallpaper: true) } } label: {
                Label("制作连心壁纸", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(!canOutput)
        }.disabled(model.busy || loadingPhoto)
    }

    private var canOutput: Bool { !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && outputText.count <= 200 }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(model.profile.message.isEmpty ? (model.profile.idolName.isEmpty ? "期待与你连心" : model.profile.idolName) : model.profile.messageIdol,
                  systemImage: "heart").font(.headline)
                .padding(10).background(.regularMaterial, in: Capsule())
            Spacer(minLength: 160)
            VStack(alignment: .leading, spacing: 12) {
                Text(model.profile.message.isEmpty ? "写下你期待的情境，让一句话来到你身边。" : model.profile.message)
                    .font(.title3).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(model.profile.exampleContent == true ? "示例内容，非 AI 生成 · 连心" : "AI 创作 · 连心").font(.caption)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
        .padding(20).frame(maxWidth: .infinity, minHeight: 390, alignment: .leading)
        .background {
            GeometryReader { proxy in
                if let photo = model.photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
                } else { Color.secondary.opacity(0.12) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))

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
                Section("与你连心的人") {
                    TextField("你的称呼（最多 100 字）", text: $model.profile.userName)
                    TextField("IDOL 名字（最多 100 字）", text: $model.profile.idolName)
                }
                Section {
                    TextField("例如：用温柔、略带暧昧的语气，对刚下班的我说一句晚安。", text: $model.profile.prompt, axis: .vertical)
                        .lineLimit(5...12)
                } header: { Text("你的提示词") } footer: {
                    Text("由你决定关系、语气、情境、语言和长度，最多 12000 字。留空时不会发起生成。")
                }
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
