import SwiftUI
import WidgetKit
import CoreGraphics

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let document: TodoDocument?
    var appearance = TodoAppearance()
    let error: String?
    var background: CGImage?
}
struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        let now = Date()
        return TodoWidgetEntry(date: now, document: TodoDocument(items: [
            TodoItem(id: UUID(), title: "记下重要的小事", isCompleted: false, createdAt: now, updatedAt: now)
        ]), error: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        defer { WidgetPhotoCache.releaseDecodedSources() }
        var entry = context.isPreview ? placeholder(in: context) : read()
        entry.background = WidgetPhotoCache.prepared(style: entry.appearance.widget, size: context.displaySize, date: entry.date)
        completion(entry)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        defer { WidgetPhotoCache.releaseDecodedSources() }
        let initial = read()
        // Keep only today/tomorrow bitmap resources alive. Request the next pair
        // at the next day boundary; the second entry is a scheduling fallback.
        let rotating = initial.appearance.widget.photoRotation?.enabled == true
        let dates = WidgetDayTimeline.dates(now: initial.date, count: rotating ? 2 : 1)
        let entries = dates.map { date in
            TodoWidgetEntry(date: date, document: initial.document, appearance: initial.appearance, error: initial.error,
                background: WidgetPhotoCache.prepared(style: initial.appearance.widget, size: context.displaySize, date: date))
        }
        completion(Timeline(entries: entries, policy: dates.count > 1 ? .after(dates[1]) : .never))
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
        let readable = ReadableResolver.scrim(style: style, date: entry.date, scheme: scheme)
        TodoWidgetContent(document: entry.document, appearance: entry.appearance,
            error: entry.error, family: previewFamily)
            .containerBackground(for: .widget) {
                WidgetBackgroundView(style: style, date: entry.date, preparedPhoto: entry.background, preparedOnly: true,
                                     scrim: readable.value, scrimAnchor: style.readable.anchor,
                                     scrimHeightRatio: style.readable.heightRatio, scrimColor: readable.color)
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
