import Foundation
import CoreGraphics
import CoreImage

enum WidgetFeedbackRenderChecks {
    static func run(out: URL) throws {
        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws { try D34Checks.require(condition(), message) }
        var outputs = 0
        for emoji in ["❤️", "👍🏽", "🧑🏽‍💻"] {
            for size in [8, 10, 12, 16, 19, 20, 24, 32, 48] {
                for scale in [1, 3] {
                    let pixels = (size + 8) * scale
                    let context = try D34Checks.blank(pixels, pixels)
                    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
                    MarkerDrawing.draw(marker: TodoMarker(kind: .emoji, emoji: emoji), completed: false,
                        style: MarkerStyle(), textColor: WallpaperColor(),
                        rect: CGRect(x: 4, y: 4, width: CGFloat(size), height: CGFloat(size)), context: context)
                    guard let image = context.makeImage() else { throw WallpaperError.renderingFailed }
                    let bytes = [UInt8](try WallpaperRenderChecks.pixels(image))
                    var xs: [Int] = [], ys: [Int] = []
                    for y in 0..<pixels { for x in 0..<pixels {
                        let i = (y * pixels + x) * 4
                        if Int(bytes[i]) - min(Int(bytes[i+1]), Int(bytes[i+2])) > 35 || max(bytes[i], max(bytes[i+1],bytes[i+2])) - min(bytes[i], min(bytes[i+1],bytes[i+2])) > 45 {
                            xs.append(x); ys.append(y)
                        }
                    } }
                    guard let left = xs.min(), let right = xs.max(), let bottom = ys.min(), let top = ys.max() else { throw WallpaperError.renderingFailed }
                    try require(left >= 4 * scale - 1 && right <= (size + 4) * scale && bottom >= 4 * scale - 1 && top <= (size + 4) * scale,
                        "Small Emoji actual ink stays within allocated cell")
                    try require(right - left >= Int(Double(size * scale) * 0.5), "Emoji ink must not shrink with device pixel scale")
                    let tag = emoji == "❤️" ? "heart" : emoji == "👍🏽" ? "skin" : "composed"
                    try WallpaperRenderer.writePNG(image, to: out.appendingPathComponent("fit-\(tag)-\(size)-\(scale)x.png"), expected: WallpaperSize(width: pixels, height: pixels))
                    outputs += 1
                }
            }
        }
        var settings = WallpaperSettings(); settings.includeCompleted = true
        settings.canvasAspect = 1; settings = try settings.withOutputHeight(600)
        var appearance = TodoAppearance(); appearance.defaultMarker = TodoMarker(kind: .emoji, emoji: "❤️")
        let item = TodoItem(id: UUID(), title: "静态壁纸标记", isCompleted: true, createdAt: .now, updatedAt: .now)
        let ci = CIContext(options: [.cacheIntermediates: false])
        appearance.markerStyle.completion = .replace
        let first = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: appearance)
        appearance.markerStyle.completion = .thinCircle
        let second = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: appearance)
        let firstHash = try D34Checks.digest(first.image), secondHash = try D34Checks.digest(second.image)
        try require(firstHash == secondHash, "Wallpaper ignores interactive marker completion policies")
        print("PASS: \(outputs) actual small-heart/skin/composed Emoji raster fits at 1x/3x, plus static wallpaper decoration independent of completion interaction.")
    }
}
