import SwiftUI
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
    @Environment(\.colorScheme) private var scheme
    private var extent: Double { min(maximumSize, MarkerDrawing.extent(marker: marker, style: style, completed: completed)) }
    var body: some View {
        if extent > 0 {
            Canvas { graphics, size in
                graphics.withCGContext { context in
                    context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
                    MarkerDrawing.draw(marker: marker, completed: completed, style: style,
                        textColor: WallpaperColor.resolved(textColor, dark: scheme == .dark),
                        rect: CGRect(origin: .zero, size: size), context: context)
                }
            }
            .frame(width: extent, height: extent)
            .offset(y: style.verticalOffset)
            .accessibilityHidden(true)
        }
    }
}
