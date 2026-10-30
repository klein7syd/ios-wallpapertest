import Foundation
import ImageIO
import UniformTypeIdentifiers

actor WidgetPhotoStore {
    static let shared = WidgetPhotoStore()
    private var transactions: [UUID: Set<String>] = [:]
    private func journal(_ id: UUID, directory: URL) throws {
        let folder = directory.appendingPathComponent("PhotoImports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Array(transactions[id] ?? []).sorted()).write(to: folder.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }
    func beginBatch(sharedDirectory: URL? = nil) throws -> UUID {
        let directory = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        let id = UUID(); transactions[id] = []
        do { try journal(id, directory: directory); return id }
        catch { transactions.removeValue(forKey: id); throw error }
    }
    func commitBatch(_ id: UUID, sharedDirectory: URL? = nil) throws {
        guard transactions[id] != nil else { throw PhotoImportError.invalidTransaction }
        let directory = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        transactions.removeValue(forKey: id)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("PhotoImports/" + id.uuidString + ".json"))
    }
    func rollbackBatch(_ id: UUID, sharedDirectory: URL? = nil) {
        guard let names = transactions.removeValue(forKey: id), let directory = try? sharedDirectory ?? TodoSharedStorage.sharedDirectory() else { return }
        for name in names {
            if let url = try? WidgetPhotoReference.url(for: name, in: directory) { try? FileManager.default.removeItem(at: url) }
            AppearanceStore.shared.removeAnalysis(for: name)
        }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("PhotoImports/" + id.uuidString + ".json"))
    }
    func collect(retaining names: Set<String>, sharedDirectory: URL? = nil, now: Date = .now) throws -> PhotoAssetCollection? {
        guard transactions.isEmpty else { return nil }
        let directory = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        let result = try PhotoAssetGarbageCollector.collect(directory: directory, retaining: names, now: now)
        for name in result.deleted where WidgetPhotoReference.isValid(name) { AppearanceStore.shared.removeAnalysis(for: name) }
        AppearanceStore.shared.cleanOrphanAnalysis(existing: result.existingPhotos)
        return result
    }

    func importMarker(_ data: Data, sharedDirectory: URL? = nil) throws -> String {
        guard data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
        let shared = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        try FileManager.default.createDirectory(at: MarkerImageReference.directory(in: shared), withIntermediateDirectories: true)
        let name = "marker-image-\(UUID().uuidString).png"
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { throw WallpaperError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        try (output as Data).write(to: MarkerImageReference.url(for: name, in: shared), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }
    func importPhoto(_ data: Data, sharedDirectory: URL? = nil, transactionID: UUID? = nil) throws -> String {
        guard data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1536,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
        let shared = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        let directory = WidgetPhotoReference.directory(in: shared)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "widget-photo-\(UUID().uuidString).jpg"
        let url = try WidgetPhotoReference.url(for: name, in: shared)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { throw WallpaperError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        try (output as Data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if let transactionID {
            guard transactions[transactionID] != nil else { try? FileManager.default.removeItem(at: url); throw PhotoImportError.invalidTransaction }
            transactions[transactionID, default: []].insert(name)
            do { try journal(transactionID, directory: shared) }
            catch {
                transactions[transactionID]?.remove(name)
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }
        return name
    }
}
