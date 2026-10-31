// Target Membership：独立 macOS 原生检查；不调用真实付费 API。
import Foundation

@main
enum LianxinChecks {
    static func main() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "LianxinChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        func rejects(_ operation: () throws -> Void) throws {
            do { try operation() } catch { return }
            throw NSError(domain: "LianxinChecks", code: 2, userInfo: [NSLocalizedDescriptionKey: "应拒绝非法输入"])
        }
        var profile = LianxinProfile()
        profile.userName = "小林"; profile.idolName = "虚构角色"; profile.prompt = "한국어와中文，温柔地说晚安。"
        profile.endpoint = "https://example.invalid/v1/chat/completions"; profile.model = "user-model"
        let request = try LianxinAPIService.request(profile: profile, key: "test-only-placeholder")
        try require(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-placeholder", "POST 与用户密钥")
        guard let body = request.httpBody, let object = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let messages = object["messages"] as? [[String: String]], let content = messages.first?["content"] else { throw LianxinError.invalidResponse }
        try require(content.contains(profile.prompt) && content.contains(profile.userName) && content.contains(profile.idolName), "提示词与中韩混排不丢失")
        try require(object["model"] as? String == profile.model && object["stream"] as? Bool == false, "用户模型与非流式响应")
        try require(!String(decoding: body, as: UTF8.self).contains("test-only-placeholder") && object["photo"] == nil, "正文不含密钥或照片")
        for endpoint in ["http://example.invalid", "https://user:secret@example.invalid/api", "https://example.invalid/api?key=secret", "https://example.invalid/#key", "not-a-url"] {
            var invalid = profile; invalid.endpoint = endpoint
            try rejects { _ = try LianxinAPIService.request(profile: invalid, key: "test") }
        }
        for key in ["", "key\nheader", "space key"] { try rejects { _ = try LianxinAPIService.request(profile: profile, key: key) } }
        var empty = profile; empty.prompt = "  "
        try rejects { _ = try LianxinAPIService.request(profile: empty, key: "test") }
        let valid = Data(#"{"choices":[{"message":{"content":"  晚安，잘 자요。  "}}]}"#.utf8)
        try require(try LianxinAPIService.decode(valid, status: 200) == "晚安，잘 자요。", "响应解码与去首尾空白")
        for status in [301, 401, 403, 429, 500] { try rejects { _ = try LianxinAPIService.decode(valid, status: status) } }
        for response in [#"{"choices":[]}"#, #"{"choices":[{"message":{"content":null}}]}"#, #"{"choices":[{"message":{"content":" "}}]}"#, "bad-json"] {
            try rejects { _ = try LianxinAPIService.decode(Data(response.utf8), status: 200) }
        }
        let mock = MockLianxinService(text: "测试返回")
        try require(try await mock.generate(profile: profile, key: "") == "测试返回", "可替换 AI 服务")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lianxin-check-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let published = LianxinPublication(idol: profile.idolName, text: "晚安，잘 자요。", photo: Data([1, 2, 3]), date: Date(timeIntervalSince1970: 1))
        try require(try LianxinPublication.load(directory: directory) == nil, "首次组件为空")
        try published.save(directory: directory)
        try require(try LianxinPublication.load(directory: directory) == published, "组件文字与底图原子往返")
        let oversized = LianxinPublication(idol: "角色", text: String(repeating: "心", count: 201), photo: nil, date: .now)
        try rejects { try oversized.save(directory: directory) }
        try require(try LianxinPublication.load(directory: directory) == published, "非法发布不覆盖已有组件")
        let bytes = try Data(contentsOf: directory.appendingPathComponent("lianxin-published-v1.json"))
        let json = String(decoding: bytes, as: UTF8.self)
        try require(!json.contains("endpoint") && !json.contains("prompt") && !json.contains("test-only-placeholder"), "共享数据不含连接凭证或私有提示词")
        try await LianxinWizardChecks.run()
        print("PASS: 连心请求校验、用户提示词、响应错误、Mock替换、组件原子发布及凭证隔离；未调用真实 API。")
    }
}
