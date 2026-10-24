import Foundation

struct WallpaperLoadedDraft: Sendable {
    let draft: WallpaperDraft
    let photoURL: URL?
}

/// A private, local wallpaper draft. Never reads or writes the App Group todo files.
actor WallpaperDraftStore {
    private let files = FileManager.default
    let directory: URL
    let exportDirectory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("WallpaperEditor", isDirectory: true),
         exportDirectory: URL = URL.cachesDirectory.appendingPathComponent("WallpaperExports", isDirectory: true)) {
        self.directory = directory
        self.exportDirectory = exportDirectory
    }

    func load() throws -> WallpaperLoadedDraft {
        let url = directory.appendingPathComponent("draft-v1.json")
        guard files.fileExists(atPath: url.path) else {
            return WallpaperLoadedDraft(draft: WallpaperDraft(), photoURL: nil)
        }
        let data = try Data(contentsOf: url)
        guard let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = header["schemaVersion"] as? Int else { throw WallpaperError.invalidDraft }
        guard version == 1 else { throw WallpaperError.unsupportedDraft }
        guard let draft = try? JSONDecoder().decode(WallpaperDraft.self, from: data) else { throw WallpaperError.invalidDraft }
        _ = try draft.settings.validated()
        let photo = try photoURL(for: draft.photoFileName)
        if let photo { _ = try WallpaperRenderer.photoInfo(at: photo) }
        return WallpaperLoadedDraft(draft: draft, photoURL: photo)
    }

    func photoURL(for name: String?) throws -> URL? {
        guard let name else { return nil }
        guard name.hasPrefix("photo-"), name.hasSuffix(".source"),
              name == URL(fileURLWithPath: name).lastPathComponent,
              !name.contains("/") && !name.contains("\\") else { throw WallpaperError.invalidDraft }
        return directory.appendingPathComponent(name)
    }

    func importPhoto(_ data: Data) throws -> URL {
        guard data.count <= 80 * 1024 * 1024 else { throw WallpaperError.photoTooLarge }
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("photo-\(UUID()).source")
        do {
            try data.write(to: url, options: .atomic)
            _ = try WallpaperRenderer.photoInfo(at: url)
            protect(url)
            return url
        } catch {
            try? files.removeItem(at: url)
            throw error
        }
    }

    func save(_ draft: WallpaperDraft, replaceUnreadable: Bool = false) throws {
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("draft-v1.json")
        if files.fileExists(atPath: url.path) {
            do { _ = try load() }
            catch {
                guard replaceUnreadable else { throw error }
                let preserved = directory.appendingPathComponent("draft-preserved-\(UUID()).json")
                try files.copyItem(at: url, to: preserved)
                protect(preserved)
            }
        }
        var validated = draft
        validated.settings = try draft.settings.validated()
        _ = try photoURL(for: draft.photoFileName)
        try JSONEncoder().encode(validated).write(to: url, options: .atomic)
        protect(url)
    }

    func clearExportCache() throws {
        guard files.fileExists(atPath: exportDirectory.path) else { return }
        for url in try files.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)
            where url.pathExtension == "png" && url.lastPathComponent.hasPrefix("TodoWallpaper-") {
            try files.removeItem(at: url)
        }
    }

    func cleanExpired(keeping photoName: String?) {
        let threshold = Date().addingTimeInterval(-86400)
        for root in [directory, exportDirectory] {
            guard let urls = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in urls {
                let isPhoto = url.lastPathComponent.hasPrefix("photo-") && url.pathExtension == "source"
                let isExport = url.lastPathComponent.hasPrefix("TodoWallpaper-") && url.pathExtension == "png"
                guard isPhoto || isExport, url.lastPathComponent != photoName,
                      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let date = values.contentModificationDate, date < threshold else { continue }
                try? files.removeItem(at: url)
            }
        }
    }

    private func protect(_ url: URL) {
        #if os(iOS)
        try? files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }
}
