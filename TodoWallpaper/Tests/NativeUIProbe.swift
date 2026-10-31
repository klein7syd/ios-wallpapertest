#if TODO_UI_CHECKS
import SwiftUI
import UIKit
import CryptoKit
import CoreText
import WidgetKit

/// Compiled only into the CI Simulator Debug app, never the delivered device IPA.
@MainActor
enum NativeUIProbe {
    private final class ProbeTrackingSlider: UISlider { override var isTracking: Bool { true } }
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
            var sliderValue = 0.0, sliderPublications = 0, sliderBegins = 0, sliderEnds = 0
            let slider = ProbeTrackingSlider()
            let sliderDriver = SmoothValueSlider.Coordinator(value: Binding(get: { sliderValue }, set: { sliderValue = $0; sliderPublications += 1 }),
                editing: { editing in if editing { sliderBegins += 1 } else { sliderEnds += 1 } })
            sliderDriver.begin()
            for index in 0..<600 { slider.value = Float(index) / 600; sliderDriver.changed(slider) }
            try require(sliderPublications == 0, "Touch sampling does not publish model state before a display frame")
            sliderDriver.flush(); sliderDriver.end()
            try require(sliderPublications == 1 && sliderBegins == 1 && sliderEnds == 1, "600 native slider samples coalesce into one test frame and one undo group")
            report["native_slider_600_samples_one_forced_frame_model_publications"] = sliderPublications
            guard let convertedP3 = WallpaperColor.sRGB(UIColor(displayP3Red: 0.6, green: 0.4, blue: 0.3, alpha: 0.5)) else {
                throw NSError(domain: "NativeUIProbe.P3Conversion", code: 1)
            }
            try require(abs(convertedP3.red - 0.6345) < 0.01 && abs(convertedP3.green - 0.3887) < 0.01
                        && abs(convertedP3.blue - 0.2801) < 0.01 && abs(convertedP3.alpha - 0.5) < 0.001,
                        "Display P3 is color-converted into sRGB, not reinterpreted as unchanged RGB components")
            let repairStore = makeStore()
            repairStore.beginAppearanceInteraction()
            let repairHistory = EditorUndoState<TodoAppearance>()
            repairHistory.synchronize(repairStore.appearance)
            var invalidLook = repairStore.appearance
            invalidLook.defaultMarker = TodoMarker(kind: .emoji, emoji: "invalid")
            try require(!repairStore.setAppearance(invalidLook) && repairStore.appearanceError != nil,
                        "Semantic appearance errors remain visible and cannot corrupt the current state")
            var numericLook = repairStore.appearance; numericLook.widget.textColor.red = 1.2
            numericLook.widget.fontSize = 99
            try require(repairStore.setAppearance(numericLook) && repairStore.appearanceError == nil
                        && repairStore.appearance.widget.fontSize == 20 && repairStore.appearance.widget.textColor.red == 1,
                        "Numeric validation repairs and accepts the edit, clearing the previous error immediately")
            repairHistory.observe(repairStore.appearance)
            try await repairHistory.undo(read: { repairStore.appearance }) { previous, _ in
                guard repairStore.setAppearance(previous) else { throw AppearanceError.invalidStyle }
            }
            try require(repairStore.appearance.widget.fontSize == 15 && !repairHistory.canUndo && !repairHistory.isRestoring,
                        "A repaired editing value can be undone through the production store without locking the session")
            let storageFixture = output.appendingPathComponent("appearance-error-fixture", isDirectory: true)
            try FileManager.default.createDirectory(at: storageFixture, withIntermediateDirectories: true)
            let storageRepository = AppearanceRepository(directory: storageFixture)
            var futureLook = TodoAppearance(); futureLook.schemaVersion = 99
            let futureBytes = try JSONEncoder().encode(futureLook)
            try futureBytes.write(to: storageRepository.fileURL)
            let protectedStore = TodoStore(repository: TodoRepository(directoryURL: storageFixture), appearanceRepository: storageRepository)
            protectedStore.beginAppearanceInteraction(); protectedStore.reloadAppearance()
            let protectedError = protectedStore.appearanceError
            try require(protectedError != nil && protectedStore.setAppearance(protectedStore.appearance)
                        && protectedStore.appearanceError == protectedError,
                        "A same-value valid setter cannot hide a future-schema storage protection error")
            var protectedEdit = protectedStore.appearance; protectedEdit.widget.fontSize = 100
            try require(protectedStore.setAppearance(protectedEdit) && protectedStore.appearanceError == protectedError,
                        "Successful numeric repair clears only validation errors, preserving unresolved storage errors")
            protectedStore.flushAppearance()
            let retainedFutureBytes = try Data(contentsOf: storageRepository.fileURL)
            try require(protectedStore.appearanceError != nil && retainedFutureBytes == futureBytes,
                        "Failed persistence never overwrites a future-schema file or hides its recovery state")
            try JSONEncoder().encode(TodoAppearance()).write(to: storageRepository.fileURL)
            protectedStore.reloadAppearance()
            try require(protectedStore.appearanceError == nil, "An actual successful reload clears the storage error")
            report["readability_numeric_repair_undo_and_srgb"] = "passed"
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
            var tapValue = 0
            let tapSession = EditorUndoState<Int>(); tapSession.synchronize(tapValue)
            let taps = tapSession.coalescingContext(read: { tapValue })
            for next in 1...3 {
                taps.begin("wallpaper.panel.nudge"); tapValue = next; tapSession.observe(tapValue); taps.end()
            }
            try await Task.sleep(for: .milliseconds(600))
            try await tapSession.undo(read: { tapValue }) { before, _ in tapValue = before }
            try require(tapValue == 0 && !tapSession.canUndo, "A burst of begin/end nudge taps coalesces to one undo")
            taps.begin("wallpaper.panel.nudge"); tapValue = 4; tapSession.observe(tapValue); taps.end()
            let regular = tapSession.context(read: { tapValue }); regular.begin("slider")
            tapValue = 5; tapSession.observe(tapValue)
            try await Task.sleep(for: .milliseconds(600))
            tapValue = 6; tapSession.observe(tapValue); regular.end()
            try await tapSession.undo(read: { tapValue }) { before, _ in tapValue = before }
            try require(tapValue == 4, "A pending nudge timer cannot end a later slider gesture")
            try await tapSession.undo(read: { tapValue }) { before, _ in tapValue = before }
            try require(tapValue == 0 && !tapSession.canUndo, "Separate tap bursts retain their own undo baseline")
            report["nudge_begin_end_coalescing_and_later_gesture_isolation"] = "passed"
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
            let batchStore = WidgetPhotoStore()
            let batch = try await batchStore.beginBatch(sharedDirectory: sharedPhotoFixture)
            let rolledBackPhoto = try await batchStore.importPhoto(sample, sharedDirectory: sharedPhotoFixture, transactionID: batch)
            let busyCollection = try await batchStore.collect(retaining: [], sharedDirectory: sharedPhotoFixture)
            try require(busyCollection == nil, "Active import prevents collection before any storage reads")
            let journal = sharedPhotoFixture.appendingPathComponent("PhotoImports/" + batch.uuidString + ".json")
            let journalNames = try JSONDecoder().decode([String].self, from: Data(contentsOf: journal))
            try require(journalNames == [rolledBackPhoto], "Each written photo has a durable transaction journal")
            await batchStore.rollbackBatch(batch, sharedDirectory: sharedPhotoFixture)
            let rolledBackURL = try WidgetPhotoReference.url(for: rolledBackPhoto, in: sharedPhotoFixture)
            try require(!FileManager.default.fileExists(atPath: rolledBackURL.path) && !FileManager.default.fileExists(atPath: journal.path), "Cancellation/failed batch rollback removes only its files and journal")
            let committedBatch = try await batchStore.beginBatch(sharedDirectory: sharedPhotoFixture)
            let committedPhoto = try await batchStore.importPhoto(sample, sharedDirectory: sharedPhotoFixture, transactionID: committedBatch)
            try await batchStore.commitBatch(committedBatch, sharedDirectory: sharedPhotoFixture)
            await batchStore.rollbackBatch(committedBatch, sharedDirectory: sharedPhotoFixture)
            let committedURL = try WidgetPhotoReference.url(for: committedPhoto, in: sharedPhotoFixture)
            try require(FileManager.default.fileExists(atPath: committedURL.path), "After durable publication a cancelled task cannot roll back committed photos")
            let retainedHistory = EditorUndoState<Set<String>>()
            var retainedNames = Set<String>()
            retainedHistory.retainedValuesChanged = { values in retainedNames = values.reduce(into: []) { $0.formUnion($1) } }
            retainedHistory.synchronize([committedPhoto]); retainedHistory.observe([rolledBackPhoto])
            try require(retainedNames == [committedPhoto, rolledBackPhoto], "Editor retention callback protects both sides of undo steps synchronously")
            report["album_transaction_rollback_commit_busy_and_undo_retention"] = "passed"
            let widgetPhoto = try await WidgetPhotoStore().importPhoto(sample, sharedDirectory: sharedPhotoFixture)
            let secondAnalysisPhoto = try await WidgetPhotoStore().importPhoto(sample, sharedDirectory: sharedPhotoFixture)
            let analysisSuite = "NativeUIProbe.Analysis.\(UUID().uuidString)"
            guard let analysisDefaults = UserDefaults(suiteName: analysisSuite) else { throw AppearanceError.unreadable }
            defer { analysisDefaults.removePersistentDomain(forName: analysisSuite) }
            let analysisCache = AppearanceStore(defaults: analysisDefaults,
                requestDirectory: sharedPhotoFixture.appendingPathComponent("AnalysisRequests", isDirectory: true))
            let analysisStore = TodoStore(repository: TodoRepository(directoryURL: sharedPhotoFixture),
                appearanceRepository: AppearanceRepository(directory: sharedPhotoFixture),
                analysisDirectory: sharedPhotoFixture, analysisCache: analysisCache)
            analysisStore.beginAppearanceInteraction()
            var analysisLook = TodoAppearance(); analysisLook.widget.backdrop = .photo
            analysisLook.widget.backgroundPhotoName = widgetPhoto
            analysisLook.widget.photoRotation = WidgetAlbumRotation(title: "分析调度", photos: [widgetPhoto, secondAnalysisPhoto], anchor: .now)
            try require(analysisStore.setAppearance(analysisLook), "Photo analysis fixture is a valid editing state")
            try await Task.sleep(for: .milliseconds(450))
            try require(analysisStore.analysisRevision == 0 && analysisCache.knownRequests().isEmpty,
                        "Continuous interaction never starts analysis even after the debounce duration")
            analysisStore.endAppearanceInteraction()
            try await Task.sleep(for: .milliseconds(150))
            try require(analysisStore.analysisRevision == 0, "The 400ms delay begins after interaction ends")
            analysisStore.beginAppearanceInteraction()
            analysisLook.widget.backgroundCrop = PhotoCrop(zoom: 2, panX: 0.5)
            try require(analysisStore.setAppearance(analysisLook), "A newer crop supersedes the pending generation")
            analysisStore.endAppearanceInteraction()
            let actualRequest = analysisLook.widget.analysisRequest(photoName: secondAnalysisPhoto, canvasAspect: 1.83, darkBackground: false)
            analysisCache.registerMissing(actualRequest)
            analysisStore.resumePhotoAnalysis()
            for _ in 0..<70 {
                if analysisCache.contains(actualRequest) && analysisCache.knownRequests().count == 8 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            try require(analysisStore.analysisRevision > 0 && analysisCache.contains(actualRequest)
                        && analysisCache.knownRequests().count == 8
                        && analysisCache.knownRequests().allSatisfy { $0.crop == PhotoCrop(zoom: 2, panX: 0.5) },
                        "Observable results refresh after debounce; a late actual-aspect miss rescans both album photos without stale-generation output")
            analysisStore.beginAppearanceInteraction()
            report["photo_analysis_interaction_debounce_generation_and_actual_aspect"] = "passed"
            var snapshotStyle = analysisLook.widget
            snapshotStyle.followsSystemText = false; snapshotStyle.textColor = WallpaperColor()
            let snapshotRequest = snapshotStyle.analysisRequest(photoName: widgetPhoto, canvasAspect: 1.83, darkBackground: false)
            let snapshotAnalysis = ImageAnalysis(meanLuma: 0.9, contrast: 0.5)
            let snapshot = [snapshotRequest.cacheID + "." + snapshotStyle.readable.anchor.rawValue: snapshotAnalysis]
            AppearanceStore.shared.clearMemoryCache()
            let snapshotScrim = ReadableResolver.scrim(style: snapshotStyle, date: .now, scheme: .light,
                canvasAspect: 1.83, preparedAnalyses: snapshot)
            try require(abs(snapshotScrim.value - snapshotStyle.readable.autoScrim(analysis: snapshotAnalysis)) < 0.000000001,
                        "A prepared Widget analysis snapshot survives another provider clearing the process cache")
            let snapshotValues = Dictionary(uniqueKeysWithValues: TextAnchor.allCases.map { ($0, snapshotAnalysis) })
            try require(AppearanceStore.shared.setAnalysis(snapshotValues, for: snapshotRequest), "Snapshot-isolation fixture warms a distinct global result")
            let emptySnapshotScrim = ReadableResolver.scrim(style: snapshotStyle, date: .now, scheme: .light,
                canvasAspect: 1.83, preparedAnalyses: [:])
            let liveCacheScrim = ReadableResolver.scrim(style: snapshotStyle, date: .now, scheme: .light, canvasAspect: 1.83)
            AppearanceStore.shared.removeAnalysis(for: widgetPhoto)
            try require(abs(emptySnapshotScrim.value - 0.4) < 0.000000001 && liveCacheScrim.value > 0.4,
                        "An explicitly empty entry snapshot falls back safely instead of borrowing mutable global cache")
            guard let decodedPhoto = WidgetPhotoCache.image(named: widgetPhoto, sharedDirectory: sharedPhotoFixture) else {
                throw NSError(domain: "WidgetPhotoReadback", code: 1)
            }
            try require(decodedPhoto.width == 40 && decodedPhoto.height == 60, "Widget photo roundtrip reads generated shared reference")
            var photoStyle = WidgetAppearance(); photoStyle.backdrop = .photo; photoStyle.backgroundPhotoName = widgetPhoto
            let photoImage = try render(WidgetBackgroundView(style: photoStyle, sharedDirectory: sharedPhotoFixture)
                .frame(width: 170, height: 170), name: "widget-photo-background", directory: output)
            let photoBytes = [UInt8](try pixels(photoImage))
            func effectBackground(mode: WidgetRenderingMode, family: WidgetFamily, scrim: Double, name: String) throws -> Data {
                let image = try render(WidgetBackgroundView(style: photoStyle, sharedDirectory: sharedPhotoFixture,
                    scrim: scrim, scrimAnchor: .bottom, effectsFamily: family)
                    .frame(width: 170, height: 170)
                    .environment(\.widgetRenderingMode, mode),
                    name: name, directory: output, scale: 1)
                return try pixels(image)
            }
            var excludedModes = [("vibrant", WidgetRenderingMode.vibrant, WidgetFamily.systemSmall),
                                 ("accessory", WidgetRenderingMode.fullColor, WidgetFamily.accessoryRectangular)]
            if #available(iOS 18.0, *) { excludedModes.append(("accented", .accented, .systemSmall)) }
            for (tag, mode, family) in excludedModes {
                let base = try effectBackground(mode: mode, family: family, scrim: 0, name: "readable-\(tag)-base")
                let guarded = try effectBackground(mode: mode, family: family, scrim: 0.7, name: "readable-\(tag)-guarded")
                try require(base == guarded, "Actual background pixels disable photo scrims in tinted and lock-screen families")
            }
            let fullBase = try effectBackground(mode: .fullColor, family: .systemSmall, scrim: 0, name: "readable-full-base")
            let fullScrim = try effectBackground(mode: .fullColor, family: .systemSmall, scrim: 0.7, name: "readable-full-scrim")
            try require(fullBase != fullScrim, "Full-color home-screen photos still receive the configured scrim")
            var scrimPixels: [Data] = []
            for inset in [-12.0, 0, 12] {
                let image = try render(ScrimView(anchor: .bottom, strength: 0.6, heightRatio: 0.45, extraInset: inset)
                    .frame(width: 100, height: 200).background(.white), name: "readable-inset-\(Int(inset))", directory: output, scale: 1)
                scrimPixels.append(try pixels(image))
            }
            try require(scrimPixels[0] == scrimPixels[1] && scrimPixels[1] != scrimPixels[2],
                        "Native negative scrim inset matches zero; positive inset extends coverage")
            var markerLook = TodoAppearance()
            markerLook.widget.followsSystemText = false
            markerLook.widget.header = WidgetHeaderAppearance(showsTitle: false, showsSummary: false)
            markerLook.widget.showsFooter = false
            markerLook.widget.markerStyle.followsTextColor = false
            markerLook.widget.markerStyle.stroke = WallpaperColor(red: 1, green: 0, blue: 0)
            let markerOnly = TodoItem(id: UUID(), title: "", isCompleted: false, createdAt: .now, updatedAt: .now)
            var markerShadowPixels: [Data] = []
            for family in [WidgetFamily.systemSmall, .accessoryRectangular] {
                let image = try render(TodoWidgetContent(document: TodoDocument(items: [markerOnly]), appearance: markerLook,
                    error: nil, family: .small, interactive: false, effectsFamily: family).frame(width: 138, height: 138).background(.white)
                    .environment(\.widgetRenderingMode, .fullColor),
                    name: "readable-marker-shadow-\(family.rawValue)", directory: output, scale: 3)
                markerShadowPixels.append(try pixels(image))
            }
            try require(markerShadowPixels[0] != markerShadowPixels[1],
                        "The production marker receives a shadow at home and excludes it on the lock screen")
            var centeredLook = TodoAppearance()
            centeredLook.widget.readableAnchor = .center; centeredLook.widget.readableEdgeInset = 130
            let centeredDocument = TodoDocument(items: [TodoItem(id: UUID(), title: "居中跨尺寸测试", isCompleted: false, createdAt: .now, updatedAt: .now)])
            let smallLayout = WidgetContentLayout.make(document: centeredDocument, appearance: centeredLook, family: .small,
                width: 138, height: 138, bodyUnit: 15, headerUnit: 17, footerUnit: 11)
            let largeLayout = WidgetContentLayout.make(document: centeredDocument, appearance: centeredLook, family: .large,
                width: 332, height: 350, bodyUnit: 15, headerUnit: 17, footerUnit: 11)
            try require(smallLayout.inset == 40 && largeLayout.inset > 40,
                        "The shared native layout reduces a saved large centered offset for the smaller family")
            let centeredBackground = try render(WidgetBackgroundView(style: centeredLook.widget, scrim: 0.6,
                scrimAnchor: .center, scrimExtraInset: 130, contentDocument: centeredDocument,
                contentAppearance: centeredLook, contentFamily: .small,
                contentMargins: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                .frame(width: 170, height: 170).environment(\.dynamicTypeSize, .large),
                name: "readable-centered-small-effective", directory: output, scale: 1)
            let centeredReference = try render(WidgetBackgroundView(style: centeredLook.widget, scrim: 0.6,
                scrimAnchor: .center, scrimExtraInset: 40).frame(width: 170, height: 170)
                .environment(\.dynamicTypeSize, .large), name: "readable-centered-small-reference", directory: output, scale: 1)
            let centeredPixels = try pixels(centeredBackground), referencePixels = try pixels(centeredReference)
            try require(centeredPixels == referencePixels,
                        "A large saved inset cannot move the small Widget scrim away from its actual text offset")
            report["readability_centered_family_offsets"] = ["small": smallLayout.inset, "large": largeLayout.inset]
            let center = ((photoImage.height / 2) * photoImage.width + photoImage.width / 2) * 4
            try require(Int(photoBytes[center+2]) > Int(photoBytes[center]) + 50, "Actual Widget background pixels contain the selected blue photo")
            // Exercise the exact pre-staged image path used by the extension,
            // not just the app preview's file-loading path.
            var preparedSizes: [String: [Int]] = [:]
            for family in WidgetPreviewFamily.allCases {
                guard let prepared = WidgetPhotoCache.prepared(style: photoStyle,
                    size: CGSize(width: family.width, height: family.height), date: .now, sharedDirectory: sharedPhotoFixture) else {
                    throw NSError(domain: "WidgetPreparedPhoto", code: 1)
                }
                try require(max(prepared.width, prepared.height) <= 768 && prepared.bytesPerRow * prepared.height <= 768 * 768 * 4,
                    "Actual timeline bitmap stays within its pixel/memory bound")
                preparedSizes[family.id] = [prepared.width, prepared.height, prepared.bytesPerRow * prepared.height]
                // Prove that the archived view can render after its source file is
                // unavailable. This catches accidental extension-body file reads.
                let source = try WidgetPhotoReference.url(for: widgetPhoto, in: sharedPhotoFixture)
                let hidden = source.appendingPathExtension("held")
                try FileManager.default.moveItem(at: source, to: hidden)
                defer { try? FileManager.default.moveItem(at: hidden, to: source) }
                let image = try render(WidgetBackgroundView(style: photoStyle, preparedPhoto: prepared, preparedOnly: true)
                    .frame(width: family.width, height: family.height), name: "widget-prepared-photo-\(family.id)", directory: output, scale: 2)
                let bytes = [UInt8](try pixels(image)); let offset = ((image.height / 2) * image.width + image.width / 2) * 4
                try require(Int(bytes[offset+2]) > Int(bytes[offset]) + 50, "Prepared photo survives source-file absence in all families")
            }
            let markerName = try await WidgetPhotoStore().importMarker(sample, sharedDirectory: sharedPhotoFixture)
            let customMarker = TodoMarker(kind: .image, imageName: markerName)
            let markerImage = try render(TodoMarkerView(marker: customMarker, completed: false, assetDirectory: sharedPhotoFixture)
                .padding(4).background(.white), name: "widget-custom-image-marker", directory: output)
            let markerPixels = [UInt8](try pixels(markerImage)); var blueMarkerPixels = 0
            for index in stride(from: 0, to: markerPixels.count, by: 4) {
                if Int(markerPixels[index+2]) > Int(markerPixels[index]) + 50 { blueMarkerPixels += 1 }
            }
            try require(blueMarkerPixels > 100, "Custom image marker renders real colored pixels in native UI")
            var photoLook = TodoAppearance(); photoLook.widget = photoStyle
            let photoTask = TodoItem(id: UUID(), title: "照片模式修改文字与完成状态", isCompleted: false, createdAt: .now, updatedAt: .now)
            let prepped = WidgetPhotoCache.prepared(style: photoStyle, size: CGSize(width: 364, height: 170), date: .now, sharedDirectory: sharedPhotoFixture)
            var photoContentHashes = Set<String>()
            for index in 0..<4 {
                var variant = photoLook
                if index == 1 { variant.widget.weight = .bold }
                if index == 2 { variant.widget.header?.text = "不同标题"; variant.widget.header = WidgetHeaderAppearance(text: "不同标题") }
                var task = photoTask; task.isCompleted = index == 3
                let image = try render(TodoWidgetContent(document: TodoDocument(items: [task]), appearance: variant, error: nil, family: .medium, interactive: false)
                    .padding(16).frame(width: 364, height: 170)
                    .background { WidgetBackgroundView(style: variant.widget, preparedPhoto: prepped, preparedOnly: true) },
                    name: "widget-photo-live-setting-\(index)", directory: output, scale: 2)
                photoContentHashes.insert(SHA256.hash(data: try pixels(image)).map { String(format: "%02x", $0) }.joined())
            }
            try require(photoContentHashes.count == 4, "Font/title/completion continue changing actual pixels while photo backdrop stays selected")
            report["prepared_widget_photo_sizes_and_bytes"] = preparedSizes
            report["photo_background_settings_and_completion_pixel_variants"] = photoContentHashes.count
            report["custom_image_marker_native_color_pixels"] = blueMarkerPixels
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
            headingLook.widget.readableAnchor = .top
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
            var insetInk: [String: Int] = [:]
            for inset in [0.0, 12, 24] {
                headingLook.widget.header?.topInset = inset
                let image = try render(TodoWidgetContent(document: TodoDocument(items: []), appearance: headingLook,
                    error: nil, family: .medium, interactive: false).padding(16).frame(width: 364, height: 170)
                    .background(.white).environment(\.colorScheme, .light), name: "widget-title-inset-\(Int(inset))", directory: output)
                let ink = try redInk(image); insetInk[String(Int(inset))] = ink
                try require(Double(ink) >= Double(referenceInk) * 0.95, "Top whitespace never cuts title glyphs")
                if let baselineInk = insetInk["0"] {
                    try require(abs(ink - baselineInk) <= max(10, baselineInk / 100),
                        "Moving title down preserves at least 99 percent of its original ink; no centered-frame clipping")
                }
            }
            report["full_title_ink_at_insets"] = insetInk
            var blackLook = TodoAppearance(); blackLook.widget.theme = .light; blackLook.widget.backdrop = .solid
            blackLook.widget.panelColor = WallpaperColor(red: 0, green: 0, blue: 0)
            blackLook.widget.followsSystemText = false; blackLook.widget.textColor = WallpaperColor(red: 0, green: 0, blue: 0)
            let blackImage = try render(TodoWidgetContent(document: TodoDocument(items: []), appearance: blackLook, error: nil, family: .medium, interactive: false)
                .padding(16).frame(width: 364, height: 170).background { WidgetBackgroundView(style: blackLook.widget) }
                .environment(\.colorScheme, .light), name: "widget-black-text-black-panel-light-system", directory: output)
            let blackBytes = [UInt8](try pixels(blackImage)); var protectedInk = 0
            for index in stride(from: 0, to: blackBytes.count, by: 4) {
                if min(blackBytes[index], min(blackBytes[index+1], blackBytes[index+2])) > 200 { protectedInk += 1 }
            }
            try require(blackBytes[0] < 10, "Black custom text renders exactly as chosen; readability is handled by the scrim")
            report["black_on_black_light_mode_visible_ink"] = protectedInk

            // The production gesture display path updates retained CA layers only.
            let motion = PhotoMotionView(frame: CGRect(x: 0, y: 0, width: 170, height: 170))
            motion.setPhoto(decodedPhoto)
            var displayCommits = 0; motion.onFinish = { _ in displayCommits += 1 }
            for endings in [[true, false], [false, true], [true, true], [false, false]] {
                motion.crop = PhotoCrop()
                var began = 0, ended = 0
                motion.onBegin = { began += 1 }; motion.onFinish = { _ in ended += 1 }
                motion.begin(motion.panRecognizer); motion.begin(motion.pinchRecognizer)
                let changed = PhotoCrop(zoom: 2, panX: 0.4, panY: -0.3)
                motion.crop = changed; motion.updateLayers()
                try require(ended == 0, "Changing retained layers does not publish a partial gesture")
                motion.finish(motion.panRecognizer, cancelled: endings[0])
                try require(motion.isTracking && ended == 0, "First recognizer end waits for its partner")
                motion.finish(motion.pinchRecognizer, cancelled: endings[1])
                let allCancelled = endings.allSatisfy { $0 }
                try require(motion.crop == (allCancelled ? PhotoCrop() : changed) && began == 1 && ended == 1 && !motion.isTracking,
                    "Mixed pan/pinch endings commit if either succeeds, and all-cancel restores the original exactly once")
                motion.finish(motion.pinchRecognizer, cancelled: false)
                try require(ended == 1, "Duplicate terminal callbacks cannot submit a second undo")
            }
            for cancelled in [true, false] {
                motion.crop = PhotoCrop(); motion.begin(motion.panRecognizer)
                motion.crop = PhotoCrop(zoom: 3); motion.finish(motion.panRecognizer, cancelled: cancelled)
                try require(motion.crop.zoom == (cancelled ? 1 : 3), "Single-recognizer cancellation retains its previous rollback behavior")
            }
            motion.onFinish = { _ in displayCommits += 1 }
            report["mixed_gesture_endings_and_all_cancel_rollback"] = "passed"
            let motionStarted = Date.timeIntervalSinceReferenceDate
            for index in 0..<600 {
                motion.crop = PhotoCrop(zoom: 2, panX: Double(index % 100) / 50 - 1, panY: 0)
                motion.updateLayers()
            }
            let motionMilliseconds = (Date.timeIntervalSinceReferenceDate - motionStarted) * 1000
            try require(displayCommits == 0, "Motion frames never commit editor state or trigger persistence")
            motion.onFinish(motion.crop)
            try require(displayCommits == 1, "One finished gesture owns one commit")
            let halves = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60), format: sampleFormat).pngData { drawing in
                UIColor.red.setFill(); drawing.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
                UIColor.blue.setFill(); drawing.fill(CGRect(x: 60, y: 0, width: 60, height: 60))
            }
            let halvesName = try await WidgetPhotoStore().importPhoto(halves, sharedDirectory: sharedPhotoFixture)
            var croppedStyle = WidgetAppearance(); croppedStyle.theme = .light; croppedStyle.backdrop = .photo
            croppedStyle.backgroundPhotoName = halvesName
            for pan in [-1.0, 1.0] {
                croppedStyle.backgroundCrop = PhotoCrop(panX: pan)
                let image = try render(WidgetBackgroundView(style: croppedStyle, sharedDirectory: sharedPhotoFixture)
                    .frame(width: 170, height: 170), name: "widget-crop-\(pan)", directory: output)
                let bytes = [UInt8](try pixels(image)); let center = ((image.height / 2) * image.width + image.width / 2) * 4
                try require(pan < 0 ? Int(bytes[center+2]) > Int(bytes[center]) + 100 : Int(bytes[center]) > Int(bytes[center+2]) + 100,
                    "Real Widget pixels follow normalized photo pan")
            }
            croppedStyle.backgroundPhotoOpacity = 0
            let transparent = try render(WidgetBackgroundView(style: croppedStyle, sharedDirectory: sharedPhotoFixture)
                .frame(width: 170, height: 170), name: "widget-photo-opacity-zero", directory: output)
            let transparentBytes = [UInt8](try pixels(transparent)); let tc = ((transparent.height / 2) * transparent.width + transparent.width / 2) * 4
            try require(transparentBytes[tc] > 240 && transparentBytes[tc+1] > 240 && transparentBytes[tc+2] > 240,
                "Photo opacity zero reveals light theme base")
            var darkLook = TodoAppearance(); darkLook.widget.theme = .dark
            let darkImage = try render(TodoWidgetContent(document: TodoDocument(items: []), appearance: darkLook,
                error: nil, family: .medium, interactive: false).padding(16).frame(width: 364, height: 170)
                .background { WidgetBackgroundView(style: darkLook.widget) }.environment(\.colorScheme, .light),
                name: "widget-dark-on-system-light", directory: output)
            let darkBytes = [UInt8](try pixels(darkImage)); var whiteInk = 0
            for i in stride(from: 0, to: darkBytes.count, by: 4) {
                if min(darkBytes[i], min(darkBytes[i+1], darkBytes[i+2])) > 200 { whiteInk += 1 }
            }
            try require(darkBytes[0] < 50 && whiteInk > 100, "Dark Widget on light system keeps dark base and visible white text")
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
            try require(Set(effectHashes.values).count == WidgetTextCompletion.allCases.count, "Every text-completion effect must change actual iOS-rendered pixels")
            items[0].isCompleted = false
            let types: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
                ("small", .xSmall, .extraSmall), ("standard", .large, .large), ("large", .xxxLarge, .extraExtraExtraLarge),
                ("a11y", .accessibility3, .accessibilityExtraLarge), ("a11y-max", .accessibility5, .accessibilityExtraExtraExtraLarge)
            ]
            var lianxinImages = 0
            for family in WidgetPreviewFamily.allCases {
                for type in [DynamicTypeSize.large, .xxxLarge, .accessibility3] {
                    for (index, text) in ["晚安", String(repeating: "心", count: 200), "中文与한국어一起，잘 자요。", "🧑🏽‍💻❤️📚"].enumerated() {
                        var style = WidgetAppearance(); style.showsFooter = false
                        let content = LianxinPublication(idol: "角色", text: text, photo: nil, date: .now, example: index % 2 == 0)
                        let image = try render(LianxinWidgetContent(content: content, style: style, family: family)
                            .padding(16).frame(width: family.width, height: family.height).background(.white)
                            .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, type),
                            name: "lianxin-\(family.id)-\(lianxinImages)", directory: output, scale: 2)
                        try require(image.width > 0 && image.height > 0, "连心真实共享视图按组件边界渲染")
                        lianxinImages += 1
                    }
                }
            }
            report["lianxin_shared_content_matrix"] = lianxinImages
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
                        let used = budget.usedHeight
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
                "retained_photo_layer_600_updates_ms_on_Simulator": motionMilliseconds,
                "gesture_display_frame_commits": 0, "gesture_end_commits": 1,
                "widget_crop_opacity_and_mismatched_system_theme_pixels": "passed",
                "performance_scope": "layer/model CPU callbacks, not real iPhone touch FPS",
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
