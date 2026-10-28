import SwiftUI

// MARK: - 蒙层

/// 只压暗文字所在区域，不碰整张图
struct ScrimView: View {
    let anchor: TextAnchor
    let strength: Double
    let heightRatio: CGFloat

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
                RadialGradient(
                    colors: [.black.opacity(strength * 0.55), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: proxy.size.height * 0.55
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// 三个 stop 避免出现明显的一条带
    private var stops: [Gradient.Stop] {
        [
            .init(color: .black.opacity(strength), location: 0),
            .init(color: .black.opacity(strength * 0.45), location: 0.5),
            .init(color: .clear, location: 1)
        ]
    }
}

// MARK: - 文字样式

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

// MARK: - 核心容器

struct ReadableLayer<Content: View>: View {
    var anchor: TextAnchor = .bottom
    var scrim: Double = 0.4
    var scrimHeightRatio: CGFloat = 0.45
    var shadowPreset: ShadowPreset = .standard
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if isAccessory {
            content()
        } else {
            ZStack(alignment: alignment) {
                if showsEffects && scrim > 0 {
                    ScrimView(anchor: anchor, strength: scrim, heightRatio: scrimHeightRatio)
                }
                content()
                    .modifier(TextStyleModifier(preset: shadowPreset, enabled: showsEffects))
                    .frame(maxWidth: .infinity, alignment: alignment)
                    .padding(paddingForFamily)
            }
        }
    }

    private var alignment: Alignment {
        switch anchor {
        case .top: return .topLeading
        case .center: return .center
        case .bottom: return .bottomLeading
        }
    }

    /// accented / vibrant 由系统着色，额外阴影会脏
    private var showsEffects: Bool {
        renderingMode == .fullColor
    }

    private var isAccessory: Bool {
        switch family {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline:
            return true
        default:
            return false
        }
    }

    private var paddingForFamily: CGFloat {
        switch family {
        case .systemSmall: return 12
        case .systemMedium: return 14
        case .systemLarge: return 16
        default: return padding
        }
    }
}
