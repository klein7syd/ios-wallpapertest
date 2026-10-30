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
        let actualDigest = try D34Checks.digest(image.image), referenceDigest = try D34Checks.digest(reference.image)
        try D34Checks.require(actualDigest != referenceDigest, "Custom image contributes actual PNG pixels")
        try D34Checks.require(WallpaperRenderer.effectiveTextColor(settings.glyphKey) == WallpaperRenderer.effectiveTextColor(settings), "Live glyph cache preserves opaque-panel contrast category")
        try D34Checks.require(WallpaperRenderer.effectiveTextColor(settings) != settings.textColor, "Opaque dark wallpaper panel protects black text")
        var nudgeCases = 0
        for outputHeight in [2048, 4096] {
            for width in [0.3, 0.88, 0.96] {
                var base = try WallpaperSettings().withOutputHeight(outputHeight)
                base.panelWidth = width; base.customPosition = true
                let layout = try WallpaperRenderer.layout(settings: base, items: [item], appearance: look)
                for x in [0.0, 0.5, 1] { for y in [0.0, 0.5, 1] {
                    var current = base; current.panelX = x; current.panelY = y
                    let before = layout.positioned(using: current).panel
                    for (dx, dy) in [(-1.0, 0.0), (1.0, 0.0), (0.0, -1.0), (0.0, 1.0)] {
                        let next = current.nudged(in: layout, dx: dx, dy: dy)
                        let after = layout.positioned(using: next).panel
                        let pixelX = Double(after.midX - before.midX) * Double(base.size.width) / Double(layout.canvas.width)
                        let pixelY = Double(after.midY - before.midY) * Double(base.size.height) / Double(layout.canvas.height)
                        try D34Checks.require(abs(pixelX) <= 1.00001 && abs(pixelY) <= 1.00001, "A nudge at a clamped edge cannot visually jump more than one output pixel")
                        let fitsX = before.width + 16 + 2 * layout.canvas.width / Double(base.size.width) < layout.canvas.width
                        let fitsY = before.height + 16 + 2 * layout.canvas.height / Double(base.size.height) < layout.canvas.height
                        if x == 0.5 && y == 0.5 && fitsX && fitsY {
                            try D34Checks.require(abs(pixelX - dx) < 0.00001 && abs(pixelY - dy) < 0.00001, "Unclamped nudges preserve the existing exact one-output-pixel step")
                        }
                        nudgeCases += 1
                    }
                } }
            }
        }
        print("PASS: \(nudgeCases) production nudge edge/center cases at 2048/4096 output heights; no geometry jump and unchanged one-pixel step. iPhone visual reproduction pending.")
        print("PASS: actual bounded custom image decode and 1890x4096 native image-marker PNG; opaque-panel text contrast.")
    }
}
