import Foundation

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date
    var updatedAt: Date
}

struct TodoDocument: Codable {
    var schemaVersion = 1
    var items: [TodoItem] = []
}

enum TodoDataError: LocalizedError {
    case invalidTitle, missingItem, invalidOrder, invalidDocument
    case unsupportedSchema(Int), unreadableDocument, primaryMissing, lockFailed(Int32)
    case sharedUnavailable(String), migrationRequired, migrationConflict, migrationMetadataInvalid
    case recoveryUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidTitle: return "待办内容需要 1–200 个字符。"
        case .missingItem: return "这条待办已变更，请重新读取后再试。"
        case .invalidOrder: return "列表已变更，请重新读取后再排序。"
        case .invalidDocument: return "待办数据不完整，原文件已保留。请勿卸载 App。"
        case .unsupportedSchema(let version): return "数据版本 \(version) 需要更新的 App，原文件已保留。"
        case .unreadableDocument: return "无法读取待办文件，原文件已保留。请勿卸载 App。"
        case .primaryMissing: return "发现已有备份但主文件缺失，已停止写入以保留数据。"
        case .lockFailed(let code): return "暂时无法访问待办文件（\(code)），请稍后重试。"
        case .sharedUnavailable(let group): return "没有获得共享存储权限（\(group)）。旧待办仍保留，请核对签名后重试。"
        case .migrationRequired: return "请先打开 Todo Wallpaper 完成数据迁移。"
        case .migrationConflict: return "共享存储与迁移记录不一致，已停止迁移并保留原数据。"
        case .migrationMetadataInvalid: return "迁移记录无法验证，原数据已保留。请勿卸载 App。"
        case .recoveryUnavailable: return "没有可安全恢复的备份，原文件已保留。"
        }
    }
}

enum TodoOrder {
    static func moving(_ ids: [UUID], from offsets: IndexSet, to destination: Int) throws -> [UUID] {
        guard destination >= 0, destination <= ids.count,
              offsets.allSatisfy({ ids.indices.contains($0) }) else { throw TodoDataError.invalidOrder }
        let moving = offsets.sorted().map { ids[$0] }
        var remaining = ids.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        remaining.insert(contentsOf: moving, at: insertion)
        return remaining
    }
}
