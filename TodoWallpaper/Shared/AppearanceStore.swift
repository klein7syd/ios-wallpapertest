import Foundation

/// 只负责图片分析结果的读写；可读性设置本身存在 WidgetAppearance 里。
final class AppearanceStore {
    static let shared = AppearanceStore()

    private enum Key {
        static let analysisPrefix = "readable.analysis."
    }

    private let defaults: UserDefaults
    /// 视图 body 里不再读 UserDefaults / 解 JSON，全部走这里
    private var cache: [String: ImageAnalysis] = [:]

    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
    }

    private func key(_ imageID: String, _ anchor: TextAnchor) -> String {
        Key.analysisPrefix + imageID + "." + anchor.rawValue
    }

    func analysis(for imageID: String, anchor: TextAnchor) -> ImageAnalysis? {
        let cacheKey = key(imageID, anchor)
        if let cached = cache[cacheKey] { return cached }
        guard let data = defaults.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode(ImageAnalysis.self, from: data) else { return nil }
        cache[cacheKey] = decoded
        return decoded
    }

    func setAnalysis(_ analysis: ImageAnalysis, for imageID: String, anchor: TextAnchor) {
        guard let data = try? JSONEncoder().encode(analysis) else { return }
        let cacheKey = key(imageID, anchor)
        cache[cacheKey] = analysis
        defaults.set(data, forKey: cacheKey)
    }

    /// 三个锚点一次写好，切换锚点不用重算
    func setAnalysis(_ analyses: [TextAnchor: ImageAnalysis], for imageID: String) {
        for (anchor, analysis) in analyses {
            setAnalysis(analysis, for: imageID, anchor: anchor)
        }
    }

    func removeAnalysis(for imageID: String) {
        for anchor in TextAnchor.allCases {
            let cacheKey = key(imageID, anchor)
            cache.removeValue(forKey: cacheKey)
            defaults.removeObject(forKey: cacheKey)
        }
    }
}

/// App Group 常量集中在这里
enum AppGroup {
    static let identifier = TodoWidgetConstants.originalGroupID
    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// 旧版本把可读性设置存在 UserDefaults，这里做一次性迁移
enum ReadableSettingsMigration {
    private enum Key {
        static let anchor = "readable.anchor"
        static let intensity = "readable.intensity"
        static let scrimOverride = "readable.scrimOverride"
        static let shadowPreset = "readable.shadowPreset"
        static let scrimHeightRatio = "readable.scrimHeightRatio"
    }

    static func take() -> ReadableSettings? {
        let defaults = AppGroup.defaults
        let hasLegacy = defaults.string(forKey: Key.anchor) != nil
            || defaults.string(forKey: Key.intensity) != nil
            || defaults.object(forKey: Key.scrimOverride) != nil
        guard hasLegacy else { return nil }

        var settings = ReadableSettings()
        if let raw = defaults.string(forKey: Key.anchor), let value = TextAnchor(rawValue: raw) { settings.anchor = value }
        if let raw = defaults.string(forKey: Key.intensity), let value = ReadabilityIntensity(rawValue: raw) { settings.intensity = value }
        if let raw = defaults.string(forKey: Key.shadowPreset), let value = ShadowPreset(rawValue: raw) { settings.shadowPreset = value }
        if let value = defaults.object(forKey: Key.scrimOverride) as? Double { settings.scrimOverride = value }
        let ratio = defaults.double(forKey: Key.scrimHeightRatio)
        if ratio > 0 { settings.heightRatio = ratio }

        for key in [Key.anchor, Key.intensity, Key.scrimOverride, Key.shadowPreset, Key.scrimHeightRatio] {
            defaults.removeObject(forKey: key)
        }
        return settings
    }
}
