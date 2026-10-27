import Foundation
import CoreGraphics

enum WallpaperAspect: String, CaseIterable, Identifiable {
    case modern, classic, custom
    var id: String { rawValue }
    var title: String { self == .modern ? "现代全面屏 · 19.5:9" : self == .classic ? "经典屏幕 · 16:9" : "自定义比例" }
    var ratio: Double? { self == .modern ? 9 / 19.5 : self == .classic ? 9 / 16 : nil }
}
enum WallpaperQuality: String, CaseIterable, Identifiable {
    case medium, high, custom
    var id: String { rawValue }
    var title: String { self == .medium ? "适中 · 高 2048" : self == .high ? "4K 级 · 高 4096" : "自定义像素" }
    var height: Int? { self == .medium ? 2048 : self == .high ? 4096 : nil }
}
extension WallpaperSettings {
    func withOutputHeight(_ height: Int) throws -> WallpaperSettings {
        guard aspectRatio.isFinite, (0.25...2).contains(aspectRatio), (480...4096).contains(height) else { throw WallpaperError.invalidSize }
        var next = self
        next.canvasAspect = aspectRatio
        next.size = WallpaperSize(width: Int((Double(height) * aspectRatio).rounded()), height: height)
        return try next.validated()
    }
    /// Custom pixel output must preserve the chosen canvas ratio within one pixel.
    func withOutputSize(_ size: WallpaperSize) throws -> WallpaperSettings {
        guard size.isValid, abs(Double(size.width) - Double(size.height) * aspectRatio) <= 1 else {
            throw WallpaperError.ratioMismatch
        }
        var next = self; next.canvasAspect = aspectRatio; next.size = size
        return try next.validated()
    }
    var glyphKey: WallpaperSettings {
        var copy = self
        copy.size = WallpaperSize(); copy.canvasAspect = aspectRatio
        copy.customPosition = false; copy.panelX = 0.5; copy.panelY = 0.5
        copy.backgroundZoom = 1; copy.backgroundPanX = 0; copy.backgroundPanY = 0
        copy.glassOpacity = 0; copy.blurRadius = 0; copy.borderOpacity = 0; copy.highlight = 0
        copy.cornerRadius = 0; copy.darkGlass = false
        // Legacy completion effects are retained in JSON but never affect static wallpaper.
        copy.completionStyle = .check
        return copy
    }
}
extension WallpaperLayout {
    func positioned(using settings: WallpaperSettings) -> WallpaperLayout {
        let desiredX = CGFloat(settings.customPosition ? settings.panelX : 0.5) * canvas.width
        let desiredY = CGFloat(settings.customPosition ? settings.panelY : 0.5) * canvas.height
        let x = min(canvas.width - panel.width - 8, max(8, desiredX - panel.width / 2))
        let y = min(canvas.height - panel.height - 8, max(8, desiredY - panel.height / 2))
        let moved = CGRect(x: x, y: y, width: panel.width, height: panel.height)
        let delta = moved.minY - panel.minY
        let movedRows = rows.map { WallpaperRow(item: $0.item, block: $0.block, top: $0.top + delta,
            marker: $0.marker, markerTop: $0.markerTop + delta, markerSize: $0.markerSize) }
        return WallpaperLayout(canvas: canvas, panel: moved, markerColumn: markerColumn, textWidth: textWidth,
            rows: movedRows, hiddenCount: hiddenCount, footer: footer, footerTop: footerTop + delta,
            emptyText: emptyText, emptyTop: emptyTop + delta)
    }
}
