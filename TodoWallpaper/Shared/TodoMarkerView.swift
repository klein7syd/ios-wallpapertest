import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension WallpaperColor {
    var swiftColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    static func resolved(_ color: Color, dark: Bool) -> WallpaperColor {
        #if canImport(UIKit)
        let native = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if native.getRed(&r, green: &g, blue: &b, alpha: &a) { return WallpaperColor(red: r, green: g, blue: b, alpha: a) }
        #else
        if let native = NSColor(color).usingColorSpace(.sRGB) {
            return WallpaperColor(red: native.redComponent, green: native.greenComponent, blue: native.blueComponent, alpha: native.alphaComponent)
        }
        #endif
        return WallpaperColor(red: dark ? 1 : 0, green: dark ? 1 : 0, blue: dark ? 1 : 0)
    }
}

/// Uses the same bounded Core Text color-glyph renderer as native PNG output.
/// No fixed Text frame/minimumScaleFactor can clip a small heart or hide size changes.
struct TodoMarkerView: View {
    let marker: TodoMarker
    let completed: Bool
    var style = MarkerStyle()
    var textColor: Color = .primary
    var maximumSize: Double = 48
    var assetDirectory: URL?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    private var extent: Double { min(maximumSize, MarkerDrawing.extent(marker: marker, style: style, completed: completed)) }
    var body: some View {
        if extent > 0 {
            Group {
                if [.emoji, .image].contains(style.resolved(marker, completed: completed).marker.kind),
                   let bitmap = MarkerBitmapCache.image(marker: marker, completed: completed, style: style,
                       extent: extent, scale: displayScale, directory: assetDirectory) {
                    if #available(iOS 18.0, macOS 15.0, *) {
                        Image(decorative: bitmap, scale: displayScale).resizable().widgetAccentedRenderingMode(.fullColor)
                    } else { Image(decorative: bitmap, scale: displayScale).resizable() }
                } else { Canvas { graphics, size in
                graphics.withCGContext { context in
                    context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
                    MarkerDrawing.draw(marker: marker, completed: completed, style: style,
                        textColor: WallpaperColor.resolved(textColor, dark: scheme == .dark),
                        rect: CGRect(origin: .zero, size: size), context: context, assetDirectory: assetDirectory)
                }
            } }
            }
            .frame(width: extent, height: extent)
            .offset(y: style.verticalOffset)
            .accessibilityHidden(true)
        }
    }
}

private enum MarkerBitmapCache {
    private static let cache = NSCache<NSString, CGImage>()
    static func image(marker: TodoMarker, completed: Bool, style: MarkerStyle, extent: Double, scale: Double, directory: URL?) -> CGImage? {
        let result = style.resolved(marker, completed: completed)
        let pixels = max(1, Int(ceil(extent * min(3, max(1, scale)))))
        let key = "\(result.marker.kind):\(result.marker.emoji):\(result.marker.imageName ?? ""):\(result.opacity):\(pixels):\(directory?.path ?? "shared")" as NSString
        if let image = cache.object(forKey: key) { return image }
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(pixels) / extent, y: CGFloat(pixels) / extent)
        MarkerDrawing.draw(marker: marker, completed: completed, style: style, textColor: WallpaperColor(),
            rect: CGRect(x: 0, y: 0, width: extent, height: extent), context: context, assetDirectory: directory)
        guard let image = context.makeImage() else { return nil }
        cache.totalCostLimit = 2 * 1024 * 1024
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
