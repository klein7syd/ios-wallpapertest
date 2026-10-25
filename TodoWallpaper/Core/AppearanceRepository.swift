import Foundation
import Darwin

struct AppearanceRepository {
    let directory: URL
    var fileURL: URL { directory.appendingPathComponent("appearance-v1.json") }
    var backupURL: URL { directory.appendingPathComponent("appearance-v1.backup.json") }
    func load() throws -> TodoAppearance { try locked { try read() } }
    private func decode(_ data: Data) throws -> TodoAppearance {
        guard let header = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = header["schemaVersion"] as? Int else { throw AppearanceError.unreadable }
        guard version == 1 else { throw AppearanceError.unsupportedVersion }
        guard let value = try? JSONDecoder().decode(TodoAppearance.self, from: data) else { throw AppearanceError.unreadable }
        do { try value.validate() } catch { throw AppearanceError.unreadable }; return value
    }
    private func read() throws -> TodoAppearance {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            guard !FileManager.default.fileExists(atPath: backupURL.path) else { throw AppearanceError.unreadable }
            return TodoAppearance()
        }
        return try decode(Data(contentsOf: fileURL))
    }
    func save(_ value: TodoAppearance) throws {
        try locked {
            _ = try read(); try value.validate()
            let data = try JSONEncoder().encode(value)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try write(Data(contentsOf: fileURL), to: backupURL)
            }
            try write(data, to: fileURL)
        }
    }
    func recover() throws {
        try locked {
            // A valid or future-version primary is never rolled back.
            do { _ = try read(); throw TodoDataError.recoveryUnavailable }
            catch AppearanceError.unreadable { }
            let data = try Data(contentsOf: backupURL); _ = try decode(data)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try write(Data(contentsOf: fileURL), to: directory.appendingPathComponent("appearance-preserved-\(UUID()).json"))
            }
            try write(data, to: fileURL)
        }
    }
    private func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    private func locked<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = Darwin.open(directory.appendingPathComponent("appearance-v1.lock").path,
                                     O_CREAT | O_RDWR | O_EXLOCK, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw TodoDataError.lockFailed(errno) }
        defer { Darwin.close(descriptor) }
        return try operation()
    }
}
