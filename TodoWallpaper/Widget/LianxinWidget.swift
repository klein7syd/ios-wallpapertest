// Target Membership：仅 Widget。
import SwiftUI
import WidgetKit
import ImageIO

struct LianxinEntry: TimelineEntry {
    let date: Date
    let content: LianxinPublication?
    let photo: CGImage?
    var failed = false
}

struct LianxinProvider: TimelineProvider {
    func placeholder(in context: Context) -> LianxinEntry {
        LianxinEntry(date: .now, content: LianxinPublication(idol: "连心", text: "把想听的话，留在每天看得见的地方。", photo: nil, date: .now), photo: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (LianxinEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read(size: context.displaySize))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LianxinEntry>) -> Void) {
        completion(Timeline(entries: [read(size: context.displaySize)], policy: .never))
    }
    private func read(size: CGSize) -> LianxinEntry {
        do {
            let content = try LianxinPublication.load(directory: TodoSharedStorage.sharedDirectory())
            var photo: CGImage?
            if let data = content?.photo, let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) {
                photo = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: min(1200, max(1, max(size.width, size.height) * 3))] as CFDictionary)
            }
            return LianxinEntry(date: .now, content: content, photo: photo)
        } catch { return LianxinEntry(date: .now, content: nil, photo: nil, failed: true) }
    }
}

struct LianxinWidgetView: View {
    let entry: LianxinEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode
    private var accessory: Bool { family == .accessoryCircular || family == .accessoryRectangular }
    var body: some View {
        Group {
            if family == .accessoryCircular {
                VStack { Image(systemName: "heart"); Text(entry.content?.idol ?? "连心").font(.caption2).lineLimit(1) }
                    .accessibilityLabel(entry.content?.text ?? "在连心中发布一句话")
            } else {
                VStack(alignment: .leading, spacing: accessory ? 2 : 8) {
                    Text("\(entry.content?.idol ?? "连心") · \(entry.content?.contentLabel ?? "AI 创作")").font(.caption).lineLimit(1)
                    Text(entry.content?.text ?? (entry.failed ? "暂时无法读取，请打开 App 重试。" : "打开 App，在连心中生成并发布话语。"))
                        .font(accessory ? .caption : .body)
                        .lineLimit(accessory ? 3 : family == .systemSmall ? 4 : family == .systemMedium ? 5 : 12)
                        .minimumScaleFactor(0.85)
                    if !accessory { Spacer(minLength: 0) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(accessory ? 0 : 10)
                    .background {
                        if !accessory && mode == .fullColor { RoundedRectangle(cornerRadius: 16).fill(.regularMaterial) }
                    }
            }
        }
        .containerBackground(for: .widget) {
            if !accessory, mode == .fullColor, let photo = entry.photo {
                GeometryReader { proxy in
                    Image(decorative: photo, scale: 1).resizable().scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height).clipped()
                }
            } else { Color.clear }
        }
    }
}

struct LianxinWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LianxinPublication.kind, provider: LianxinProvider()) { LianxinWidgetView(entry: $0) }
            .configurationDisplayName("连心")
            .description("展示你生成并发布的话语与照片底图。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct TodoWallpaperWidgetBundle: WidgetBundle {
    var body: some Widget { TodoWallpaperWidget(); LianxinWidget() }
}
