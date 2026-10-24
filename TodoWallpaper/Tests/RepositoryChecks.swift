import Foundation

@main
enum RepositoryChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw NSError(domain: "RepositoryChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TodoWallpaper-Checks-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TodoRepository(directoryURL: root)
        let initial = try repository.load()
        try require(initial.items.isEmpty, "New document must start empty")
        let first = try repository.add(title: "  练习中文与 emoji 🧩  ")
        let a = first.items[0].id
        _ = try repository.add(title: "第二件事")
        let loaded = try TodoRepository(directoryURL: root).load()
        let b = loaded.items[1].id
        try require(loaded.items[0].title == "练习中文与 emoji 🧩", "Trim and Unicode round trip")
        _ = try repository.setCompleted(id: a, completed: true)
        _ = try repository.rename(id: a, title: "编辑后")
        var reloaded = try TodoRepository(directoryURL: root).load()
        try require(reloaded.items[0].id == a && reloaded.items[0].title == "编辑后" && reloaded.items[0].isCompleted, "Edit must retain identity and completion")
        _ = try repository.setCompleted(id: a, completed: false)
        let moved = try TodoOrder.moving([a,b], from: IndexSet(integer: 0), to: 2)
        try require(moved == [b,a], "Drag reorder semantics")
        _ = try repository.reorder(ids: moved)
        reloaded = try TodoRepository(directoryURL: root).load()
        try require(reloaded.items.map(\.id) == [b,a] && !reloaded.items[1].isCompleted, "Restore/order persist across repository instance")
        do { _ = try repository.reorder(ids: [a,a]); throw NSError(domain: "ExpectedInvalidOrder", code: 1) }
        catch TodoDataError.invalidOrder { }
        _ = try repository.delete(ids: [b])
        reloaded = try repository.load()
        try require(reloaded.items.count == 1 && reloaded.items[0].id == a, "Delete persists")
        let validData = try Data(contentsOf: repository.fileURL)
        let backup = try JSONSerialization.jsonObject(with: Data(contentsOf: repository.backupURL)) as! [String:Any]
        try require((backup["items"] as? [[String:Any]])?.count == 2, "Previous valid document backed up")
        do { _ = try repository.add(title: " \n "); throw NSError(domain: "ExpectedInvalidTitle", code: 1) }
        catch TodoDataError.invalidTitle { }
        try require(tryData(repository.fileURL) == validData, "Rejected edit must leave file unchanged")
        var future = try JSONSerialization.jsonObject(with: validData) as! [String:Any]
        future["schemaVersion"] = 99
        let futureData = try JSONSerialization.data(withJSONObject: future)
        try futureData.write(to: repository.fileURL)
        do { _ = try repository.add(title: "不能覆盖未来版本"); throw NSError(domain: "ExpectedUnsupportedSchema", code: 1) }
        catch TodoDataError.unsupportedSchema(99) { }
        try require(tryData(repository.fileURL) == futureData, "Unknown schema must never be reset")
        let corrupt = Data("not-json".utf8)
        try corrupt.write(to: repository.fileURL)
        do { _ = try repository.add(title: "不能覆盖损坏文件"); throw NSError(domain: "ExpectedUnreadable", code: 1) }
        catch TodoDataError.unreadableDocument { }
        try require(tryData(repository.fileURL) == corrupt, "Corrupt file must be preserved")
        try FileManager.default.removeItem(at: repository.fileURL)
        do { _ = try repository.load(); throw NSError(domain: "ExpectedBackupProtection", code: 1) }
        catch TodoDataError.primaryMissing { }
        print("PASS: CRUD, Unicode, completion/restore, reorder, fresh-instance persistence, backup, rejected writes, unknown schema and corruption preservation.")
    }

    private static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
