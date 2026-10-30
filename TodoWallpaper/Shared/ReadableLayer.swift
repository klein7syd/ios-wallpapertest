import SwiftUI
import WidgetKit

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
                    .offset(y: extraInset)
            }
        }
        .allowsHitTesting(false)
    }

    private func coverHeight(_ height: Double) -> Double {
        ReadableRules.coverHeight(height, ratio: heightRatio, extraInset: extraInset)
    }

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
    /// 这一层用的是哪套配方；nil 表示按文字亮度取默认配方
    var recipe: ShadowRecipe?
    var isLightText: Bool
    var intensity: ReadabilityIntensity = .standard
    var enabled: Bool = true

    func body(content: Content) -> some View {
        guard enabled else { return AnyView(content) }
        let chosen = recipe ?? (isLightText ? ReadableDefaults.lightTextRecipe : ReadableDefaults.darkTextRecipe)
        let tint = chosen.usesWhite ? Color.white : Color.black
        let layers = chosen.layers
        let opacityScale = intensity.shadowOpacityMultiplier
        let radiusScale = intensity.shadowRadiusScale

        return AnyView(Group {
            switch layers.count {
            case 0:
                content
            case 1:
                content.shadow(color: tint.opacity(layers[0].opacity * opacityScale),
                               radius: layers[0].radius * radiusScale, x: 0, y: layers[0].y)
            case 2:
                content.shadow(color: tint.opacity(layers[0].opacity * opacityScale),
                               radius: layers[0].radius * radiusScale, x: 0, y: layers[0].y)
                       .shadow(color: tint.opacity(layers[1].opacity * opacityScale),
                               radius: layers[1].radius * radiusScale, x: 0, y: layers[1].y)
            default:
                content.shadow(color: tint.opacity(layers[0].opacity * opacityScale),
                               radius: layers[0].radius * radiusScale, x: 0, y: layers[0].y)
                       .shadow(color: tint.opacity(layers[1].opacity * opacityScale),
                               radius: layers[1].radius * radiusScale, x: 0, y: layers[1].y)
                       .shadow(color: tint.opacity(layers[2].opacity * opacityScale),
                               radius: layers[2].radius * radiusScale, x: 0, y: layers[2].y)
            }
        })
    }
}

extension View {
    func readableText(recipe: ShadowRecipe? = nil, isLightText: Bool = true,
                      intensity: ReadabilityIntensity = .standard, enabled: Bool = true) -> some View {
        modifier(TextStyleModifier(recipe: recipe, isLightText: isLightText,
                                   intensity: intensity, enabled: enabled))
    }
}

// MARK: - 只负责文字阴影

struct ReadableLayer<Content: View>: View {
    var isLightText: Bool = true
    var intensity: ReadabilityIntensity = .standard
    /// 调试对比页用它指定配方
    var recipe: ShadowRecipe?
    @ViewBuilder var content: () -> Content

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if isAccessory || renderingMode != .fullColor {
            content()
        } else {
            content().modifier(TextStyleModifier(recipe: recipe, isLightText: isLightText, intensity: intensity))
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

// MARK: - 唯一色调解算

/// 文字色、深浅判定、蒙层色、是否启用效果，全部从这里出
struct ReadableTone {
    var textColor: Color
    var isLightText: Bool
    var scrimColor: Color
    var enabled: Bool

    static func resolve(style: WidgetAppearance, scheme: ColorScheme,
                        renderingMode: WidgetRenderingMode, family: WidgetFamily = .systemMedium) -> ReadableTone {
        let dark = style.isExplicitlyDark ?? (scheme == .dark)
        let requested = style.followsSystemText
            ? (dark ? WallpaperColor() : WallpaperColor(red: 0, green: 0, blue: 0))
            : style.textColor
        // 0.179 是与黑、白对比度相等的分界点，粉/绿/浅蓝不再被判成深色
        let light = TextLegibility.luminance(requested) > 0.179
        return ReadableTone(textColor: renderingMode == .fullColor ? requested.swiftColor : .primary,
                            isLightText: light,
                            scrimColor: light ? .black : .white,
                            enabled: ReadableRules.permitsEffects(isFullColor: renderingMode == .fullColor, isAccessory: family.isReadableAccessory))
    }
}

// MARK: - 蒙层取值

enum ReadableResolver {
    /// 蒙层只在照片背景下出现；颜色跟文字亮度联动
    static func scrim(style: WidgetAppearance, date: Date, scheme: ColorScheme,
                      renderingMode: WidgetRenderingMode = .fullColor,
                      family: WidgetFamily = .systemMedium, canvasAspect: Double = 1,
                      preparedAnalyses: [String: ImageAnalysis]? = nil) -> (value: Double, color: Color) {
        guard style.backdrop == .photo, !style.materialEnabled else { return (0, .black) }
        let tone = ReadableTone.resolve(style: style, scheme: scheme, renderingMode: renderingMode, family: family)
        guard tone.enabled else { return (0, tone.scrimColor) }
        let settings = style.readable
        let imageID = style.photoName(at: date)
        let analysis = imageID.flatMap { name in
            let request = style.analysisRequest(photoName: name, canvasAspect: canvasAspect,
                darkBackground: style.isExplicitlyDark ?? (scheme == .dark))
            if let preparedAnalyses { return preparedAnalyses[request.cacheID + "." + settings.anchor.rawValue] }
            return AppearanceStore.shared.cachedAnalysis(for: request, anchor: settings.anchor)
        }
        let value = settings.scrim(auto: settings.autoScrim(analysis: analysis, isLightText: tone.isLightText))
        return (value, tone.scrimColor)
    }
}

extension WidgetFamily {
    var isReadableAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
        default: return false
        }
    }
}

struct ReadableGeometryPreference: PreferenceKey {
    static var defaultValue = ReadableContentGeometry()
    static func reduce(value: inout ReadableContentGeometry, nextValue: () -> ReadableContentGeometry) { value = nextValue() }
}
