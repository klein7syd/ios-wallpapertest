import Foundation
import CoreGraphics
import CoreImage

enum PhotoRepairRenderChecks {
    static func run(out: URL, fixture: URL) throws {
        let shared = out.appendingPathComponent("temporary-marker-assets")
        defer { try? FileManager.default.removeItem(at: shared) }
        try FileManager.default.createDirectory(at: MarkerImageReference.directory(in: shared), withIntermediateDirectories: true)
        let name = "marker-image-\(UUID().uuidString).png"
        try FileManager.default.copyItem(at: fixture, to: MarkerImageReference.url(for: name, in: shared))
        guard let source = MarkerImageReference.image(named: name, sharedDirectory: shared) else { throw WallpaperError.unreadablePhoto }
        try D34Checks.require(max(source.width, source.height) <= 512, "Image marker decode has a fixed 512px bound")
        let marker = TodoMarker(kind: .image, imageName: name)
        let item = TodoItem(id: UUID(), title: "图片标记与真实高清文字", marker: marker, isCompleted: false, createdAt: .now, updatedAt: .now)
        var settings = WallpaperSettings(); settings.glassOpacity = 0.88; settings.darkGlass = true
        settings.textColor = WallpaperColor(red: 0, green: 0, blue: 0)
        var look = TodoAppearance(); look.markerStyle.size = 48
        let context = CIContext(options: [.cacheIntermediates: false])
        let image = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: context, appearance: look, assetDirectory: shared)
        try D34Checks.require(image.image.width == 1890 && image.image.height == 4096 && image.layout.rows.first?.marker.imageName == name, "Real 4K renderer lays out the custom image marker")
        try WallpaperRenderer.writePNG(image.image, to: out.appendingPathComponent("custom-image-marker-4k.png"), expected: settings.size)
        let reference = try WallpaperRenderer.render(settings: settings, items: [TodoItem(id: item.id, title: item.title, marker: TodoMarker(kind: .none), isCompleted: false, createdAt: item.createdAt, updatedAt: item.updatedAt)], photoURL: nil, ciContext: context, appearance: look)
        try D34Checks.require(try D34Checks.digest(image.image) != D34Checks.digest(reference.image), "Custom image contributes actual PNG pixels")
        try D34Checks.require(WallpaperRenderer.effectiveTextColor(settings.glyphKey) == WallpaperRenderer.effectiveTextColor(settings), "Live glyph cache preserves opaque-panel contrast category")
        try D34Checks.require(WallpaperRenderer.effectiveTextColor(settings) != settings.textColor, "Opaque dark wallpaper panel protects black text")
        print("PASS: actual bounded custom image decode and 1890x4096 native image-marker PNG; opaque-panel text contrast.")
    }
}
