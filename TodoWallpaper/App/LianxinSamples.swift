// Target Membership：App + macOS检查；内置示例不请求网络，不模拟真实人物发言。
import Foundation

enum LianxinSamples {
    static func text(_ profile: LianxinProfile, language: String) -> String {
        let user = String(LianxinRoleRules.clean(profile.userName).prefix(30))
        let idol = String(LianxinRoleRules.clean(profile.idolName).prefix(30))
        let name = idol.isEmpty ? "TA" : idol
        let identity = LianxinLanguageRules.identity(language)
        let lead = user.isEmpty ? "" : user + (identity == "en" ? ", " : "，")
        let templates: [String]
        switch identity {
        case "ko": templates = ["오늘도 수고했어요. \(name)을 떠올릴 때, 자신에게도 따뜻한 마음을 나눠 줘요.", "\(name)을 좋아하는 마음을, 애쓰는 자신에게도 조금 나눠 줘요.", "오늘은 푹 쉬어요. 내일도 \(name)을 좋아하는 마음으로 한 걸음씩 가요.", "\(name)에게 받은 용기가 평범한 오늘에도 함께하길 바라요."]
        case "ja": templates = ["今日もお疲れさま。\(name)を思い出したら、自分にも少し優しくしてね。", "\(name)を好きな気持ちを、頑張る自分にも少し分けてあげて。", "今日はゆっくり休もう。明日も\(name)を思いながら、一歩ずつ進もう。", "\(name)からもらった勇気が、何気ない今日にも寄り添いますように。"]
        case "en": templates = ["You did well today. When you think of \(name), save a little warmth for yourself too.", "Share a little of your love for \(name) with the part of you that keeps trying.", "Rest well today. Tomorrow, take another small step with your love for \(name).", "May the courage you find in \(name) stay with you through this ordinary day."]
        default: templates = ["今天也辛苦啦。想起\(name)时，也给自己留一点暖意。", "喜欢\(name)的这份心情，也记得分一点给努力生活的自己。", "今天先好好休息。明天带着喜欢\(name)的心情，再向前走一步。", "希望\(name)带给你的勇气，也能陪你度过平凡的今天。"]
        }
        return lead + templates[abs((profile.exampleIndex ?? 0) % templates.count)]
    }
    static func response(_ profile: LianxinProfile) throws -> String {
        let original = text(profile, language: LianxinLanguageRules.source(profile))
        guard profile.translationEnabled == true else { return original }
        let data = try JSONSerialization.data(withJSONObject: ["text": original, "translation": text(profile, language: LianxinLanguageRules.target(profile))])
        return String(decoding: data, as: UTF8.self)
    }
}
