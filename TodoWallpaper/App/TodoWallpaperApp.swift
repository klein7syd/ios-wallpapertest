import SwiftUI

@main
struct TodoWallpaperApp: App {
    @StateObject private var store = TodoStore()
    @StateObject private var wallpaperModel = WallpaperEditorModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation = AppNavigationState()
    #if TODO_UI_CHECKS
    @State private var didRunUIProbe = false
    @MainActor init() {
        if ProcessInfo.processInfo.arguments.contains("--native-ui-probe") {
            _store = StateObject(wrappedValue: NativeUIProbe.makeStore())
            UserDefaults.standard.set(ProcessInfo.processInfo.arguments.contains("--native-advanced"), forKey: EditorStandards.advancedKey)
        }
    }
    #endif

    var body: some Scene {
        WindowGroup {
            primaryTabs
            .task {
                #if TODO_UI_CHECKS
                if ProcessInfo.processInfo.arguments.contains("--native-ui-probe") {
                    guard !didRunUIProbe else { return }
                    didRunUIProbe = true
                    store.reload()
                    if ProcessInfo.processInfo.arguments.contains("--native-widget-screen") {
                        navigation.selectPage(.widget)
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--native-about-screen") {
                        navigation.selectPage(.about)
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--native-wallpaper-marker") {
                        navigation.selectTool(.marker)
                        return
                    }
                    if ProcessInfo.processInfo.arguments.contains("--native-wallpaper-panel") {
                        navigation.selectTool(.panel)
                        return
                    }
                    await NativeUIProbe.run()
                    navigation.selectTool(.panel)
                    return
                }
                #endif
                store.reload()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload() } else { store.flushAppearance() }
            }
        }
    }
    private var primaryTabs: some View {
            TabView(selection: Binding(get: { navigation.page }, set: { navigation.selectPage($0) })) {
                TodoListView(store: store)
                    .tabItem { Label("待办", systemImage: "checklist") }
                    .tag(AppPage.todos)
                WallpaperEditorView(store: store, navigation: $navigation, model: wallpaperModel)
                    .tabItem { Label("壁纸", systemImage: "photo") }
                    .tag(AppPage.wallpaper)
                NavigationStack { WidgetAppearanceEditor(store: store) }
                    .tabItem { Label("小组件", systemImage: "square.grid.2x2") }
                    .tag(AppPage.widget)
                AboutView(store: store)
                    .tabItem { Label("关于", systemImage: "info.circle") }
                    .tag(AppPage.about)
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
    @State private var importCalendar = false
    @State private var importAfterEditor = false

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
                                .swipeActions(edge: .leading) {
                                    Button { perform { try store.setCompleted(id: item.id, completed: !item.isCompleted) } } label: {
                                        Label(item.isCompleted ? "恢复待办" : "完成待办", systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                                    }.tint(.green)
                                }
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
                    Button { importCalendar = true } label: { Label("从日历或提醒事项导入", systemImage: "calendar.badge.plus") }
                        .disabled(!store.hasLoaded || store.loadError != nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editor = EditorRequest(item: nil) } label: {
                        Label("新增待办", systemImage: "plus")
                    }.disabled(!store.hasLoaded || store.loadError != nil)
                }
            }
            .sheet(isPresented: $importCalendar) { CalendarImportView(store: store) }
            .sheet(item: $editor, onDismiss: {
                if importAfterEditor { importAfterEditor = false; importCalendar = true }
            }) { request in
                TodoEditorView(item: request.item, onImport: { importAfterEditor = true }) { title, marker, schedule in
                    try store.saveTask(id: request.item?.id, title: title, marker: marker, schedule: schedule)
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
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
            Button { editor = EditorRequest(item: item) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                        .multilineTextAlignment(.leading).lineLimit(3)
                    if let schedule = item.schedule { Label(schedule.label, systemImage: schedule.includesTime ? "clock" : "calendar").font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
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
    let onSave: (String, TodoMarker?, TodoSchedule?) throws -> Void
    let onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var markerOverride: TodoMarker
    @State private var inheritsMarker: Bool
    @State private var scheduled: Bool
    @State private var scheduleDate: Date
    @State private var includesTime: Bool
    @State private var saveError: DisplayError?
    @FocusState private var focused: Bool

    init(item: TodoItem?, onImport: @escaping () -> Void = { }, onSave: @escaping (String, TodoMarker?, TodoSchedule?) throws -> Void) {
        self.item = item
        self.onSave = onSave; self.onImport = onImport
        _scheduled = State(initialValue: item?.schedule != nil)
        _scheduleDate = State(initialValue: item?.schedule?.date() ?? .now)
        _includesTime = State(initialValue: item?.schedule?.includesTime ?? false)
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
                Section("日期") {
                    Toggle("指定日期", isOn: $scheduled)
                    if scheduled {
                        DatePicker("日期", selection: $scheduleDate, displayedComponents: .date)
                        Toggle("指定时间", isOn: $includesTime)
                        if includesTime { DatePicker("时间", selection: $scheduleDate, displayedComponents: .hourAndMinute) }
                    }
                    if item == nil { Button("从日历 / 提醒事项导入", systemImage: "calendar.badge.plus") { onImport(); dismiss() } }
                }
                Section("单项标记") {
                    Toggle("继承壁纸标记", isOn: $inheritsMarker)
                    if !inheritsMarker { MarkerChoiceEditor(choice: $markerOverride) }
                    Text("单项设置优先；恢复继承后使用壁纸默认标记。新待办默认继承。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(item == nil ? "新增待办" : "编辑待办")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try onSave(title, inheritsMarker ? nil : markerOverride, scheduled ? TodoSchedule(date: scheduleDate, includesTime: includesTime) : nil); dismiss() }
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
    @AppStorage(EditorStandards.advancedKey) private var advancedControls = false
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
                Section {
                    Toggle("高级编辑选项", isOn: $advancedControls)
                        .accessibilityIdentifier("about.advancedControls")
                } header: { Text("编辑器") } footer: {
                    Text("开启后可单独调整字号、间距、尺寸、线宽和精确位置。关闭仅隐藏这些控件，保留已有设置。排版缩放会按标准排版成套调整。")
                }
                Section("本次测试") {
                    Text("支持新增、编辑、删除、拖动排序和完成待办。")
                    Text("支持主屏幕小组件直接完成或恢复待办，以及本地壁纸编辑与 PNG 导出。")
                    Text("安装标识：\(Bundle.main.bundleIdentifier ?? "未知")").font(.caption).textSelection(.enabled)
                }
            }
            .navigationTitle("关于")
        }
    }
}
