import Foundation

/// Transient presentation state only. Nothing here changes persisted task or draft data.
enum AppPage: String, CaseIterable, Identifiable {
    case todos, wallpaper, widget, about
    var id: String { rawValue }
    var title: String {
        switch self { case .todos: return "待办"; case .wallpaper: return "壁纸"
        case .widget: return "小组件"; case .about: return "关于" }
    }
    var icon: String {
        switch self { case .todos: return "checklist"; case .wallpaper: return "photo"
        case .widget: return "square.grid.2x2"; case .about: return "info.circle" }
    }
}
enum WallpaperTool: String, CaseIterable, Identifiable {
    case background, panel, text, marker, output
    var id: String { rawValue }
    var title: String {
        switch self { case .background: return "背景"; case .panel: return "面板"; case .text: return "文字"
        case .marker: return "标记"; case .output: return "导出" }
    }
    var icon: String {
        switch self { case .background: return "photo"; case .panel: return "rectangle.center.inset.filled"
        case .text: return "textformat"; case .marker: return "face.smiling"; case .output: return "square.and.arrow.up" }
    }
}
struct AppNavigationState: Equatable {
    private(set) var page = AppPage.todos
    private(set) var wallpaperTool: WallpaperTool?
    private(set) var inspectorExpanded = false
    var isEditing: Bool { page == .wallpaper && wallpaperTool != nil }
    mutating func selectPage(_ next: AppPage) {
        page = next
        exitEditing()
    }
    mutating func selectTool(_ next: WallpaperTool) {
        page = .wallpaper
        wallpaperTool = next
        inspectorExpanded = true
    }
    mutating func toggleInspector() {
        guard isEditing else { return }
        inspectorExpanded.toggle()
    }
    mutating func exitEditing() { wallpaperTool = nil; inspectorExpanded = false }
}

/// Capabilities drive conditional controls without clearing dormant saved values.
struct MarkerControlVisibility: Equatable {
    let kind: MarkerKind
    var visible: Bool { kind != .none }
    var emoji: Bool { kind == .emoji }
    var shape: Bool { visible && !emoji }
    var stroke: Bool { [.hollow, .thin, .bordered, .square].contains(kind) }
    var fill: Bool { [.filled, .bordered].contains(kind) }
    func completionColor(_ completion: MarkerCompletion) -> Bool { shape && completion == .checkShapes }
    func completionEmoji(_ completion: MarkerCompletion) -> Bool { visible && completion == .replace }
}

enum EditorSizing {
    /// Leave a real canvas above the Dock, including when the keyboard reduces height.
    static func panelHeight(available: Double, expanded: Bool) -> Double {
        guard available.isFinite, available > 0 else { return 0 }
        if !expanded { return min(64, available) }
        return min(310, max(160, available * 0.46), max(64, available - 110))
    }
    static func widgetPreviewHeight(available: Double) -> Double {
        guard available.isFinite, available > 0 else { return 0 }
        if available < 320 { return min(100, max(52, available * 0.30)) }
        return min(310, available * 0.43, available - 160)
    }
}

enum WidgetPreviewFamily: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { self == .small ? "小号" : self == .medium ? "中号" : "大号" }
    // Reference points, not a promise of identical system dimensions on every device.
    var width: Double { self == .small ? 170 : 364 }
    var height: Double { self == .large ? 382 : 170 }
    func scale(availableWidth: Double, availableHeight: Double) -> Double {
        max(0, min(1, max(0, availableWidth) / width, max(0, availableHeight) / height))
    }
    func rowLimit(appearance: WidgetAppearance, accessibility: Bool) -> Int {
        if accessibility { return self == .large ? 3 : 1 }
        let base = self == .large ? 6 : self == .medium ? 3 : 2
        if appearance.fontSize > 17 || appearance.spacing > 8 { return max(1, base - 1) }
        return appearance.compact && self == .large ? 8 : base
    }
}
