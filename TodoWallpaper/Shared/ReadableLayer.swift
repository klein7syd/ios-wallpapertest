import SwiftUI

// MARK: - 蒙层（铺满全幅，画在背景层）

struct ScrimView: View {
    let anchor: TextAnchor
    let strength: Double
    let heightRatio: Double
    var color: Color = .black
    /// 额外覆盖的高度，文字块留白变大时用它兜住
    var extraInset: Double = 0

    var body: some View {
        GeometryReader { proxy in
            switch anchor {
            case .bottom:
                LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
                    .frame(height: coverHeight(proxy.size.height))
                    .frame(maxHeight: .infinity, alignment: .bottom)

            case .top:
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .frame(height: coverHeight(proxy.size.height))
                    .frame(maxHeight: .infinity, alignment: .top)

            case .center:
                RadialGradient(colors: [color.opacity(strength * 0.55), .clear],
                               center: .center,
                               startRadius: 0,
                               endRadius: proxy.size.height * 0.55)
            }
        }
        .allowsHitTesting(false)
    }

    private func coverHeight(_ height: Double) -> Double {
        min(height, height * heightRatio + abs(extraInset))
    }

    /// 三个 stop 避免出现明显的一条带
    private var stops: [Gradient.Stop] {
        [
            .init(color: color.opacity(strength), location: 0),
            .init(color: color.opacity(strength * 0.45), location: 0.5),
            .init(color: .clear, location: 1)
        ]
    }
}

// MARK: - 文字阴影

struct TextStyleModifier: ViewModifier {
    let preset: ShadowPreset
    /// 浅色文字用黑阴影，深色文字用一层很轻的白阴影
    let isLightText: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isLightText {
            content
                // 紧贴字形的细黑边：在蒙层上也要看得见，所以不透明度比原来高
                .shadow(color: .black.opacity(0.55 * preset.opacityScale), radius: 1, x: 0, y: 0.5)
                // 柔和外晕
                .shadow(color: .black.opacity(0.30 * preset.opacityScale), radius: 3.5, x: 0, y: 1)
        } else {
            // 深色文字只留一层细白影，加大 radius 就会发白发糊
            content
                .shadow(color: .white.opacity(0.35 * preset.opacityScale), radius: 1, x: 0, y: 0.5)
        }
    }
}

extension View {
    func readableText(style: ShadowPreset = .standard, isLightText: Bool = true) -> some View {
        modifier(TextStyleModifier(preset: style, isLightText: isLightText))
    }
}

// MARK: - 只负责文字阴影

struct ReadableLayer<Content: View>: View {
    var shadowPreset: ShadowPreset = .standard
    var isLightText: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    var body: some View {
        #if DEBUG
        let _ = debugLog()
        #endif
        if isAccessory || renderingMode != .fullColor {
            content()
        } else {
            content().modifier(TextStyleModifier(preset: shadowPreset, isLightText: isLightText))
        }
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    #if DEBUG
    /// 只有 DEBUG 才会打印，方便排查真机是否被 accented / vibrant 关掉了阴影
    private func debugLog() -> Void {
        print("[ReadableLayer] renderingMode=\(renderingMode) family=\(family) lightText=\(isLightText) accessory=\(isAccessory)")
    }
    #endif
}

// MARK: - 蒙层取值

enum ReadableResolver {
    /// 蒙层只在照片背景下出现；颜色跟文字亮度联动
    static func scrim(style: WidgetAppearance, date: Date, scheme: ColorScheme) -> (value: Double, color: Color) {
        guard style.backdrop == .photo, !style.materialEnabled else { return (0, .black) }
        let settings = style.readable
        let imageID = style.photoName(at: date)
        let analysis = imageID.flatMap { AppearanceStore.shared.analysis(for: $0, anchor: settings.anchor) }
        let value = settings.scrim(auto: settings.autoScrim(analysis: analysis))
        let dark = style.isExplicitlyDark ?? (scheme == .dark)
        let requested = style.followsSystemText
            ? (dark ? WallpaperColor() : WallpaperColor(red: 0, green: 0, blue: 0))
            : style.textColor
        let base = TextLegibility.widgetBase(style, dark: dark)
        let light = TextLegibility.luminance(TextLegibility.readable(requested, on: base)) > 0.5
        return (value, light ? .black : .white)
    }
}
