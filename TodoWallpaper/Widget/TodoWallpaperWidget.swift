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
    private var style: WidgetAppearance { entry.appearance.widget }
    @Environment(\.colorScheme) private var defaultScheme
    private var scheme: ColorScheme { style.theme == .system ? defaultScheme : style.theme == .dark ? .dark : .light }
    private var previewFamily: WidgetPreviewFamily { family == .systemLarge ? .large : family == .systemMedium ? .medium : .small }
    var body: some View {
        TodoWidgetContent(document: entry.document, appearance: entry.appearance,
            error: entry.error, family: previewFamily)
            .containerBackground(for: .widget) {
                if style.backdrop == .solid { style.panelColor.swiftColor }
                else { Rectangle().fill(.background) }
            }
            .environment(\.colorScheme, scheme)
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
