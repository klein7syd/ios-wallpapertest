import Foundation

/// Layout distances use a 390-unit-wide canvas; centers and image pan are normalized.
/// Preview size never changes wrapping or the exported composition.
struct WallpaperSize: Codable, Equatable, Sendable {
    var width: Int = 1170
    var height: Int = 2532
    var aspectRatio: Double { Double(width) / Double(height) }
    var logicalHeight: Double { 390 / aspectRatio }
    var label: String { "\(width) × \(height)" }
    var isValid: Bool {
        (480...4096).contains(width) && (480...4096).contains(height) && width * height <= 12_000_000
    }
}

enum WallpaperPreset: String, CaseIterable, Identifiable {
    case iPhone13Pro, mini, proMax13, pro14, proMax14, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .iPhone13Pro: return "iPhone 13 / 13 Pro"
        case .mini: return "iPhone 12 / 13 mini"
        case .proMax13: return "iPhone 12 / 13 Pro Max"
        case .pro14: return "iPhone 14 Pro / 15 / 15 Pro"
        case .proMax14: return "iPhone 14 Pro Max / 15 Plus / 15 Pro Max"
        case .custom: return "自定义像素尺寸"
        }
    }
    var size: WallpaperSize? {
        switch self {
        case .iPhone13Pro: return WallpaperSize(width: 1170, height: 2532)
        case .mini: return WallpaperSize(width: 1080, height: 2340)
        case .proMax13: return WallpaperSize(width: 1284, height: 2778)
        case .pro14: return WallpaperSize(width: 1179, height: 2556)
        case .proMax14: return WallpaperSize(width: 1290, height: 2796)
        case .custom: return nil
        }
    }
}

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

struct WallpaperSettings: Codable, Equatable, Sendable {
    var size = WallpaperSize()
    var backgroundZoom: Double = 1
    var backgroundPanX: Double = 0
    var backgroundPanY: Double = 0
    var customPosition = false
    var panelX: Double = 0.5
    var panelY: Double = 0.5
    var panelWidth: Double = 0.88
    var automaticHeight = true
    var panelHeight: Double = 0.38
    var cornerRadius: Double = 24
    var glassOpacity: Double = 0.22
    var darkGlass = true
    var blurRadius: Double = 22
    var borderOpacity: Double = 0.25
    var highlight: Double = 0.12
    var padding: Double = 20
    var includeCompleted = false
    var maximumItems: Int = 8
    var fontSize: Double = 18
    var font = WallpaperFont.system
    var weight = WallpaperWeight.medium
    var textColor = WallpaperColor()
    var lineSpacing: Double = 4
    var itemSpacing: Double = 12
    var alignment = WallpaperAlignment.leading
    var completionStyle = WallpaperCompletionStyle.strikeAndDim
    var maximumLines: Int = 4

    func validated() throws -> WallpaperSettings {
        guard size.isValid else { throw WallpaperError.invalidSize }
        var v = self
        func c(_ n: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            n.isFinite ? min(range.upperBound, max(range.lowerBound, n)) : fallback
        }
        v.backgroundZoom = c(backgroundZoom, 1...4, 1)
        v.backgroundPanX = c(backgroundPanX, -1...1, 0); v.backgroundPanY = c(backgroundPanY, -1...1, 0)
        v.panelX = c(panelX, 0...1, 0.5); v.panelY = c(panelY, 0...1, 0.5)
        v.panelWidth = c(panelWidth, 0.3...0.96, 0.88); v.panelHeight = c(panelHeight, 0.12...0.94, 0.38)
        v.cornerRadius = c(cornerRadius, 0...80, 24); v.glassOpacity = c(glassOpacity, 0...0.85, 0.22)
        v.blurRadius = c(blurRadius, 0...45, 22); v.borderOpacity = c(borderOpacity, 0...1, 0.25)
        v.highlight = c(highlight, 0...0.6, 0.12); v.padding = c(padding, 8...48, 20)
        v.maximumItems = min(20, max(1, maximumItems)); v.maximumLines = min(8, max(1, maximumLines))
        v.fontSize = c(fontSize, 10...38, 18); v.lineSpacing = c(lineSpacing, 0...20, 4)
        v.itemSpacing = c(itemSpacing, 0...36, 12)
        v.textColor.red = c(textColor.red, 0...1, 1); v.textColor.green = c(textColor.green, 0...1, 1)
        v.textColor.blue = c(textColor.blue, 0...1, 1); v.textColor.alpha = c(textColor.alpha, 0...1, 1)
        return v
    }

    func filtered(_ items: [TodoItem]) -> [TodoItem] { items.filter { includeCompleted || !$0.isCompleted } }
}

struct WallpaperDraft: Codable, Sendable {
    var schemaVersion = 1
    var settings = WallpaperSettings()
    var photoFileName: String?
}
enum WallpaperError: LocalizedError {
    case invalidSize, unreadablePhoto, photoTooLarge, renderingFailed
    case encodingFailed, dimensionsMismatch, photoPermission, unsupportedDraft, invalidDraft
    var errorDescription: String? {
        switch self {
        case .invalidSize: return "宽高各需为 480–4096 像素，总像素不能超过 1200 万。"
        case .unreadablePhoto: return "无法读取这张照片。请重新选择一张静态图片。"
        case .photoTooLarge: return "照片文件超过 80 MB，请选择较小的静态图片。"
        case .renderingFailed: return "图片渲染失败。请稍后重试或降低输出尺寸。"
        case .encodingFailed: return "PNG 写入失败，请检查设备剩余空间。"
        case .dimensionsMismatch: return "导出图片的像素尺寸未通过校验，未保存到相册。"
        case .photoPermission: return "没有相册添加权限。可在系统设置中允许添加照片，或使用系统分享。"
        case .unsupportedDraft: return "壁纸草稿来自较新版本，已保留原文件，当前未覆盖它。"
        case .invalidDraft: return "壁纸草稿无法读取，原文件已保留。可确认恢复默认以重新开始；待办不受影响。"
        }
    }
}
