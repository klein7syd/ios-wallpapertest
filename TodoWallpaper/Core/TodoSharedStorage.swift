import Foundation
import Darwin

enum TodoWidgetConstants {
    static let kind = "TodoWallpaperTasks"
    static let originalGroupID = "group.org.todowallpaper.app"
}

/// Shared by the app and extension. No fallback to an independent private store.
enum TodoSharedStorage {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "TodoAppGroupIdentifier") as? String
            ?? TodoWidgetConstants.originalGroupID
    }

    static func sharedDirectory() throws -> URL {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { throw TodoDataError.sharedUnavailable(groupID) }
        return container.appendingPathComponent("TodoWallpaper", isDirectory: true)
    }

    private static func migration() throws -> TodoMigration {
        TodoMigration(legacyDirectory: TodoRepository.defaultDirectory,
                      sharedDirectory: try sharedDirectory(), groupID: groupID)
    }

    static func appRepository() throws -> TodoRepository { try migration().prepare() }
    static func widgetRepository() throws -> TodoRepository {
        try TodoMigration.readyRepository(sharedDirectory: sharedDirectory(), groupID: groupID)
    }
    static func canRecover() -> Bool { (try? migration().recoveryRepository().canRecoverFromBackup()) ?? false }
    static func recover() throws { try migration().recoveryRepository().recoverFromBackup() }
}

private struct TodoMigrationReceipt: Codable {
    var version = 1
    let groupID: String
    let origin: String
    let verifiedItemCount: Int
}

/// Lock order: migration lock -> private repository -> shared repository.
/// Widgets only use the shared repository lock, and cannot write before ready.
struct TodoMigration {
    let legacyDirectory: URL
    let sharedDirectory: URL
    let groupID: String
    private var readyURL: URL { sharedDirectory.appendingPathComponent("migration-ready-v1.json") }
    private var acknowledgementURL: URL { legacyDirectory.appendingPathComponent("appgroup-migration-v1.json") }

    func prepare() throws -> TodoRepository {
        try FileManager.default.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
        let path = sharedDirectory.appendingPathComponent("migration-v1.lock").path
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_EXLOCK, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TodoDataError.lockFailed(errno) }
        defer { Darwin.close(descriptor) }
        guard legacyDirectory.standardizedFileURL != sharedDirectory.standardizedFileURL else { throw TodoDataError.migrationConflict }
        let acknowledged = try Self.readReceipt(at: acknowledgementURL, groupID: groupID)
        let ready = try Self.readReceipt(at: readyURL, groupID: groupID)
        let shared = TodoRepository(directoryURL: sharedDirectory, requiresExistingFile: true)

        if ready != nil || acknowledged != nil {
            // Already migrated: a missing/broken shared file must NEVER cause a
            // stale Stage-B copy to be imported again or an empty file to appear.
            let document = try shared.load()
            let receipt = ready ?? TodoMigrationReceipt(groupID: groupID, origin: "verified-existing-shared", verifiedItemCount: document.items.count)
            if ready == nil { try Self.write(receipt, to: readyURL) }
            if acknowledged == nil { try Self.write(receipt, to: acknowledgementURL) }
            return shared
        }

        let source: Data
        let origin: String
        if let existing = try shared.existingSnapshot() {
            // Resume an interrupted migration. Preserve any existing shared data.
            source = existing.data
            origin = "verified-existing-shared"
        } else if let legacy = try TodoRepository(directoryURL: legacyDirectory).existingSnapshot() {
            source = legacy.data
            origin = "stage-b-private-container"
            let saved = sharedDirectory.appendingPathComponent("stage-b-original-v1.json")
            if !FileManager.default.fileExists(atPath: saved.path) { try Self.write(source, to: saved) }
        } else {
            source = try JSONEncoder().encode(TodoDocument())
            origin = "fresh-install"
        }
        let document = try shared.installIfAbsent(source)
        // installIfAbsent verified the full copied bytes and decoded UUID/order/
        // title/state/schema. Publish ready only AFTER that succeeds.
        let receipt = TodoMigrationReceipt(groupID: groupID, origin: origin, verifiedItemCount: document.items.count)
        try Self.write(receipt, to: readyURL)
        try Self.write(receipt, to: acknowledgementURL)
        // Stage-B main and backup files remain untouched in the private container.
        return shared
    }

    static func readyRepository(sharedDirectory: URL, groupID: String) throws -> TodoRepository {
        let ready = sharedDirectory.appendingPathComponent("migration-ready-v1.json")
        guard try readReceipt(at: ready, groupID: groupID) != nil else { throw TodoDataError.migrationRequired }
        let repository = TodoRepository(directoryURL: sharedDirectory, requiresExistingFile: true)
        _ = try repository.load()
        return repository
    }

    func recoveryRepository() throws -> TodoRepository {
        // A prior migration acknowledgement makes shared storage authoritative,
        // even if its document/ready file is damaged. Never restore stale private
        // data into it automatically.
        let migrated = FileManager.default.fileExists(atPath: acknowledgementURL.path)
            || FileManager.default.fileExists(atPath: readyURL.path)
            || FileManager.default.fileExists(atPath: sharedDirectory.appendingPathComponent("todos-v1.json").path)
        return TodoRepository(directoryURL: migrated ? sharedDirectory : legacyDirectory, requiresExistingFile: migrated)
    }

    private static func readReceipt(at url: URL, groupID: String) throws -> TodoMigrationReceipt? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let receipt: TodoMigrationReceipt
        do { receipt = try JSONDecoder().decode(TodoMigrationReceipt.self, from: Data(contentsOf: url)) }
        catch { throw TodoDataError.migrationMetadataInvalid }
        guard receipt.version == 1 else { throw TodoDataError.migrationMetadataInvalid }
        guard receipt.groupID == groupID else { throw TodoDataError.migrationConflict }
        return receipt
    }

    private static func write(_ value: TodoMigrationReceipt, to url: URL) throws {
        try write(JSONEncoder().encode(value), to: url)
    }

    private static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
