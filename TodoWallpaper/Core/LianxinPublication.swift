// Target Membership：App + Widget。共享内容只包含用户明确发布的话语与底图。
import Foundation

struct LianxinLine: Codable, Equatable, Sendable {
    var text: String
    var translation: String?
    var isValid: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 200 && (translation?.count ?? 0) <= 200 }
}

struct LianxinPublication: Codable, Equatable {
    static let kind = "LianxinWidget"
    var schemaVersion = 1
    let idol: String
    var text: String
    let photo: Data?
    let date: Date
    var resolvedLines: [LianxinLine] { if let lines, !lines.isEmpty { return lines }; return text.isEmpty ? [] : [LianxinLine(text: text, translation: translation)] }
    var example: Bool?
    var translation: String?
    // 公开署名摘要，供可开关的标题右侧团体文字使用；不是角色设定。
    var signatureSubtitle: String?
    var lines: [LianxinLine]?
    var contentLabel: String { example == true ? "示例内容，非 AI 生成" : "AI 创作" }

    // 旧单句与等价的新数组表示同一份内容，编码升级不应造成虚假的内容变化。
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion && lhs.idol == rhs.idol && lhs.resolvedLines == rhs.resolvedLines
            && lhs.photo == rhs.photo && lhs.date == rhs.date && lhs.example == rhs.example
            && lhs.signatureSubtitle == rhs.signatureSubtitle
    }

    func validate() throws {
        guard schemaVersion == 1, !idol.isEmpty, idol.count <= 100,
              !resolvedLines.isEmpty, resolvedLines.count <= 8, resolvedLines.allSatisfy(\.isValid),
              (translation?.count ?? 0) <= 200,
              (signatureSubtitle?.count ?? 0) <= 100,
              (photo?.count ?? 0) <= 12 * 1024 * 1024 else { throw TodoDataError.invalidDocument }
    }
    // 编码始终带首条旧字段，旧客户端仍可显示首句。
    enum CodingKeys: String, CodingKey { case schemaVersion, idol, text, photo, date, example, translation, signatureSubtitle, lines }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion); try c.encode(idol, forKey: .idol)
        try c.encode(resolvedLines.first?.text ?? text, forKey: .text)
        try c.encodeIfPresent(resolvedLines.first?.translation, forKey: .translation)
        try c.encodeIfPresent(photo, forKey: .photo); try c.encode(date, forKey: .date)
        try c.encodeIfPresent(example, forKey: .example); try c.encodeIfPresent(signatureSubtitle, forKey: .signatureSubtitle)
        try c.encode(resolvedLines, forKey: .lines)
    }
    static func load(directory: URL) throws -> LianxinPublication? {
        let url = directory.appendingPathComponent("lianxin-published-v1.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        var value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        value.lines = value.resolvedLines
        value.text = value.resolvedLines.first?.text ?? value.text
        value.translation = value.resolvedLines.first?.translation
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
