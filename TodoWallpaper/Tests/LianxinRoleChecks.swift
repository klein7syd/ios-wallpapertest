// Target Membership：独立macOS原生检查；只使用假请求与网络陷阱。
import Foundation

enum LianxinRoleChecks {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw NSError(domain: "LianxinRoleChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func run() async throws {
        try await reliabilityChecks()
        var profile = LianxinProfile(); profile.idolName = "虚构成员"; profile.userName = "读者甲"
        profile.endpoint = "https://example.invalid/v1/chat/completions"; profile.model = "fixture"
        profile.prompt = "  这是用户的原文\n保留空白和换行。  "
        let basic = LianxinRoleRules.block(profile)
        try require(basic.contains("名字：虚构成员") && basic.contains("不要猜测具体身份") && !basic.contains("团体：") && !basic.contains("定位："), "只有名字、空字段省略、无团体防猜测")
        try require(LianxinRoleRules.fit(profile) == .basic && LianxinRoleRules.suggestion(profile)?.contains("团体") == true, "基础贴合度和团体优先建议")
        profile.groupName = "虚构队伍"
        let grouped = LianxinRoleRules.block(profile)
        try require(grouped.contains("团体：虚构队伍") && !grouped.contains("不要猜测具体身份"), "有团体去掉歧义规则")
        try require(LianxinRoleRules.fit(profile) == .good && LianxinRoleRules.suggestion(profile)?.contains("示例话语") == true, "团体贴合较好与示例优先")
        profile.otherNames = ["Alias", "가명"]; profile.position = "主唱"; profile.fanName = "听众"
        profile.personality = "慢慢说话"; profile.catchphrases = "别急呀"; profile.notes = "公开舞台形象，喜欢短句"
        profile.exampleLines = ["示例一", "示例二", "示例三", "绝不能出现的第四条"]
        let full = LianxinRoleRules.block(profile)
        for token in ["Alias", "가명", "定位：主唱", "粉丝名：听众", "慢慢说话", "别急呀", "只学语气", "不得照抄", "示例三"] { try require(full.contains(token), "完整角色字段与例句规则：" + token) }
        try require(!full.contains("绝不能出现的第四条") && LianxinRoleRules.fit(profile) == .great, "最多3条示例与很好贴合")
        profile.exampleLines = Array((profile.exampleLines ?? []).prefix(3))
        let system = LianxinWritingRules.system(profile)
        let ordered = [LianxinWritingRules.task, "创作对象：", "写作准则：", "语言规则：", "输出格式："]
        var position = system.startIndex
        for token in ordered {
            guard let range = system.range(of: token, range: position..<system.endIndex) else { throw LianxinError.invalidResponse }; position = range.upperBound
        }
        for token in ["口语化", "一两次", "约60字", "虚构人物", "安全规则", "不使用 Markdown", "不输出译文"] { try require(system.contains(token), "写作/语言/输出块：" + token) }
        try require(!system.contains("{称呼}") && system.contains(profile.userName), "示意称呼替换为用户称呼")
        var long = profile; long.notes = String(repeating: "低价值补充", count: 5000); long.personality = String(repeating: "性格", count: 3000)
        let clipped = LianxinRoleRules.block(long)
        try require(clipped.count <= 2000 && clipped.contains("团体：虚构队伍") && clipped.contains("示例三") && clipped.contains("定位：主唱") && clipped.contains(LianxinRoleRules.safety), "2000字预算保留团体/示例/定位和安全规则")
        let request = try LianxinAPIService.request(profile: profile, key: "fixture-only")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        let messages = body?["messages"] as? [[String: String]]
        try require(messages?.count == 2 && messages?[1]["content"] == profile.prompt && messages?[0]["content"] == system, "system顺序与user原文原样")
        try require(body?["temperature"] == nil && body?["photo"] == nil && body?["api_key"] == nil, "不添加temperature、照片、正文密钥")
        let recognized = #"{"recognized":true,"confidence":"high","group":"核对队伍","member":"核对名字","otherNames":["Checked"],"position":"队长","fanName":"应援名","notes":"公开信息"}"#
        for raw in [recognized, "```json\n" + recognized + "\n```", "这是结果：\n" + recognized + "\n请核对。"] {
            let result = LianxinRoleResult.parse(raw)
            try require(result.reviewable && result.member == "核对名字" && result.otherNames == ["Checked"], "核对宽容解析")
        }
        for raw in ["unknown", "非JSON", "{}", #"{"recognized":false,"confidence":"high"}"#, #"{"recognized":true,"confidence":"low","member":"unknown"}"#] {
            try require(!LianxinRoleResult.parse(raw).reviewable, "未知/缺字段/低把握不预填")
        }
        let checked = LianxinRoleResult.parse(recognized)
        try require(!LianxinWritingRules.system(profile).contains("核对名字") && profile.verifiedProfile == nil, "待确认核对结果未进入生成资料")
        let confirmed = LianxinRoleRules.confirmed(checked, in: profile, now: Date(timeIntervalSince1970: 123))
        try require(confirmed.verifiedProfile?.confirmedAt == Date(timeIntervalSince1970: 123) && confirmed.idolName == "核对名字" && LianxinWritingRules.system(confirmed).contains("核对队伍"), "确认才保存、回填及进入请求")
        var override = confirmed; override.groupName = "用户修改队伍"; override.position = "用户修改定位"; override.otherNames = ["UserAlias"]
        let overrideBlock = LianxinRoleRules.block(override)
        try require(overrideBlock.contains("用户修改队伍") && overrideBlock.contains("用户修改定位") && !overrideBlock.contains("核对队伍") && !overrideBlock.contains("Checked"), "冲突字段用户输入优先")
        let roleRequest = try LianxinAPIService.request(profile: profile, key: "fixture-only")
        let roleJSON = try JSONSerialization.jsonObject(with: roleRequest.httpBody ?? Data()) as? [String: Any]
        let roleMessages = roleJSON?["messages"] as? [[String: String]]
        try require(roleMessages?.count == 2 && roleMessages?[0]["content"] == LianxinWritingRules.system(profile) && roleMessages?[1]["content"] == profile.prompt && roleJSON?["temperature"] == nil, "识别与创作合并一次请求，用户原文不改写")
        var recent = profile
        for index in 0..<8 { recent.idolName = "名字\(index)"; recent.groupName = "团体\(index)"; LianxinRoleRules.remember(&recent) }
        try require(recent.recentNames?.count == 5 && recent.recentNames?.first == "名字7" && recent.recentGroups?.last == "团体3", "最近名字和团体各保留5个")
        var extras = LianxinProfile(); extras.idolName = "名字"; extras.position = "主唱"; extras.fanName = "听众"
        try require(LianxinRoleRules.fit(extras) == .good, "无团体但两项其他资料为较好")
        try await languageChecks(profile)
        let old = Data(#"{"userName":"旧称呼","idolName":"旧名字","prompt":"旧提示词","endpoint":"https://example.invalid/v1/chat/completions","model":"old","message":"旧话语","messageIdol":"旧名字"}"#.utf8)
        let decoded = try JSONDecoder().decode(LianxinProfile.self, from: old)
        try require(decoded.idolName == "旧名字" && decoded.verifiedProfile == nil && decoded.translationEnabled != true && LianxinLanguageRules.source(decoded) == "中文", "旧JSON、新角色字段/语言/翻译默认兼容")
        var migrated = profile
        migrated.verifiedProfile = LianxinVerifiedProfile(result: checked, confirmedAt: .distantPast)
        migrated.roleNotesMigrated = nil
        migrated.migrateRoleNotes(); let once = migrated; migrated.migrateRoleNotes()
        try require(migrated == once && (migrated.notes ?? "").contains("其他写法：Alias") && (migrated.notes?.count ?? 0) <= 500 && migrated.otherNames == nil && migrated.position == nil && migrated.fanName == nil && migrated.personality == nil && migrated.catchphrases == nil && migrated.exampleLines == nil && migrated.verifiedProfile == nil, "旧角色一次迁移进500字补充并清空，重复升级不重复拼接")
        let oldPublication = LianxinPublication(idol: "名字", text: "旧句", photo: nil, date: .distantPast)
        let batchPublication = LianxinPublication(idol: "名字", text: "首句", photo: nil, date: .distantPast, lines: [LianxinLine(text: "首句", translation: "First"), LianxinLine(text: "次句", translation: nil)])
        let batchBytes = try JSONEncoder().encode(batchPublication)
        let batchDecoded = try JSONDecoder().decode(LianxinPublication.self, from: batchBytes)
        var batchProfile = decoded; batchProfile.setLines(batchPublication.resolvedLines)
        let profileDecoded = try JSONDecoder().decode(LianxinProfile.self, from: JSONEncoder().encode(batchProfile))
        try require(decoded.resolvedLines.first?.text == "旧话语" && profileDecoded.message == "首句" && profileDecoded.translation == "First" && profileDecoded.resolvedLines.count == 2 && oldPublication.resolvedLines == [LianxinLine(text: "旧句", translation: nil)] && batchDecoded.resolvedLines.count == 2 && batchDecoded.text == "首句" && batchDecoded.translation == "First" && batchDecoded.shareText.contains("次句") && batchDecoded.shareText.contains("AI 创作"), "新旧多句兼容、首句旧字段与分享后缀")
        let publication = LianxinPublication(idol: "署名", text: "原文", photo: nil, date: .distantPast, translation: "译文")
        let data = try JSONEncoder().encode(publication)
        let shared = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        try require(shared["translation"] as? String == "译文" && publication.shareText.contains("原文\n译文") && publication.shareText.contains("AI 创作"), "译文共享及复制分享带后缀")
        for key in ["endpoint", "key", "prompt", "groupName", "otherNames", "position", "fanName", "personality", "catchphrases", "exampleLines", "notes", "verifiedProfile", "userName", "sourceLanguage"] { try require(shared[key] == nil, "共享不含私有字段：" + key) }
        print("PASS: 角色块顺序/预算/空字段/歧义/示例、核对JSON及确认隔离、贴合度、语言翻译解析、旧JSON、共享隐私、离线双语零网络。")
    }
    static func reliabilityChecks() async throws {
        for raw in [#"{"text":"晚安","translation":"잘 자요"}"#, "```json\n{\"lines\":[{\"text\":\"晚安\"}]}\n```", #"说明 {"lines":[{"text":"晚安"}]} 结束"#] {
            let result = LianxinGeneratedBatch.parse(raw, count: 4, translated: true)
            try require(result.lines.first?.text == "晚安" && result.lines.count == 1, "生产批量解析兼容旧对象与围栏")
        }
        for raw in [#"{"lines":[{"text":"坏数据"}"#, #"{"translation":"没有原文"}"#, #"{"lines":[]}"#] {
            try require(LianxinGeneratedBatch.parse(raw, count: 4, translated: true).lines.isEmpty, "结构残片不能作为话语发布")
        }
        let body = try JSONSerialization.data(withJSONObject: ["lines": [["text": "有效原文", "translation": String(repeating: "长", count: 201)], ["text": "另一句", "translation": "   "]]])
        let batch = LianxinGeneratedBatch.parse(String(decoding: body, as: UTF8.self), count: 4, translated: true)
        try require(batch.lines.count == 2 && batch.lines.allSatisfy { $0.translation == nil } && batch.notice?.contains("译文") == true, "坏译文不丢原文并汇总不足提示")
        let models = try LianxinAPIService.models(Data(#"{"data":[{"id":"chat-model","sub_type":"chat"},{"id":"vector-model","sub_type":"embedding"},{"id":"embedding-v3"}]}"#.utf8))
        try require(models == ["chat-model"], "目录过滤明确非聊天能力")
        try LianxinAPIService.validateTestResponse(Data(#"{"choices":[{"message":{"role":"assistant","content":null},"finish_reason":"length"}]}"#.utf8))
        try require(LianxinAPIService.error(status: 429, data: Data("insufficient_quota".utf8)).localizedDescription.contains("配额"), "配额不冒充余额")
        try require(LianxinPublicResearchService.identityScore(title: "Luna", excerpt: "Member of Aurora", name: "Luna", group: "Aurora") > 0 && LianxinPublicResearchService.identityScore(title: "Luna", excerpt: "Member of Aurora", name: "Luna", group: "Other") == 0, "同名候选按团体筛选")
        let clean = LianxinPublicResearchService.usefulText("Luna (born January 1) is a singer in Aurora. Her address is private.", fanWiki: false)
        try require(clean.contains("singer") && !clean.contains("born") && !clean.contains("address"), "出生括注与私人内容移除，公开职业保留")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("LianxinReliability-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = LianxinStorage(directory: root)
        let loaded = try await storage.load()
        var profile = loaded.profile; profile.idolName = "旧角色"
        profile.providerConfigurations = ["custom": LianxinProviderConfiguration(endpoint: "https://example.invalid/v1/chat/completions", model: "saved-model")]
        try await storage.save(profile, revision: 1)
        profile.idolName = "新角色"
        try await storage.save(profile, revision: 2)
        var stale = profile; stale.idolName = "不该回写"
        try await storage.save(stale, revision: 1)
        try require(try await storage.load().profile.idolName == "新角色", "旧保存版本不能回写")
        let file = root.appendingPathComponent("profile-v1.json")
        let corrupted = Data("broken json".utf8); try corrupted.write(to: file)
        do { _ = try await storage.load(); throw NSError(domain: "ExpectedLoadFailure", code: 1) } catch is DecodingError { }
        do { try await storage.save(profile, revision: 3); throw NSError(domain: "ExpectedWriteBlock", code: 1) } catch is LianxinError { }
        try require(try Data(contentsOf: file) == corrupted, "加载失败禁止覆盖坏文件")
        try await storage.recover()
        let restored = try await storage.load()
        try require(restored.profile.idolName == "旧角色" && restored.profile.providerConfigurations?["custom"]?.model == "saved-model", "备份恢复私有资料与服务商配置")
        var missing = restored.profile; missing.photoName = "widget-photo-" + UUID().uuidString + ".jpg"
        try await storage.save(missing, revision: 4)
        let missingPhoto = try await storage.load()
        try require(missingPhoto.missingPhoto && missingPhoto.profile.idolName == "旧角色", "缺图不阻断文字资料")
        var future = missing; future.schemaVersion = 99
        let futureData = try JSONEncoder().encode(future); try futureData.write(to: file)
        do { _ = try await storage.load(); throw NSError(domain: "ExpectedFutureBlock", code: 1) } catch is LianxinError { }
        try require(try Data(contentsOf: file) == futureData, "未来版本原文件保留")
    }
    static func languageChecks(_ input: LianxinProfile) async throws {
        var profile = input
        for source in LianxinLanguageRules.choices {
            profile.sourceLanguage = source; profile.translationLanguage = source; profile.translationEnabled = true
            let normalized = LianxinLanguageRules.normalized(profile)
            try require(normalized.translationLanguage != source && normalized.translationLanguage == (source == "中文" ? "韩语" : "中文"), "同语言自动选择合理默认")
            let system = LianxinWritingRules.system(normalized)
            try require(system.contains("请用\(source)") && system.contains("同时给出译文") && system.contains(LianxinWritingRules.translatedOutput), "翻译开时语言与JSON格式")
        }
        for raw in [#"{"text":"晚安","translation":"잘 자요"}"#, "```json\n{\"text\":\"晚安\",\"translation\":\"잘 자요\"}\n```", "说明：{\"text\":\"晚安\",\"translation\":\"잘 자요\"}结束"] {
            let parsed = LianxinGeneratedMessage.parse(raw, translated: true)
            try require(parsed.text == "晚安" && parsed.translation == "잘 자요" && parsed.notice == nil, "译文宽容JSON解析")
        }
        let missing = LianxinGeneratedMessage.parse(#"{"text":"晚安"}"#, translated: true)
        try require(missing.text == "晚安" && missing.translation == nil && missing.notice == LianxinGeneratedMessage.translationWarning, "缺译文保留原文并提示")
        for raw in ["整段非JSON", #"{"translation":"缺原文"}"#] {
            let parsed = LianxinGeneratedMessage.parse(raw, translated: true)
            try require(parsed.text == raw && parsed.translation == nil && parsed.notice == LianxinGeneratedMessage.translationWarning, "解析失败整段回退并提示")
        }
        profile.sourceLanguage = "英语"; profile.translationLanguage = "English"; profile.translationEnabled = true
        try require(LianxinLanguageRules.normalized(profile).translationLanguage == "中文", "常见语言别名也防止同语言互译")
        let trap = LianxinWizardChecks.NetworkTrap()
        for source in LianxinLanguageRules.choices {
            profile.sourceLanguage = source; profile.translationEnabled = true
            profile.translationLanguage = source == "中文" ? "韩语" : "中文"
            let raw = try await LianxinGeneration.generate(example: true, profile: profile, key: "", service: trap)
            let parsed = LianxinGeneratedMessage.parse(raw, translated: true)
            try require(parsed.text.contains(profile.idolName) && parsed.text.contains(profile.userName) && parsed.translation?.contains(profile.idolName) == true && parsed.text.count <= 200 && (parsed.translation?.count ?? 0) <= 200, "离线多语言示例代入双方名字、各200字")
        }
        let calls = await trap.calls
        try require(calls == 0, "多语言翻译体验不触发网络")
        profile.translationEnabled = false
        try require(!LianxinWritingRules.system(profile).contains("同时给出译文") && LianxinWritingRules.system(profile).contains(LianxinWritingRules.plainOutput), "翻译关闭不输出译文")
    }
}
