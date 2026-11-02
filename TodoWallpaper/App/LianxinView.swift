// Target Membership：仅 App。
import SwiftUI
import PhotosUI

struct LianxinFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
private struct LianxinEditableRow: Identifiable {
    let id: UUID
    let index: Int
    let line: LianxinLine
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
    @State private var showsLanguage = false
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var lineIDs = (0..<8).map { _ in UUID() }
    private enum Field: Hashable { case prompt, message(UUID), translation(UUID) }
    @Environment(\.dynamicTypeSize) private var typeSize
    @FocusState private var focused: Field?
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View { NavigationStack { configuredPage } }
    private var scrollContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !model.loaded {
                        VStack(alignment: .leading, spacing: 10) {
                            if model.loading { ProgressView("正在读取连心资料…") }
                            else { Button("重新读取连心资料") { Task { await model.load() } } }
                            if model.canRecoverProfile { Button("恢复上次有效资料") { Task { await model.recoverProfile() } } }
                        }
                    }
                    if model.photoSyncPending { Button("重试同步已保存的底图") { Task { await model.retryPhotoSync() } }.disabled(model.busy) }
                    connectionStatus
                    LianxinRoleView(model: model).disabled(!model.loaded)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("想听什么", systemImage: "text.bubble").font(.headline)
                        TextField("比如：今天很累，想被哄一哄", text: limited(\.prompt, 12000), axis: .vertical)
                            .lineLimit(3...10).focused($focused, equals: .prompt)
                        Text("像平常聊天一样写就好。").font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup(isExpanded: $showsLanguage) {
                            LianxinLanguageView(model: model).padding(.top, 8)
                        } label: {
                            HStack {
                                Label("语言与翻译", systemImage: "globe").font(.subheadline)
                                Spacer()
                                Text(languageSummary).font(.caption).foregroundStyle(.secondary)
                            }.frame(minHeight: 44)
                        }
                    }.textFieldStyle(LianxinFieldStyle()).disabled(!model.loaded || model.busy)
                    actions
                    if let notice = model.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
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
                        }.disabled(!model.loaded || !canOutput || model.busy)
                    }
                    appearanceSection
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
            .onDisappear { Task { await model.saveInputsNow() } }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.retryCredentials(); await syncPreview() } } }
            .task(id: LianxinPreviewInput(content: model.publication, style: store.appearance.style(in: .lianxin), marker: store.appearance.lianxinWallpaperMarker, markerStyle: store.appearance.lianxinWallpaperMarkerStyle)) { await syncPreview() }
            .task(id: selection) { await importSelection() }
    }

    private var outputControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("你的话语", systemImage: "quote.bubble").font(.headline)
                Spacer()
                Text("\(editableRows.count) 句 · 可直接编辑").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(editableRows) { row in
                let index = row.index
                let line = row.line
                VStack(alignment: .leading, spacing: 8) {
                    Text("第 \(index + 1) 句").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("话语 \(index + 1)", text: lineBinding(index, translation: false), axis: .vertical)
                        .lineLimit(2...8).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .message(row.id))
                    if model.profile.translationEnabled == true {
                        TextField("译文", text: lineBinding(index, translation: true), axis: .vertical)
                            .lineLimit(2...8).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .translation(row.id))
                    }
                    HStack {
                        Text("原文 \(line.text.count)/200 · 译文 \(line.translation?.count ?? 0)/200").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("删除", role: .destructive) { deleteLine(at: index) }
                            .disabled(model.profile.resolvedLines.count == 1)
                            .accessibilityLabel("删除第\(index + 1)句话语").frame(minHeight: 44)
                    }
                    if !line.isValid {
                        Text(line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "请填写这句话语；暂未同步。" : line.text.count > 200 ? "这句原文超过200字，请缩短后同步。" : "这句译文超过200字，请缩短后同步。")
                            .font(.caption).foregroundStyle(.red)
                    }
                }.padding(14)
                    .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            if model.canUndoContentEdit {
                Button("撤销删除或恢复上一批", systemImage: "arrow.uturn.backward") { focused = nil; model.undoContentEdit() }.frame(minHeight: 44)
            }
            if model.profile.resolvedLines.count == 1 { Text("至少保留一句；可以直接编辑替换，或重新生成。").font(.caption).foregroundStyle(.secondary) }
            if !canOutput { Text("每句话语需为1–200字，译文最多200字；无效输入保留上次内容。").font(.caption).foregroundStyle(.secondary) }
            if let error = model.syncError {
                HStack { Text(error).font(.caption); Button("重试") { model.scheduleSync() } }
            } else if let date = model.syncedAt {
                Text("已保存并请求小组件刷新 · " + date.formatted(date: .omitted, time: .standard)).font(.caption2).foregroundStyle(.tertiary)
            }
        }.disabled(!model.loaded || model.busy || loadingPhoto)
    }

    private var editableRows: [LianxinEditableRow] {
        model.profile.resolvedLines.prefix(8).enumerated().map { LianxinEditableRow(id: lineIDs[$0.offset], index: $0.offset, line: $0.element) }
    }
    private func deleteLine(at index: Int) {
        var values = model.profile.resolvedLines
        guard values.count > 1, values.indices.contains(index) else { return }
        if focused == .message(lineIDs[index]) || focused == .translation(lineIDs[index]) { focused = nil }
        lineIDs.remove(at: index); lineIDs.append(UUID())
        values.remove(at: index); model.editLines(values)
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
        Group {
            if family != .small || typeSize >= .xxxLarge { VStack(spacing: 16) { wallpaperPreview; widgetPreview } }
            else { ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) { wallpaperPreview.frame(width: 140); widgetPreview.frame(width: 170) }
                VStack(spacing: 16) { wallpaperPreview; widgetPreview }
            } }
        }
    }
    private var wallpaperPreview: some View {
        VStack {
            Text("壁纸").font(.subheadline.weight(.medium))
            WallpaperLiveCanvas(model: wallpaper, editsBackground: false, editable: false).frame(height: 280)
                .onTapGesture { openEditor(.wallpaper) }
            Button { openEditor(.wallpaper) } label: {
                Label("调整壁纸", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered).disabled(!canOutput)
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
            Button { openEditor(.widget) } label: {
                Label("调整小组件", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.bordered)
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
            generationLayout {
                countControl
                Button { dismissKeyboard(); if model.connected { model.generate() } else { openSettings() } } label: {
                    Text(!model.connected ? "连接 AI" : model.profile.resolvedLines.isEmpty ? "生成话语" : "重新生成").frame(minWidth: 70, maxWidth: .infinity, minHeight: 52)
                }.buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 18)).disabled(!model.loaded || model.busy || loadingPhoto)
            }
            if model.isGenerating { Button("取消生成") { model.cancel() }.frame(minHeight: 44) }
        }.padding(16).frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var generationLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12)) }

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

    private var languageSummary: String {
        let source = LianxinLanguageRules.source(model.profile)
        return model.profile.translationEnabled == true ? source + " → " + LianxinLanguageRules.target(model.profile) : source
    }
    private var connectionStatus: some View {
        Button { openSettings() } label: {
            HStack(spacing: 12) {
                Image(systemName: model.connected ? "checkmark.circle.fill" : "link")
                    .foregroundStyle(model.connected ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.connected ? model.provider.name + " · 已连接" : "连接你的 AI").font(.subheadline.weight(.semibold))
                    Text(model.connected ? model.profile.model : "首次使用，先选择服务商并填写密钥")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }.buttonStyle(.plain).disabled(!model.loaded || model.busy || loadingPhoto)
    }
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("外观预览", systemImage: "paintpalette").font(.headline)
            previews
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { photoControls }
                VStack(alignment: .leading, spacing: 8) { photoControls }
            }
        }.padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .disabled(!model.loaded || model.busy || loadingPhoto)
    }
    @ViewBuilder private var photoControls: some View {
        let hasPhoto = store.appearance.lianxin?.backgroundPhotoName != nil
        PhotosPicker(selection: $selection, matching: .images) {
            Label(hasPhoto ? "更换底图" : "选择底图", systemImage: "photo")
                .frame(minHeight: 44)
        }.buttonStyle(.bordered)
        if store.appearance.lianxin?.backgroundPhotoName != nil {
            Button("移除底图", role: .destructive) { Task { await model.setPhoto(nil) } }.frame(minHeight: 44)
        }
    }

    private var settings: some View {
        NavigationStack {
            LianxinSetupView(model: model, onFinished: { showsSettings = false })
            .navigationTitle("连接 AI").navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(model.busy)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        Task { await model.saveInputsNow(); showsSettings = false }
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
