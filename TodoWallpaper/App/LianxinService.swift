// Target Membership：仅 App；网络协议检查在 macOS 独立编译。
import Foundation

struct LianxinProviderConfiguration: Codable, Equatable, Sendable {
    var endpoint: String
    var model: String
    var connectedSignature: String?
    var setupFinished: Bool?
}

struct LianxinProfile: Codable, Equatable, Sendable {
    // 全部仅存App私有目录；nil兼容旧版，密钥不在此结构中。
    var schemaVersion: Int?
    var providerConfigurations: [String: LianxinProviderConfiguration]?
    var messageGroup: String?
    var messageIdentityCaptured: Bool?
    var pendingPhotoSync: Bool?
    var providerID: String?
    var setupFinished: Bool?
    var connectedSignature: String?
    var exampleContent: Bool?
    var exampleIndex: Int?
    var userName = ""
    var idolName = ""
    var prompt = ""
    var endpoint = ""
    var model = ""
    var sharedPhotoName: String?
    var photoName: String?
    var message = ""
    var messageIdol = ""
    var groupName: String?
    var otherNames: [String]?
    var position: String?
    var fanName: String?
    var personality: String?
    var catchphrases: String?
    var exampleLines: [String]?
    var notes: String?
    var verifiedProfile: LianxinVerifiedProfile?
    var recentNames: [String]?
    var recentGroups: [String]?
    var sourceLanguage: String?
    var translationEnabled: Bool?
    var translationLanguage: String?
    var translation: String?
    var lines: [LianxinLine]?
    var generationCount: Int?
    var understood: String?
    var confidence: String?
    var researchSources: [LianxinPublicSource]?
    var roleNotesMigrated: Bool? = true
    var requestedCount: Int { min(8, max(1, generationCount ?? 4)) }
    var resolvedLines: [LianxinLine] { if let lines, !lines.isEmpty { return lines }; return message.isEmpty ? [] : [LianxinLine(text: message, translation: translation)] }
    mutating func setLines(_ values: [LianxinLine]) { lines = values; message = values.first?.text ?? ""; translation = values.first?.translation }
    mutating func migrateRoleNotes() {
        guard roleNotesMigrated != true else { return }
        var parts: [String] = []
        func add(_ label: String, _ value: String?) { if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append(label + "：" + value) } }
        add("补充", notes); add("其他写法", otherNames?.joined(separator: "、")); add("定位", position)
        add("粉丝名", fanName); add("性格与说话习惯", personality); add("口头禅", catchphrases); add("示例话语", exampleLines?.joined(separator: "；"))
        if let v = verifiedProfile?.result { add("已核对团体", v.group); add("已核对名字", v.member); add("已核对其他写法", v.otherNames.joined(separator: "、")); add("已核对定位", v.position); add("已核对粉丝名", v.fanName); add("已核对补充", v.notes) }
        notes = String(parts.joined(separator: "\n").prefix(500))
        otherNames = nil; position = nil; fanName = nil; personality = nil; catchphrases = nil; exampleLines = nil; verifiedProfile = nil
        roleNotesMigrated = true
    }
}

