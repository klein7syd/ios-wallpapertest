// Target Membership：仅 App。复用生产壁纸引擎，连心草稿与待办草稿互相独立。
import SwiftUI

struct LianxinWallpaperRequest: Identifiable {
    let id = UUID()
    let content: LianxinPublication
    let sourcePhoto: Data?
}

struct LianxinWallpaperView: View {
    let request: LianxinWallpaperRequest
    @StateObject private var model = WallpaperEditorModel(files: WallpaperDraftStore(
        directory: URL.applicationSupportDirectory.appendingPathComponent("LianxinWallpaper"),
        exportDirectory: URL.cachesDirectory.appendingPathComponent("LianxinExports")))
    @State private var editsBackground = false
    @State private var prepared = false
    @Environment(\.dismiss) private var dismiss

    private var textFits: Bool {
        guard let layout = model.layout else { return false }
        return layout.hiddenCount == 0 && !layout.rows.isEmpty && layout.rows.allSatisfy { !$0.block.truncated }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                WallpaperLiveCanvas(model: model, editsBackground: editsBackground)
                    .frame(minHeight: 200).padding(.horizontal)
                ScrollView {
                    VStack(spacing: 12) {
                        Toggle("调整照片（关闭后拖动文字面板）", isOn: $editsBackground)
                        PreciseSlider(title: "字号", value: $model.settings.fontSize, range: 10...38, standard: 18)
                        PreciseSlider(title: "面板宽度", value: $model.settings.panelWidth, range: 0.3...0.96, standard: 0.88, precision: 2)
                        PreciseSlider(title: "玻璃透明度", value: $model.settings.glassOpacity, range: 0...0.85, standard: 0.22, precision: 2)
                        if !textFits { Text("文字尚未完整显示：请减小字号、加宽面板，或返回缩短文案后再保存。").font(.caption).foregroundStyle(.red) }
                        Text("通用 19.5:9 比例，1890 × 4096 像素。可拖动文字面板，双指缩放底图。请先检查预览。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.horizontal)
                }.frame(maxHeight: 220)
            }
            .disabled(model.busy || !prepared)
            .navigationTitle("连心壁纸").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() }.disabled(model.busy) } }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if model.busy || !prepared { ProgressView("正在准备壁纸") }
                    Button { Task { await model.export(saveToPhotos: true) } } label: {
                        Label("保存壁纸到相册", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).disabled(!prepared || model.busy || model.previewError != nil || model.draftBlocked || !textFits)
                }.padding().background(.bar)
            }
            .task { await prepare() }
            .onDisappear { Task { await model.saveNow() } }
            .interactiveDismissDisabled(model.busy)
            .alert("连心壁纸", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
                Button("好") { model.message = nil }
            } message: { Text(model.message ?? "") }
        }
    }

    private func prepare() async {
        guard !prepared else { return }
        var appearance = TodoAppearance()
        appearance.defaultMarker = TodoMarker(kind: .none)
        let item = TodoItem(id: request.id, title: request.content.text + "\n—— " + request.content.idol + " · " + request.content.contentLabel,
                            marker: TodoMarker(kind: .none), isCompleted: false, createdAt: .now, updatedAt: .now)
        await model.start(items: [item], appearance: appearance)
        guard !model.draftBlocked else { return }
        model.settings.maximumLines = 8
        do {
            if let source = request.sourcePhoto { try await model.importPhotoData(source) }
            else { model.removePhoto() }
            prepared = true
        } catch { model.message = "底图读取失败，请返回连心重新选择照片。" }
    }
}
