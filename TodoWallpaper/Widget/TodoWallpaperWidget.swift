import SwiftUI
import WidgetKit
import CoreGraphics

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let document: TodoDocument?
    var appearance = TodoAppearance()
    let error: String?
    var background: CGImage?
    var canvasAspect: Double = 1
    var analyses: [String: ImageAnalysis] = [:]
}
struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        let now = Date()
        return TodoWidgetEntry(date: now, document: TodoDocument(items: [
            TodoItem(id: UUID(), title: "记下重要的小事", isCompleted: false, createdAt: now, updatedAt: now)
        ]), error: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        AppearanceStore.shared.clearMemoryCache()
        defer { WidgetPhotoCache.releaseDecodedSources() }
        var entry = context.isPreview ? placeholder(in: context) : read()
        entry.canvasAspect = context.displaySize.width / max(1, context.displaySize.height)
        entry.analyses = registerAnalysisRequests(style: entry.appearance.widget, date: entry.date, aspect: entry.canvasAspect)
        entry.background = WidgetPhotoCache.prepared(style: entry.appearance.widget, size: context.displaySize, date: entry.date)
        completion(entry)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        AppearanceStore.shared.clearMemoryCache()
        defer { WidgetPhotoCache.releaseDecodedSources() }
        let initial = read()
        // Keep only today/tomorrow bitmap resources alive. Request the next pair
        // at the next day boundary; the second entry is a scheduling fallback.
        let rotating = initial.appearance.widget.photoRotation?.enabled == true
        let dates = WidgetDayTimeline.dates(now: initial.date, count: rotating ? 2 : 1)
        let entries = dates.map { date in
            let aspect = context.displaySize.width / max(1, context.displaySize.height)
            let analyses = registerAnalysisRequests(style: initial.appearance.widget, date: date, aspect: aspect)
            return TodoWidgetEntry(date: date, document: initial.document, appearance: initial.appearance, error: initial.error,
                background: WidgetPhotoCache.prepared(style: initial.appearance.widget, size: context.displaySize, date: date),
                canvasAspect: aspect, analyses: analyses)
        }
        completion(Timeline(entries: entries, policy: dates.count > 1 ? .after(dates[1]) : .never))
    }
    private func registerAnalysisRequests(style: WidgetAppearance, date: Date, aspect: Double) -> [String: ImageAnalysis] {
        guard style.backdrop == .photo, !style.materialEnabled, let name = style.photoName(at: date) else { return [:] }
        let backgrounds = style.theme == .system && style.photoOpacity < 1 ? [false, true] : [style.isExplicitlyDark ?? false]
        var analyses: [String: ImageAnalysis] = [:]
        for dark in backgrounds {
            let request = style.analysisRequest(photoName: name, canvasAspect: aspect, darkBackground: dark)
            AppearanceStore.shared.registerMissing(request)
            for anchor in TextAnchor.allCases {
                analyses[request.cacheID + "." + anchor.rawValue] = AppearanceStore.shared.analysis(for: request, anchor: anchor)
            }
        }
        return analyses
    }
    private func read() -> TodoWidgetEntry {
        do {
            let document = try TodoSharedStorage.widgetSnapshot().document
            let appearance = try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).load()
            return TodoWidgetEntry(date: .now, document: document, appearance: appearance, error: nil)
        } catch { return TodoWidgetEntry(date: .now, document: nil, error: error.localizedDescription) }
    }
}
struct TodoWidgetView: View {
    let entry: TodoWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetContentMargins) private var contentMargins
    private var style: WidgetAppearance { entry.appearance.widget }
    @Environment(\.colorScheme) private var defaultScheme
    private var scheme: ColorScheme { style.theme == .system ? defaultScheme : style.theme == .dark ? .dark : .light }
    private var previewFamily: WidgetPreviewFamily { family == .systemLarge ? .large : family == .systemMedium ? .medium : .small }
    var body: some View {
        let readable = ReadableResolver.scrim(style: style, date: entry.date, scheme: scheme,
            renderingMode: renderingMode, family: family, canvasAspect: entry.canvasAspect, preparedAnalyses: entry.analyses)
        TodoWidgetContent(document: entry.document, appearance: entry.appearance,
            error: entry.error, family: previewFamily, effectsFamily: family)
            .containerBackground(for: .widget) {
                WidgetBackgroundView(style: style, date: entry.date, preparedPhoto: entry.background, preparedOnly: true,
                                     scrim: readable.value, scrimAnchor: style.readable.anchor,
                                     scrimHeightRatio: style.readable.heightRatio, scrimColor: readable.color,
                                      scrimExtraInset: style.readable.edgeInset,
                                      contentDocument: entry.document, contentAppearance: entry.appearance,
                                      contentFamily: previewFamily, contentMargins: contentMargins, effectsFamily: family)
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
