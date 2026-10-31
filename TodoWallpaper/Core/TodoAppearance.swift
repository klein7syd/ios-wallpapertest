import Foundation

enum MarkerKind: String, Codable, CaseIterable, Identifiable {
    case hollow, filled, thin, bordered, square, emoji, image, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hollow: return "空心圆"; case .filled: return "实心圆"; case .thin: return "细线圆"
        case .bordered: return "带边框圆"; case .square: return "方框"; case .emoji: return "自定义 Emoji"; case .image: return "自定义图片"; case .none: return "不显示"
        }
    }
}
struct TodoMarker: Codable, Equatable, Sendable {
    var kind = MarkerKind.hollow
    var emoji = "⭐"
    var imageName: String?
    func validate() throws {
        if kind == .emoji, !EmojiInput.isValid(emoji) { throw AppearanceError.invalidEmoji }
        if let imageName, !MarkerImageReference.isValid(imageName) { throw AppearanceError.invalidStyle }
    }
}
enum EmojiInput {
    static func isValid(_ string: String) -> Bool {
        guard string.count == 1, string.utf16.count <= 64, string.utf8.count <= 128,
              string == string.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        let scalars = string.unicodeScalars
        let emoji = scalars.contains { $0.properties.isEmoji && !(0x1F3FB...0x1F3FF).contains($0.value) }
        let presentation = scalars.contains { $0.properties.isEmojiPresentation || $0.value == 0xFE0F || $0.value == 0x20E3 }
        return emoji && (presentation || scalars.contains { $0.value >= 0x2300 && $0.properties.isEmoji })
    }
}
enum MarkerCompletion: String, Codable, CaseIterable, Identifiable {
    case keep, dim, replace, checkShapes, thinCircle
    var id: String { rawValue }
    var title: String {
        switch self { case .keep: return "保留原标记"; case .dim: return "降低透明度"; case .replace: return "替换为自定义 Emoji"; case .checkShapes: return "原图形加勾"; case .thinCircle: return "替换为细线完成圆" }
    }
}
struct MarkerStyle: Codable, Equatable, Sendable {
    var size: Double = 18
    var emojiSize: Double = 22
    var gap: Double = 10
    var verticalOffset: Double = 0
    var lineWidth: Double = 1.5
    var followsTextColor = true
    var fill = WallpaperColor()
    var stroke = WallpaperColor()
    var completedColor = WallpaperColor(red: 0.2, green: 0.75, blue: 0.4)
    var completion = MarkerCompletion.checkShapes
    var completionEmoji = "✅"
    func validate() throws {
        guard (8...48).contains(size), (8...48).contains(emojiSize), (0...32).contains(gap),
              (-16...16).contains(verticalOffset), (0.3...6).contains(lineWidth),
              fill.isValid, stroke.isValid, completedColor.isValid,
              EmojiInput.isValid(completionEmoji) else { throw AppearanceError.invalidStyle }
    }
    func resolved(_ marker: TodoMarker, completed: Bool) -> (marker: TodoMarker, opacity: Double, checked: Bool) {
        // Hiding a marker must not resurrect it through a dormant completion policy.
        // Keep that policy saved so choosing a visible marker restores its behavior.
        if marker.kind == .none { return (marker, 1, false) }
        if completed && completion == .replace { return (TodoMarker(kind: .emoji, emoji: completionEmoji), 1, false) }
        if completed && completion == .thinCircle { return (TodoMarker(kind: .thin), 1, true) }
        return (marker, completed && completion == .dim ? 0.4 : 1,
                completed && completion == .checkShapes && marker.kind != .emoji && marker.kind != .image && marker.kind != .none)
    }
}
extension WallpaperColor {
    var isValid: Bool { [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) } }
}
enum WidgetTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "跟随系统" : self == .light ? "亮色" : "深色" }
}
enum WidgetBackdrop: String, Codable, CaseIterable, Identifiable {
    case system, solid, photo
    var id: String { rawValue }
    var title: String { self == .system ? "系统" : self == .solid ? "底色" : "照片" }
}
struct WidgetHeaderAppearance: Codable, Equatable, Sendable {
    var text = "待办"
    var showsTitle = true
    var showsSummary = true
    var followsTextColor = true
    var color = WallpaperColor()
    var font = WallpaperFont.system
    var weight = WallpaperWeight.semibold
    var fontSize: Double = 17
    /// Position within the available title region, excluding the summary.
    var horizontalPosition: Double = 0
    var topInset: Double = 0
    var visibleTitle: Bool { showsTitle && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func validate() throws {
        guard text.count <= 40, !text.contains(where: { $0.isNewline }), color.isValid,
              (12...32).contains(fontSize), (0...1).contains(horizontalPosition),
              (0...24).contains(topInset) else { throw AppearanceError.invalidStyle }
    }
}
enum WidgetCompleted: String, Codable, CaseIterable, Identifiable {
    case recent, hidden, all
    var id: String { rawValue }
    var title: String { self == .recent ? "最近完成一项" : self == .hidden ? "仅未完成" : "全部事项" }
}
enum WidgetTextCompletion: String, Codable, CaseIterable, Identifiable {
    case fadeStrike, strike, fade, keep, color, hidden
    var id: String { rawValue }
    var title: String {
        switch self { case .fadeStrike: return "变淡并划线"; case .strike: return "仅划线"
        case .fade: return "仅变淡"; case .keep: return "保持原样"; case .color: return "自定义颜色"
        case .hidden: return "点按后隐藏" }
    }
    var strikes: Bool { self == .fadeStrike || self == .strike }
    var fades: Bool { self == .fadeStrike || self == .fade }
    /// Completed rows leave the widget entirely instead of staying visibly crossed out.
    var hidesCompleted: Bool { self == .hidden }
}
struct WidgetAppearance: Codable, Equatable, Sendable {
    var theme = WidgetTheme.system
    var backdrop = WidgetBackdrop.system
    var panelColor = WallpaperColor(red: 0.12, green: 0.12, blue: 0.12)
    var followsSystemText = true
    var textColor = WallpaperColor()
    var font = WallpaperFont.system
    var weight = WallpaperWeight.regular
    var fontSize: Double = 15
    var markerOverride: TodoMarker?
    var markerStyle = MarkerStyle()
    var spacing: Double = 5
    var compact = false
    var maximumItems = 6
    var completed = WidgetCompleted.recent
    // Optional additive fields keep the complete 0.4.1 appearance JSON decodable.
    var completedTextStyle: WidgetTextCompletion?
    var completedTextColor: WallpaperColor?
    var showsSeparators: Bool?
    var header: WidgetHeaderAppearance?
    var backgroundPhotoName: String?
    var backgroundCrop: PhotoCrop?
    var backgroundPhotoOpacity: Double?
    var photoRotation: WidgetAlbumRotation?
    var systemMaterial: Bool?
    var showsFooter: Bool?
    /// Extra inter-row padding; the separate line-count policy avoids forcing
    /// two text lines into every large Widget row when tight spacing is selected.
    var lianxinShowsSignature: Bool?
    var lianxinCentered: Bool?
    var maximumTitleLines: Int?
    /// One marker style for every task, ignoring per-item overrides.
    var unifiedMarkers: Bool?
    /// Completed tasks leave the widget immediately after a tap.
    var hidesCompletedTasks: Bool?
    // 可读性层设置（随撤销与预览实时生效）
    var readableAnchor: TextAnchor?
    var readableIntensity: ReadabilityIntensity?
    var readableScrimOverride: Double?
    var readableHeightRatio: Double?
    var readableShadowPreset: ShadowPreset?
    var readableEdgeInset: Double?

