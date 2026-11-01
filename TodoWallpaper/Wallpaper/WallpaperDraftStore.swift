import Foundation

struct WallpaperLoadedDraft: Sendable {
    let draft: WallpaperDraft
    let photoURL: URL?
}

/// A private, local wallpaper draft. Never reads or writes the App Group todo files.
actor WallpaperDraftStore {
    private let files = FileManager.default
    private let initialSettings: WallpaperSettings
    let directory: URL
    let exportDirectory: URL

    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("WallpaperEditor", isDirectory: true),
         exportDirectory: URL = URL.cachesDirectory.appendingPathComponent("WallpaperExports", isDirectory: true),
         initialSettings: WallpaperSettings = WallpaperSettings()) {
        self.initialSettings = initialSettings
        self.directory = directory
        self.exportDirectory = exportDirectory
    }

    func load() throws -> WallpaperLoadedDraft {
        let url = directory.appendingPathComponent("draft-v1.json")
        guard files.fileExists(atPath: url.path) else {
            return WallpaperLoadedDraft(draft: WallpaperDraft(settings: initialSettings), photoURL: nil)
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

    // actor内比较源文件，首次恢复同一底图时也保留原裁剪，不重复导入/解码。
    func photoMatches(_ data: Data, name: String?) throws -> Bool {
        guard let url = try photoURL(for: name), files.fileExists(atPath: url.path) else { return false }
        return try Data(contentsOf: url, options: .mappedIfSafe) == data
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
        // Archive a readable 0.3.0 draft before first writing the optional ratio field.
        let original = directory.appendingPathComponent("draft-before-d34.json")
        if files.fileExists(atPath: url.path), !files.fileExists(atPath: original.path),
           let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
           let settings = object["settings"] as? [String: Any], settings["canvasAspect"] == nil {
            try files.copyItem(at: url, to: original); protect(original)
        }
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

    // 历史归档保留的不只是参数；归档引用的源图也必须可恢复。
    private func archivedPhotoReferences() throws -> Set<String> {
        guard files.fileExists(atPath: directory.path) else { return [] }
        var names = Set<String>()
        for url in try files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            where url.pathExtension == "json" && (url.lastPathComponent == "draft-v1.json" || url.lastPathComponent == "draft-before-d34.json" || url.lastPathComponent.hasPrefix("draft-preserved-")) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw WallpaperError.invalidDraft }
            let draft = try JSONDecoder().decode(WallpaperDraft.self, from: Data(contentsOf: url))
            guard draft.schemaVersion == 1 else { throw WallpaperError.unsupportedDraft }
            if let name = draft.photoFileName { _ = try photoURL(for: name); names.insert(name) }
        }
        return names
    }

    func cleanExpired(keeping photoName: String?) {
        let threshold = Date().addingTimeInterval(-86400)
        // 任一归档不可读时，不推断它没有照片；本轮只清理可再生成的导出缓存。
        let retained = try? archivedPhotoReferences().union(Set([photoName].compactMap { $0 }))
        for root in [directory, exportDirectory] {
            guard let urls = try? files.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in urls {
                let isPhoto = url.lastPathComponent.hasPrefix("photo-") && url.pathExtension == "source"
                let isExport = url.lastPathComponent.hasPrefix("TodoWallpaper-") && url.pathExtension == "png"
                guard isPhoto || isExport else { continue }
                if isPhoto {
                    guard let retained, !retained.contains(url.lastPathComponent) else { continue }
                }
                guard url.lastPathComponent != photoName,
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
