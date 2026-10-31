import Foundation
import CoreGraphics
import CoreImage
import CoreText
import ImageIO

/// Synthetic fixtures only. The shipped editor always receives TodoStore.items.
@main
enum WallpaperRenderChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "WallpaperRenderChecks", code: 1,
                                       userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func readImage(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw WallpaperError.unreadablePhoto }
        return image
    }
    static func pixels(_ image: CGImage) throws -> Data {
        let context = try WallpaperRenderer.bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { throw WallpaperError.renderingFailed }
        var packed = Data()
        for row in 0..<context.height {
            packed.append(data.advanced(by: row * context.bytesPerRow).assumingMemoryBound(to: UInt8.self), count: context.width * 4)
        }
        return packed
    }
    static func main() async throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixture = out.appendingPathComponent("fixture-input.png")
        let context = CIContext(options: [.cacheIntermediates: false])
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let titles = [
            "今天也照顾好自己",
            "整理周末计划，给重要的事情留一点时间",
            "阅读 20 分钟 · Read a little 📖",
            "把想法写下来，然后一步一步开始",
            "和朋友约好下次见面的时间",
            String(repeating: "长标题测试：认真生活，也记得休息 🧩 ", count: 8)
        ]
        let items = titles.enumerated().map {
            TodoItem(id: UUID(), title: $0.element, isCompleted: $0.offset == 2, createdAt: now, updatedAt: now)
        }
        var settings = WallpaperSettings()
        settings.size = WallpaperSize(width: 1170, height: 2532); settings.canvasAspect = nil
        let defaultLayout = try WallpaperRenderer.layout(settings: settings, items: items)
        try require(abs(defaultLayout.panel.midX - 195) < 0.01, "Default horizontal center")
        try require(abs(defaultLayout.panel.midY - defaultLayout.canvas.height / 2) < 0.01, "Default vertical center")
        try require(defaultLayout.rows.allSatisfy { !$0.item.isCompleted }, "Real pending filter")
        try require(defaultLayout.rows.map(\.item.id) == settings.filtered(items).prefix(defaultLayout.rows.count).map(\.id), "Stable task identity and manual order")
        let full = try WallpaperRenderer.render(settings: settings, items: items, photoURL: fixture, ciContext: context)
        let preview = try WallpaperRenderer.render(settings: settings, items: items, photoURL: fixture, previewWidth: 390, ciContext: context)
        try require(full.image.width == 1170 && full.image.height == 2532, "Exact iPhone 13 Pro physical pixels")
        try require(full.layout.panel == preview.layout.panel &&
            full.layout.rows.map(\.top) == preview.layout.rows.map(\.top) &&
            full.layout.rows.map { $0.block.lines.count } == preview.layout.rows.map { $0.block.lines.count },
            "Preview/export use identical logical frame, wrapping and baselines")
        try WallpaperRenderer.writePNG(full.image, to: out.appendingPathComponent("iphone13pro-export.png"), expected: settings.size)
        try WallpaperRenderer.writePNG(preview.image, to: out.appendingPathComponent("iphone13pro-preview.png"),
                                        expected: WallpaperSize(width: 390, height: 844))
        // Zero material, border, highlight and text alpha must not tint the original pixels.
        var clear = settings
        clear.glassOpacity = 0; clear.blurRadius = 0; clear.borderOpacity = 0; clear.highlight = 0
        clear.textColor.alpha = 0
        let clearImage = try WallpaperRenderer.render(settings: clear, items: items, photoURL: fixture, ciContext: context).image
        let originalPixels = try pixels(readImage(fixture))
        let clearPixels = try pixels(clearImage)
        try require(originalPixels.count == clearPixels.count, "Comparable RGBA buffers")
        var maximumDifference = 0
        for (a, b) in zip(originalPixels, clearPixels) { maximumDifference = max(maximumDifference, abs(Int(a) - Int(b))) }
        try require(maximumDifference <= 1, "No tint / vertical flip / unintended crop when material is zero")
        try WallpaperRenderer.writePNG(clearImage, to: out.appendingPathComponent("zero-material.png"), expected: settings.size)

        settings.includeCompleted = true
        settings.maximumItems = 3
        settings.customPosition = true; settings.panelX = 0.5; settings.panelY = 0.62
        let limited = try WallpaperRenderer.layout(settings: settings, items: items)
        try require(limited.rows.contains { $0.item.isCompleted }, "Completed tasks available")
        try require(limited.rows.count <= 3 && limited.hiddenCount >= 3 && limited.footer != nil, "Limit and overflow footer")
        let long = WallpaperRenderer.text(titles[5], width: 100, settings: settings, maxLines: 2)
        try require(long.lines.count == 2 && long.truncated, "Unicode wraps and truncates with ellipsis")

        var checkedSizes: [String] = []
        for ratio in [9.0 / 19.5, 9.0 / 16, 1.0] {
            var value = settings; value.canvasAspect = ratio
            let layout = try WallpaperRenderer.layout(settings: value, items: items)
            try require(layout.panel.minY >= 0, "Aspect presets remain in bounds")
            checkedSizes.append("ratio \(ratio)")
        }
        for size in [WallpaperSize(width: 1200, height: 1200), WallpaperSize(width: 1600, height: 900)] {
            var value = settings
            value.size = size; value.canvasAspect = size.aspectRatio; value.automaticHeight = false; value.panelHeight = 0.8
            let result = try WallpaperRenderer.render(settings: value, items: items, photoURL: fixture, ciContext: context)
            try require(result.image.width == size.width && result.image.height == size.height, "Custom resolution")
            try WallpaperRenderer.writePNG(result.image, to: out.appendingPathComponent("custom-\(size.width)x\(size.height).png"), expected: size)
            checkedSizes.append(size.label)
        }
        for position in [0.0, 0.5, 1.0] {
            var value = settings
            value.panelX = position; value.panelY = position
            value.panelWidth = 0.3; value.padding = 48; value.fontSize = 38
            value.automaticHeight = false; value.panelHeight = 0.12
            let layout = try WallpaperRenderer.layout(settings: value, items: items)
            try require(layout.panel.minX >= 0 && layout.panel.minY >= 0 &&
                layout.panel.maxX <= layout.canvas.width && layout.panel.maxY <= layout.canvas.height,
                "Extreme panel remains within canvas")
            for row in layout.rows {
                try require(row.top >= layout.panel.minY && row.top + row.block.height <= layout.panel.maxY,
                            "Text stays within panel")
            }
        }
        for pan in [-1.0, 0, 1.0] {
            var value = settings
            value.backgroundZoom = 1.8; value.backgroundPanX = pan; value.backgroundPanY = pan
            let canvas = CGSize(width: 390, height: value.logicalHeight)
            let crop = WallpaperRenderer.backgroundRect(source: CGSize(width: 3000, height: 1600), canvas: canvas, settings: value)
            try require(crop.minX <= 0.001 && crop.minY <= 0.001 &&
                crop.maxX >= canvas.width - 0.001 && crop.maxY >= canvas.height - 0.001, "Aspect fill cannot reveal blank edges")
        }
        let empty = try WallpaperRenderer.layout(settings: WallpaperSettings(), items: [])
        try require(empty.rows.isEmpty && empty.emptyText != nil, "Empty state")
        try await draftChecks(out: out, fixture: fixture)
        var custom = WallpaperSettings()
        custom.panelX = 0.62; custom.panelY = 0.41; custom.customPosition = true
        custom.lineSpacing = 13; custom.itemSpacing = 31; custom.backgroundZoom = 1.8
        let untouched = try JSONEncoder().encode(custom)
        for scale in stride(from: EditorStandards.wallpaperScale.lowerBound,
                            through: EditorStandards.wallpaperScale.upperBound, by: 0.02) {
            let scaled = try custom.withStandardScale(scale).validated()
            try require(scaled.size == custom.size && scaled.canvasAspect == custom.canvasAspect &&
                scaled.panelX == custom.panelX && scaled.panelY == custom.panelY && scaled.backgroundZoom == custom.backgroundZoom,
                "Standard scaling keeps canvas, composition and crop")
            try require(abs(scaled.padding / 20 - scaled.fontSize / 18) < 0.00001 &&
                abs(scaled.itemSpacing / 12 - scaled.lineSpacing / 4) < 0.00001,
                "Standard wallpaper metrics share one scale")
        }
        let oldCustom = try JSONDecoder().decode(WallpaperSettings.self, from: untouched)
        try require(oldCustom == custom, "Advanced UI changes need no saved-draft schema migration")
        let standard = custom.withStandardScale(1)
        let image = try WallpaperRenderer.render(settings: standard, items: items, photoURL: fixture, ciContext: context)
        try require(image.image.width == standard.size.width && image.image.height == standard.size.height,
            "Standard-scale export still renders at actual target pixels")
        try WallpaperRenderer.writePNG(image.image, to: out.appendingPathComponent("standard-layout-4k.png"), expected: standard.size)
        try await D34Checks.run(out: out, fixture: fixture)
        try WidgetFeedbackRenderChecks.run(out: out)
        try FeedbackRepairRenderChecks.run(out: out)
        try PhotoRepairRenderChecks.run(out: out, fixture: fixture)
        try await LianxinWallpaperChecks.run(out: out)
        try await LianxinDisplayRenderChecks.run(out: out, fixture: fixture)
        let report: [String: Any] = [
            "result": "passed", "engine": "production CoreGraphics + CoreText + CoreImage on macOS",
            "iphone_device_validation": "pending", "synthetic_fixture_only": true,
            "export_pixels": [1170, 2532], "preview_pixels": [390, 844],
            "logical_layout_and_wrapping_match": true, "zero_material_max_channel_difference": maximumDifference,
            "checked_sizes": checkedSizes, "checks": [
                "stable real-item identities and manual order", "pending/all filters", "completed style input",
                "Unicode wrapping and truncation", "default center", "relative centers", "custom pixels",
                "overflow footer", "extreme bounds", "aspect fill / pan", "PNG readback", "private draft preservation"
            ]
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("wallpaper-render-checks.json"))
        print("PASS: production wallpaper renderer: physical PNG pixels, shared preview/export layout, Unicode wrapping, zero-tint/orientation, crops, presets, custom size, overflow and private draft checks.")
    }

    static func draftChecks(out: URL, fixture: URL) async throws {
        let directory = out.appendingPathComponent("temporary-draft-checks", isDirectory: true)
        let exports = directory.appendingPathComponent("exports")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = WallpaperDraftStore(directory: directory, exportDirectory: exports)
        let imported = try await store.importPhoto(Data(contentsOf: fixture))
        var settings = WallpaperSettings()
        settings.panelY = 0.6
        try await store.save(WallpaperDraft(settings: settings, photoFileName: imported.lastPathComponent))
        let reloaded = try await WallpaperDraftStore(directory: directory, exportDirectory: exports).load()
        try require(reloaded.draft.settings == settings && reloaded.photoURL == imported, "Draft and original photo persist")
        let originalPhoto = try Data(contentsOf: imported)
        let url = directory.appendingPathComponent("draft-v1.json")
        let future = Data(#"{"schemaVersion":99}"#.utf8)
        try future.write(to: url)
        do { try await store.save(WallpaperDraft()); throw WallpaperError.renderingFailed }
        catch WallpaperError.unsupportedDraft { }
        let preservedFuture = try Data(contentsOf: url)
        try require(preservedFuture == future, "Future draft never silently overwritten")
        try await store.save(WallpaperDraft(), replaceUnreadable: true)
        let archived = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("draft-preserved-") }
        try require(archived.count == 1, "Explicit reset preserves unreadable draft")
        let retainedPhoto = try Data(contentsOf: imported)
        try require(retainedPhoto == originalPhoto, "Reset never deletes source image")
    }
}
