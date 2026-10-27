import Foundation

enum TextLegibility {
    static func luminance(_ color: WallpaperColor) -> Double {
        func channel(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return channel(color.red) * 0.2126 + channel(color.green) * 0.7152 + channel(color.blue) * 0.0722
    }
    static func contrast(_ a: WallpaperColor, _ b: WallpaperColor) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func composite(_ front: WallpaperColor, over back: WallpaperColor) -> WallpaperColor {
        WallpaperColor(red: front.red * front.alpha + back.red * (1 - front.alpha),
            green: front.green * front.alpha + back.green * (1 - front.alpha),
            blue: front.blue * front.alpha + back.blue * (1 - front.alpha))
    }
    static func readable(_ requested: WallpaperColor, on background: WallpaperColor) -> WallpaperColor {
        if contrast(composite(requested, over: background), background) >= 3 { return requested }
        let black = WallpaperColor(red: 0, green: 0, blue: 0), white = WallpaperColor()
        return contrast(black, background) > contrast(white, background) ? black : white
    }
    static func widgetBase(_ style: WidgetAppearance, dark: Bool) -> WallpaperColor {
        let base = dark ? WallpaperColor(red: 0.09, green: 0.09, blue: 0.09) : WallpaperColor()
        return style.backdrop == .solid && !style.materialEnabled ? composite(style.panelColor, over: base) : base
    }
}
