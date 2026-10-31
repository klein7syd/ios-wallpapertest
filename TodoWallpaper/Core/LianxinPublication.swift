// Target Membership：App + Widget。共享内容只包含用户明确发布的话语与底图。
import Foundation

struct LianxinPublication: Codable, Equatable {
    static let kind = "LianxinWidget"
    var schemaVersion = 1
    let idol: String
    let text: String
    let photo: Data?
    let date: Date
    var example: Bool?
    var contentLabel: String { example == true ? "示例内容，非 AI 生成" : "AI 创作" }

    func validate() throws {
        guard schemaVersion == 1, !idol.isEmpty, idol.count <= 100,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 200,
              (photo?.count ?? 0) <= 12 * 1024 * 1024 else { throw TodoDataError.invalidDocument }
    }
    static func load(directory: URL) throws -> LianxinPublication? {
        let url = directory.appendingPathComponent("lianxin-published-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }
    func save(directory: URL) throws {
        try validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 文字与缩略底图单文件原子发布，组件不会读到一新一旧的组合。
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent("lianxin-published-v1.json"), options: .atomic)
    }
}
