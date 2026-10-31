// Target Membership：App + Widget；只处理已同步的画面内容，不读取私有角色资料。
import Foundation

enum LianxinTranslationDisplay: String, Codable, CaseIterable, Identifiable, Sendable {
    case both, original, translation
    var id: String { rawValue }
    var title: String { self == .both ? "原文+译文" : self == .original ? "仅原文" : "仅译文" }
}
struct LianxinDisplayStyle: Codable, Equatable, Sendable {
    var translationDisplay = LianxinTranslationDisplay.both
    var translationScale = 0.85
    var translationOpacity = 0.8
    // nil自动，0不限，1…4显式上限；待办的maximumTitleLines保持原含义。
    var maximumLines: Int?
    var showsSignature = true
    var centered = false
    var showsCreationLabel = false
    func validate() throws {
        guard translationScale.isFinite, (0.5...1).contains(translationScale),
              translationOpacity.isFinite, (0...1).contains(translationOpacity),
              maximumLines.map({ (0...4).contains($0) }) ?? true else { throw AppearanceError.invalidStyle }
    }
    var clamped: Self {
        var value = self
        value.translationScale = ReadableRules.finiteClamp(value.translationScale, to: 0.5...1, fallback: 0.85)
        value.translationOpacity = ReadableRules.finiteClamp(value.translationOpacity, to: 0...1, fallback: 0.8)
        value.maximumLines = value.maximumLines.map { min(4, max(0, $0)) }
        return value
    }
}
struct LianxinPresentation {
    static let itemID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    let primary: String
    let secondary: String?
    init(_ content: LianxinPublication, style: LianxinDisplayStyle) {
        switch style.translationDisplay {
        case .both: primary = content.text; secondary = content.translation.flatMap { $0.isEmpty ? nil : $0 }
        case .original: primary = content.text; secondary = nil
        case .translation: primary = content.translation ?? ""; secondary = nil
        }
    }
    var item: TodoItem {
        TodoItem(id: Self.itemID, title: primary, marker: nil, isCompleted: false, createdAt: .distantPast, updatedAt: .distantPast)
    }
    static func header(_ raw: WidgetHeaderAppearance, customTitle: String?, member: String, subtitle: String?) -> WidgetHeaderAppearance {
        var value = raw
        let custom = (customTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        value.text = String((custom.isEmpty ? member : custom).filter { !$0.isNewline }.prefix(40))
        value.showsSummary = raw.showsSummary && !(subtitle ?? "").isEmpty
        return value
    }
    static func look(content: LianxinPublication, style: WidgetAppearance) -> TodoAppearance {
        var value = TodoAppearance(); value.widget = style
        value.defaultMarker = TodoMarker(kind: .none)
        value.widget.markerOverride = style.lianxinDisplay.translationDisplay == .translation ? TodoMarker(kind: .none) : (style.lianxinMarker ?? TodoMarker(kind: .none))
        value.widget.maximumItems = 1; value.widget.unifiedMarkers = true
        value.widget.showsFooter = false; value.widget.showsSeparators = false; value.widget.completedTextStyle = .keep
        value.widget.maximumTitleLines = style.lianxinDisplay.maximumLines.flatMap { $0 == 0 ? nil : $0 }
        value.widget.header = header(style.heading, customTitle: style.lianxinCustomTitle, member: content.idol, subtitle: content.signatureSubtitle)
        return value
    }
    static func annotations(_ content: LianxinPublication, style: LianxinDisplayStyle) -> [String] {
        (style.showsSignature ? [content.idol] : []) + (style.showsCreationLabel ? [content.contentLabel] : [])
    }
}
extension WidgetAppearance {
    var lianxinDisplay: LianxinDisplayStyle {
        if let lianxinDisplayStyle { return lianxinDisplayStyle }
        var value = LianxinDisplayStyle()
        value.maximumLines = maximumTitleLines
        value.showsSignature = lianxinShowsSignature != false
        value.centered = lianxinCentered == true
        value.showsCreationLabel = lianxinShowsCreationLabel == true
        return value
    }
}
