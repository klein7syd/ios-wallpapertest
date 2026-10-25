import SwiftUI
import UIKit

private enum WidgetEditorTool: String, CaseIterable, Identifiable {
    case theme = "主题", text = "文字", marker = "标记", content = "内容"
    var id: String { rawValue }
}
struct WidgetAppearanceEditor: View {
    @ObservedObject var store: TodoStore
    @State private var error: String?
    @State private var tool = WidgetEditorTool.theme
    @State private var family = WidgetPreviewFamily.medium
    @State private var advanced = false
    @State private var editGlobalMarker = false
    @State private var showHelp = false
    @State private var previousWidgetMarker: TodoMarker?
    @Environment(\.colorScheme) private var systemScheme
    private var shared: Binding<TodoAppearance> {
        Binding(get: { store.appearance }, set: { store.setAppearance($0) })
    }
    private var widget: Binding<WidgetAppearance> {
        Binding(get: { store.appearance.widget }, set: { var next = store.appearance; next.widget = $0; store.setAppearance(next) })
    }
    private var scheme: ColorScheme {
        let theme = store.appearance.widget.theme
        return theme == .system ? systemScheme : theme == .dark ? .dark : .light
    }
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                fixedPreview(height: EditorSizing.widgetPreviewHeight(available: geometry.size.height, family: family))
                if geometry.size.height < 320 {
                    HStack {
                        Picker("类别", selection: $tool) { ForEach(WidgetEditorTool.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.menu)
                        Spacer()
                        Button(advanced ? "返回常用" : "更多") { advanced.toggle() }.frame(minHeight: 44)
                    }.padding(.horizontal, 18)
                } else {
                Picker("设置类别", selection: $tool) {
                    ForEach(WidgetEditorTool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 10)
                .accessibilityIdentifier("widget.tools")
                InspectorHeading(title: tool.rawValue, advanced: $advanced).padding(.horizontal, 18)
                }
                InspectorViewport(pageID: tool.id + (advanced ? ".advanced" : ".basic") + (editGlobalMarker ? ".global" : ".widget")) {
                    if let message = store.appearanceError {
                        Text(message).font(.caption).foregroundStyle(.red)
                        Button("重试") { store.reloadAppearance() }
                        Button("恢复有效样式备份") {
                            do { try store.recoverAppearance() } catch { self.error = error.localizedDescription }
                        }
                    }
                    switch tool {
                    case .theme: themeControls
                    case .text: textControls
                    case .marker: markerControls
                    case .content: contentControls
                    }
                }
                .frame(maxHeight: .infinity).accessibilityIdentifier("widget.settings")
            }
            .clipped()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("小组件").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: { Image(systemName: "questionmark.circle") }.accessibilityLabel("小组件帮助")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .onChange(of: tool) { _, _ in advanced = false }
        .onChange(of: editGlobalMarker) { _, _ in advanced = false }
        .onDisappear { store.flushAppearance() }
        .sheet(isPresented: $showHelp) { help }
        .alert("样式", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { }
        } message: { Text(error ?? "") }
    }
    private func fixedPreview(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            if height >= 100 {
            Picker("预览尺寸", selection: $family) {
                ForEach(WidgetPreviewFamily.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).frame(maxWidth: 280)
            }
            GeometryReader { proxy in
                let scale = family.scale(availableWidth: proxy.size.width - 32, availableHeight: proxy.size.height - 8)
                TodoWidgetContent(document: store.hasLoaded && store.loadError == nil ? TodoDocument(items: store.items) : nil,
                    appearance: store.appearance, error: store.loadError, family: family, interactive: false)
                    .padding(16)
                    .frame(width: family.width, height: family.height)
                    .background {
                        if store.appearance.widget.backdrop == .solid { store.appearance.widget.panelColor.swiftColor }
                        else { Rectangle().fill(.background) }
                    }
                    .environment(\.colorScheme, scheme)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .scaleEffect(scale)
                    .frame(width: family.width * scale, height: family.height * scale)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .background(TransparencyGrid())
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(height: height).padding(.horizontal, 16).padding(.top, 6)
        .accessibilityElement(children: .contain).accessibilityLabel("\(family.title)小组件外观预览，使用真实待办")
        .accessibilityIdentifier("widget.fixedPreview")
    }
    @ViewBuilder private var themeControls: some View {
        if !advanced {
            Picker("明暗", selection: widget.theme) { ForEach(WidgetTheme.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("背景", selection: widget.backdrop) { ForEach(WidgetBackdrop.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if store.appearance.widget.backdrop == .solid { StyleColorControl(title: "面板底色", value: widget.panelColor) }
        } else {
            Text("网格用于显示自定义底色的不透明度，不会出现在主屏幕小组件中。系统可能按主屏幕的深浅、着色或透明风格调整实际背景。")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("请求更新小组件") { store.flushAppearance(); store.reload() }
        }
    }
    @ViewBuilder private var textControls: some View {
        if !advanced {
            Toggle("文字跟随系统", isOn: widget.followsSystemText)
            if !store.appearance.widget.followsSystemText { StyleColorControl(title: "文字色", value: widget.textColor) }
            PreciseSlider(title: "字号", value: widget.fontSize, range: 12...20)
            Picker("字重", selection: widget.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        } else {
            Picker("字体", selection: widget.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        }
    }
    @ViewBuilder private var markerControls: some View {
        Picker("设置范围", selection: $editGlobalMarker) {
            Text("仅小组件").tag(false); Text("全局默认").tag(true)
        }.pickerStyle(.segmented)
        if editGlobalMarker {
            if !advanced { MarkerChoiceEditor(choice: shared.defaultMarker) }
            MarkerStyleEditor(style: shared.markerStyle, kind: store.appearance.defaultMarker.kind, advanced: advanced)
        } else {
            if !advanced {
                Toggle("继承全局标记", isOn: Binding(get: { store.appearance.widget.markerOverride == nil }, set: { inherit in
                    var next = store.appearance
                    if inherit { previousWidgetMarker = next.widget.markerOverride; next.widget.markerOverride = nil }
                    else { next.widget.markerOverride = previousWidgetMarker ?? next.defaultMarker }
                    store.setAppearance(next)
                }))
                if store.appearance.widget.markerOverride != nil {
                    MarkerChoiceEditor(choice: Binding(get: { store.appearance.widget.markerOverride ?? store.appearance.defaultMarker }, set: { value in
                        var next = store.appearance; next.widget.markerOverride = value; store.setAppearance(next)
                    }))
                }
            }
            MarkerStyleEditor(style: widget.markerStyle,
                kind: (store.appearance.widget.markerOverride ?? store.appearance.defaultMarker).kind, advanced: advanced)
        }
        if advanced {
            Text(editGlobalMarker ? "全局默认用于 App、壁纸和继承它的小组件。任务单项设置始终优先。" : "任务单项设置优先；这里只调整小组件的默认外观。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var contentControls: some View {
        if !advanced {
            Toggle("紧凑布局", isOn: widget.compact)
            PreciseSlider(title: "行距", value: widget.spacing, range: 0...12)
            Stepper("最多 \(store.appearance.widget.maximumItems) 项", value: widget.maximumItems, in: 1...10)
            Picker("完成事项", selection: widget.completed) { ForEach(WidgetCompleted.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
        } else {
            Button("请求更新小组件") { store.flushAppearance(); store.reload() }
            Text("预览复用扩展的内容布局。实际尺寸、动态字体、系统外观及刷新时机会影响主屏幕显示。预览中的任务不会执行完成操作。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var help: some View {
        NavigationStack {
            List {
                Section("添加与操作") {
                    Text("长按主屏幕，添加 Todo Wallpaper 小组件。点击任务可直接完成或恢复。")
                    Text("更改样式会请求系统更新小组件。这里的小、中、大预览复用 Widget 内容，按比例缩放以保留设置空间。")
                }
                Section("背景与透明度") {
                    Text("不透明度 0 表示不绘制自定义底色，1 表示完全实色。它不控制系统为小组件合成的背景材质。")
                    Text("实际背景由 iOS 主屏幕外观决定，App 无法保证任意照片完全透出。没有使用截图拼接来模拟透明。")
                }
                Section("标记") { Text("单项标记优先于小组件默认，再到全局默认。切换样式不会删除尺寸、颜色等已保存参数。") }
            }
            .navigationTitle("小组件帮助").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showHelp = false } } }
        }
    }
}

private struct TransparencyGrid: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(uiColor: .secondarySystemGroupedBackground)))
            let step: CGFloat = 14
            for y in 0...Int(size.height / step) {
                for x in 0...Int(size.width / step) where (x + y).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(x) * step, y: CGFloat(y) * step, width: step, height: step)),
                        with: .color(.secondary.opacity(0.07)))
                }
            }
        }.accessibilityHidden(true)
    }
}
