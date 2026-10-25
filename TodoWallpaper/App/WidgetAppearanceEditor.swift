import SwiftUI

struct WidgetAppearanceEditor: View {
    @ObservedObject var store: TodoStore
    @State private var error: String?
    private var shared: Binding<TodoAppearance> {
        Binding(get: { store.appearance }, set: { store.setAppearance($0) })
    }
    private var widget: Binding<WidgetAppearance> {
        Binding(get: { store.appearance.widget }, set: { var next = store.appearance; next.widget = $0; store.setAppearance(next) })
    }
    var body: some View {
        Form {
            Section("当前真实待办 · 样式预览") {
                VStack(alignment: .leading, spacing: store.appearance.widget.spacing) {
                    ForEach(store.appearance.widget.rows(store.items, capacity: 3)) { item in
                        HStack(spacing: 8) {
                            TodoMarkerView(marker: store.appearance.marker(for: item, widgetContext: true), completed: item.isCompleted,
                                           style: store.appearance.widget.markerStyle, textColor: previewText, maximumSize: 24)
                            Text(item.title).font(Font(NativeTypography.font(family: store.appearance.widget.font,
                                weight: store.appearance.widget.weight, size: store.appearance.widget.fontSize))).lineLimit(2)
                        }
                    }
                    if store.items.isEmpty { Text("添加待办后可预览标记") }
                }
                .foregroundStyle(previewText).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(previewBackground, in: RoundedRectangle(cornerRadius: 16))
            }
            if let message = store.appearanceError {
                Section { Text(message).font(.caption); Button("重试") { store.reloadAppearance() }
                    Button("恢复有效样式备份") { do { try store.recoverAppearance() } catch { self.error = error.localizedDescription } }
                }
            }
            Section("全局默认 · App / 壁纸 / Widget") {
                MarkerChoiceEditor(choice: shared.defaultMarker)
                MarkerStyleEditor(style: shared.markerStyle)
            }
            Section("小组件主题") {
                Picker("明暗", selection: widget.theme) { ForEach(WidgetTheme.allCases) { Text($0.title).tag($0) } }
                Picker("背景", selection: widget.backdrop) { ForEach(WidgetBackdrop.allCases) { Text($0.title).tag($0) } }
                if store.appearance.widget.backdrop == .solid { StyleColorControl(title: "面板底色", value: widget.panelColor) }
                Toggle("文字跟随系统", isOn: widget.followsSystemText)
                if !store.appearance.widget.followsSystemText { StyleColorControl(title: "文字色", value: widget.textColor) }
                Picker("字体", selection: widget.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }
                Picker("字重", selection: widget.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }
                PreciseSlider(title: "字号", value: widget.fontSize, range: 12...20)
            }
            Section("小组件标记") {
                Toggle("继承全局默认标记", isOn: Binding(get: { store.appearance.widget.markerOverride == nil }, set: { inherit in
                    var next = store.appearance; next.widget.markerOverride = inherit ? nil : next.defaultMarker; store.setAppearance(next)
                }))
                if store.appearance.widget.markerOverride != nil {
                    MarkerChoiceEditor(choice: Binding(get: { store.appearance.widget.markerOverride ?? store.appearance.defaultMarker }, set: { value in
                        var next = store.appearance; next.widget.markerOverride = value; store.setAppearance(next)
                    }))
                }
                MarkerStyleEditor(style: widget.markerStyle)
                Text("优先级：任务单项标记 → 小组件默认 → 全局默认。小组件内标记最多显示 24 点，避免挤占标题。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("密度与内容") {
                Toggle("紧凑布局", isOn: widget.compact)
                PreciseSlider(title: "行距", value: widget.spacing, range: 0...12)
                Stepper("最多 \(store.appearance.widget.maximumItems) 项", value: widget.maximumItems, in: 1...10)
                Picker("完成事项", selection: widget.completed) { ForEach(WidgetCompleted.allCases) { Text($0.title).tag($0) } }
                Text("实际数量受系统尺寸和动态字体约束。系统可能统一着色或调整背景，无法提供任意照片透明背景。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("请求更新小组件") { store.flushAppearance(); store.reload() }
            }
        }
        .navigationTitle("小组件与标记").navigationBarTitleDisplayMode(.inline)
        .onDisappear { store.flushAppearance() }
        .alert("样式", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { }
        } message: { Text(error ?? "") }
    }
    private var previewText: Color {
        store.appearance.widget.followsSystemText ? (store.appearance.widget.theme == .dark ? .white : store.appearance.widget.theme == .light ? .black : .primary) : store.appearance.widget.textColor.swiftColor
    }
    private var previewBackground: Color {
        store.appearance.widget.backdrop == .solid ? store.appearance.widget.panelColor.swiftColor :
            store.appearance.widget.theme == .dark ? Color(white: 0.12) : Color.gray.opacity(0.1)
    }
}
