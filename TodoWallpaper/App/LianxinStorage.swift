// Target Membership：仅 App。私有资料的版本检查、备份和媒体读写都在 actor 中。
import Foundation

struct LianxinLoadedProfile: Sendable {
    var profile: LianxinProfile
    var photo: Data?
    var missingPhoto: Bool
}

actor LianxinStorage {
    private let root: URL
    private var writable = false
    private var revision: UInt64 = 0
    private var collectedAt = Date.distantPast
    init(directory: URL = URL.applicationSupportDirectory.appendingPathComponent("Lianxin", isDirectory: true)) { root = directory }
    private var file: URL { root.appendingPathComponent("profile-v1.json") }
    private var backup: URL { root.appendingPathComponent("profile-v1.backup.json") }
    private func directory() throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func decode(_ data: Data) throws -> LianxinProfile {
        let value = try JSONDecoder().decode(LianxinProfile.self, from: data)
        guard value.schemaVersion == nil || value.schemaVersion == 1 else { throw LianxinError.storage }
        return value
    }
    func load() throws -> LianxinLoadedProfile {
        writable = false
        _ = try directory()
        var profile: LianxinProfile
        if FileManager.default.fileExists(atPath: file.path) {
            profile = try decode(Data(contentsOf: file))
        } else {
            guard !FileManager.default.fileExists(atPath: backup.path) else { throw LianxinError.storage }
            profile = LianxinProfile()
        }
        if profile.roleNotesMigrated != true { profile.migrateRoleNotes() }
        profile.schemaVersion = 1
        // 照片损坏只影响底图，不阻断仍可读取的角色和话语。
        let photo = profile.photoName.flatMap { try? photoData($0) }
        writable = true
        return LianxinLoadedProfile(profile: profile, photo: photo, missingPhoto: profile.photoName != nil && photo == nil)
    }
    func canRecover() -> Bool { (try? decode(Data(contentsOf: backup))) != nil }
    func recover() throws {
        let data = try Data(contentsOf: backup)
        _ = try decode(data)
        if FileManager.default.fileExists(atPath: file.path) {
            let preserved = root.appendingPathComponent("profile-preserved-\(UUID()).json")
            try Data(contentsOf: file).write(to: preserved, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        writable = false
    }
    func save(_ profile: LianxinProfile, revision next: UInt64) throws {
        try Task.checkCancellation()
        guard writable else { throw LianxinError.storage }
        guard next > revision else { return }
        _ = try directory()
        var value = profile
        value.schemaVersion = 1
        let data = try JSONEncoder().encode(value)
        if FileManager.default.fileExists(atPath: file.path) {
            let previous = try Data(contentsOf: file)
            _ = try decode(previous) // 损坏/未来版本绝不能被自动覆盖。
            if previous == data { revision = next; return }
            try previous.write(to: backup, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } else if FileManager.default.fileExists(atPath: backup.path) { throw LianxinError.storage }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        revision = next
        collectUnusedPhotos()
    }
    #if os(iOS)
    func importPhoto(_ data: Data) async throws -> (String, Data) {
        let root = try directory()
        let name = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: root)
        do {
            try Task.checkCancellation()
            try data.write(to: root.appendingPathComponent(name + ".source"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return (name, try Data(contentsOf: WidgetPhotoReference.url(for: name, in: root)))
        } catch { removePhoto(name); throw error }
    }
    #endif
    func photoData(_ name: String?, original: Bool = false) throws -> Data? {
        guard let name else { return nil }
        let thumbnail = try WidgetPhotoReference.url(for: name, in: root)
        let source = root.appendingPathComponent(name + ".source")
        return try Data(contentsOf: original && FileManager.default.fileExists(atPath: source.path) ? source : thumbnail)
    }
    func sharedPhotoData(name: String, directory: URL) throws -> Data {
        try Data(contentsOf: WidgetPhotoReference.url(for: name, in: directory))
    }
    func publish(_ content: LianxinPublication, directory: URL) throws {
        try Task.checkCancellation()
        try content.save(directory: directory)
    }
    func currentContent(directory: URL) throws -> LianxinPublication? { try LianxinPublication.load(directory: directory) }
    private func retainedPhotos() throws -> Set<String> {
        var names = Set<String>()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        for url in files where url.lastPathComponent == file.lastPathComponent || url.lastPathComponent == backup.lastPathComponent || url.lastPathComponent.hasPrefix("profile-preserved-") {
            let profile = try decode(Data(contentsOf: url))
            if let name = profile.photoName { names.insert(name) }
        }
        return names
    }
    func removePhoto(_ name: String?) {
        guard let name, let keep = try? retainedPhotos(), !keep.contains(name),
              let url = try? WidgetPhotoReference.url(for: name, in: root) else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name + ".source"))
    }
    private func collectUnusedPhotos() {
        guard Date.now.timeIntervalSince(collectedAt) > 600 else { return }
        collectedAt = .now
        // 任一备份/恢复档案不可读就整轮跳过，不能误删恢复所需原图。
        guard let keep = try? retainedPhotos(),
              let urls = try? FileManager.default.contentsOfDirectory(at: WidgetPhotoReference.directory(in: root), includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in urls where WidgetPhotoReference.isValid(url.lastPathComponent) && !keep.contains(url.lastPathComponent) {
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  Date.now.timeIntervalSince(date) > 600 else { continue }
            removePhoto(url.lastPathComponent)
        }
    }
}
