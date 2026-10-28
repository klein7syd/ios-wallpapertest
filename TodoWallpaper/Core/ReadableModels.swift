import Foundation

/// 文字锚点：同时决定文字对齐与蒙层方向
enum TextAnchor: String, Codable, CaseIterable, Identifiable {
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

/// 阴影预设：只改透明度，radius 固定
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

    var opacityScale: Double {
        switch self {
        case .subtle: return 0.7
        case .standard: return 1.0
        case .strong: return 1.35
        }
    }
}

/// 标准值集中在这里，只改这一处
enum ReadableDefaults {
    static let anchor: TextAnchor = .bottom
    /// 没有图片分析结果时的回退值（不是固定值，正常走自动）
    static let scrim: Double = 0.4
    static let scrimHeightRatio: Double = 0.45
    static let shadowPreset: ShadowPreset = .standard
    static let scrimRange: ClosedRange<Double> = 0...0.8
    static let heightRatioRange: ClosedRange<Double> = 0.25...0.7
}

/// 可读性强度：自动走图片分析，其余三档在自动值上乘系数
enum ReadabilityIntensity: String, Codable, CaseIterable, Identifiable {
    case automatic, subtle, standard, strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "自动"
        case .subtle: return "弱"
        case .standard: return "标准"
        case .strong: return "强"
        }
    }

    var multiplier: Double {
        switch self {
        case .automatic: return 1.0
        case .subtle: return 0.7
        case .standard: return 1.0
        case .strong: return 1.3
        }
    }
}

/// 主 App 侧对一张图的亮度分析结果，写进 App Group 供 Widget 只读
struct ImageAnalysis: Codable, Equatable, Sendable {
    var meanLuma: Double
    var contrast: Double
    var suggestedScrim: Double

    static let fallback = ImageAnalysis(meanLuma: 0.5, contrast: 0.5, suggestedScrim: 0.4)
}