enum LianxinError: LocalizedError {
    case invalidEndpoint, requiresHTTPS, missingInput, invalidKey, invalidResponse, http(Int), storage, balance, quota, missingModel, network, invalidLanguage, invalidRole
    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "请填写完整的 HTTPS 接口地址，不能包含账号、密码、查询参数或锚点。"
        case .missingInput: return "请填写想听什么（最多12000字），并检查称呼是否超过100字。"
        case .invalidKey: return "请填写有效的 API 密钥，不能包含空格或换行。"
        case .invalidRole: return "请填写名字，并检查公开形象信息的字数。其他角色信息都可留空。"
        case .invalidLanguage: return "请填写自定义语言名称（最多20字），说话语言与译文语言需要不同。"
        case .invalidResponse: return "接口没有返回可用文字，或内容过长。请确认它支持 Chat Completions 格式。"
        case .requiresHTTPS: return "需要 https，请向服务商确认安全的接口地址后再填。"
        case .missingModel: return "请在连接设置中选择或填写模型名称（最多200字）。"
        case .quota: return "账户额度或用量上限已用完，请到服务商查看配额、预算和可用额度后再试。"
        case .balance: return "账户余额不足，请到服务商充值，再回来测试连接。"
        case .network: return "网络连不上或请求超时，请检查网络后重试；部分服务商可能需要特定网络。"
        case .http(let code):
            if code == 401 { return "密钥不对或已失效，请检查是否复制完整，再重新保存并测试。" }
            if code == 403 { return "请求被服务商拒绝，请检查密钥是否复制完整，以及模型权限、账号或地域限制。" }
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
        try LianxinRoleRules.validate(profile)
        try LianxinLanguageRules.validate(profile)
        guard !profile.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              profile.userName.count <= 100, profile.prompt.count <= 12000 else { throw LianxinError.missingInput }
        var request = try authorizedRequest(profile: profile, key: key)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": profile.model.trimmingCharacters(in: .whitespacesAndNewlines), "stream": false,
            "messages": [["role": "system", "content": LianxinWritingRules.system(profile)], ["role": "user", "content": profile.prompt]]
        ])
        return request
    }
    // 连接测试共用传输安全校验，不受尚未填写的创作提示词或语言影响。
    static func authorizedRequest(profile: LianxinProfile, key: String) throws -> URLRequest {
        let address = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil, let url = components.url else { throw LianxinError.invalidEndpoint }
        guard !profile.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, profile.model.count <= 200 else { throw LianxinError.missingModel }
        guard !key.isEmpty, key.count <= 4096, key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw LianxinError.invalidKey }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
        if status == 402 || ["insufficient_balance", "insufficient balance", "余额不足", "balance not enough"].contains(where: { text.contains($0) }) { return .balance }
        if ["insufficient_quota", "quota_exceeded", "quota exceeded", "usage_limit", "用量上限", "配额不足"].contains(where: { text.contains($0) }) { return .quota }
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
        var request = try Self.authorizedRequest(profile: fixture, key: key)
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": fixture.model, "stream": false,
            "max_tokens": 1, "messages": [["role": "user", "content": "Hi"]]])
        return request
    }
    // 极小请求可以因token上限返回空正文，但必须仍是有效Chat Completions响应。
    static func validateTestResponse(_ data: Data) throws {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["error"] == nil,
              let choice = (object["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any],
              message["role"] as? String == "assistant",
              message["content"] is String || choice["finish_reason"] as? String == "length" else { throw LianxinError.invalidResponse }
    }
    static func models(_ data: Data) throws -> [String] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["data"] as? [[String: Any]] else { throw LianxinError.invalidResponse }
        let candidates = entries.compactMap { entry -> String? in
            guard let id = entry["id"] as? String, !id.isEmpty, id.count <= 200 else { return nil }
            if let architecture = entry["architecture"] as? [String: Any],
               let outputs = architecture["output_modalities"] as? [String], !outputs.contains("text") { return nil }
            if let type = entry["sub_type"] as? String, type != "chat" { return nil }
            // 无能力元数据的目录只排除明确的非聊天类型，未知型号仍允许用户手动验证。
            let lower = id.lowercased()
            if ["embedding", "rerank", "whisper", "transcribe", "tts-", "dall-e", "image-generation", "moderation"].contains(where: { lower.contains($0) }) { return nil }
            return id
        }
        return Array(Set(candidates)).sorted()
    }
    static func modelsRequest(provider: LianxinProviderPreset, key: String) -> URLRequest? {
        guard let endpoint = provider.modelsEndpoint, var parts = URLComponents(string: endpoint) else { return nil }
        // 预设本身仍为无查询参数的官方地址；只在这里添加官方支持的受控目录过滤。
        if provider.id == "siliconflow" { parts.queryItems = [URLQueryItem(name: "sub_type", value: "chat")] }
        guard let url = parts.url else { return nil }
        var request = URLRequest(url: url); request.timeoutInterval = 8
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        return request
    }
    func test(profile: LianxinProfile, key: String, provider: LianxinProviderPreset) async throws -> [String] {
        // 每次用户主动测试仅发一条极短生成请求，不自动重试；目录不能证明所选模型可用。
        let response = try await Self.fetch(Self.testRequest(profile: profile, key: key))
        try Self.validateTestResponse(response)
        try Task.checkCancellation()
        guard let request = Self.modelsRequest(provider: provider, key: key) else { return [profile.model] }
        do {
            let models = try Self.models(await Self.fetch(request))
            try Task.checkCancellation()
            return [profile.model] + models.filter { $0 != profile.model }
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw error }
        catch { return [profile.model] } // 目录是可选增强；已验证的模型不因目录失败变成不可用。
    }
}

