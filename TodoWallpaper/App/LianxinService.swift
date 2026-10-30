// Target Membership：仅 App；网络协议检查在 macOS 独立编译。
import Foundation

struct LianxinProfile: Codable, Equatable, Sendable {
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
    case invalidEndpoint, missingInput, invalidKey, invalidResponse, http(Int), storage
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请填写完整的 HTTPS 接口地址，不能包含账号、密码、查询参数或锚点。"
        case .missingInput: return "请填写你的称呼、IDOL 名字、提示词和模型名称。"
        case .invalidKey: return "请填写有效的 API 密钥，不能包含空格或换行。"
        case .invalidResponse: return "接口没有返回可用文字，或内容过长。请确认它支持 Chat Completions 格式。"
        case .http(let code):
            if code == 401 || code == 403 { return "API 拒绝访问（\(code)），请检查密钥和模型权限。" }
            if code == 429 { return "请求过于频繁或额度不足（429），请稍后重试或查看服务商额度。" }
            if (300...399).contains(code) { return "接口发生跳转。为保护密钥，请直接填写服务商的最终接口地址。" }
            return "服务商返回错误（\(code)），请检查接口和模型后重试。"
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
        guard (200...299).contains(status) else { throw LianxinError.http(status) }
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

    func generate(profile: LianxinProfile, key: String) async throws -> String {
        let request = try Self.request(profile: profile, key: key)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: LianxinRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LianxinError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw LianxinError.http(http.statusCode) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { throw LianxinError.invalidResponse }
            data.append(byte)
        }
        return try Self.decode(data, status: http.statusCode)
    }
}

struct MockLianxinService: AIServiceProtocol {
    let text: String
    func generate(profile: LianxinProfile, key: String) async throws -> String { text }
}
