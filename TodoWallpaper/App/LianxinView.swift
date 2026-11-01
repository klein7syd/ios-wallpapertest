// Target Membership：仅 App。
import SwiftUI
import PhotosUI

struct LianxinFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
private struct LianxinPreviewInput: Equatable {
    let content: LianxinPublication
    let style: WidgetAppearance
    let marker: TodoMarker?
    let markerStyle: MarkerStyle?
}
struct LianxinView: View {
    @ObservedObject var model: LianxinModel
    @ObservedObject var store: TodoStore
    @ObservedObject var wallpaper: WallpaperEditorModel
    @Binding var navigation: AppNavigationState
    @State private var family = WidgetPreviewFamily.small
    @AppStorage("editor.contentMode") private var contentMode = "todo"
    @State private var showsSettings = false
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    private enum Field: Hashable { case prompt, message(Int), translation(Int) }
    @FocusState private var focused: Field?
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View { NavigationStack { configuredPage } }
    private var scrollContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.loaded { Button("重新读取连心资料") { Task { await model.load() } } }
                    if model.connected {
                        Button("已连接：\(model.provider.name)") { openSettings() }.font(.caption)
                    } else {
                        HStack {
                            Button("连接 AI（约 1 分钟）") { openSettings() }
                        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    previews
                    LianxinRoleView(model: model)
                    LianxinLanguageView(model: model)
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("想听什么？比如：今天很累，想被哄一哄", text: limited(\.prompt, 12000), axis: .vertical).lineLimit(4...10).focused($focused, equals: .prompt)
                        Text("像平常聊天一样写就好，语气和表达会由连心整理。").font(.caption).foregroundStyle(.secondary)
                    }.textFieldStyle(LianxinFieldStyle()).disabled(model.busy)
                    actions
                    if !model.profile.message.isEmpty || model.currentContent != nil {
                        outputControls
                        HStack {
                            Button { UIPasteboard.general.string = model.publication.shareText; model.notice = "已复制话语" } label: {
                                Label("复制", systemImage: "doc.on.doc").frame(minHeight: 44)
                            }
                            Spacer()
                            ShareLink(item: model.publication.shareText) {
                                Label("分享文字", systemImage: "square.and.arrow.up").frame(minHeight: 44)
                            }
                        }
                    }
                    if store.appearance.lianxin?.backgroundPhotoName != nil {
                        Button("移除底图", role: .destructive) { Task { await model.setPhoto(nil) } }
                            .frame(minHeight: 44).disabled(model.busy || loadingPhoto)
                    }
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                    Text("连心里的话语由 AI 创作，不代表任何真实人物的真实言论。生成时仅用名字和团体查找公开 Wiki；资料摘要会交给你选择的 AI，照片不会上传。")
                        .font(.caption).foregroundStyle(.secondary).padding(14)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }.padding(20)
            }
    }
    private var page: some View {
        scrollContent
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground).onTapGesture { dismissKeyboard() })
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .navigationTitle("连心")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { dismissKeyboard() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { openSettings() } label: { Label("连心设置", systemImage: "gearshape") }
                        .disabled(!model.loaded || model.busy || loadingPhoto)
                }
            }

    }
    private var configuredPage: some View {
        page
            .task { await model.load(); await model.prepareStyle(store) }
            .sheet(isPresented: $showsSettings) { settings }
            .alert("连心", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("好") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .onDisappear { model.cancel(); Task { await model.saveInputsNow() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { model.cancel() } else { Task { await syncPreview() } } }
            .task(id: LianxinPreviewInput(content: model.publication, style: store.appearance.style(in: .lianxin), marker: store.appearance.lianxinWallpaperMarker, markerStyle: store.appearance.lianxinWallpaperMarkerStyle)) { await syncPreview() }
            .task(id: selection) { await importSelection() }
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(model.profile.resolvedLines.enumerated()), id: \.offset) { index, line in
                VStack(alignment: .leading, spacing: 8) {
                    TextField("话语 \(index + 1)", text: lineBinding(index, translation: false), axis: .vertical)
                        .lineLimit(2...8).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .message(index))
                    if model.profile.translationEnabled == true {
                        TextField("译文", text: lineBinding(index, translation: true), axis: .vertical)
                            .lineLimit(2...8).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .translation(index))
                    }
                    HStack {
                        Text("原文 \(line.text.count)/200 · 译文 \(line.translation?.count ?? 0)/200").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("删除", role: .destructive) { var values = model.profile.resolvedLines; if values.indices.contains(index) { values.remove(at: index); model.profile.setLines(values) } }
                    }
                }
            }
            if !canOutput { Text("每句话语需为1–200字，译文最多200字；无效输入保留上次内容。").font(.caption).foregroundStyle(.secondary) }
            if let error = model.syncError {
                HStack { Text(error).font(.caption); Button("重试") { model.scheduleSync() } }
            } else if let date = model.syncedAt {
                Text("小组件已更新 · " + date.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.tertiary)
            }
            Button { openEditor(.wallpaper) } label: {
                Label("去调整壁纸样式", systemImage: "photo").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(!canOutput)
            Button { openEditor(.widget) } label: {
                Label("去调整小组件样式", systemImage: "square.grid.2x2").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered)
        }.disabled(model.busy || loadingPhoto)
    }

    private var canOutput: Bool { !model.profile.resolvedLines.isEmpty && model.profile.resolvedLines.count <= 8 && model.profile.resolvedLines.allSatisfy(\.isValid) }
    private func lineBinding(_ index: Int, translation: Bool) -> Binding<String> {
        Binding(get: { let values = model.profile.resolvedLines; guard values.indices.contains(index) else { return "" }; return translation ? (values[index].translation ?? "") : values[index].text }, set: { value in
            var values = model.profile.resolvedLines; guard values.indices.contains(index) else { return }
            if translation { values[index].translation = value } else { values[index].text = value }
            model.profile.setLines(values)
        })
    }


    private func dismissKeyboard() {
        focused = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

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
            WidgetFamilyPicker(family: $family)
            GeometryReader { proxy in
                let scale = family.scale(availableWidth: proxy.size.width, availableHeight: proxy.size.height)
                let style = store.appearance.style(in: .lianxin)
                let scheme: ColorScheme = style.theme == .system ? systemScheme : (style.theme == .dark ? .dark : .light)
                LianxinWidgetContent(content: model.publication, style: style, family: family)
                    .padding(16).frame(width: family.width, height: family.height)
                    .background { LianxinWidgetBackground(content: model.publication, style: style, family: family) }
                    .environment(\.colorScheme, scheme)
                    .clipShape(RoundedRectangle(cornerRadius: 22)).scaleEffect(scale)
                    .frame(width: family.width * scale, height: family.height * scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }.frame(height: family == .large ? 280 : 170).contentShape(Rectangle()).onTapGesture { openEditor(.widget) }
            Button("调整小组件") { openEditor(.widget) }
        }
    }
    private var previewItems: [TodoItem] { WallpaperContentSource.lianxin(model.publication).items }
    private var previewAppearance: TodoAppearance {
        var value = store.appearance; value.widget = value.style(in: .lianxin); value.defaultMarker = value.lianxinWallpaperMarker ?? TodoMarker(kind: .none); value.markerStyle = value.lianxinWallpaperMarkerStyle ?? MarkerStyle(); return value
    }
    private func syncPreview() async {
        do {
            try await Task.sleep(for: .milliseconds(350)); try Task.checkCancellation()
            await wallpaper.start(items: previewItems, appearance: previewAppearance, content: model.publication)
            try await wallpaper.syncSharedPhoto(reference: store.appearance.lianxin?.photoName(at: .now)) { try await model.wallpaperPhotoData() }
        } catch is CancellationError { }
        catch { model.notice = "壁纸预览暂未更新，请重试。" }
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if model.busy || loadingPhoto { ProgressView(loadingPhoto ? "正在导入底图" : "正在处理") }
            HStack {
                countControl
                Button { model.generate() } label: {
                    Text(model.profile.resolvedLines.isEmpty ? "生成话语" : "重新生成").frame(minWidth: 70, minHeight: 64)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 18)).disabled(!model.loaded || model.busy || loadingPhoto)
            }
            HStack {
                PhotosPicker(selection: $selection, matching: .images) { Label("底图", systemImage: "photo").frame(minHeight: 44) }
                    .buttonStyle(.bordered).disabled(!model.loaded || model.busy || loadingPhoto)
                if model.busy { Button("取消") { model.cancel() }.frame(minHeight: 44) }
            }
        }.padding(.horizontal, 16).padding(.vertical, 8).background(.bar)
    }

    private var countControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("生成几句").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button { model.profile.generationCount = max(1, model.profile.requestedCount - 1) } label: {
                    Image(systemName: "minus").frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.disabled(model.profile.requestedCount == 1).accessibilityLabel("少生成一句")
                Text("\(model.profile.requestedCount)").font(.headline.monospacedDigit()).frame(minWidth: 24)
                Button { model.profile.generationCount = min(8, model.profile.requestedCount + 1) } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44).background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.disabled(model.profile.requestedCount == 8).accessibilityLabel("多生成一句")
            }.buttonStyle(.plain)
        }.padding(10).frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(model.busy || loadingPhoto)
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
            .scrollDismissesKeyboard(.interactively)
            .buttonBorderShape(.roundedRectangle(radius: 14))
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
