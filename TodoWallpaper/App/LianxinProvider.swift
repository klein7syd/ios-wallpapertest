// Target Membership：仅App；macOS原生检查同时编译。
import Foundation

struct LianxinProviderPreset: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let detail: String
    let endpoint: String
    let keyPage: String
    let model: String
    let modelsEndpoint: String?
    static let all: [Self] = [
        .init(id: "deepseek", name: "DeepSeek", detail: "通用中文创作，使用DeepSeek开放平台账号。", endpoint: "https://api.deepseek.com/chat/completions", keyPage: "https://platform.deepseek.com/api_keys", model: "deepseek-flash", modelsEndpoint: "https://api.deepseek.com/models"),
        .init(id: "bailian", name: "阿里云百炼", detail: "通义千问；预设使用中国北京地域的密钥。", endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", keyPage: "https://help.aliyun.com/zh/model-studio/get-api-key", model: "qwen-plus", modelsEndpoint: nil),
        .init(id: "kimi", name: "Kimi（月之暗面）", detail: "使用Kimi API开放平台，和聊天会员分开计费。", endpoint: "https://api.moonshot.cn/v1/chat/completions", keyPage: "https://platform.kimi.com/console/api-keys", model: "kimi-k3.1-pro", modelsEndpoint: nil),
        .init(id: "glm", name: "智谱 GLM", detail: "需要模型标准API密钥，套餐密钥可能不通用。", endpoint: "https://open.bigmodel.cn/api/paas/v4/chat/completions", keyPage: "https://bigmodel.cn/usercenter/proj-mgmt/apikeys", model: "glm-4.7", modelsEndpoint: nil),
        .init(id: "siliconflow", name: "硅基流动", detail: "多个模型可选，使用硅基流动平台密钥。", endpoint: "https://api.siliconflow.cn/v1/chat/completions", keyPage: "https://cloud.siliconflow.cn/account/ak", model: "deepseek-ai/DeepSeek-V3.2", modelsEndpoint: "https://api.siliconflow.cn/v1/models"),
        .init(id: "openai", name: "OpenAI", detail: "使用API平台账号，和ChatGPT订阅分开计费。", endpoint: "https://api.openai.com/v1/chat/completions", keyPage: "https://platform.openai.com/api-keys", model: "gpt-4.1-mini", modelsEndpoint: "https://api.openai.com/v1/models"),
        .init(id: "openrouter", name: "OpenRouter", detail: "统一入口选择多个服务商的模型。", endpoint: "https://openrouter.ai/api/v1/chat/completions", keyPage: "https://openrouter.ai/settings/keys", model: "openai/gpt-4.1-mini", modelsEndpoint: "https://openrouter.ai/api/v1/models"),
        .init(id: "custom", name: "自定义", detail: "已有其他兼容服务？按服务商说明填写。", endpoint: "", keyPage: "", model: "", modelsEndpoint: nil)
    ]
    static func preset(_ id: String?) -> Self { all.first { $0.id == id } ?? all[all.count - 1] }
}

enum LianxinSetupRules {
    static func cleanKey(_ input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
        for _ in 0..<4 {
            if let first = value.first, let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") || (first == "“" && last == "”") {
                value = String(value.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if value.lowercased().hasPrefix("bearer ") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return value
    }
    static func endpoint(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("http://") { throw LianxinError.requiresHTTPS }
        if !value.contains("://") { value = "https://" + value }
        guard var parts = URLComponents(string: value), parts.scheme?.lowercased() == "https", let host = parts.host,
              !host.isEmpty, host.contains("."), parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { throw LianxinError.invalidEndpoint }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        if path.isEmpty { path = "/v1/chat/completions" }
        else if path.hasSuffix("/v1") || path.hasSuffix("/v2") { path += "/chat/completions" }
        parts.path = path
        guard let url = parts.url else { throw LianxinError.invalidEndpoint }
        return url.absoluteString
    }
    // 旧版资料没有providerID，明确归入自定义；保留用户原来的地址/模型。
    static func migratedProvider(_ profile: LianxinProfile) -> String { LianxinProviderPreset.preset(profile.providerID).id }
    static func account(_ provider: String) -> String { "api-key." + LianxinProviderPreset.preset(provider).id }
}

protocol LianxinCredentialStore {
    func read(account: String) throws -> String
    func save(_ key: String, account: String) throws
}
enum LianxinCredentialMigration {
    static func migrate(profile: LianxinProfile, store: any LianxinCredentialStore) throws {
        let old = try store.read(account: "api-key")
        guard !old.isEmpty else { return }
        let account = LianxinSetupRules.account(LianxinSetupRules.migratedProvider(profile))
        if try store.read(account: account).isEmpty { try store.save(old, account: account) }
        // 新记录写成功才删除旧值，重复启动不覆盖按服务商保存的密钥。
        try store.save("", account: "api-key")
    }
}

protocol LianxinConnectionService: Sendable {
    func test(profile: LianxinProfile, key: String, provider: LianxinProviderPreset) async throws -> [String]
}
struct MockLianxinConnection: LianxinConnectionService {
    func test(profile: LianxinProfile, key: String, provider: LianxinProviderPreset) async throws -> [String] { [provider.model] }
}
