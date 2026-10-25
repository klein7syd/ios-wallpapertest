import SwiftUI

@main
struct TodoWallpaperApp: App {
    @StateObject private var store = TodoStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                TodoListView(store: store)
                    .tabItem { Label("待办", systemImage: "checklist") }
                WallpaperEditorView(store: store)
                    .tabItem { Label("壁纸", systemImage: "photo") }
                AboutView(store: store)
                    .tabItem { Label("关于", systemImage: "info.circle") }
            }
            .task { store.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload() } else { store.flushAppearance() }
            }
        }
    }
}

private struct EditorRequest: Identifiable {
    let id = UUID()
    let item: TodoItem?
}

private struct DisplayError: Identifiable {
    let id = UUID()
    let message: String
}

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var editor: EditorRequest?
    @State private var displayError: DisplayError?
    @State private var confirmRecovery = false

    var body: some View {
        NavigationStack {
            Group {
                if let error = store.loadError {
                    ContentUnavailableView {
                        Label("暂时无法读取待办", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("重新读取") { store.reload() }
                        if store.canRecover {
                            Button("从上次备份恢复") { confirmRecovery = true }
                        }
                    }
                } else if !store.hasLoaded {
                    ProgressView("正在读取")
                } else {
                    List {
                        ForEach(store.items) { item in
                            row(item)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { perform { try store.delete(ids: [item.id]) } } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                    Button { editor = EditorRequest(item: item) } label: {
                                        Label("编辑", systemImage: "pencil")
                                    }.tint(.blue)
                                }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.compactMap { store.items.indices.contains($0) ? store.items[$0].id : nil })
                            perform { try store.delete(ids: ids) }
                        }
                        .onMove { offsets, destination in
                            perform { try store.move(from: offsets, to: destination) }
                        }
                    }
                    .overlay {
                        if store.items.isEmpty {
                            ContentUnavailableView("还没有待办", systemImage: "checklist", description: Text("点右上角 +，记下第一件事。"))
                        }
                    }
                }
            }
            .navigationTitle("待办")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton().disabled(store.items.isEmpty || store.loadError != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = EditorRequest(item: nil) } label: {
                        Label("新增待办", systemImage: "plus")
                    }.disabled(!store.hasLoaded || store.loadError != nil)
                }
            }
            .sheet(item: $editor) { request in
                TodoEditorView(item: request.item) { title, marker in
                    if let item = request.item { try store.edit(id: item.id, title: title, marker: marker) }
                    else { try store.add(title: title, marker: marker) }
                }
            }
            .alert(item: $displayError) { error in
                Alert(title: Text("操作未保存"), message: Text(error.message), dismissButton: .default(Text("好")))
            }
            .confirmationDialog("从上次成功保存的备份恢复？", isPresented: $confirmRecovery, titleVisibility: .visible) {
                Button("恢复备份") { perform { try store.recoverFromBackup() } }
                Button("取消", role: .cancel) { }
            } message: {
                Text("备份可能少一次修改。当前损坏文件会另存保留，不会删除原文件。")
            }
        }
    }

    private func row(_ item: TodoItem) -> some View {
        HStack(spacing: 12) {
            Button {
                perform { try store.setCompleted(id: item.id, completed: !item.isCompleted) }
            } label: {
                TodoMarkerView(marker: store.appearance.marker(for: item), completed: item.isCompleted,
                               style: store.appearance.markerStyle)
                    .frame(minWidth: 24, minHeight: 32)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
            Button { editor = EditorRequest(item: item) } label: {
                Text(item.title)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() }
        catch { displayError = DisplayError(message: error.localizedDescription) }
    }
}

struct TodoEditorView: View {
    let item: TodoItem?
    let onSave: (String, TodoMarker?) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var markerOverride: TodoMarker
    @State private var inheritsMarker: Bool
    @State private var saveError: DisplayError?
    @FocusState private var focused: Bool

    init(item: TodoItem?, onSave: @escaping (String, TodoMarker?) throws -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item?.title ?? "")
        _markerOverride = State(initialValue: item?.marker ?? TodoMarker(kind: .emoji, emoji: "⭐"))
        _inheritsMarker = State(initialValue: item?.marker == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("想完成什么？", text: $title, axis: .vertical)
                        .lineLimit(3...6).focused($focused)
                } footer: {
                    Text("\(title.trimmingCharacters(in: .whitespacesAndNewlines).count) / 200 字符")
                }
                Section("单项标记") {
                    Toggle("继承全局默认标记", isOn: $inheritsMarker)
                    if !inheritsMarker { MarkerChoiceEditor(choice: $markerOverride) }
                    Text("单项设置优先；关闭单项覆盖后恢复全局默认。新待办默认继承。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item == nil ? "新增待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try onSave(title, inheritsMarker ? nil : markerOverride); dismiss() }
                        catch { saveError = DisplayError(message: error.localizedDescription) }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).count > 200)
                }
            }
            .alert(item: $saveError) { error in
                Alert(title: Text("无法保存"), message: Text(error.message), dismissButton: .default(Text("好")))
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AboutView: View {
    @ObservedObject var store: TodoStore
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var body: some View {
        NavigationStack {
            Form {
                Section("Todo Wallpaper") {
                    LabeledContent("版本", value: "\(version) · 构建 \(build)")
                    Text("原生待办与个性化壁纸")
                }
                Section("数据") {
                    Text("待办保存在这台 iPhone，当前没有跨设备同步。")
                    Text("升级时请使用同一签名账号和安装标识直接覆盖。卸载 App 会删除本机数据。")
                }
                Section("本次测试") {
                    Text("支持新增、编辑、删除、拖动排序和完成待办。")
                    Text("支持主屏幕小组件直接完成或恢复待办，以及本地壁纸编辑与 PNG 导出。")
                    Text("安装标识：\(Bundle.main.bundleIdentifier ?? "未知")").font(.caption).textSelection(.enabled)
                }
                Section("小组件") {
                    NavigationLink("小组件外观与全局标记") { WidgetAppearanceEditor(store: store) }
                    Text(store.hasLoaded && store.loadError == nil ? "共享存储已就绪" : "请先处理待办页的读取提示")
                    Text("长按主屏幕，添加 Todo Wallpaper 小组件。任务按钮可直接操作，空白区域仍可打开 App。")
                    Button("请求刷新小组件") { store.reload() }
                }
            }
            .navigationTitle("关于")
        }
    }
}
