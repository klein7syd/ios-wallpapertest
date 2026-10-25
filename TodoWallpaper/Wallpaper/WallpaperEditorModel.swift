import SwiftUI
import Combine
import PhotosUI
import Photos
import UIKit

struct WallpaperShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor
final class WallpaperEditorModel: ObservableObject {
    @Published var settings = WallpaperSettings() {
        didSet { if ready { schedulePreview(); scheduleSave() } }
    }
    @Published private(set) var preview: WallpaperRendered?
    @Published private(set) var livePhoto: WallpaperLivePhoto?
    @Published private(set) var layout: WallpaperLayout?
    @Published private(set) var appearance = TodoAppearance()
    private var layoutKey: WallpaperSettings?
    private var layoutItems: [TodoItem] = []
    private var layoutAppearance = TodoAppearance()
    @Published private(set) var isRendering = false
    @Published private(set) var isImporting = false
    @Published private(set) var isExporting = false
    @Published private(set) var ready = false
    @Published private(set) var previewError: String?
    @Published var message: String?
    @Published var needsPhotoPermission = false
    @Published var shareFile: WallpaperShareFile?
    @Published private(set) var lastExportSize: String?
    @Published private(set) var photoName: String?
    @Published private(set) var draftBlocked = false
    private var photoURL: URL?
    private(set) var items: [TodoItem] = []
    private let files = WallpaperDraftStore()
    private let renderer = WallpaperRenderService()
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasBootstrapped = false

    var busy: Bool { isExporting || isImporting }
    var hasPhoto: Bool { photoURL != nil }

    func start(items: [TodoItem], appearance: TodoAppearance) async {
        self.items = items
        self.appearance = appearance
        guard !hasBootstrapped else { schedulePreview(); return }
        hasBootstrapped = true
        do {
            let loaded = try await files.load()
            settings = loaded.draft.settings
            photoURL = loaded.photoURL
            photoName = loaded.draft.photoFileName
            if let photoURL { livePhoto = try await renderer.loadPhoto(at: photoURL) }
        } catch { draftBlocked = true; message = error.localizedDescription }
        ready = true
        if !draftBlocked { await files.cleanExpired(keeping: photoName) }
        schedulePreview()
    }

    func updateAppearance(_ value: TodoAppearance) {
        appearance = value
        if ready { schedulePreview() }
    }
    var sourceIsSoft: Bool {
        guard let info = livePhoto?.info else { return false }
        let needed = max(Double(settings.size.width) / Double(info.width), Double(settings.size.height) / Double(info.height)) * settings.backgroundZoom
        return needed > 1.01 || Double(max(info.width, info.height)) * needed > 6144
    }
    func updateItems(_ items: [TodoItem]) {
        self.items = items
        if ready { schedulePreview() }
    }

    func importPhoto(_ selection: PhotosPickerItem) async {
        guard !busy, !draftBlocked else { return }
        saveTask?.cancel()
        isImporting = true
        defer { isImporting = false }
        do {
            guard let data = try await selection.loadTransferable(type: Data.self) else { throw WallpaperError.unreadablePhoto }
            let url = try await files.importPhoto(data)
            var next = settings
            next.backgroundZoom = 1; next.backgroundPanX = 0; next.backgroundPanY = 0
            let live = try await renderer.loadPhoto(at: url)
            try await files.save(WallpaperDraft(settings: next, photoFileName: url.lastPathComponent))
            photoURL = url; photoName = url.lastPathComponent; livePhoto = live
            settings = next
        } catch { message = error.localizedDescription }
    }

    func removePhoto() {
        guard !busy, !draftBlocked else { return }
        photoURL = nil; photoName = nil; livePhoto = nil
        settings.backgroundZoom = 1; settings.backgroundPanX = 0; settings.backgroundPanY = 0
        schedulePreview(); scheduleSave()
    }

    func resetLayout() async {
        guard !busy else { return }
        saveTask?.cancel()
        var defaults = WallpaperSettings()
        defaults.size = settings.size
        defaults.canvasAspect = settings.aspectRatio
        let name = draftBlocked ? nil : photoName
        do {
            try await files.save(WallpaperDraft(settings: defaults, photoFileName: name), replaceUnreadable: true)
            if draftBlocked { photoURL = nil; photoName = nil; livePhoto = nil }
            draftBlocked = false
            settings = defaults
        } catch { message = error.localizedDescription }
    }

    func saveNow() async {
        saveTask?.cancel()
        guard ready, !draftBlocked else { return }
        do { try await files.save(WallpaperDraft(settings: settings, photoFileName: photoName)) }
        catch { message = "壁纸草稿未保存：\(error.localizedDescription)" }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard !draftBlocked else { return }
        let draft = WallpaperDraft(settings: settings, photoFileName: photoName)
        saveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(350))
                try Task.checkCancellation()
                try await files.save(draft)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { message = "壁纸草稿未保存：\(error.localizedDescription)" } }
        }
    }

    private func schedulePreview() {
        // Background/position/blur/tint changes do NOT reshape text or regenerate pixels.
        if layoutKey != settings.glyphKey || layoutItems != items || layoutAppearance.defaultMarker != appearance.defaultMarker || layoutAppearance.markerStyle != appearance.markerStyle {
            do {
                layout = try WallpaperRenderer.layout(settings: settings.glyphKey, items: items, appearance: appearance)
                layoutKey = settings.glyphKey; layoutItems = items; layoutAppearance = appearance
            } catch { previewError = error.localizedDescription }
        }
        previewTask?.cancel()
        isRendering = true
        let snapshot = settings, tasks = items, photo = photoURL, look = appearance
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(240))
                let rendered = try await renderer.preview(settings: snapshot, items: tasks, photoURL: photo, appearance: look)
                try Task.checkCancellation()
                preview = rendered; previewError = nil; isRendering = false
            } catch is CancellationError { }
            catch {
                if !Task.isCancelled { previewError = error.localizedDescription; isRendering = false }
            }
        }
    }

    func export(saveToPhotos: Bool) async {
        guard ready, !busy, !draftBlocked else { return }
        isExporting = true; needsPhotoPermission = false
        previewTask?.cancel(); isRendering = false
        let snapshot: WallpaperSettings
        do { snapshot = try settings.validated() }
        catch { message = error.localizedDescription; isExporting = false; return }
        let tasks = items, photo = photoURL, look = appearance
        defer { isExporting = false }
        do {
            let url = try await renderer.export(settings: snapshot, items: tasks, photoURL: photo,
                                                 directory: files.exportDirectory, appearance: look)
            lastExportSize = snapshot.size.label
            if saveToPhotos {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    needsPhotoPermission = true; throw WallpaperError.photoPermission
                }
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                }
                message = "已保存 PNG 到相册，像素尺寸 \(snapshot.size.label)。"
            } else { shareFile = WallpaperShareFile(url: url) }
        } catch { message = error.localizedDescription }
    }

    func clearCache() async {
        guard !busy, shareFile == nil else { return }
        do { try await files.clearExportCache(); message = "已清理导出缓存，背景照片、草稿和待办均保留。" }
        catch { message = error.localizedDescription }
    }
}
