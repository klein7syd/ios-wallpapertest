#if TODO_UI_CHECKS
import SwiftUI
import UIKit
import CryptoKit
import CoreText

/// Compiled only into the CI Simulator Debug app, never the delivered device IPA.
@MainActor
enum NativeUIProbe {
    static func makeStore() -> TodoStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("native-ui-fixture")
        let repository = TodoRepository(directoryURL: directory)
        if (try? repository.load().items.isEmpty) == true {
            _ = try? repository.add(title: "听音乐", marker: TodoMarker(kind: .emoji, emoji: "❤️"))
            _ = try? repository.add(title: "学习与整理这一周的待办", marker: TodoMarker(kind: .emoji, emoji: "📚"))
            _ = try? repository.add(title: "组合 Emoji 测试", marker: TodoMarker(kind: .emoji, emoji: "🧑🏽‍💻"))
        }
        return TodoStore(repository: repository)
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "NativeUIProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func pixels(_ image: CGImage) throws -> Data {
        let row = image.width * 4
        var data = Data(count: row * image.height)
        let ok = data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: row, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
            return true
        }
        try require(ok, "Pixel readback")
        return data
    }
    static func render<V: View>(_ view: V, name: String, directory: URL, scale: CGFloat = 3) throws -> CGImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage, let png = UIImage(cgImage: image).pngData() else { throw NSError(domain: "NativeUIProbe.empty", code: 1) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        return image
    }
    static func run() async {
        let output = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("native-ui-checks")
        var report: [String: Any] = ["result": "failed", "environment": "iOS Simulator; not a real iPhone", "system": UIDevice.current.systemVersion]
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try await Task.sleep(for: .milliseconds(200))
            // Execute the production editing-session coordinator on iOS, including
            // gesture coalescing, retry after failure, and the draft/photo restore path.
            var position = 0
            let session = EditorUndoState<Int>()
            session.synchronize(position)
            let events = session.context(read: { position })
            events.begin("slider")
            for index in 1...120 { position = index; session.observe(position) }
            events.end()
            try await session.undo(read: { position }) { previous, _ in position = previous }
            try require(position == 0 && !session.canUndo, "One iOS undo reverses a full continuous gesture")
            position = 2; session.observe(position)
            do {
                try await session.undo(read: { position }) { _, _ in throw NSError(domain: "ExpectedRestoreFailure", code: 1) }
                throw NSError(domain: "UnexpectedRestoreSuccess", code: 1)
            } catch let error as NSError where error.domain == "ExpectedRestoreFailure" { }
            try require(session.canUndo && position == 2 && !session.isRestoring, "Failed restore keeps a retryable session")
            try await session.undo(read: { position }) { previous, _ in position = previous }
            try require(position == 0, "Failed restore can be retried")
            let editor = WallpaperEditorModel()
            await editor.start(items: [], appearance: TodoAppearance())
            try require(editor.ready && !editor.draftBlocked, "CI draft is readable")
            let initialSettings = editor.settings, initialName = editor.photoName
            let sampleFormat = UIGraphicsImageRendererFormat(); sampleFormat.scale = 1
            let sample = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 60), format: sampleFormat).pngData { drawing in
                UIColor.systemBlue.setFill(); drawing.fill(CGRect(x: 0, y: 0, width: 40, height: 60))
            }
            let localFiles = WallpaperDraftStore()
            let sampleURL = try await localFiles.importPhoto(sample)
            var modified = initialSettings; modified.fontSize = 24
            try await editor.restoreEditorState(settings: modified, photoName: sampleURL.lastPathComponent)
            editor.removePhoto()
            try await editor.restoreEditorState(settings: modified, photoName: sampleURL.lastPathComponent)
            try require(editor.hasPhoto && editor.livePhoto != nil && editor.photoName == sampleURL.lastPathComponent,
                "Undo restores the real local source photo without album writes")
            let retainedSample = try Data(contentsOf: sampleURL)
            try require(retainedSample == sample, "Undo keeps source image bytes unchanged")
            try await editor.restoreEditorState(settings: initialSettings, photoName: initialName)
            await editor.saveNow()
            let restored = try await localFiles.load()
            try require(restored.draft.settings == initialSettings && restored.draft.photoFileName == initialName,
                "Restored editor state persists through the production draft store")
            // Parameter undo must not enter the photo-loading path or queue full bitmaps.
            let undoStarted = Date.timeIntervalSinceReferenceDate
            for index in 0..<40 {
                var snapshot = initialSettings; snapshot.panelX = Double(index) / 40; snapshot.customPosition = true
                try await editor.restoreEditorState(settings: snapshot, photoName: initialName)
                try require(!editor.isImporting && !editor.isRendering, "Ordinary undo avoids photo/bitmap work")
            }
            let undoMilliseconds = (Date.timeIntervalSinceReferenceDate - undoStarted) * 1000
            try await editor.restoreEditorState(settings: initialSettings, photoName: initialName)
            await editor.saveNow()
            let ownershipItem = TodoItem(id: UUID(), title: "已有单项 Emoji", marker: TodoMarker(kind: .emoji, emoji: "❤️"),
                isCompleted: false, createdAt: .now, updatedAt: .now)
            editor.updateItems([ownershipItem]); editor.settings.usesTaskMarkers = false
            var independent = TodoAppearance(); independent.defaultMarker = TodoMarker(kind: .square)
            independent.widget.markerOverride = TodoMarker(kind: .emoji, emoji: "🌙")
            editor.updateAppearance(independent)
            try require(editor.layout?.rows.first?.marker.kind == .square, "Live model draws edited wallpaper marker despite task/Widget overrides")
            editor.settings.usesTaskMarkers = true
            try require(editor.layout?.rows.first?.marker.emoji == "❤️", "Live model restores preserved individual Emoji")
            try await editor.restoreEditorState(settings: initialSettings, photoName: initialName)
            editor.updateItems([]); editor.updateAppearance(TodoAppearance()); await editor.saveNow()
            let sharedPhotoFixture = output.appendingPathComponent("widget-photo-fixture", isDirectory: true)
            let widgetPhoto = try await WidgetPhotoStore().importPhoto(sample, sharedDirectory: sharedPhotoFixture)
            guard let decodedPhoto = WidgetPhotoCache.image(named: widgetPhoto, sharedDirectory: sharedPhotoFixture) else {
                throw NSError(domain: "WidgetPhotoReadback", code: 1)
            }
            try require(decodedPhoto.width == 40 && decodedPhoto.height == 60, "Widget photo roundtrip reads generated shared reference")
            var photoStyle = WidgetAppearance(); photoStyle.backdrop = .photo; photoStyle.backgroundPhotoName = widgetPhoto
            let photoImage = try render(WidgetBackgroundView(style: photoStyle, sharedDirectory: sharedPhotoFixture)
                .frame(width: 170, height: 170), name: "widget-photo-background", directory: output)
            let photoBytes = [UInt8](try pixels(photoImage))
            let center = ((photoImage.height / 2) * photoImage.width + photoImage.width / 2) * 4
            try require(Int(photoBytes[center+2]) > Int(photoBytes[center]) + 50, "Actual Widget background pixels contain the selected blue photo")
            var headingLook = TodoAppearance(); headingLook.widget.completed = .all
            headingLook.widget.header = WidgetHeaderAppearance(text: "今天的计划", followsTextColor: false,
                color: WallpaperColor(red: 1, green: 0, blue: 0), fontSize: 24, horizontalPosition: 0.5)
            func redInk(_ image: CGImage) throws -> Int {
                let bytes = [UInt8](try pixels(image)); var count = 0
                for i in stride(from: 0, to: bytes.count, by: 4) {
                    if Int(bytes[i]) - max(Int(bytes[i+1]), Int(bytes[i+2])) > 80 { count += 1 }
                }
                return count
            }
            let headerReference = try render(Text("今天的计划")
                .font(Font(NativeTypography.font(family: .system, weight: .semibold, size: 24)))
                .foregroundStyle(.red).fixedSize().padding(4).background(.white),
                name: "header-complete-glyph-reference", directory: output)
            let referenceInk = try redInk(headerReference)
            var headingHashes = Set<String>()
            for summary in [true, false] {
                headingLook.widget.header?.showsSummary = summary
                let image = try render(TodoWidgetContent(document: TodoDocument(items: []), appearance: headingLook,
                    error: nil, family: .medium, interactive: false).padding(16).frame(width: 364, height: 170)
                    .background(.white).environment(\.colorScheme, .light),
                    name: "widget-custom-header-\(summary ? "summary" : "no-summary")", directory: output)
                headingHashes.insert(SHA256.hash(data: try pixels(image)).map { String(format: "%02x", $0) }.joined())
                let redPixels = try redInk(image)
                try require(Double(redPixels) >= Double(referenceInk) * 0.85,
                    "Complete custom title glyphs remain visible, not just its first characters")
                let bytes = [UInt8](try pixels(image)); var summaryInk = 0
                for y in 0..<min(image.height, 48 * 3) { for x in (image.width * 7 / 10)..<image.width {
                    let i = (y * image.width + x) * 4
                    if max(bytes[i], max(bytes[i+1], bytes[i+2])) < 160 { summaryInk += 1 }
                } }
                try require(summary ? summaryInk > 10 : summaryInk == 0,
                    "Top-right count pixels actually follow the summary switch")
            }
            try require(headingHashes.count == 2, "Summary toggle changes native Widget output")
            var heartWidths: [String: Int] = [:]
            for size in [8, 10, 12, 16, 19, 20, 24, 32, 48] {
                var style = MarkerStyle(); style.emojiSize = Double(size)
                let image = try render(TodoMarkerView(marker: TodoMarker(kind: .emoji, emoji: "❤️"), completed: false,
                    style: style, textColor: .black).padding(4).background(.white), name: "heart-\(size)pt", directory: output)
                let bytes = [UInt8](try pixels(image)); var xs: [Int] = [], ys: [Int] = []
                for y in 0..<image.height { for x in 0..<image.width {
                    let i = (y * image.width + x) * 4
                    if Int(bytes[i]) - max(Int(bytes[i+1]), Int(bytes[i+2])) > 35 { xs.append(x); ys.append(y) }
                } }
                guard let left = xs.min(), let right = xs.max(), let top = ys.min(), let bottom = ys.max() else { throw NSError(domain: "NativeUIProbe.heartMissing", code: size) }
                try require(left >= 11 && right <= (size + 4) * 3 + 1 && top >= 11 && bottom <= (size + 4) * 3 + 1, "Small heart fits its own cell at \(size)pt")
                try require(right - left >= Int(Double(size * 3) * 0.5), "Heart must remain fully sized at \(size)pt")
                heartWidths[String(size)] = right - left
            }
            try require((heartWidths["48"] ?? 0) > (heartWidths["24"] ?? 0) * 3 / 2, "Marker keeps growing above 24pt")
            _ = try render(MarkerChoiceEditor(choice: .constant(TodoMarker())).padding(8).frame(width: 340, height: 130)
                .background(.white).environment(\.dynamicTypeSize, .accessibility5), name: "marker-choices-accessibility", directory: output, scale: 2)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            var items = [
                TodoItem(id: UUID(), title: "听音乐，给每项任务自己的 Emoji", marker: TodoMarker(kind: .emoji, emoji: "❤️"), isCompleted: true, createdAt: now, updatedAt: now),
                TodoItem(id: UUID(), title: "组合和肤色 🧑🏽‍💻", marker: TodoMarker(kind: .emoji, emoji: "🧑🏽‍💻"), isCompleted: false, createdAt: now, updatedAt: now),
                TodoItem(id: UUID(), title: "较长标题在固定空间内安全截断与换行", marker: TodoMarker(kind: .emoji, emoji: "📚"), isCompleted: false, createdAt: now, updatedAt: now)
            ]
            var appearance = TodoAppearance()
            appearance.widget.completed = .all; appearance.widget.showsSeparators = true
            appearance.widget.completedTextColor = WallpaperColor(red: 0.9, green: 0.15, blue: 0.2)
            var effectHashes: [String: String] = [:]
            for effect in WidgetTextCompletion.allCases {
                appearance.widget.completedTextStyle = effect
                let image = try render(TodoWidgetContent(document: TodoDocument(items: items), appearance: appearance,
                    error: nil, family: .medium, interactive: false).padding(16).frame(width: 364, height: 170).background(.white)
                    .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large),
                    name: "text-\(effect.rawValue)", directory: output, scale: 2)
                effectHashes[effect.rawValue] = SHA256.hash(data: try pixels(image)).map { String(format: "%02x", $0) }.joined()
            }
            try require(Set(effectHashes.values).count == 5, "Five text-completion effects must change actual iOS-rendered pixels")
            items[0].isCompleted = false
            let types: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
                ("small", .xSmall, .extraSmall), ("standard", .large, .large), ("large", .xxxLarge, .extraExtraExtraLarge),
                ("a11y", .accessibility3, .accessibilityExtraLarge), ("a11y-max", .accessibility5, .accessibilityExtraExtraExtraLarge)
            ]
            var measuredFonts: [String: Double] = [:]; var matrix = 0
            appearance.widget.markerStyle.emojiSize = 48; appearance.widget.markerStyle.gap = 32
            for (name, type, category) in types {
                let points = UIFontMetrics(forTextStyle: .body).scaledValue(for: 15, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
                measuredFonts[name] = points
                for family in WidgetPreviewFamily.allCases {
                    for reduced in [false, true] {
                        let width = family.width * (reduced ? 0.85 : 1)
                        let height = family.height * (reduced ? 0.85 : 1)
                        let font = NativeTypography.font(family: .system, weight: .regular, size: points)
                        let line = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font))
                        let budget = WidgetLayoutMetrics.make(items: items, appearance: appearance, family: family,
                            width: width - 32, height: height - 32, fontLineHeight: line,
                            headerHeight: max(22, points * 1.3), footerHeight: max(15, points))
                        let count = budget.capacity
                        let used = Double(count) * budget.rowHeight + Double(max(0, count - 1)) * (budget.spacing + budget.separatorHeight)
                        try require(used <= budget.availableRowHeight + 0.001, "Real UIFontMetrics size must fit allocated rows")
                        let image = try render(TodoWidgetContent(document: TodoDocument(items: items), appearance: appearance,
                            error: nil, family: family, interactive: false).padding(16).frame(width: width, height: height)
                            .background(.white).environment(\.colorScheme, .light).environment(\.dynamicTypeSize, type),
                            name: "widget-\(family.id)-\(name)-\(reduced ? "reduced" : "regular")", directory: output, scale: 2)
                        try require(image.width > 0 && image.height > 0, "Native Widget image output")
                        matrix += 1
                    }
                }
            }
            try require((measuredFonts["a11y-max"] ?? 0) > (measuredFonts["standard"] ?? 0), "System font metrics grow with accessibility category")
            report.merge(["result": "passed", "small_heart_pixel_widths": heartWidths,
                "ordinary_undo_40_steps_milliseconds_on_Simulator": undoMilliseconds,
                "ordinary_undo_photo_loading_and_full_bitmap_work": "none",
                "live_wallpaper_marker_ownership": "passed", "widget_header_summary_and_photo_pixels": "passed", "text_effect_pixel_hashes": effectHashes,
                "grouped_edit_undo_retry_and_photo_draft_restore": "passed_on_iOS_Simulator",
                "UIFontMetrics_point_sizes": measuredFonts, "widget_type_size_matrix_images": matrix,
                "reduced_space_scope": "85% logical-size stress test; not an actual iPhone Display Zoom setting",
                "device_signing_installation_and_acceptance": "not_verified"], uniquingKeysWith: { _, next in next })
        } catch { report["error"] = error.localizedDescription }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("done.json"))
        } catch { print("Native UI probe could not write result") }
    }
}
#endif
