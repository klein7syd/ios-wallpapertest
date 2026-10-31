import Foundation

// Target Membership：App + Widget；文件回收仅由主 App 的后台 actor 调用。
enum PhotoAssetReferences {
    static func marker(_ value: TodoMarker?) -> Set<String> { Set([value?.imageName].compactMap { $0 }) }
    static func widget(_ value: WidgetAppearance) -> Set<String> {
        marker(value.markerOverride).union([value.backgroundPhotoName].compactMap { $0 })
            .union(value.photoRotation?.photos ?? [])
    }
    static func appearance(_ value: TodoAppearance) -> Set<String> { marker(value.defaultMarker).union(widget(value.widget)).union(value.lianxin.map(widget) ?? []) }
    static func items(_ values: [TodoItem]) -> Set<String> { values.reduce(into: Set<String>()) { $0.formUnion(marker($1.marker)) } }
}

enum PhotoImportError: LocalizedError {
    case noPhotos, majorityFailed, invalidTransaction
    var errorDescription: String? {
        switch self {
        case .noPhotos: return "没有成功读取的照片，本次导入已撤回。"
        case .majorityFailed: return "超过一半照片读取失败，本次导入已撤回，请检查 iCloud 下载后重试。"
        case .invalidTransaction: return "照片导入会话已结束，请重新选择相册。"
        }
    }
}

struct PhotoImportProgress {
    let total: Int
    private(set) var names: [String] = []
    private(set) var failed = 0
    mutating func succeeded(_ name: String) { names.append(name) }
    mutating func skipped() { failed += 1 }
    func validateResult() throws {
        guard !names.isEmpty else { throw PhotoImportError.noPhotos }
        guard failed * 2 <= total else { throw PhotoImportError.majorityFailed }
    }
}

struct PhotoAssetCollection {
    let deleted: Set<String>
    let existingPhotos: Set<String>
}

enum PhotoAssetGarbageCollector {
    static func collect(directory: URL, retaining: Set<String>, now: Date = .now) throws -> PhotoAssetCollection {
        let files = FileManager.default
        // 两个权威主文件与可恢复备份必须全部可验证；失败时尚未进行任何删除。
        let todo = TodoRepository(directoryURL: directory, requiresExistingFile: true)
        let look = AppearanceRepository(directory: directory)
        guard files.fileExists(atPath: look.fileURL.path) else { throw AppearanceError.unreadable }
        let keep = try retaining.union(todo.assetReferences()).union(look.assetReferences())
        var candidates: [URL] = [], existing = Set<String>()
        for folder in [WidgetPhotoReference.directory(in: directory), MarkerImageReference.directory(in: directory)] {
            if files.fileExists(atPath: folder.path) {
                let folderValues = try folder.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard folderValues.isSymbolicLink != true, folderValues.isDirectory == true else { throw AppearanceError.unreadable }
                for url in try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey]) {
                    let name = url.lastPathComponent
                    guard folder.lastPathComponent == "WidgetPhotos" ? WidgetPhotoReference.isValid(name) : MarkerImageReference.isValid(name) else { continue }
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .creationDateKey, .contentModificationDateKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                    if WidgetPhotoReference.isValid(name) { existing.insert(name) }
                    guard !keep.contains(name), let created = values.creationDate, let modified = values.contentModificationDate,
                          now.timeIntervalSince(max(created, modified)) >= 600 else { continue }
                    candidates.append(url)
                }
            }
        }
        var deleted = Set<String>()
        for url in candidates {
            do { try files.removeItem(at: url); deleted.insert(url.lastPathComponent); existing.remove(url.lastPathComponent) }
            catch { /* 删除失败保留文件；后续回收可以重试。 */ }
        }
        return PhotoAssetCollection(deleted: deleted, existingPhotos: existing)
    }
}
