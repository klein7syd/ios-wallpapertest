import Foundation
import Darwin

/// The UI owns no persistence rules. This directory can later be migrated to
/// an App Group without changing the document schema or item identities.
struct TodoRepository {
    let directoryURL: URL
    var fileURL: URL { directoryURL.appendingPathComponent("todos-v1.json") }
    var backupURL: URL { directoryURL.appendingPathComponent("todos-v1.backup.json") }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("TodoWallpaper", isDirectory: true)
    }

    func load() throws -> TodoDocument {
        try withLock { try readDocument() }
    }

    func add(title: String) throws -> TodoDocument {
        let title = try validatedTitle(title)
        return try update { document in
            let now = Date()
            document.items.append(TodoItem(id: UUID(), title: title, isCompleted: false, createdAt: now, updatedAt: now))
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
            guard (try? validatedTitle(item.title)) == item.title else { throw TodoDataError.invalidDocument }
        }
    }

    private func readDocument() throws -> TodoDocument {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard !FileManager.default.fileExists(atPath: backupURL.path) else { throw TodoDataError.primaryMissing }
            return TodoDocument()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document: TodoDocument
        do { document = try decoder.decode(TodoDocument.self, from: data) }
        catch { throw TodoDataError.unreadableDocument }
        try validate(document)
        return document
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
