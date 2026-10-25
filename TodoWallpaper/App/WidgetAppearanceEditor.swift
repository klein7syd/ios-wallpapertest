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
    @State private var selectedTaskID: UUID?
    @State private var preview = WidgetPreviewState()
    @State private var showHelp = false
    @State private var previousWidgetMarker: TodoMarker?
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.dynamicTypeSize) private var typeSize
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
                if geometry.size.height < 320 || typeSize.isAccessibilitySize {
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
                InspectorViewport(pageID: tool.id + (advanced ? ".advanced" : ".basic") + (selectedTaskID?.uuidString ?? ".default")) {
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
        .onChange(of: store.items.map(\.id)) { _, ids in if let selectedTaskID, !ids.contains(selectedTaskID) { self.selectedTaskID = nil } }
        .onDisappear { store.flushAppearance() }
        .sheet(isPresented: $showHelp) { help }
        .alert("样式", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好", role: .cancel) { }
        } message: { Text(error ?? "") }
    }
    private func fixedPreview(height: CGFloat) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(WidgetPreviewFamily.allCases) { size in Button(size.title) { family = size } }
                } label: { Label(family.title, systemImage: "rectangle.3.group").font(.subheadline) }
                Spacer(minLength: 0)
                Text("点标记编辑 · 点文字试完成").font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Button { preview.reset() } label: { Image(systemName: "arrow.counterclockwise").frame(width: 44, height: 44) }
                    .accessibilityLabel("重置预览完成状态，不修改真实待办")
            }
            GeometryReader { proxy in
                let scale = family.scale(availableWidth: proxy.size.width - 32, availableHeight: proxy.size.height - 8)
                TodoWidgetContent(document: store.hasLoaded && store.loadError == nil ? TodoDocument(items: preview.items(store.items)) : nil,
                    appearance: store.appearance, error: store.loadError, family: family, interactive: false,
                    onPreviewToggle: { id in if let item = store.items.first(where: { $0.id == id }) { preview.toggle(item) } },
                    onPreviewMarker: { id in selectedTaskID = id; tool = .marker; advanced = false }, selectedTaskID: selectedTaskID)
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
            if hasVisibleMarker { PreciseSlider(title: "与标记间距", value: widget.markerStyle.gap, range: 0...32) }
            Picker("字重", selection: widget.weight) { ForEach(WallpaperWeight.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("完成文字", selection: Binding(get: { store.appearance.widget.textCompletion }, set: { widget.wrappedValue.completedTextStyle = $0 })) {
                ForEach(WidgetTextCompletion.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            if store.appearance.widget.textCompletion == .color {
                StyleColorControl(title: "完成文字色", value: Binding(get: { store.appearance.widget.completionColor }, set: { widget.wrappedValue.completedTextColor = $0 }))
            }
        } else {
            Picker("字体", selection: widget.font) { ForEach(WallpaperFont.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
        }
    }
    @ViewBuilder private var markerControls: some View {
        Menu {
            Button("小组件默认") { selectedTaskID = nil; advanced = false }
            ForEach(store.items) { item in Button(item.title) { selectedTaskID = item.id; advanced = false } }
        } label: { Label(selectedTask?.title ?? "小组件默认", systemImage: selectedTask == nil ? "square.grid.2x2" : "pencil.circle").lineLimit(2) }
        if let item = selectedTask {
            if !advanced {
                MarkerChoiceEditor(choice: Binding(get: { store.appearance.marker(for: item, widgetContext: true) }, set: { setTaskMarker($0, id: item.id) }))
                if item.marker != nil { Button("恢复小组件默认") { setTaskMarker(nil, id: item.id) } }
            }
            MarkerStyleEditor(style: widget.markerStyle, kind: store.appearance.marker(for: item, widgetContext: true).kind, advanced: advanced)
            Text("此项标记单独保存；尺寸与完成效果用于整个小组件。").font(.caption).foregroundStyle(.secondary)
        } else {
            if !advanced {
                Toggle("继承壁纸标记", isOn: Binding(get: { store.appearance.widget.markerOverride == nil }, set: { inherit in
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
            Text("继承壁纸的标记类型与 Emoji；大小、间距和完成效果在这里独立设置。").font(.caption).foregroundStyle(.secondary)
        }
    }
    private var selectedTask: TodoItem? { store.items.first { $0.id == selectedTaskID } }
    private var hasVisibleMarker: Bool {
        (store.appearance.widget.markerOverride ?? store.appearance.defaultMarker).kind != .none ||
        store.items.contains { store.appearance.marker(for: $0, widgetContext: true).kind != .none }
    }
    private func setTaskMarker(_ marker: TodoMarker?, id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }) else { return }
        do { try store.edit(id: id, title: item.title, marker: marker) }
        catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private var contentControls: some View {
        if !advanced {
            Toggle("紧凑布局", isOn: widget.compact)
            PreciseSlider(title: "行距", value: widget.spacing, range: 0...12)
            Toggle("显示行分隔线", isOn: Binding(get: { store.appearance.widget.separatesRows }, set: { widget.wrappedValue.showsSeparators = $0 }))
            Stepper("最多 \(store.appearance.widget.maximumItems) 项", value: widget.maximumItems, in: 1...10)
            Picker("完成事项", selection: widget.completed) { ForEach(WidgetCompleted.allCases) { Text($0.title).tag($0) } }.pickerStyle(.menu)
        } else {
            Button("请求更新小组件") { store.flushAppearance(); store.reload() }
            Text("预览复用扩展的内容布局。实际尺寸、动态字体、系统外观及刷新时机会影响主屏幕显示。预览中的试点不会写入真实任务状态。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private var help: some View {
        NavigationStack {
            List {
                Section("添加与操作") {
                    Text("长按主屏幕，添加 Todo Wallpaper 小组件。点击任务可直接完成或恢复。")
                    Text("点预览标记可编辑该任务的 Emoji；点文字试完成或恢复。试点状态只留在预览，重置按钮可清除。单项标记修改会保存到真实任务。")
                    Text("预览遵守完成事项筛选。若试完成后该项隐藏，可重置预览，或选择显示全部事项来比较效果。")
                    Text("小组件字体随系统文字大小调整。较大的标记或字体会减少可显示行数，不会让滑块后半段失效。")
                }
                Section("背景与透明度") {
                    Text("不透明度 0 表示不绘制自定义底色，1 表示完全实色。它不控制系统为小组件合成的背景材质。")
                    Text("实际背景由 iOS 主屏幕外观决定，App 无法保证任意照片完全透出。没有使用截图拼接来模拟透明。")
                }
                Section("标记") { Text("单项标记优先于小组件默认，再到壁纸标记。壁纸标记只作静态装饰，小组件的完成效果独立设置。") }
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
