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
    private var items: [TodoItem] = []
    private let files = WallpaperDraftStore()
    private let renderer = WallpaperRenderService()
    private var previewTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasBootstrapped = false

    var busy: Bool { isExporting || isImporting }
    var hasPhoto: Bool { photoURL != nil }

    func start(items: [TodoItem]) async {
        self.items = items
        guard !hasBootstrapped else { schedulePreview(); return }
        hasBootstrapped = true
        do {
            let loaded = try await files.load()
            settings = loaded.draft.settings
            photoURL = loaded.photoURL
            photoName = loaded.draft.photoFileName
        } catch { draftBlocked = true; message = error.localizedDescription }
        ready = true
        if !draftBlocked { await files.cleanExpired(keeping: photoName) }
        schedulePreview()
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
            try await files.save(WallpaperDraft(settings: next, photoFileName: url.lastPathComponent))
            photoURL = url; photoName = url.lastPathComponent
            settings = next
        } catch { message = error.localizedDescription }
    }

    func removePhoto() {
        guard !busy, !draftBlocked else { return }
        photoURL = nil; photoName = nil
        settings.backgroundZoom = 1; settings.backgroundPanX = 0; settings.backgroundPanY = 0
        schedulePreview(); scheduleSave()
    }

    func resetLayout() async {
        guard !busy else { return }
        saveTask?.cancel()
        var defaults = WallpaperSettings()
        defaults.size = settings.size
        let name = draftBlocked ? nil : photoName
        do {
            try await files.save(WallpaperDraft(settings: defaults, photoFileName: name), replaceUnreadable: true)
            if draftBlocked { photoURL = nil; photoName = nil }
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
        previewTask?.cancel()
        isRendering = true
        let snapshot = settings, tasks = items, photo = photoURL
        previewTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(45))
                let rendered = try await renderer.preview(settings: snapshot, items: tasks, photoURL: photo)
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
        let tasks = items, photo = photoURL
        defer { isExporting = false }
        do {
            let url = try await renderer.export(settings: snapshot, items: tasks, photoURL: photo,
                                                 directory: files.exportDirectory)
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
