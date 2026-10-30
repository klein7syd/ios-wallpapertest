import Foundation

// Target Membership：独立 macOS 原生状态检查，不加入正式 App / Widget。
enum PhotoAssetMaintenanceChecks {
    static func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "PhotoAssetMaintenanceChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func run() throws {
        var partial = PhotoImportProgress(total: 3)
        partial.succeeded("a"); partial.skipped(); partial.succeeded("b")
        try partial.validateResult()
        try require(partial.failed == 1 && partial.names == ["a", "b"], "Single failure is skipped without losing successful imports")
        var half = PhotoImportProgress(total: 2); half.succeeded("a"); half.skipped(); try half.validateResult()
        var majority = PhotoImportProgress(total: 3); majority.succeeded("a"); majority.skipped(); majority.skipped()
        do { try majority.validateResult(); throw AppearanceError.invalidStyle } catch PhotoImportError.majorityFailed { }
        var empty = PhotoImportProgress(total: 2); empty.skipped(); empty.skipped()
        do { try empty.validateResult(); throw AppearanceError.invalidStyle } catch PhotoImportError.noPhotos { }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoAssetChecks-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = FileManager.default
        let now = Date()
        func asset(marker: Bool = false, recent: Bool = false) throws -> String {
            let name = marker ? "marker-image-\(UUID().uuidString).png" : "widget-photo-\(UUID().uuidString).jpg"
            let folder = marker ? MarkerImageReference.directory(in: root) : WidgetPhotoReference.directory(in: root)
            try files.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try Data([1, 2, 3]).write(to: url)
            let date = recent ? now : now.addingTimeInterval(-1200)
            try files.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
            return name
        }
        let background = try asset(), rotation = try asset(), oldBackup = try asset()
        let defaultMarker = try asset(marker: true), widgetMarker = try asset(marker: true), taskMarker = try asset(marker: true)
        let undoPhoto = try asset(), undoMarker = try asset(marker: true)
        let orphan = try asset(), orphanMarker = try asset(marker: true), recent = try asset(recent: true)
        let repository = TodoRepository(directoryURL: root)
        _ = try repository.add(title: "带图片标记", marker: TodoMarker(kind: .image, imageName: taskMarker))
        let appearance = AppearanceRepository(directory: root)
        var value = TodoAppearance(); value.widget.backgroundPhotoName = oldBackup; try appearance.save(value)
        value.defaultMarker = TodoMarker(kind: .image, imageName: defaultMarker)
        value.widget.markerOverride = TodoMarker(kind: .image, imageName: widgetMarker)
        value.widget.backgroundPhotoName = background
        value.widget.photoRotation = WidgetAlbumRotation(title: "停用相册仍保留", photos: [rotation], anchor: now, enabled: false)
        try appearance.save(value)
        var history = EditorHistory<Set<String>>()
        history.synchronize([undoPhoto]); history.observe([undoMarker])
        let keep = history.retainedValues.reduce(into: Set<String>()) { $0.formUnion($1) }
        let result = try PhotoAssetGarbageCollector.collect(directory: root, retaining: keep, now: now)
        try require(result.deleted == [orphan, orphanMarker], "Only old unreferenced photos and marker images are collected")
        try require(result.existingPhotos == [background, rotation, oldBackup, undoPhoto, recent], "Current, dormant album, backup, undo and recent photos remain")
        let guarded = try asset()
        try Data("broken".utf8).write(to: repository.fileURL)
        do { _ = try PhotoAssetGarbageCollector.collect(directory: root, retaining: [], now: now); throw AppearanceError.invalidStyle }
        catch TodoDataError.unreadableDocument { }
        try require(files.fileExists(atPath: WidgetPhotoReference.directory(in: root).appendingPathComponent(guarded).path), "Unreadable todos skips the entire collection")
        try files.removeItem(at: repository.fileURL)
        _ = try repository.add(title: "恢复有效待办")
        try Data("broken".utf8).write(to: appearance.backupURL)
        do { _ = try PhotoAssetGarbageCollector.collect(directory: root, retaining: [], now: now); throw AppearanceError.invalidStyle }
        catch AppearanceError.unreadable { }
        try require(files.fileExists(atPath: WidgetPhotoReference.directory(in: root).appendingPathComponent(guarded).path), "Unreadable recoverable appearance backup skips deletion")
        print("PASS: album single/half/majority/all failure policy; old orphan collection; dormant/current/task/backup/undo/recent retention; fail-closed storage protection.")
    }
}
