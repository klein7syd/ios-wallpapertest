// Target Membership：独立macOS原生检查；假凭证后端与禁止联网替身。
import Foundation

enum LianxinWizardChecks {
    final class Credentials: LianxinCredentialStore {
        var values: [String: String] = [:]
        var rejectsWrites = false
        func read(account: String) throws -> String { values[account] ?? "" }
        func save(_ key: String, account: String) throws {
            if rejectsWrites { throw LianxinError.storage }
            values[account] = key
        }
    }
    actor NetworkTrap: AIServiceProtocol {
        var calls = 0
        func generate(profile: LianxinProfile, key: String) async throws -> String { calls += 1; throw LianxinError.network }
    }
    static func run() async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "LianxinWizardChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let presets = LianxinProviderPreset.all
        try require(Set(presets.map(\.id)).count == 8, "预设ID唯一、七家官方服务商加自定义")
        for p in presets where p.id != "custom" {
            try require(!p.name.isEmpty && !p.detail.isEmpty && !p.model.isEmpty, "预设展示信息完整")
            for address in [p.endpoint, p.keyPage] + (p.modelsEndpoint.map { [$0] } ?? []) {
                let url = URLComponents(string: address)
                try require(url?.scheme == "https" && url?.host != nil && url?.query == nil && url?.user == nil && url?.fragment == nil, "预设地址安全")
            }
            try require(try LianxinSetupRules.endpoint(p.endpoint) == p.endpoint, "预设聊天地址不重复补全")
        }
        for (input, expected) in [("example.com", "https://example.com/v1/chat/completions"),
                                   ("https://example.com/v1/", "https://example.com/v1/chat/completions"),
                                   ("https://example.com/api/v2", "https://example.com/api/v2/chat/completions"),
                                   ("https://example.com/special-endpoint", "https://example.com/special-endpoint"),
                                   (" https://example.com/v1/chat/completions ", "https://example.com/v1/chat/completions")] {
            try require(try LianxinSetupRules.endpoint(input) == expected, "域名/BaseURL/完整地址补全")
        }
        for invalid in ["http://example.com", "https://user:pass@example.com", "https://example.com?key=secret", "https://example.com/#secret"] {
            do { _ = try LianxinSetupRules.endpoint(invalid); throw NSError(domain: "UnexpectedAcceptedURL", code: 1) }
            catch is LianxinError { }
        }
        for input in [" key ", "\"key\"", "'key'", "Bearer key", "\"Bearer key\"", "Bearer 'key'", "\nkey\r\n", "ke\ny"] {
            try require(LianxinSetupRules.cleanKey(input) == "key", "密钥空白/引号/前缀/换行清洗")
        }
        try require(LianxinAPIService.error(status: 401).localizedDescription.contains("密钥不对"), "401原因下一步")
        try require(LianxinAPIService.error(status: 403).localizedDescription.contains("复制完整"), "403原因下一步")
        try require(LianxinAPIService.error(status: 402).localizedDescription.contains("充值"), "402余额")
        try require(LianxinAPIService.error(status: 400, data: Data(#"{"error":{"message":"insufficient balance private-secret"}}"#.utf8)).localizedDescription.contains("余额不足"), "服务商余额不足正文仅分类")
        try require(!LianxinAPIService.error(status: 500, data: Data("secret".utf8)).localizedDescription.contains("secret"), "报错不回显正文")
        try require(LianxinAPIService.error(status: 404).localizedDescription.contains("模型"), "404")
        try require(LianxinAPIService.error(status: 429).localizedDescription.contains("额度"), "429")
        try require(LianxinError.network.localizedDescription.contains("特定网络"), "网络失败/超时")
        let credentials = Credentials(); credentials.values["api-key"] = "old-key"
        var profile = LianxinProfile(); profile.endpoint = "https://example.com/v1/chat/completions"; profile.model = "old-model"
        try LianxinCredentialMigration.migrate(profile: profile, store: credentials)
        try require(credentials.values["api-key.custom"] == "old-key" && credentials.values["api-key"] == "", "旧版单一密钥迁移自定义")
        credentials.values["api-key"] = "legacy"; credentials.values["api-key.deepseek"] = "separate"
        try LianxinCredentialMigration.migrate(profile: profile, store: credentials)
        try require(credentials.values["api-key.custom"] == "old-key" && credentials.values["api-key.deepseek"] == "separate", "幂等与服务商隔离")
        credentials.values["api-key"] = "preserve"; credentials.rejectsWrites = true
        do { try LianxinCredentialMigration.migrate(profile: profile, store: credentials); throw NSError(domain: "ExpectedStorageFailure", code: 1) }
        catch is LianxinError { }
        try require(credentials.values["api-key"] == "preserve", "迁移失败保留旧密钥")
        let oldJSON = Data(#"{"userName":"旧名字","idolName":"旧角色","prompt":"旧提示词","endpoint":"https://example.com/v1/chat/completions","model":"old-model","message":"旧话语","messageIdol":"旧角色"}"#.utf8)
        let old = try JSONDecoder().decode(LianxinProfile.self, from: oldJSON)
        try require(LianxinSetupRules.migratedProvider(old) == "custom" && old.model == "old-model" && old.message == "旧话语", "旧资料保留")
        let trap = NetworkTrap()
        let example = try await LianxinGeneration.generate(example: true, profile: profile, key: "", service: trap)
        try require(!example.isEmpty, "示例返回文字")
        let calls = await trap.calls
        try require(calls == 0, "体验模式绝不进入真实网络服务")
        let mock = MockLianxinConnection()
        let p = presets[0]
        let models = try await mock.test(profile: profile, key: "test", provider: p)
        try require(models == [p.model], "Mock连接到选模型")
        let request = try LianxinAPIService.testRequest(profile: profile, key: "test")
        let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        try require(json?["max_tokens"] as? Int == 1, "测试连接只生成1token")
        print("PASS: wizard presets, URL/key cleanup, errors, provider-key migration/failure/legacy, Mock connection and zero-network experience.")
    }
}
