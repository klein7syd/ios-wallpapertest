// Target Membership：仅 App；网络协议检查在 macOS 独立编译。
import Foundation

struct LianxinProfile: Codable, Equatable, Sendable {
    var providerID: String?
    var setupFinished: Bool?
    var connectedSignature: String?
    var exampleContent: Bool?
    var userName = ""
    var idolName = ""
    var prompt = ""
    var endpoint = ""
    var model = ""
    var photoName: String?
    var message = ""
    var messageIdol = ""
}

enum LianxinError: LocalizedError {
    case invalidEndpoint, requiresHTTPS, missingInput, invalidKey, invalidResponse, http(Int), storage, balance, network
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请填写完整的 HTTPS 接口地址，不能包含账号、密码、查询参数或锚点。"
        case .missingInput: return "请填写你的称呼、IDOL 名字、提示词和模型名称。"
        case .invalidKey: return "请填写有效的 API 密钥，不能包含空格或换行。"
        case .invalidResponse: return "接口没有返回可用文字，或内容过长。请确认它支持 Chat Completions 格式。"
        case .requiresHTTPS: return "需要 https，请向服务商确认安全的接口地址后再填。"
        case .balance: return "账户余额不足，请到服务商充值，再回来测试连接。"
        case .network: return "网络连不上或请求超时，请检查网络后重试；部分服务商可能需要特定网络。"
        case .http(let code):
            if code == 401 || code == 403 { return "密钥不对或已失效，请检查是否复制完整，再重新保存并测试。" }
            if code == 402 { return LianxinError.balance.localizedDescription }
            if code == 404 { return "接口地址或模型名不对，请重新选择服务商/模型；自定义服务请核对最终地址。" }
            if code == 429 { return "请求太频繁或额度用完，请稍后重试，或到服务商查看额度。" }
            if (300...399).contains(code) { return "接口发生跳转，请在自定义中填写服务商最终HTTPS地址后再测试。" }
            return "服务暂时未能完成请求，请稍后重试；持续失败请联系服务商。"
        case .storage: return "连心资料或密钥未能保存，请稍后重试。"
        }
    }
}

protocol AIServiceProtocol: Sendable {
    func generate(profile: LianxinProfile, key: String) async throws -> String
}

// 不跟随重定向，避免用户密钥被转发到其他地址。
final class LianxinRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct LianxinAPIService: AIServiceProtocol {
    static func request(profile: LianxinProfile, key: String) throws -> URLRequest {
        let address = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, let url = components.url else { throw LianxinError.invalidEndpoint }
        let fields = [profile.userName, profile.idolName, profile.prompt, profile.model]
        guard fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              profile.userName.count <= 100, profile.idolName.count <= 100,
              profile.prompt.count <= 12000, profile.model.count <= 200 else { throw LianxinError.missingInput }
        guard !key.isEmpty, key.count <= 4096, key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw LianxinError.invalidKey }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": profile.model.trimmingCharacters(in: .whitespacesAndNewlines), "stream": false,
            "messages": [["role": "user", "content": "创作对象：\(profile.idolName)\n对方的称呼：\(profile.userName)\n以下是我的创作提示词，请按它决定语气、关系、情境、语言和长度，直接输出话语：\n\(profile.prompt)"]]
        ])
        return request
    }

    static func decode(_ data: Data, status: Int) throws -> String {
        guard (200...299).contains(status) else { throw Self.error(status: status, data: data) }
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        guard data.count <= 1_048_576,
              let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= 20000 else { throw LianxinError.invalidResponse }
        return text
    }

    static func error(status: Int, data: Data = Data()) -> LianxinError {
        if status == 401 || status == 403 { return .http(status) }
        let text = String(decoding: data.prefix(65536), as: UTF8.self).lowercased()
        if status == 402 || ["insufficient_balance", "insufficient balance", "insufficient_quota", "余额不足", "balance not enough"].contains(where: { text.contains($0) }) { return .balance }
        return .http(status)
    }
    static func fetch(_ request: URLRequest) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: LianxinRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse else { throw LianxinError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < 1_048_576 else { throw LianxinError.invalidResponse }
                data.append(byte)
            }
            guard (200...299).contains(http.statusCode) else { throw Self.error(status: http.statusCode, data: data) }
            return data
        } catch let error as URLError where error.code != .cancelled { throw LianxinError.network }
    }
    func generate(profile: LianxinProfile, key: String) async throws -> String {
        let data = try await Self.fetch(Self.request(profile: profile, key: key))
        return try Self.decode(data, status: 200)
    }

}

struct MockLianxinService: AIServiceProtocol {
    let text: String
    func generate(profile: LianxinProfile, key: String) async throws -> String { text }
}

// 与生成共用相同的HTTPS、禁止重定向、Cookie/缓存关闭及响应上限。
extension LianxinAPIService: LianxinConnectionService {
    static func testRequest(profile: LianxinProfile, key: String) throws -> URLRequest {
        var fixture = profile
        fixture.userName = "测试"; fixture.idolName = "测试"; fixture.prompt = "回复好"
        var request = try Self.request(profile: fixture, key: key)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": fixture.model, "stream": false,
            "max_tokens": 1, "messages": [["role": "user", "content": "Hi"]]])
        return request
    }
    static func models(_ data: Data) throws -> [String] {
        struct List: Decodable { struct Model: Decodable { let id: String }; let data: [Model] }
        guard let result = try? JSONDecoder().decode(List.self, from: data) else { throw LianxinError.invalidResponse }
        return Array(Set(result.data.map(\.id).filter { !$0.isEmpty && $0.count <= 200 })).sorted()
    }
    func test(profile: LianxinProfile, key: String, provider: LianxinProviderPreset) async throws -> [String] {
        // OpenRouter公开模型列表不证明密钥有效，先做最小生成请求。
        if provider.modelsEndpoint == nil || provider.id == "openrouter" {
            _ = try await Self.fetch(Self.testRequest(profile: profile, key: key))
        }
        guard let endpoint = provider.modelsEndpoint, let url = URL(string: endpoint) else { return [profile.model] }
        var request = URLRequest(url: url); request.timeoutInterval = 30
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        let models = try Self.models(await Self.fetch(request))
        guard !models.isEmpty else { throw LianxinError.invalidResponse }
        return models
    }
}

// 体验模式由独立分支分发，不构造网络请求，也不接收真实密钥。
enum LianxinGeneration {
    static func generate(example: Bool, profile: LianxinProfile, key: String, service: any AIServiceProtocol) async throws -> String {
        if example { return try await MockLianxinService(text: "今天也辛苦啦。先照顾好自己，今晚做个甜甜的梦。明天，再一起慢慢来。").generate(profile: profile, key: "") }
        return try await service.generate(profile: profile, key: key)
    }
}
