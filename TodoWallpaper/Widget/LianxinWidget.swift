// Target Membership：仅 Widget。
import SwiftUI
import WidgetKit
import ImageIO

struct LianxinEntry: TimelineEntry {
    let date: Date
    let content: LianxinPublication?
    let photo: CGImage?
    var failed = false
    var style = WidgetAppearance()
    var aspect: Double = 1
    var analyses: [String: ImageAnalysis] = [:]
}

struct LianxinProvider: TimelineProvider {
    func placeholder(in context: Context) -> LianxinEntry {
        LianxinEntry(date: .now, content: LianxinPublication(idol: "连心", text: "把想听的话，留在每天看得见的地方。", photo: nil, date: .now), photo: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LianxinEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(size: context.displaySize))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LianxinEntry>) -> Void) {
        let initial = read(size: context.displaySize)
        let dates = WidgetDayTimeline.dates(now: initial.date, count: initial.style.photoRotation?.enabled == true ? 2 : 1)
        let entries = [initial] + dates.dropFirst().map { read(size: context.displaySize, date: $0) }
        completion(Timeline(entries: entries, policy: dates.count > 1 ? .after(dates[1]) : .never))
    }
    private func read(size: CGSize, date: Date = .now) -> LianxinEntry {
        AppearanceStore.shared.clearMemoryCache()
        defer { WidgetPhotoCache.releaseDecodedSources() }
        do {
            let content = try LianxinPublication.load(directory: TodoSharedStorage.sharedDirectory())
            let root = try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).load()
            let style = root.lianxin ?? root.widget
            var photo: CGImage?
            if let data = content?.photo, let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) {
                photo = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(1200, max(1, max(size.width, size.height) * 3))] as CFDictionary)
            }
            let aspect = size.width / max(1, size.height)
            var analyses: [String: ImageAnalysis] = [:]
            if style.backdrop == .photo, !style.materialEnabled, let name = style.photoName(at: date) {
                for dark in style.theme == .system && style.photoOpacity < 1 ? [false, true] : [style.isExplicitlyDark ?? false] {
                    let request = style.analysisRequest(photoName: name, canvasAspect: aspect, darkBackground: dark)
                    AppearanceStore.shared.registerMissing(request)
                    for anchor in TextAnchor.allCases { analyses[request.cacheID + "." + anchor.rawValue] = AppearanceStore.shared.analysis(for: request, anchor: anchor) }
                }
            }
            return LianxinEntry(date: date, content: content, photo: WidgetPhotoCache.prepared(style: style, size: size, date: date) ?? (root.lianxin == nil ? photo : nil), style: style, aspect: aspect, analyses: analyses)

        } catch { return LianxinEntry(date: .now, content: nil, photo: nil, failed: true) }
    }
}

struct LianxinWidgetView: View {
    let entry: LianxinEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    @Environment(\.colorScheme) private var scheme
    private var accessory: Bool { family == .accessoryCircular || family == .accessoryRectangular }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack(spacing: 2) { Image(systemName: "heart"); Text(entry.content?.example == true ? "示例" : (entry.content?.idol ?? "连心")).font(.caption2).lineLimit(1); if entry.style.lianxinShowsCreationLabel == true { Text(entry.content?.contentLabel ?? "AI 创作").font(.system(size: 8)).lineLimit(1) } }
                    .accessibilityLabel((entry.content?.contentLabel ?? "连心") + "，" + (entry.content?.text ?? "在连心中发布一句话"))
            } else {
                if accessory {
                    VStack(alignment: .leading) {
                        Text(entry.content?.text ?? "打开连心").font(.caption).lineLimit(2)
                        if entry.style.lianxinShowsCreationLabel == true { Text(entry.content?.contentLabel ?? "AI 创作").font(.caption2).lineLimit(1) }
                    }
                } else { LianxinWidgetContent(content: entry.content, style: entry.style, family: family == .systemLarge ? .large : family == .systemMedium ? .medium : .small, effectsFamily: family) }

            }
        }
        .containerBackground(for: .widget) {
            if !accessory {
                let readable = ReadableResolver.scrim(style: entry.style, date: entry.date, scheme: scheme, renderingMode: mode, family: family, canvasAspect: entry.aspect, preparedAnalyses: entry.analyses)
                WidgetBackgroundView(style: entry.style, date: entry.date, preparedPhoto: entry.photo, preparedOnly: true,
                    scrim: readable.value, scrimAnchor: entry.style.readable.anchor, scrimHeightRatio: entry.style.readable.heightRatio,
                    scrimColor: readable.color, scrimExtraInset: entry.style.readable.edgeInset, effectsFamily: family)
            } else { Color.clear }

        }
    }
}

struct LianxinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LianxinPublication.kind, provider: LianxinProvider()) { LianxinWidgetView(entry: $0) }
            .configurationDisplayName("连心")
            .description("自动同步连心中的话语与照片底图。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct TodoWallpaperWidgetBundle: WidgetBundle {
    var body: some Widget { TodoWallpaperWidget(); LianxinWidget() }
}
