import Foundation
import Darwin

/// The UI owns no persistence rules. This directory can later be migrated to
/// an App Group without changing the document schema or item identities.
struct TodoRepository {
    let directoryURL: URL
    var requiresExistingFile = false
    var fileURL: URL { directoryURL.appendingPathComponent("todos-v1.json") }
    var backupURL: URL { directoryURL.appendingPathComponent("todos-v1.backup.json") }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("TodoWallpaper", isDirectory: true)
    }

    func load() throws -> TodoDocument {
        try withLock { try readDocument() }
    }

    func add(title: String, marker: TodoMarker? = nil) throws -> TodoDocument {
        let title = try validatedTitle(title)
        try marker?.validate()
        return try update { document in
            let now = Date()
            document.items.append(TodoItem(id: UUID(), title: title, marker: marker, isCompleted: false, createdAt: now, updatedAt: now))
        }
    }

    func rename(id: UUID, title: String) throws -> TodoDocument {
        let title = try validatedTitle(title)
        return try update { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw TodoDataError.missingItem }
            document.items[index].title = title
            document.items[index].updatedAt = Date()
        }
    }

    func edit(id: UUID, title: String, marker: TodoMarker?) throws -> TodoDocument {
        let title = try validatedTitle(title)
        try marker?.validate()
        return try update { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw TodoDataError.missingItem }
            document.items[index].title = title
            document.items[index].marker = marker
            document.items[index].updatedAt = Date()
        }
    }

    func setCompleted(id: UUID, completed: Bool) throws -> TodoDocument {
        try update { document in
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw TodoDataError.missingItem }
            document.items[index].isCompleted = completed
            document.items[index].updatedAt = Date()
        }
    }

    func delete(ids: Set<UUID>) throws -> TodoDocument {
        try update { document in
            guard ids.isSubset(of: Set(document.items.map(\.id))) else { throw TodoDataError.missingItem }
            document.items.removeAll { ids.contains($0.id) }
        }
    }

    func reorder(ids: [UUID]) throws -> TodoDocument {
        try update { document in
            guard ids.count == document.items.count, Set(ids).count == ids.count,
                  Set(ids) == Set(document.items.map(\.id)) else { throw TodoDataError.invalidOrder }
            let byID = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0) })
            document.items = try ids.map { id in
                guard let item = byID[id] else { throw TodoDataError.invalidOrder }
                return item
            }
        }
    }

    private func validatedTitle(_ value: String) throws -> String {
        let title = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 200 else { throw TodoDataError.invalidTitle }
        return title
    }

    private func validate(_ document: TodoDocument) throws {
        guard document.schemaVersion == 1 else { throw TodoDataError.unsupportedSchema(document.schemaVersion) }
        guard Set(document.items.map(\.id)).count == document.items.count else { throw TodoDataError.invalidDocument }
        for item in document.items {
            do { try item.marker?.validate() } catch { throw TodoDataError.invalidDocument }
            guard (try? validatedTitle(item.title)) == item.title else { throw TodoDataError.invalidDocument }
        }
    }

    private func readDocument() throws -> TodoDocument {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard !requiresExistingFile, !FileManager.default.fileExists(atPath: backupURL.path) else { throw TodoDataError.primaryMissing }
            return TodoDocument()
        }
        return try decodeDocument(Data(contentsOf: fileURL))
    }

    private func decodeDocument(_ data: Data) throws -> TodoDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Read schema first, even if a future version changes all item fields.
        struct Header: Decodable { let schemaVersion: Int }
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw TodoDataError.unreadableDocument }
        guard header.schemaVersion == 1 else { throw TodoDataError.unsupportedSchema(header.schemaVersion) }
        let document: TodoDocument
        do { document = try decoder.decode(TodoDocument.self, from: data) }
        catch { throw TodoDataError.unreadableDocument }
        try validate(document)
        return document
    }

    func existingSnapshot() throws -> (document: TodoDocument, data: Data)? {
        try withLock {
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                guard !FileManager.default.fileExists(atPath: backupURL.path) else { throw TodoDataError.primaryMissing }
                return nil
            }
            return (try readDocument(), try Data(contentsOf: fileURL))
        }
    }

    /// Only used before migration publishes its ready receipt. Never replaces
    /// an existing shared document, even if another process arrived first.
    func installIfAbsent(_ data: Data) throws -> TodoDocument {
        try withLock {
            if FileManager.default.fileExists(atPath: fileURL.path) { return try readDocument() }
            guard !FileManager.default.fileExists(atPath: backupURL.path) else { throw TodoDataError.primaryMissing }
            let document = try decodeDocument(data)
            try writeAtomically(data, to: fileURL)
            guard try Data(contentsOf: fileURL) == data else { throw TodoDataError.migrationConflict }
            _ = try readDocument()
            return document
        }
    }

    func canRecoverFromBackup() -> Bool {
        (try? withLock { recoveryPermitted() }) ?? false
    }

    /// An explicit user action; the damaged file is archived before restore.
    func recoverFromBackup() throws {
        try withLock {
            guard recoveryPermitted() else { throw TodoDataError.recoveryUnavailable }
            let backup = try Data(contentsOf: backupURL)
            _ = try decodeDocument(backup)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let archive = directoryURL.appendingPathComponent("recovery-preserved-\(UUID().uuidString).json")
                try writeAtomically(Data(contentsOf: fileURL), to: archive)
            }
            try writeAtomically(backup, to: fileURL)
            _ = try readDocument()
        }
    }

    private func recoveryPermitted() -> Bool {
        guard let backup = try? Data(contentsOf: backupURL), (try? decodeDocument(backup)) != nil else { return false }
        if !FileManager.default.fileExists(atPath: fileURL.path) { return true }
        do { _ = try readDocument(); return false }
        catch TodoDataError.unreadableDocument { return true }
        catch TodoDataError.invalidDocument { return true }
        catch { return false } // Never roll back a future schema or an I/O error.
    }

    private func update(_ mutation: (inout TodoDocument) throws -> Void) throws -> TodoDocument {
        try withLock {
            var document = try readDocument()
            try mutation(&document)
            try validate(document)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let newData = try encoder.encode(document)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                // Only a document successfully read and validated above can be
                // promoted to backup. A corrupt/newer file is never overwritten.
                try writeAtomically(Data(contentsOf: fileURL), to: backupURL)
            }
            try writeAtomically(newData, to: fileURL)
            return document
        }
    }

    private func writeAtomically(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func withLock<T>(_ action: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let path = directoryURL.appendingPathComponent("todos-v1.lock").path
        // Reuse the BSD locking approach already compiled in the R1 baseline.
        let descriptor = Darwin.open(path, O_CREAT | O_RDWR | O_EXLOCK, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TodoDataError.lockFailed(errno) }
        defer { Darwin.close(descriptor) }
        return try action()
    }
}
