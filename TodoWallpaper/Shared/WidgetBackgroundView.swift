import SwiftUI
import ImageIO

/// Widget photos are local App Group assets, never a screenshot of the Home Screen.
/// Read once per reference so ordinary sliders don't repeatedly decode an image.
struct WidgetBackgroundView: View {
    let style: WidgetAppearance
    var sharedDirectory: URL?
    var date: Date = .now
    var preparedPhoto: CGImage?
    var preparedOnly = false
    /// 蒙层画在背景层，铺满全幅，不受内容 padding 影响
    var scrim: Double = 0
    var scrimAnchor: TextAnchor = .bottom
    var scrimHeightRatio: Double = ReadableDefaults.scrimHeightRatio
    var scrimColor: Color = .black
    @Environment(\.colorScheme) private var systemScheme
    var body: some View {
        GeometryReader { geometry in
            let image = preparedPhoto ?? (style.backdrop == .photo && !preparedOnly ? WidgetPhotoCache.image(named: style.photoName(at: date), sharedDirectory: sharedDirectory) : nil)
            ZStack {
                if style.materialEnabled {
                    WidgetGlassBackground()
                } else {
                    (style.backdrop == .solid ? style.panelColor.swiftColor :
                        (style.isExplicitlyDark ?? (systemScheme == .dark) ? Color(white: 0.09) : .white))
                    if let image {
                        let frame = preparedPhoto != nil ? CGRect(origin: .zero, size: geometry.size) : style.photoCrop.frame(source: CGSize(width: image.width, height: image.height), canvas: geometry.size)
                        Image(decorative: image, scale: 1).resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY).opacity(style.photoOpacity)
                    }
                }
                if scrim > 0 {
                    ScrimView(anchor: scrimAnchor, strength: scrim, heightRatio: scrimHeightRatio, color: scrimColor)
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()

        }
    }
}
enum WidgetPhotoCache {
    private static let cache = NSCache<NSString, CGImage>()
    static func releaseDecodedSources() { cache.removeAllObjects() }
    static func image(named name: String?, sharedDirectory: URL? = nil) -> CGImage? {
        guard let name, WidgetPhotoReference.isValid(name) else { return nil }
        guard let directory = sharedDirectory ?? (try? TodoSharedStorage.sharedDirectory()),
              let url = try? WidgetPhotoReference.url(for: name, in: directory) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        cache.totalCostLimit = 4 * 1024 * 1024
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}

/// Public API only. Whether SpringBoard supplies its wallpaper behind this view
/// in default-icon mode must be verified on a device, not inferred from app blur.
private struct WidgetGlassBackground: View {
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else { Rectangle().fill(.ultraThinMaterial) }
    }
}

extension WidgetPhotoCache {
    /// Make a small, self-contained image before handing a timeline to WidgetKit.
    /// The view no longer performs shared-file I/O or carries a 1536px source
    /// into each of eight future snapshots. The archived bitmap has a hard bound.
    static func prepared(style: WidgetAppearance, size: CGSize, date: Date, sharedDirectory: URL? = nil) -> CGImage? {
        guard style.backdrop == .photo, !style.materialEnabled else { return nil }
        return autoreleasepool {
            guard let source = image(named: style.photoName(at: date), sharedDirectory: sharedDirectory) else { return nil }
            let factor = min(2, 768 / max(1, max(size.width, size.height)))
            let width = max(1, Int((size.width * factor).rounded())), height = max(1, Int((size.height * factor).rounded()))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            let top = style.photoCrop.frame(source: CGSize(width: source.width, height: source.height), canvas: CGSize(width: width, height: height))
            let rect = CGRect(x: top.minX, y: CGFloat(height) - top.maxY, width: top.width, height: top.height)
            context.interpolationQuality = .high
            context.draw(source, in: rect)
            return context.makeImage()
        }
    }
}
