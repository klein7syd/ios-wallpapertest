import Foundation

/// 文字锚点：同时决定文字对齐与蒙层方向
enum TextAnchor: String, Codable, CaseIterable, Identifiable, Sendable {
    case top, center, bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "顶部"
        case .center: return "居中"
        case .bottom: return "底部"
        }
    }
}

/// 一层阴影
struct ShadowLayer: Equatable, Sendable {
    var radius: Double
    var y: Double
    var opacity: Double
}

/// 一套阴影配方：同一套配方里阴影颜色一致
struct ShadowRecipe: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let layers: [ShadowLayer]
    let usesWhite: Bool

    var summary: String {
        guard !layers.isEmpty else { return "无阴影" }
        return layers.map { String(format: "r%.1f %.2f", $0.radius, $0.opacity) }.joined(separator: " + ")
    }
}

enum ShadowRecipes {
    /// 浅色文字（黑阴影）
    static let light: [ShadowRecipe] = [
        ShadowRecipe(id: "A", name: "单层", layers: [ShadowLayer(radius: 2.5, y: 1, opacity: 0.35)], usesWhite: false),
        ShadowRecipe(id: "B", name: "双层", layers: [ShadowLayer(radius: 1, y: 0.5, opacity: 0.45),
                                                ShadowLayer(radius: 3, y: 1, opacity: 0.25)], usesWhite: false),
        ShadowRecipe(id: "C", name: "宽柔", layers: [ShadowLayer(radius: 2, y: 1, opacity: 0.40),
                                                ShadowLayer(radius: 8, y: 2, opacity: 0.25)], usesWhite: false),
        ShadowRecipe(id: "D", name: "无阴影", layers: [], usesWhite: false),
        ShadowRecipe(id: "I", name: "当前默认", layers: [ShadowLayer(radius: 0.8, y: 0.5, opacity: 0.30),
                                                 ShadowLayer(radius: 2.0, y: 1.0, opacity: 0.18)], usesWhite: false)
    ]

    /// 深色文字（白阴影）
    static let dark: [ShadowRecipe] = [
        ShadowRecipe(id: "E", name: "当前", layers: [ShadowLayer(radius: 1, y: 0.5, opacity: 0.35)], usesWhite: true),
        ShadowRecipe(id: "F", name: "细光晕", layers: [ShadowLayer(radius: 1.5, y: 0.5, opacity: 0.60),
                                                 ShadowLayer(radius: 4, y: 1, opacity: 0.35)], usesWhite: true),
        ShadowRecipe(id: "G", name: "宽光晕", layers: [ShadowLayer(radius: 2, y: 1, opacity: 0.50),
                                                 ShadowLayer(radius: 8, y: 2, opacity: 0.40)], usesWhite: true),
        ShadowRecipe(id: "H", name: "无阴影", layers: [], usesWhite: true),
        ShadowRecipe(id: "J", name: "当前默认", layers: [ShadowLayer(radius: 1.0, y: 0.5, opacity: 0.40)], usesWhite: true)
    ]
}

/// 标准值集中在这里，只改这一处
enum ReadableDefaults {
    static let anchor: TextAnchor = .bottom
    /// 没有图片分析结果时的回退值
    static let scrim: Double = 0.4
    static let scrimHeightRatio: Double = 0.45
    static let scrimRange: ClosedRange<Double> = 0...0.8
    static let heightRatioRange: ClosedRange<Double> = 0.25...0.7
    static let edgeInsetRange: ClosedRange<Double> = -12...40

    /// 当前选中的阴影配方；选定字母后只改这两行
    static let lightTextRecipe: ShadowRecipe = ShadowRecipes.light[4]   // I
    static let darkTextRecipe: ShadowRecipe = ShadowRecipes.dark[4]     // J
}

/// 可读性强度：同时作用于蒙层与阴影
enum ReadabilityIntensity: String, Codable, CaseIterable, Identifiable {
    case subtle, standard, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: return "弱"
        case .standard: return "标准"
        case .strong: return "强"
        }
    }

    /// 蒙层倍率
    var multiplier: Double {
        switch self {
        case .subtle: return 0.7
        case .standard: return 1.0
        case .strong: return 1.3
        }
    }

    /// 阴影不透明度倍率，独立于蒙层
    var shadowOpacityMultiplier: Double {
        switch self {
        case .subtle: return 0.5
        case .standard: return 0.8
        case .strong: return 1.1
        }
    }

    /// 阴影半径缩放
    var shadowRadiusScale: Double {
        switch self {
        case .subtle: return 0.7
        case .standard: return 0.85
        case .strong: return 1.0
        }
    }
}

