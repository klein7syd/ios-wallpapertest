import Foundation
import Darwin

enum ProbeConstants {
    static let widgetKind = "NativeProbeTaskWidget"
    static let originalGroupID = "group.org.todowallpaper.nativeinstallprobe"
}

struct SharedProbeState: Codable {
    var schemaVersion = 1
    var storeID = UUID().uuidString
    var title = "在主屏幕完成这条测试待办"
    var isCompleted = false
    var revision = 0
    var lastWriter = "initial"
    var widgetActions = 0
}

enum ProbeStorageError: LocalizedError {
    case unavailable(String), lockFailed(Int32), unsupportedSchema, invalidTitle
    var errorDescription: String? {
        switch self {
        case .unavailable(let id): return "没有获得 \(id) 的共享容器。"
        case .lockFailed(let code): return "共享文件锁失败（\(code)）。"
        case .unsupportedSchema: return "数据版本不支持；原文件保留，请勿卸载。"
        case .invalidTitle: return "请输入 1–80 个字符。"
        }
    }
}

/// A single atomic JSON snapshot, protected by a cross-process advisory lock.
/// There is deliberately no local fallback: separate app/widget containers
/// must never look like a successful App Groups test.
struct SharedProbeStore {
    static var groupID: String {
        Bundle.main.object(forInfoDictionaryKey: "ProbeAppGroupIdentifier") as? String
            ?? ProbeConstants.originalGroupID
    }

    func read() throws -> SharedProbeState {
        try transaction { _ in false }
    }

    func setCompleted(_ completed: Bool, source: String) throws -> SharedProbeState {
        try transaction { state in
            state.isCompleted = completed
            state.revision += 1
            state.lastWriter = source
            if source == "widget" { state.widgetActions += 1 }
            return true
        }
    }

    func rename(_ title: String) throws -> SharedProbeState {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80 else { throw ProbeStorageError.invalidTitle }
        return try transaction { state in
            state.title = value
            state.revision += 1
            state.lastWriter = "app"
            return true
        }
    }

    private func transaction(_ update: (inout SharedProbeState) throws -> Bool) throws -> SharedProbeState {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.groupID
        ) else { throw ProbeStorageError.unavailable(Self.groupID) }
        let lockURL = container.appendingPathComponent("native-probe-v1.lock")
        // O_EXLOCK acquires the BSD advisory lock as part of open(). Closing
        // the descriptor releases it, including if either process is killed.
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_EXLOCK, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw ProbeStorageError.lockFailed(errno) }
        defer { Darwin.close(descriptor) }
        let dataURL = container.appendingPathComponent("native-probe-v1.json")
        let exists = FileManager.default.fileExists(atPath: dataURL.path)
        var state = exists
            ? try JSONDecoder().decode(SharedProbeState.self, from: Data(contentsOf: dataURL))
            : SharedProbeState()
        guard state.schemaVersion == 1 else { throw ProbeStorageError.unsupportedSchema }
        let changed = try update(&state)
        if changed || !exists {
            try JSONEncoder().encode(state).write(to: dataURL, options: .atomic)
        }
        return state
    }
}
