// Target Membership：App + macOS协议检查。公开资料仅留App私有资料，不进入App Group。
import Foundation

struct LianxinPublicSource: Codable, Equatable, Sendable, Identifiable {
    let title: String
    let url: URL
    let excerpt: String
    let fetchedAt: Date
    var id: String { url.absoluteString }
    var siteName: String { url.host == "kpop.fandom.com" ? "K-pop Wiki" : "维基百科" }
    var isAllowed: Bool {
        url.scheme == "https" && ["zh.wikipedia.org", "en.wikipedia.org", "kpop.fandom.com"].contains(url.host ?? "")
            && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
            && !title.isEmpty && title.count <= 200 && !excerpt.isEmpty && excerpt.count <= 1500
    }
}

protocol LianxinPublicResearching: Sendable {
    func lookup(name: String, group: String) async -> [LianxinPublicSource]
}

actor LianxinPublicResearchService: LianxinPublicResearching {
    static let shared = LianxinPublicResearchService()
    private struct Cached { let expires: Date; let sources: [LianxinPublicSource] }
    private var cache: [String: Cached] = [:]
    private struct Page: Sendable { let source: LianxinPublicSource; let englishTitle: String?; let score: Int }

    func lookup(name: String, group: String) async -> [LianxinPublicSource] {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        let group = String(group.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty, !Task.isCancelled else { return [] }
        let key = name + "\u{1f}" + group
        if let value = cache[key], value.expires > .now { return value.sources }
        let query = [name, group].filter { !$0.isEmpty }.joined(separator: " ")
        let deadline = Date().addingTimeInterval(8)
        async let chinese = Self.pages(host: "zh.wikipedia.org", query: query, fanWiki: false, names: [name], group: group, deadline: deadline)
        async let english = Self.pages(host: "en.wikipedia.org", query: query, fanWiki: false, names: [name], group: group, deadline: deadline)
        let (chinesePages, englishPages) = await (chinese, english)
        let wiki = (chinesePages + englishPages).sorted { $0.score > $1.score }
        guard !Task.isCancelled else { return [] }
        // 中文条目的英文跨语言标题可让中文名字找到对应的粉丝Wiki；不内置成员库。
        let aliases = [name] + wiki.compactMap(\.englishTitle)
        let fanQuery = wiki.first?.englishTitle ?? query
        let fan = await Self.pages(host: "kpop.fandom.com", query: fanQuery, fanWiki: true, names: aliases,
                                   group: group, deadline: deadline)
        guard !Task.isCancelled else { return [] }
        var seen = Set<String>()
        let sources = Array((wiki + fan).map(\.source).filter { $0.isAllowed && seen.insert($0.id).inserted }.prefix(3))
        if cache.count >= 16 { cache.removeAll() }
        cache[key] = Cached(expires: .now.addingTimeInterval(sources.isEmpty ? 300 : 21600), sources: sources)
        return sources
    }

    private static func pages(host: String, query: String, fanWiki: Bool, names: [String], group: String, deadline: Date) async -> [Page] {
        guard deadline > .now, !Task.isCancelled else { return [] }
        var components = URLComponents()
        components.scheme = "https"; components.host = host; components.path = fanWiki ? "/api.php" : "/w/api.php"
        var params = ["action": "query", "format": "json", "formatversion": "2", "generator": "search",
            "gsrsearch": query, "gsrlimit": "3", "gsrnamespace": "0", "inprop": "url"]
        if fanWiki {
            params["prop"] = "revisions|info"; params["rvprop"] = "content"; params["rvslots"] = "main"
        } else {
            params["prop"] = "extracts|info|langlinks|pageprops"; params["exintro"] = "1"
            params["exchars"] = "1200"; params["explaintext"] = "1"; params["lllang"] = "en"; params["lllimit"] = "1"
        }
        components.queryItems = params.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { return [] }
        do {
            let data = try await read(url, deadline: deadline)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let result = json?["query"] as? [String: Any]
            return (result?["pages"] as? [[String: Any]] ?? []).compactMap { page in
                guard (page["pageprops"] as? [String: Any])?["disambiguation"] == nil,
                      let title = page["title"] as? String, let rawURL = page["fullurl"] as? String,
                      let pageURL = URL(string: rawURL) else { return nil }
                let revisions = page["revisions"] as? [[String: Any]]
                let slots = revisions?.first?["slots"] as? [String: Any]
                let main = slots?["main"] as? [String: Any]
                let raw = fanWiki ? main?["content"] as? String : page["extract"] as? String
                let excerpt = usefulText(raw ?? "", fanWiki: fanWiki)
                let source = LianxinPublicSource(title: title, url: pageURL, excerpt: excerpt, fetchedAt: .now)
                guard source.isAllowed else { return nil }
                let links = page["langlinks"] as? [[String: String]]
                let englishTitle = links?.first?["title"] ?? (host == "en.wikipedia.org" ? title : nil)
                let score = names.map { identityScore(title: title, excerpt: excerpt, name: $0, group: group) }.max() ?? 0
                guard score > 0 else { return nil }
                return Page(source: source, englishTitle: englishTitle, score: score)
            }
        } catch { return [] } // 资料不可达不会阻断用户自己的AI；不输出服务器正文。
    }

    private static func read(_ url: URL, deadline: Date) async throws -> Data {
        let remaining = min(4, deadline.timeIntervalSinceNow)
        guard remaining > 0 else { throw LianxinError.network }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData; config.timeoutIntervalForResource = remaining
        let session = URLSession(configuration: config, delegate: LianxinRedirectGuard(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.timeoutInterval = remaining
        request.setValue("TodoWallpaper/0.9 (https://github.com/klein7syd/ios-wallpapertest)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // 不使用用户AI密钥，也不发送称呼、提示词、补充或照片。
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw LianxinError.network }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 524288, deadline > .now else { throw LianxinError.invalidResponse }
            data.append(byte)
        }
        return data
    }

    // 没有可靠的本地姓名/团体证据就舍弃候选，不把搜索排名当作身份确认。
    static func identityScore(title: String, excerpt: String, name: String, group: String) -> Int {
        func folded(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func contains(_ text: String, _ needle: String) -> Bool {
            guard !needle.isEmpty else { return false }
            let pattern = "(?<![a-z0-9])" + NSRegularExpression.escapedPattern(for: needle) + "(?![a-z0-9])"
            return text.range(of: pattern, options: .regularExpression) != nil
        }
        let title = folded(title), name = folded(name), group = folded(group), excerpt = folded(excerpt)
        guard contains(title, name) else { return 0 } // 团体页提到成员不够，候选标题必须匹配成员。
        guard group.isEmpty || contains(title + "\n" + excerpt, group) else { return 0 }
        return (title == name ? 4 : 2) + (group.isEmpty ? 0 : 4)
    }

    // 英文按整词检查，避免把unborn等不同词的子串误判；中文仍逐词保守排除。
    private static func containsPrivateInfo(_ text: String) -> Bool {
        let english = #"\b(?:born|birthday|parents?|siblings?|family|dating|health|blood|height|weight|address|net worth)\b"#
        return text.range(of: english, options: [.regularExpression, .caseInsensitive]) != nil
            || ["出生", "生日", "父母", "家人", "健康", "血型", "身高", "体重", "住址", "行程", "恋情", "财产"].contains { text.contains($0) }
    }
    // 出生日期常与职业写在同一简介；只移除明确的私人括注，其余片段继续保守过滤。
    static func usefulText(_ raw: String, fanWiki: Bool) -> String {
        var cleaned = raw.replacingOccurrences(of: #"(?s)<ref\b[^>]*>.*?</ref>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\[\[(?:[^\]|]*\|)?([^\]]+)\]\]"#, with: "$1", options: .regularExpression)
        if let expression = try? NSRegularExpression(pattern: #"\([^()]*\)|（[^（）]*）"#) {
            let matches = expression.matches(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: cleaned) else { continue }
                if containsPrivateInfo(String(cleaned[range])) { cleaned.removeSubrange(range) }
            }
        }
        var selected: [String] = [], trivia = false
        let paragraphs = cleaned.replacingOccurrences(of: ". ", with: ".\n").replacingOccurrences(of: "。", with: "。\n")
        for rawLine in paragraphs.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = line.lowercased()
            if line.hasPrefix("==") {
                let relevant = ["trivia", "facts", "habit", "personality", "趣事", "性格", "爱好"].contains { lower.contains($0) }
                trivia = line.hasPrefix("===") ? trivia || relevant : relevant
                continue
            }
            guard !line.isEmpty, !containsPrivateInfo(line),
                  !line.hasPrefix("|"), !line.contains("{{"), !line.contains("}}"),
                  !lower.hasPrefix("category:"), !lower.hasPrefix("file:") else { continue }
            if !fanWiki || trivia || (selected.isEmpty && ["singer", "rapper", "歌手"].contains(where: { lower.contains($0) })) { selected.append(line) }
        }
        return String(selected.joined(separator: "\n").prefix(1500))
    }
}