/// 一组完整的可读性设置，存在 WidgetAppearance 里，随撤销和预览实时生效
struct ReadableSettings: Equatable {
    var anchor: TextAnchor = ReadableDefaults.anchor
    var intensity: ReadabilityIntensity = .standard
    var scrimOverride: Double?
    var heightRatio: Double = ReadableDefaults.scrimHeightRatio
    var shadowPreset: ShadowPreset = .standard
    /// 文字块离锚点边缘的距离；居中锚点时作为垂直偏移
    var edgeInset: Double = 0

    func scrim(auto: Double) -> Double {
        let value = scrimOverride ?? auto
        return min(ReadableDefaults.scrimRange.upperBound,
                   max(ReadableDefaults.scrimRange.lowerBound, value))
    }

    func autoScrim(analysis: ImageAnalysis?, isLightText: Bool = true) -> Double {
        let base = analysis.map { ReadableRules.scrim(meanLuma: $0.meanLuma, contrast: $0.contrast, isLightText: isLightText) }
            ?? ReadableDefaults.scrim
        let value = base * intensity.multiplier
        return min(ReadableDefaults.scrimRange.upperBound,
                   max(ReadableDefaults.scrimRange.lowerBound, value))
    }
}

// Target Membership: App + Widget。纯值规则也由 macOS 原生检查直接执行。
enum ReadableRules {
    static func permitsEffects(isFullColor: Bool, isAccessory: Bool) -> Bool {
        isFullColor && !isAccessory
    }
    static func scrim(meanLuma: Double, contrast: Double, isLightText: Bool) -> Double {
        let mean = finiteClamp(meanLuma, to: 0...1, fallback: 0.5)
        let contrast = finiteClamp(contrast, to: 0...1, fallback: 0.5)
        let difficulty = isLightText ? min(1, mean / 0.8) : min(1, max(0, (0.8 - mean) / 0.8))
        var value = 0.25 + 0.25 * difficulty + 0.10 * contrast
        if isLightText ? mean < 0.25 : mean > 0.75 { value = min(value, 0.15) }
        return min(0.55, max(0.2, value))
    }
    static func coverHeight(_ height: Double, ratio: Double, extraInset: Double) -> Double {
        min(height, max(0, height * ratio + max(0, extraInset)))
    }
    static func insetRange(anchor: TextAnchor, canvasHeight: Double, textHeight: Double) -> ClosedRange<Double> {
        guard anchor == .center else { return ReadableDefaults.edgeInsetRange }
        let canvas = canvasHeight.isFinite ? max(0, canvasHeight) : 0
        let text = textHeight.isFinite ? max(0, textHeight) : canvas
        let limit = max(40, (canvas - text) / 2)
        return -limit...limit
    }
    static func inset(_ value: Double, anchor: TextAnchor, canvasHeight: Double, textHeight: Double) -> Double {
        finiteClamp(value, to: insetRange(anchor: anchor, canvasHeight: canvasHeight, textHeight: textHeight), fallback: 0)
    }
    static func finiteClamp(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

struct ReadableContentGeometry: Equatable {
    var canvasHeight: Double = 0
    var textHeight: Double = 0
}

/// 旧字段保留解码兼容，不再参与渲染
enum ShadowPreset: String, Codable, CaseIterable, Identifiable {
    case subtle, standard, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .subtle: return "弱"
        case .standard: return "标准"
        case .strong: return "强"
        }
    }

    var opacityScale: Double { 1.0 }
}

/// 主 App 侧对一张图的亮度分析结果，写进 App Group 供 Widget 只读
struct ImageAnalysis: Codable, Equatable, Sendable {
    var meanLuma: Double
    var contrast: Double
    /// 旧缓存可读；新缓存不再写入与文字颜色绑定的建议值。
    private(set) var suggestedScrim: Double?

    init(meanLuma: Double, contrast: Double) {
        self.meanLuma = meanLuma; self.contrast = contrast
    }
    private enum CodingKeys: String, CodingKey { case meanLuma, contrast, suggestedScrim }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        meanLuma = try values.decode(Double.self, forKey: .meanLuma)
        contrast = try values.decode(Double.self, forKey: .contrast)
        suggestedScrim = try values.decodeIfPresent(Double.self, forKey: .suggestedScrim)
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(meanLuma, forKey: .meanLuma)
        try values.encode(contrast, forKey: .contrast)
    }

    static let fallback = ImageAnalysis(meanLuma: 0.5, contrast: 0.5)
}
