import Foundation

struct WallpaperColor: Codable, Equatable, Sendable {
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1
    var alpha: Double = 1
}
enum WallpaperFont: String, Codable, CaseIterable, Identifiable {
    case system, serif, monospaced
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "系统"; case .serif: return "衬线"; case .monospaced: return "等宽" }
    }
}
enum WallpaperWeight: String, Codable, CaseIterable, Identifiable {
    case light, regular, medium, semibold, bold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return "细"; case .regular: return "标准"; case .medium: return "中等"
        case .semibold: return "半粗"; case .bold: return "粗"
        }
    }
    var trait: Double {
        switch self {
        case .light: return -0.4; case .regular: return 0; case .medium: return 0.23
        case .semibold: return 0.3; case .bold: return 0.4
        }
    }
}
enum WallpaperAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing
    var id: String { rawValue }
    var title: String {
        switch self { case .leading: return "左对齐"; case .center: return "居中"; case .trailing: return "右对齐" }
    }
    var flush: Double {
        switch self { case .leading: return 0; case .center: return 0.5; case .trailing: return 1 }
    }
}
enum WallpaperCompletionStyle: String, Codable, CaseIterable, Identifiable {
    case strikeAndDim, dim, check
    var id: String { rawValue }
    var title: String {
        switch self { case .strikeAndDim: return "变淡并划线"; case .dim: return "变淡"; case .check: return "仅勾选" }
    }
}

