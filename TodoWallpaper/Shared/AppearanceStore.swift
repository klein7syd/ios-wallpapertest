import Foundation

/// App Group 常量集中在这里
enum AppGroup {
    static let identifier = TodoWidgetConstants.originalGroupID
    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// 主 App 与 Widget 共用的轻量存储（可读性层专用）
final class AppearanceStore {
    static let shared = AppearanceStore()

    private enum Key {
        static let anchor = "readable.anchor"
        static let intensity = "readable.intensity"
        static let scrimOverride = "readable.scrimOverride"
        static let shadowPreset = "readable.shadowPreset"
        static let scrimHeightRatio = "readable.scrimHeightRatio"
        static let analysisPrefix = "readable.analysis."
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        // 旧描边实现的残留 key，启动时清理
        for key in ["textOutline", "readable.outline", "widget.textOutline"] {
            defaults.removeObject(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    var anchor: TextAnchor {
        get { defaults.string(forKey: Key.anchor).flatMap(TextAnchor.init(rawValue:)) ?? ReadableDefaults.anchor }
        set { defaults.set(newValue.rawValue, forKey: Key.anchor) }
    }

    var intensity: ReadabilityIntensity {
        get { defaults.string(forKey: Key.intensity).flatMap(ReadabilityIntensity.init(rawValue:)) ?? .automatic }
        set { defaults.set(newValue.rawValue, forKey: Key.intensity) }
    }

    var shadowPreset: ShadowPreset {
        get { defaults.string(forKey: Key.shadowPreset).flatMap(ShadowPreset.init(rawValue:)) ?? ReadableDefaults.shadowPreset }
        set { defaults.set(newValue.rawValue, forKey: Key.shadowPreset) }
    }

    var scrimHeightRatio: Double {
        get {
            let value = defaults.double(forKey: Key.scrimHeightRatio)
            return value <= 0 ? ReadableDefaults.scrimHeightRatio : value
        }
        set { defaults.set(newValue, forKey: Key.scrimHeightRatio) }
    }

    /// nil 表示没有手动覆盖
    var scrimOverride: Double? {
        get { defaults.object(forKey: Key.scrimOverride) as? Double }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.scrimOverride)
            } else {
                defaults.removeObject(forKey: Key.scrimOverride)
            }
        }
    }

    func analysis(for imageID: String) -> ImageAnalysis? {
        guard let data = defaults.data(forKey: Key.analysisPrefix + imageID) else { return nil }
        return try? JSONDecoder().decode(ImageAnalysis.self, from: data)
    }

    func setAnalysis(_ analysis: ImageAnalysis, for imageID: String) {
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        defaults.set(data, forKey: Key.analysisPrefix + imageID)
    }

    func removeAnalysis(for imageID: String) {
        defaults.removeObject(forKey: Key.analysisPrefix + imageID)
    }

    /// 当前背景图按自动规则算出的 scrim（不含手动覆盖）
    func autoScrim(imageID: String?) -> Double {
        let base = imageID.flatMap { analysis(for: $0)?.suggestedScrim } ?? ReadableDefaults.scrim
        return min(ReadableDefaults.scrimRange.upperBound,
                   max(ReadableDefaults.scrimRange.lowerBound, base * intensity.multiplier))
    }

    /// 小组件与预览统一走这里：手动值 > 图片分析 > 标准值
    func effectiveScrim(imageID: String?) -> Double {
        if let scrimOverride {
            return min(ReadableDefaults.scrimRange.upperBound,
                       max(ReadableDefaults.scrimRange.lowerBound, scrimOverride))
        }
        return autoScrim(imageID: imageID)
    }

    /// 是否偏离了标准值，用于普通模式下提示"已使用自定义参数"
    var hasCustomValues: Bool {
        scrimOverride != nil
            || anchor != ReadableDefaults.anchor
            || intensity != .automatic
            || shadowPreset != ReadableDefaults.shadowPreset
            || abs(scrimHeightRatio - ReadableDefaults.scrimHeightRatio) > 0.001
    }
}
