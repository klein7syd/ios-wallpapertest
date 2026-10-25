import Foundation
import CoreGraphics
import CoreText
import CoreImage
import CryptoKit

/// Exercises production models, persistence and native pixel output. No device pass is inferred.
enum D34Checks {
    static func require(_ ok: @autoclosure () -> Bool, _ message: String) throws {
        if !ok() { throw NSError(domain: "D34Checks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func digest(_ image: CGImage) throws -> String {
        SHA256.hash(data: try WallpaperRenderChecks.pixels(image)).map { String(format: "%02x", $0) }.joined()
    }
    static func ink(_ image: CGImage) throws -> Int {
        let bytes = [UInt8](try WallpaperRenderChecks.pixels(image)); var count = 0
        for i in stride(from: 0, to: bytes.count - 3, by: 4) {
            if bytes[i] < 220 && bytes[i + 1] < 220 && bytes[i + 2] < 220 { count += 1 }
        }
        return count
    }
    static func colored(_ image: CGImage) throws -> Int {
        let bytes = [UInt8](try WallpaperRenderChecks.pixels(image)); var count = 0
        for i in stride(from: 0, to: bytes.count - 3, by: 4) {
            let a = Int(bytes[i]), b = Int(bytes[i + 1]), c = Int(bytes[i + 2])
            if max(a, max(b, c)) - min(a, min(b, c)) > 40 && bytes[i + 3] > 0 { count += 1 }
        }
        return count
    }
    static func blank(_ width: Int, _ height: Int) throws -> CGContext {
        let context = try WallpaperRenderer.bitmap(width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context
    }
    static func fontSample(_ string: String, weight: WallpaperWeight, family: WallpaperFont = .system) throws -> CGImage {
        var settings = WallpaperSettings(); settings.weight = weight; settings.font = family
        settings.fontSize = 40; settings.textColor = WallpaperColor(red: 0, green: 0, blue: 0)
        let block = WallpaperRenderer.text(string, width: 700, settings: settings, maxLines: 1)
        let context = try blank(760, 100)
        context.textMatrix = .identity; context.textPosition = CGPoint(x: 20, y: 30)
        for line in block.lines { CTLineDraw(line, context) }
        guard let image = context.makeImage() else { throw WallpaperError.renderingFailed }; return image
    }
    static func run(out: URL, fixture: URL) async throws {
        var fontHashes: [String: String] = [:], chineseHashes: [String: String] = [:], fontInk: [String: Int] = [:]
        for weight in WallpaperWeight.allCases {
            let image = try fontSample("字重 Weight Aa 123", weight: weight)
            fontHashes[weight.rawValue] = try digest(image); fontInk[weight.rawValue] = try ink(image)
            chineseHashes[weight.rawValue] = try digest(fontSample("字重测试", weight: weight))
            try WallpaperRenderer.writePNG(image, to: out.appendingPathComponent("weight-\(weight.rawValue).png"), expected: WallpaperSize(width: 760, height: 100))
        }
        try require(Set(fontHashes.values).count == 5, "All five system font weights must change actual pixels")
        try require(Set(chineseHashes.values).count >= 4, "Chinese fallback must change weight; bold may reuse semibold face")
        try require((fontInk["bold"] ?? 0) > (fontInk["light"] ?? Int.max), "Bold genuinely draws more ink than light")
        let emojis = ["❤️", "🌸", "🎵", "📚", "👍🏽", "🧑🏽‍💻", "👨‍👩‍👧‍👦", "🇨🇳", "1️⃣"]
        for bad in ["", "abc", "1", "🏽", "⭐🌙", String(repeating: "❤️", count: 100), " 🌸 "] {
            try require(!EmojiInput.isValid(bad), "Reject non-marker input")
        }
        var emojiPixels: [String: Int] = [:]
        var appearance = TodoAppearance(); appearance.defaultMarker = TodoMarker(kind: .emoji, emoji: "🌸")
        appearance.markerStyle.emojiSize = 26
        var items: [TodoItem] = []
        for (index, emoji) in emojis.enumerated() {
            try require(EmojiInput.isValid(emoji), "Accept a complete Emoji grapheme")
            let context = try blank(230, 230)
            var style = MarkerStyle(); style.emojiSize = 160
            // Direct glyph raster size corresponds to large 4K output, not an enlarged thumbnail.
            MarkerDrawing.draw(marker: TodoMarker(kind: .emoji, emoji: emoji), completed: false, style: style,
                textColor: WallpaperColor(red: 0, green: 0, blue: 0), rect: CGRect(x: 35, y: 35, width: 160, height: 160), context: context)
            guard let image = context.makeImage() else { throw WallpaperError.renderingFailed }
            let count = try colored(image); emojiPixels[emoji] = count
            try require(count > 100, "Emoji must contain actual colored pixels, not tofu or monochrome")
            try WallpaperRenderer.writePNG(image, to: out.appendingPathComponent("emoji-\(index).png"), expected: WallpaperSize(width: 230, height: 230))
            items.append(TodoItem(id: UUID(), title: index == 6 ? "组合 Emoji 与长标题自动换行：家人的时间也值得好好安排" : "真实标记渲染测试 \(index + 1)",
                marker: TodoMarker(kind: .emoji, emoji: emoji), isCompleted: false, createdAt: .now, updatedAt: .now))
        }
        var geometryInk: [String: Int] = [:]
        for kind in MarkerKind.allCases where kind != .emoji {
            let context = try blank(100, 100)
            var style = MarkerStyle(); style.size = 50; style.lineWidth = 3
            MarkerDrawing.draw(marker: TodoMarker(kind: kind), completed: false, style: style,
                textColor: WallpaperColor(red: 0, green: 0, blue: 0), rect: CGRect(x: 25, y: 25, width: 50, height: 50), context: context)
            guard let image = context.makeImage() else { throw WallpaperError.renderingFailed }
            geometryInk[kind.rawValue] = try ink(image)
            try WallpaperRenderer.writePNG(image, to: out.appendingPathComponent("marker-\(kind.rawValue).png"), expected: WallpaperSize(width: 100, height: 100))
        }
        try require(geometryInk["none"] == 0, "No-marker draws nothing")
        try require((geometryInk["filled"] ?? 0) > (geometryInk["hollow"] ?? Int.max), "Filled and hollow circles differ")
        try require((geometryInk["thin"] ?? Int.max) < (geometryInk["hollow"] ?? 0), "Thin outline differs")
        let context = CIContext(options: [.cacheIntermediates: false])
        var modern = WallpaperSettings(); modern.maximumItems = 12
        let full = try WallpaperRenderer.render(settings: modern, items: items, photoURL: fixture, ciContext: context, appearance: appearance)
        try require(full.image.width == 1890 && full.image.height == 4096, "Modern 4K physical output")
        try WallpaperRenderer.writePNG(full.image, to: out.appendingPathComponent("emoji-modern-4k.png"), expected: modern.size)
        let medium = try modern.withOutputHeight(2048)
        let mediumLayout = try WallpaperRenderer.layout(settings: medium, items: items, appearance: appearance)
        try require(full.layout.panel == mediumLayout.panel && full.layout.rows.map(\.markerTop) == mediumLayout.rows.map(\.markerTop), "Resolution-only switch preserves layout and Emoji coordinates")
        try require(modern.glyphKey == medium.glyphKey, "Resolution switch does not require new live glyph layout")
        let canvas = full.layout.canvas
        let photo = CGSize(width: 3000, height: 1600)
        let crop = WallpaperRenderer.backgroundRect(source: photo, canvas: canvas, settings: modern)
        let crop2 = WallpaperRenderer.backgroundRect(source: photo, canvas: mediumLayout.canvas, settings: medium)
        try require(crop == crop2, "Resolution switch preserves photo crop")
        var previousX: CGFloat?
        for index in 0...100 {
            var value = modern; value.backgroundZoom = 2; value.backgroundPanX = Double(index) / 10000
            let rect = WallpaperRenderer.backgroundRect(source: photo, canvas: canvas, settings: value)
            if let previousX { try require(rect.minX > previousX && rect.minX - previousX < 0.2, "Continuous subpixel movement, no buckets") }
            previousX = rect.minX
        }
        for position in [0.2, 0.5, 0.8] {
            var value = modern; value.panelX = position; value.panelY = position; value.customPosition = true
            let positioned = full.layout.positioned(using: value)
            let direct = try WallpaperRenderer.layout(settings: value, items: items, appearance: appearance)
            try require(positioned.panel == direct.panel && zip(positioned.rows, direct.rows).allSatisfy { pair in abs(pair.0.top - pair.1.top) < 0.000001 }, "Live direct transforms match export layout")
        }
        var classic = modern; classic.canvasAspect = 9.0 / 16; classic = try classic.withOutputHeight(4096)
        let classicImage = try WallpaperRenderer.render(settings: classic, items: items, photoURL: fixture, ciContext: context, appearance: appearance)
        try require(classicImage.image.width == 2304 && classicImage.image.height == 4096, "Classic 4K pixels")
        try WallpaperRenderer.writePNG(classicImage.image, to: out.appendingPathComponent("emoji-classic-4k.png"), expected: classic.size)
        var square = medium; square.canvasAspect = 1; square = try square.withOutputHeight(2048)
        let squareImage = try WallpaperRenderer.render(settings: square, items: items, photoURL: fixture, ciContext: context, appearance: appearance)
        try require(squareImage.image.width == 2048 && squareImage.image.height == 2048, "Custom aspect and pixels")
        do { _ = try modern.withOutputSize(WallpaperSize(width: 2000, height: 2000)); throw WallpaperError.renderingFailed }
        catch WallpaperError.ratioMismatch { }
        try await compatibility(out: out, fixture: fixture, appearance: appearance, items: items)
        let report: [String: Any] = ["result": "passed", "system_weight_pixel_hashes": fontHashes,
            "chinese_weight_pixel_hashes": chineseHashes, "weight_ink_pixels": fontInk, "colored_emoji_pixels": emojiPixels,
            "circle_ink_pixels": geometryInk, "modern_4k": [1890,4096], "classic_4k": [2304,4096],
            "resolution_preserves_layout_and_crop": true, "continuous_transform_matches_export": true,
            "legacy_todo_backup_and_draft": "passed", "widget_style_shared_roundtrip_and_precedence": "passed",
            "iphone_gestures_widget_and_signing": "pending_user_device_test"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("d34-checks.json"))
        print("PASS: D3+D4 actual weight raster differences, colored composed/skin-tone Emoji, marker geometry, modern/classic 4K, continuous transforms, legacy tasks/draft/photos/backup, shared Widget style and marker inheritance.")
    }
    private static func compatibility(out: URL, fixture: URL, appearance: TodoAppearance, items: [TodoItem]) async throws {
        let directory = out.appendingPathComponent("temporary-d34-checks"); defer { try? FileManager.default.removeItem(at: directory) }
        let repository = TodoRepository(directoryURL: directory)
        let original = try repository.add(title: "0.3.0 旧任务")
        let id = original.items[0].id
        let raw = try Data(contentsOf: repository.fileURL)
        let object = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
        let rows = object?["items"] as? [[String: Any]]
        try require(rows?.first?["marker"] == nil, "Legacy JSON has no new field")
        let loaded = try TodoRepository(directoryURL: directory).load()
        try require(loaded.items[0].marker == nil && appearance.marker(for: loaded.items[0]) == appearance.defaultMarker, "Missing marker decodes and inherits")
        _ = try repository.edit(id: id, title: "听音乐", marker: TodoMarker(kind: .emoji, emoji: "🎵"))
        _ = try repository.setCompleted(id: id, completed: true)
        let afterIntent = try TodoRepository(directoryURL: directory).load()
        try require(afterIntent.items[0].id == id && afterIntent.items[0].marker?.emoji == "🎵" && afterIntent.items[0].isCompleted, "Intent repository operation preserves marker and ID")
        _ = try repository.edit(id: id, title: "恢复全局", marker: nil)
        try Data("broken".utf8).write(to: repository.fileURL)
        try repository.recoverFromBackup()
        let recovered = try repository.load()
        try require(recovered.items[0].marker?.emoji == "🎵" && recovered.items[0].id == id, "Backup recovers Emoji")
        let styles = AppearanceRepository(directory: directory)
        var look = appearance; look.widget.markerOverride = TodoMarker(kind: .emoji, emoji: "🌙")
        look.widget.theme = .dark; look.widget.font = .serif; look.widget.weight = .bold
        try styles.save(look)
        let reloaded = try AppearanceRepository(directory: directory).load()
        try require(reloaded == look, "Shared style round trip")
        let task = loaded.items[0]
        try require(look.marker(for: task).emoji == "🌸" && look.marker(for: task, widgetContext: true).emoji == "🌙", "Context default precedence")
        try require(look.marker(for: recovered.items[0], widgetContext: true).emoji == "🎵", "Item override survives Widget defaults")
        for limit in [1, 2, 3, 6] { try require(look.widget.rows(items, capacity: limit).count <= limit, "Widget size capacity respected") }
        let defaultLegacy = TodoAppearance().marker(for: task)
        try require(defaultLegacy.kind == .hollow, "Unconfigured old app keeps circle")
        let draftDirectory = directory.appendingPathComponent("draft")
        let draftStore = WallpaperDraftStore(directory: draftDirectory)
        let photo = try await draftStore.importPhoto(Data(contentsOf: fixture))
        var legacy = WallpaperSettings(); legacy.size = WallpaperSize(width: 1170, height: 2532)
        let encoded = try JSONEncoder().encode(WallpaperDraft(settings: legacy, photoFileName: photo.lastPathComponent))
        var draftObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]
        var oldSettings = draftObject["settings"] as? [String: Any] ?? [:]; oldSettings.removeValue(forKey: "canvasAspect")
        draftObject["settings"] = oldSettings
        let oldData = try JSONSerialization.data(withJSONObject: draftObject)
        let draftURL = draftDirectory.appendingPathComponent("draft-v1.json"); try oldData.write(to: draftURL)
        let readLegacy = try await draftStore.load()
        try require(readLegacy.draft.settings.canvasAspect == nil && readLegacy.draft.settings.aspectRatio == 1170.0 / 2532,
                    "0.3.0 draft ratio/pixels are not silently replaced with new defaults")
        try require(readLegacy.photoURL == photo, "Original photo reference retained")
        let originalPhoto = try Data(contentsOf: photo)
        var updated = readLegacy.draft; updated.settings = try updated.settings.withOutputHeight(4096)
        try await draftStore.save(updated)
        let archived = try Data(contentsOf: draftDirectory.appendingPathComponent("draft-before-d34.json"))
        let retainedPhoto = try Data(contentsOf: photo)
        try require(archived == oldData && retainedPhoto == originalPhoto, "Migration archives exact old draft and leaves original photo bytes")
    }
}
