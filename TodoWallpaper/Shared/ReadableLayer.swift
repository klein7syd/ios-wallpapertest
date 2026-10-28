import SwiftUI

// MARK: - 蒙层（铺满全幅，画在背景层）

/// 只压暗文字所在区域，不碰整张图。由 WidgetBackgroundView 调用，铺满整块背景。
struct ScrimView: View {
    let anchor: TextAnchor
    let strength: Double
    let heightRatio: Double
    var color: Color = .black

    var body: some View {
        GeometryReader { proxy in
            switch anchor {
            case .bottom:
                LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
                    .frame(height: proxy.size.height * heightRatio)
                    .frame(maxHeight: .infinity, alignment: .bottom)

            case .top:
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
                    .frame(height: proxy.size.height * heightRatio)
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
    let enabled: Bool

    func body(content: Content) -> some View {
        let scale = enabled ? preset.opacityScale : 0

        return content
            // 第一层：紧贴字形，保证边缘锐利
            .shadow(color: .black.opacity(0.35 * scale), radius: 1, x: 0, y: 0.5)
            // 第二层：柔和外晕，把文字从背景里托起来
            .shadow(color: .black.opacity(0.25 * scale), radius: 4, x: 0, y: 1)
    }
}

extension View {
    func readableText(style: ShadowPreset = .standard, enabled: Bool = true) -> some View {
        modifier(TextStyleModifier(preset: style, enabled: enabled))
    }
}

// MARK: - 只负责文字阴影

/// 蒙层已经移到背景层，这里不再加 padding，也不再画蒙层。
struct ReadableLayer<Content: View>: View {
    var shadowPreset: ShadowPreset = .standard
    var enabled: Bool = true
    @ViewBuilder var content: () -> Content

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if isAccessory || renderingMode != .fullColor {
            content()
        } else {
            content().modifier(TextStyleModifier(preset: shadowPreset, enabled: enabled))
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
