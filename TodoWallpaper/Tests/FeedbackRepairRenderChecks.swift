import Foundation
import CoreGraphics
import CoreImage

enum FeedbackRepairRenderChecks {
    static func run(out: URL) throws {
        func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws { let result = try value(); try D34Checks.require(result, message) }
        let ci = CIContext(options: [.cacheIntermediates: false])
        var settings = WallpaperSettings(); settings.canvasAspect = 1; settings = try settings.withOutputHeight(780)
        settings.includeCompleted = true; settings.blurRadius = 0; settings.glassOpacity = 0; settings.highlight = 0; settings.borderOpacity = 0
        settings.textColor = WallpaperColor(red: 0, green: 0, blue: 1)
        var look = TodoAppearance(); look.markerStyle.followsTextColor = false
        look.markerStyle.stroke = WallpaperColor(red: 1, green: 0, blue: 0)
        var item = TodoItem(id: UUID(), title: "Task", isCompleted: false, createdAt: .now, updatedAt: .now)
        let baseline = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: look)
        item.isCompleted = true
        for policy in WallpaperCompletionStyle.allCases {
            settings.completionStyle = policy
            let image = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: look)
            try require(try D34Checks.digest(image.image) == D34Checks.digest(baseline.image), "Wallpaper text ignores legacy completion policy \(policy.id)")
        }
        func inkGap(_ image: CGImage) throws -> Int {
            let bytes = [UInt8](try WallpaperRenderChecks.pixels(image))
            var red: [Int] = [], blue: [Int] = []
            for y in 0..<image.height { for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if Int(bytes[i]) - max(Int(bytes[i+1]), Int(bytes[i+2])) > 80 { red.append(x) }
                if Int(bytes[i+2]) - max(Int(bytes[i+1]), Int(bytes[i])) > 80 { blue.append(x) }
            } }
            guard let right = red.max(), let left = blue.min() else { throw WallpaperError.renderingFailed }
            return left - right
        }
        for alignment in WallpaperAlignment.allCases {
            settings.alignment = alignment
            look.markerStyle.gap = 0
            let compact = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: look)
            look.markerStyle.gap = 28
            let spaced = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: look)
            let delta = try inkGap(spaced.image) - inkGap(compact.image)
            try require((53...59).contains(delta), "Actual PNG marker/text gap grows 28 logical units at 2x in \(alignment.id), got \(delta)")
            try WallpaperRenderer.writePNG(spaced.image, to: out.appendingPathComponent("wallpaper-gap-\(alignment.id).png"), expected: settings.size)
        }
        item.marker = TodoMarker(kind: .emoji, emoji: "❤️")
        look.widget.markerOverride = TodoMarker(kind: .emoji, emoji: "🌙")
        look.widget.markerStyle.emojiSize = 44
        let widgetBefore = look.widget
        settings.usesTaskMarkers = false
        var hashes = Set<String>()
        for kind in [MarkerKind.hollow, .filled, .square, .emoji, .none] {
            look.defaultMarker = TodoMarker(kind: kind, emoji: "⭐")
            let rendered = try WallpaperRenderer.render(settings: settings, items: [item], photoURL: nil, ciContext: ci, appearance: look)
            try require(rendered.layout.rows.first?.marker.kind == kind && look.widget == widgetBefore && item.marker?.emoji == "❤️",
                "Uniform wallpaper changes without changing Widget settings or task Emoji")
            hashes.insert(try D34Checks.digest(rendered.image))
            try WallpaperRenderer.writePNG(rendered.image, to: out.appendingPathComponent("wallpaper-uniform-\(kind.id).png"), expected: settings.size)
        }
        try require(hashes.count == 5, "Five wallpaper marker choices produce five actual PNGs")
        settings.usesTaskMarkers = true
        let inherited = try WallpaperRenderer.layout(settings: settings, items: [item], appearance: look)
        try require(inherited.rows[0].marker == item.marker, "Returning to task markers restores preserved per-item Emoji")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        json.removeValue(forKey: "usesTaskMarkers")
        let legacy = try JSONDecoder().decode(WallpaperSettings.self, from: JSONSerialization.data(withJSONObject: json))
        try require(legacy.inheritsTaskMarkers && legacy.size == settings.size, "Old draft missing marker source retains composition and individual Emoji")
        print("PASS: static wallpaper completion text, three alignment gap pixel deltas, five real marker PNGs, independent Widget ownership and legacy draft marker source.")
    }
}
