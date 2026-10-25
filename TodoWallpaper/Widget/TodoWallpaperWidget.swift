import SwiftUI
import WidgetKit

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let document: TodoDocument?
    var appearance = TodoAppearance()
    let error: String?
}
struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        let now = Date()
        return TodoWidgetEntry(date: now, document: TodoDocument(items: [
            TodoItem(id: UUID(), title: "记下重要的小事", isCompleted: false, createdAt: now, updatedAt: now)
        ]), error: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .never))
    }
    private func read() -> TodoWidgetEntry {
        do {
            let document = try TodoSharedStorage.widgetRepository().load()
            let appearance = try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).load()
            return TodoWidgetEntry(date: .now, document: document, appearance: appearance, error: nil)
        } catch { return TodoWidgetEntry(date: .now, document: nil, error: error.localizedDescription) }
    }
}
struct TodoWidgetView: View {
    let entry: TodoWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize
    private var style: WidgetAppearance { entry.appearance.widget }
    private var rowLimit: Int {
        if typeSize.isAccessibilitySize { return family == .systemLarge ? 3 : 1 }
        let base = family == .systemLarge ? 6 : family == .systemMedium ? 3 : 2
        if style.fontSize > 17 || style.spacing > 8 { return max(1, base - 1) }
        return style.compact && family == .systemLarge ? 8 : base
    }
    private var foreground: Color { style.followsSystemText ? .primary : style.textColor.swiftColor }
    private var scheme: ColorScheme? { style.theme == .system ? nil : style.theme == .dark ? .dark : .light }
    var body: some View {
        content
            .foregroundStyle(foreground)
            .containerBackground(for: .widget) {
                if style.backdrop == .solid { style.panelColor.swiftColor }
                else { Rectangle().fill(.background) }
            }
            .environment(\.colorScheme, scheme ?? defaultScheme)
    }
    @Environment(\.colorScheme) private var defaultScheme
    private var content: some View {
        VStack(alignment: .leading, spacing: style.compact ? min(3, style.spacing) : style.spacing) {
            if let document = entry.document {
                let pending = document.items.filter { !$0.isCompleted }
                let shown = style.rows(document.items, capacity: rowLimit)
                HStack {
                    Text("待办").font(.headline)
                    Spacer(minLength: 4)
                    Text("\(pending.count) 未完成").font(.caption2).lineLimit(1).minimumScaleFactor(0.8).opacity(0.7)
                }
                if document.items.isEmpty {
                    Spacer(minLength: 0)
                    Text("还没有待办").font(.subheadline)
                    Text("在 App 中记下第一件事").font(.caption).opacity(0.7)
                } else {
                    ForEach(shown) { taskButton($0) }
                    if shown.isEmpty { Text("全部完成").font(.subheadline) }
                }
                Spacer(minLength: 0)
                Text(document.items.count > shown.count ? "另有 \(document.items.count - shown.count) 项 · 点标记操作" : "点任务可完成或恢复")
                    .font(.caption2).opacity(0.7).lineLimit(1)
            } else {
                Text("Todo Wallpaper").font(.headline)
                Text(entry.error ?? "请先打开 App 完成迁移").font(.caption).lineLimit(family == .systemLarge ? 8 : 4)
                Spacer(minLength: 0)
            }
        }
    }
    private func taskButton(_ item: TodoItem) -> some View {
        Button(intent: SetTodoCompletionIntent(taskID: item.id, completed: !item.isCompleted)) {
            HStack(alignment: .center, spacing: min(12, style.markerStyle.gap)) {
                TodoMarkerView(marker: entry.appearance.marker(for: item, widgetContext: true), completed: item.isCompleted,
                               style: style.markerStyle, textColor: foreground, maximumSize: family == .systemSmall ? 20 : 24)
                Text(item.title)
                    .font(Font(NativeTypography.font(family: style.font, weight: style.weight, size: style.fontSize)))
                    .strikethrough(item.isCompleted).opacity(item.isCompleted ? 0.6 : 1)
                    .lineLimit(family == .systemLarge && !style.compact ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
            .padding(.vertical, style.compact ? 0 : 2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
        .invalidatableContent()
    }
}
@main
struct TodoWallpaperWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetConstants.kind, provider: TodoWidgetProvider()) { TodoWidgetView(entry: $0) }
            .configurationDisplayName("Todo Wallpaper")
            .description("直接完成待办，与 App 共享数据和个性化标记。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