    var readable: ReadableSettings {
        ReadableSettings(anchor: readableAnchor ?? ReadableDefaults.anchor,
                         intensity: readableIntensity ?? .standard,
                         scrimOverride: readableScrimOverride,
                         heightRatio: readableHeightRatio ?? ReadableDefaults.scrimHeightRatio,
                         shadowPreset: readableShadowPreset ?? .standard,
                         edgeInset: readableEdgeInset ?? 0)
    }
    var heading: WidgetHeaderAppearance { header ?? WidgetHeaderAppearance() }
    var textCompletion: WidgetTextCompletion { completedTextStyle ?? .fadeStrike }
    var completionColor: WallpaperColor { completedTextColor ?? markerStyle.completedColor }
    var separatesRows: Bool { showsSeparators ?? false }
    func validate() throws {
        try markerOverride?.validate(); try markerStyle.validate()
        try header?.validate()
        if let readableScrimOverride, !(0...0.8).contains(readableScrimOverride) { throw AppearanceError.invalidStyle }
        if let readableHeightRatio, !(0.25...0.7).contains(readableHeightRatio) { throw AppearanceError.invalidStyle }
        if let readableEdgeInset,
           !readableEdgeInset.isFinite || (readable.anchor != .center && !(-40...40).contains(readableEdgeInset)) {
            throw AppearanceError.invalidStyle
        }
        try backgroundCrop?.validate(); try photoRotation?.validate()
        if let backgroundPhotoOpacity, !backgroundPhotoOpacity.isFinite || !(0...1).contains(backgroundPhotoOpacity) { throw AppearanceError.invalidStyle }
        if let backgroundPhotoName, !WidgetPhotoReference.isValid(backgroundPhotoName) { throw AppearanceError.invalidStyle }
        guard (12...20).contains(fontSize), (-10...40).contains(spacing), (1...10).contains(maximumItems),
              maximumTitleLines.map({ (1...4).contains($0) }) ?? true,
              textColor.isValid, panelColor.isValid, completedTextColor?.isValid != false else { throw AppearanceError.invalidStyle }
    }
    func rows(_ items: [TodoItem], capacity: Int) -> [TodoItem] {
        let limit = max(1, min(capacity, maximumItems))
        let pending = items.filter { !$0.isCompleted }
        if hidesCompletedTasks == true { return Array(pending.prefix(limit)) }
        if textCompletion.hidesCompleted { return Array(pending.prefix(limit)) }
        if completed == .all { return Array(items.prefix(limit)) }
        if completed == .hidden { return Array(pending.prefix(limit)) }
        let recent = items.filter(\.isCompleted).max { $0.updatedAt < $1.updatedAt }
        guard let recent, limit > 1 || pending.isEmpty else { return Array(pending.prefix(limit)) }
        return Array(pending.prefix(limit - 1)) + [recent]
    }
}

extension TodoAppearance {
    /// 只修复样式的数值边界；版本、Emoji 与文件引用仍须通过原校验。
    func clampedForEditing() -> TodoAppearance {
        var next = self
        next.markerStyle.clampForEditing()
        next.widget.markerStyle.clampForEditing()
        next.widget.panelColor.clampForEditing(); next.widget.textColor.clampForEditing()
        next.widget.completedTextColor?.clampForEditing()
        next.widget.fontSize = ReadableRules.finiteClamp(next.widget.fontSize, to: 12...20, fallback: 15)
        next.widget.spacing = ReadableRules.finiteClamp(next.widget.spacing, to: -10...40, fallback: 5)
        next.widget.maximumItems = min(10, max(1, next.widget.maximumItems))
        next.widget.maximumTitleLines = next.widget.maximumTitleLines.map { min(4, max(1, $0)) }
        next.widget.readableScrimOverride = next.widget.readableScrimOverride.map { ReadableRules.finiteClamp($0, to: 0...0.8, fallback: 0.4) }
        next.widget.readableHeightRatio = next.widget.readableHeightRatio.map { ReadableRules.finiteClamp($0, to: 0.25...0.7, fallback: 0.45) }
        if let inset = next.widget.readableEdgeInset {
            next.widget.readableEdgeInset = next.widget.readable.anchor == .center
                ? (inset.isFinite ? inset : 0)
                : ReadableRules.finiteClamp(inset, to: ReadableDefaults.edgeInsetRange, fallback: 0)
        }
        next.widget.backgroundPhotoOpacity = next.widget.backgroundPhotoOpacity.map { ReadableRules.finiteClamp($0, to: 0...1, fallback: 1) }
        if var crop = next.widget.backgroundCrop {
            crop.zoom = ReadableRules.finiteClamp(crop.zoom, to: 1...4, fallback: 1)
            crop.panX = ReadableRules.finiteClamp(crop.panX, to: -1...1, fallback: 0)
            crop.panY = ReadableRules.finiteClamp(crop.panY, to: -1...1, fallback: 0)
            next.widget.backgroundCrop = crop
        }
        if var header = next.widget.header {
            header.color.clampForEditing()
            header.fontSize = ReadableRules.finiteClamp(header.fontSize, to: 12...32, fallback: 17)
            header.horizontalPosition = ReadableRules.finiteClamp(header.horizontalPosition, to: 0...1, fallback: 0)
            header.topInset = ReadableRules.finiteClamp(header.topInset, to: 0...24, fallback: 0)
            next.widget.header = header
        }
        if let slot = next.lianxin {
            var isolated = TodoAppearance(); isolated.widget = slot
            next.lianxin = isolated.clampedForEditing().widget
        }
        return next
    }
}
extension WallpaperColor {
    mutating func clampForEditing() {
        red = ReadableRules.finiteClamp(red, to: 0...1, fallback: 1)
        green = ReadableRules.finiteClamp(green, to: 0...1, fallback: 1)
        blue = ReadableRules.finiteClamp(blue, to: 0...1, fallback: 1)
        alpha = ReadableRules.finiteClamp(alpha, to: 0...1, fallback: 1)
    }
}
extension MarkerStyle {
    mutating func clampForEditing() {
        size = ReadableRules.finiteClamp(size, to: 8...48, fallback: 18)
        emojiSize = ReadableRules.finiteClamp(emojiSize, to: 8...48, fallback: 22)
        gap = ReadableRules.finiteClamp(gap, to: 0...32, fallback: 10)
        verticalOffset = ReadableRules.finiteClamp(verticalOffset, to: -16...16, fallback: 0)
        lineWidth = ReadableRules.finiteClamp(lineWidth, to: 0.3...6, fallback: 1.5)
        fill.clampForEditing(); stroke.clampForEditing(); completedColor.clampForEditing()
    }
}
struct TodoAppearance: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var defaultMarker = TodoMarker()
    var markerStyle = MarkerStyle()
    var widget = WidgetAppearance()
    var lianxin: WidgetAppearance?
    func marker(for item: TodoItem, widgetContext: Bool = false) -> TodoMarker {
        if widgetContext && widget.unifiedMarkers == true {
            return widget.markerOverride ?? defaultMarker
        }
        return item.marker ?? (widgetContext ? widget.markerOverride : nil) ?? defaultMarker
    }
    func validate() throws {
        guard schemaVersion == 1 else { throw AppearanceError.unsupportedVersion }
        try defaultMarker.validate(); try markerStyle.validate(); try widget.validate(); try lianxin?.validate()
    }
}
enum AppearanceError: LocalizedError {
    case invalidEmoji, invalidStyle, unsupportedVersion, unreadable
    var errorDescription: String? {
        switch self {
        case .invalidEmoji: return "请输入一个完整 Emoji，可包含肤色或组合；不支持普通文本或多个标记。"
        case .invalidStyle: return "标记或小组件样式参数不完整，原文件已保留。"
        case .unsupportedVersion: return "样式来自较新版本，原文件已保留。"
        case .unreadable: return "无法读取共享样式，原文件已保留。请重试或恢复有效备份。"
        }
    }
}
