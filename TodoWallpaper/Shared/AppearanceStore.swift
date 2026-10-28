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
        static let scrimOverride = "readable.scrimOverride"
        static let shadowPreset = "readable.shadowPreset"
        static let analysisPrefix = "readable.analysis."
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    var anchor: TextAnchor {
        get { defaults.string(forKey: Key.anchor).flatMap(TextAnchor.init(rawValue:)) ?? .bottom }
        set { defaults.set(newValue.rawValue, forKey: Key.anchor) }
    }

    var shadowPreset: ShadowPreset {
        get { defaults.string(forKey: Key.shadowPreset).flatMap(ShadowPreset.init(rawValue:)) ?? .standard }
        set { defaults.set(newValue.rawValue, forKey: Key.shadowPreset) }
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

    /// 最终 scrim：手动覆盖 > 图片分析 > 0.4
    func effectiveScrim(imageID: String?) -> Double {
        if let scrimOverride { return scrimOverride }
        if let imageID, let analysis = analysis(for: imageID) { return analysis.suggestedScrim }
        return 0.4
    }
}
