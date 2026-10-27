import SwiftUI
import ImageIO

/// Widget photos are local App Group assets, never a screenshot of the Home Screen.
/// Read once per reference so ordinary sliders don't repeatedly decode an image.
struct WidgetBackgroundView: View {
    let style: WidgetAppearance
    var sharedDirectory: URL?
    var body: some View {
        GeometryReader { geometry in
            let image = style.backdrop == .photo ? WidgetPhotoCache.image(named: style.backgroundPhotoName, sharedDirectory: sharedDirectory) : nil
            ZStack {
                if style.backdrop == .system || style.backdrop == .photo && image == nil { Rectangle().fill(.background) }
                else { style.panelColor.swiftColor }
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
    }
}
enum WidgetPhotoCache {
    private static let cache = NSCache<NSString, CGImage>()
    static func image(named name: String?, sharedDirectory: URL? = nil) -> CGImage? {
        guard let name, WidgetPhotoReference.isValid(name) else { return nil }
        guard let directory = sharedDirectory ?? (try? TodoSharedStorage.sharedDirectory()),
              let url = try? WidgetPhotoReference.url(for: name, in: directory) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        cache.totalCostLimit = 32 * 1024 * 1024
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
