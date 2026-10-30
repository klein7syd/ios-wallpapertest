import Foundation

enum MigrationChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "MigrationChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }

    static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TodoMigration-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let old = TodoRepository(directoryURL: root.appendingPathComponent("private"))
        let sharedURL = root.appendingPathComponent("shared")
        let migration = TodoMigration(legacyDirectory: old.directoryURL, sharedDirectory: sharedURL, groupID: "group.fixture.todo")
        _ = try old.add(title: "阶段 B 原有事项 🧩")
        var before = try old.add(title: "保留顺序与状态")
        let first = before.items[0].id, second = before.items[1].id
        _ = try old.setCompleted(id: first, completed: true)
        before = try old.reorder(ids: [second,first])
        let original = try Data(contentsOf: old.fileURL)

        // A widget arriving first must not seed an empty shared file.
        do { _ = try TodoMigration.readyRepository(sharedDirectory: sharedURL, groupID: "group.fixture.todo"); throw NSError(domain: "ExpectedMigrationGate", code: 1) }
        catch TodoDataError.migrationRequired { }
        try require(!FileManager.default.fileExists(atPath: sharedURL.appendingPathComponent("todos-v1.json").path), "Widget must not create data before migration")

        let snapshot = try migration.prepareSnapshot()
        let shared = snapshot.repository
        let migrated = snapshot.document
        try require(migrated.items == before.items, "UUID, content, dates, order and completion must migrate unchanged")
        try require(tryData(shared.fileURL) == original && tryData(old.fileURL) == original, "Exact data copied; private source untouched")
        let widgetSnapshot = try TodoMigration.readySnapshot(sharedDirectory: sharedURL, groupID: "group.fixture.todo")
        try require(widgetSnapshot.document.items == migrated.items, "Widget reuses the document already validated by the readiness path")
        _ = try shared.add(title: "共享容器中的新事项")
        _ = try shared.setCompleted(id: second, completed: true)
        let newer = try Data(contentsOf: shared.fileURL)
        let repeated = try migration.prepareSnapshot()
        try require(repeated.document.items.count == migrated.items.count + 1, "Repeated migration returns the current shared snapshot, not a stale cache")
        try require(snapshot.document.items == migrated.items, "A prepared snapshot needs no second disk read after concurrent writes")
        try require(tryData(shared.fileURL) == newer && tryData(old.fileURL) == original, "Repeat migration must not overwrite newer shared data")

        // Resume after copy succeeded but before either receipt was committed.
        try FileManager.default.removeItem(at: sharedURL.appendingPathComponent("migration-ready-v1.json"))
        try FileManager.default.removeItem(at: old.directoryURL.appendingPathComponent("appgroup-migration-v1.json"))
        _ = try migration.prepare()
        try require(tryData(shared.fileURL) == newer, "Interrupted migration must keep existing shared contents")

        // Once acknowledged, missing shared data must not reimport stale private data.
        try FileManager.default.removeItem(at: shared.fileURL)
        do { _ = try migration.prepare(); throw NSError(domain: "ExpectedMissingShared", code: 1) }
        catch TodoDataError.primaryMissing { }
        try require(!FileManager.default.fileExists(atPath: shared.fileURL.path), "Missing shared file must not be recreated from old data")
        try newer.write(to: shared.fileURL, options: .atomic)
        let wrong = TodoMigration(legacyDirectory: old.directoryURL, sharedDirectory: root.appendingPathComponent("wrong-group"), groupID: "group.fixture.other")
        do { _ = try wrong.prepare(); throw NSError(domain: "ExpectedGroupMismatch", code: 1) }
        catch TodoDataError.migrationConflict { }

        // Separate processes exercise the same production cross-process lock.
        let initialCount = try shared.load().items.count
        var workers: [Process] = []
        for index in 0..<3 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            process.arguments = ["--concurrent-worker", sharedURL.path, String(index)]
            try process.run()
            workers.append(process)
        }
        for process in workers { process.waitUntilExit(); try require(process.terminationStatus == 0, "Concurrent writer failed") }
        let concurrent = try shared.load()
        try require(concurrent.items.count == initialCount + 30, "Concurrent writes must not lose tasks")
        try require(Set(concurrent.items.map(\.id)).count == concurrent.items.count, "No duplicate task identities")
        let brokenShared = Data("broken-shared".utf8)
        try brokenShared.write(to: shared.fileURL)
        let sharedRecovery = try migration.recoveryRepository()
        try require(sharedRecovery.directoryURL == sharedURL && sharedRecovery.canRecoverFromBackup(), "Recovery after migration must use shared backup")
        try sharedRecovery.recoverFromBackup()
        _ = try migration.prepare()
        try require(tryData(old.fileURL) == original, "Shared recovery must leave private source untouched")

        // A damaged private source is not migrated; explicit valid backup recovery works.
        let badOld = TodoRepository(directoryURL: root.appendingPathComponent("bad-private"))
        _ = try badOld.add(title: "可恢复事项")
        _ = try badOld.add(title: "后一次修改")
        let corrupt = Data("damaged-json".utf8)
        try corrupt.write(to: badOld.fileURL)
        let bad = TodoMigration(legacyDirectory: badOld.directoryURL, sharedDirectory: root.appendingPathComponent("bad-shared"), groupID: "group.fixture.todo")
        do { _ = try bad.prepare(); throw NSError(domain: "ExpectedCorruptSource", code: 1) }
        catch TodoDataError.unreadableDocument { }
        try require(tryData(badOld.fileURL) == corrupt, "Failed migration must preserve original bytes")
        try require(badOld.canRecoverFromBackup(), "Valid backup recovery must be available")
        try badOld.recoverFromBackup()
        let recovered = try bad.prepare().load()
        try require(recovered.items.count == 1 && recovered.items[0].title == "可恢复事项", "Explicit backup restore must migrate recovered contents")
        let archived = try FileManager.default.contentsOfDirectory(at: badOld.directoryURL, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("recovery-preserved-") }
        try require(archived.count == 1 && tryData(archived[0]) == corrupt, "Damaged source archived before recovery")

        let future = Data("{\"schemaVersion\":99,\"futureFormat\":true}".utf8)
        try future.write(to: badOld.fileURL)
        try require(!badOld.canRecoverFromBackup(), "Future schemas cannot be rolled back using an old backup")
        print("PASS: byte-exact migration, stable identities/order/state, widget readiness gate, interrupted/repeated migration, changed-group/missing-data protection, 3-process writes and explicit recovery.")
    }

    private static func tryData(_ url: URL) -> Data? { try? Data(contentsOf: url) }
}