// 体验模式由独立分支分发，不构造网络请求，也不接收真实密钥。
enum LianxinGeneration {
    static func generate(example: Bool, profile: LianxinProfile, key: String, service: any AIServiceProtocol) async throws -> String {
        if example { return try await MockLianxinService(text: LianxinSamples.response(profile)).generate(profile: profile, key: "") }
        return try await service.generate(profile: profile, key: key)
    }
}

// 中文硬规则集中在一处，用户提示词原文始终单独作为user消息。
enum LianxinWritingRules {
    static let task = "你为用户创作粉丝向的应援话语。话语是创作，不是真实人物的真实言论。"
    static let writing = """
    写作准则：口语化，像直接发给用户的一条私信或一段语音，从第一人称对“你”说话，不是向用户介绍这位成员。用短句，句式有长短变化，不要整齐的排比。
    用户只写“很累”“哄哄我”“睡不着”等家常话时，先理解情绪和需要，再自然回应，不要求用户提供专业提示词。根据已知的公开说话风格选择措辞、节奏、直接或含蓄的关心；没有可靠风格资料时写得朴素自然，不堆砌人设标签或韩剧腔。
    名字、团名是识别角色用的，不是每句的台词素材。话语里默认不出现IDOL名字、团名，不用第三人称说“喜欢某某”。用户称呼通常省略；整批话语自然使用称呼最多一两次，不必用满，禁止每句都点名或固定用称呼开头。用户明确要求昵称或自我介绍时才自然加入。
    可以有一个虚构的小场景或细节（时间、动作、感受），但不编造真实发生过的事件、今天的工作行程、见面或私下关系。公开偏好、口头禅、习惯只在身份匹配且资料有依据时轻轻带出，最多一个贴切细节；不要逐条复述百科、塞满TMI或照抄粉丝原话。
    避免鸡汤、空洞抒情、客套话和书面套话；关心应具体、留有余地，不训话，不夸张许诺。不要自称 AI，不解释自己在做什么，不出现“作为……”。每条默认1~3句，中文约60字以内；长度、语气、情境以用户提示词为准，但最终原文和译文各不超过200字，安全规则始终有效。表情符号除非用户要求，否则不用。
    以下仅为虚构人物的风格对照，不得照抄，不代表目标人物真实经历。
    反例：“愿你在人生的旅途中，如星辰般闪耀，岁月不负，前程似锦。”
    正例：“累了就先把手里的事放一放。热水喝两口，肩膀也松下来，今天已经做得够多了。”
    """
    static let plainOutput = "输出格式：只返回JSON，不加围栏或前后文字："
    static let translatedOutput = plainOutput
    static func system(_ profile: LianxinProfile) -> String {
        return [task, LianxinRoleRules.inferredBlock(profile), writing,
                LianxinLanguageRules.block(profile), LianxinGeneratedBatch.output(profile)].joined(separator: "\n\n")
    }
    static func example(_ profile: LianxinProfile) -> String {
        LianxinSamples.text(profile, language: LianxinLanguageRules.source(profile))
    }
    static func connected(profile: LianxinProfile, hasKey: Bool) -> Bool {
        let id = LianxinProviderPreset.preset(profile.providerID).id
        return hasKey && profile.connectedSignature == id + "|" + profile.endpoint + "|" + profile.model
    }
}
