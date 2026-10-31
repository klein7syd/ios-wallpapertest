// Target Membership：App + Widget；导航选择仅由App私有defaults持久化。
import Foundation

enum ContentMode: String, CaseIterable {
    case todo, lianxin
    static let key = "editor.contentMode"
    static func read(_ defaults: UserDefaults = .standard) -> Self { Self(rawValue: defaults.string(forKey: key) ?? "") ?? .todo }
    func save(_ defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.key) }
}
extension TodoAppearance {
    func style(in mode: ContentMode) -> WidgetAppearance { mode == .todo ? widget : (lianxin ?? widget) }
    mutating func setStyle(_ style: WidgetAppearance, in mode: ContentMode) {
        if mode == .todo { widget = style } else { lianxin = style }
    }
    mutating func initializeLianxin(photoName: String? = nil) {
        guard lianxin == nil else { return }
        lianxin = widget
        if let photoName { lianxin?.backgroundPhotoName = photoName; lianxin?.backdrop = .photo; lianxin?.photoRotation?.enabled = false }
    }
}
