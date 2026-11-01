// Target Membership：仅App。角色仅四项，识别与创作合并为一次请求。
import SwiftUI
struct LianxinRoleView: View {
    @ObservedObject var model: LianxinModel
    private enum Field: Hashable { case name, group, user, notes }
    @FocusState private var focused: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("角色").font(.headline)
            TextField("名字（必填）", text: Binding(get: { model.profile.idolName }, set: { model.profile.idolName = String($0.prefix(100)) })).focused($focused, equals: .name)
            if model.profile.exampleContent != true && model.profile.understood != nil {
                if model.profile.confidence == "low" || model.profile.understood?.lowercased() == "unknown" {
                    Text("AI 对这个名字不太确定，建议填写团体，或在补充里写几句关于 TA 的话").font(.caption).foregroundStyle(.orange)
                } else if !(model.profile.understood ?? "").isEmpty { Text("AI 理解的是：" + (model.profile.understood ?? "")).font(.caption).foregroundStyle(.secondary) }
            }
            TextField("团体（可选）", text: Binding(get: { model.profile.groupName ?? "" }, set: { model.profile.groupName = String($0.prefix(100)) })).focused($focused, equals: .group)
            Text("填写团体识别更准确；不填可能认错同名成员").font(.caption).foregroundStyle(.secondary)
            TextField("你的称呼", text: Binding(get: { model.profile.userName }, set: { model.profile.userName = String($0.prefix(100)) })).focused($focused, equals: .user)
            TextField("想要的感觉、你们之间的称呼，或贴 1~3 句你觉得像 TA 的话", text: Binding(get: { model.profile.notes ?? "" }, set: { model.profile.notes = String($0.prefix(500)) }), axis: .vertical).lineLimit(3...8).focused($focused, equals: .notes)
            Text("只填公开形象信息 · 补充最多500字").font(.caption).foregroundStyle(.secondary)
        }.textFieldStyle(LianxinFieldStyle()).padding(14)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous)).disabled(model.busy)
    }
}

struct LianxinLanguageView: View {
    @ObservedObject var model: LianxinModel
    private enum Field: Hashable { case source, target }
    @FocusState private var focused: Field?
    private func selection(_ value: String?) -> String { let value = value ?? "中文"; return LianxinLanguageRules.choices.contains(value) ? value : LianxinLanguageRules.custom }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("语言").font(.headline)
            if model.exampleMode { Text("体验模式提供中/韩/日/英示例；其他语种暂用中文，真实自定义语言请连接 AI。").font(.caption).foregroundStyle(.secondary) }
            Picker("说话语言", selection: Binding(get: { selection(model.profile.sourceLanguage) }, set: { model.updateLanguage(source: $0) })) {
                ForEach(LianxinLanguageRules.choices + [LianxinLanguageRules.custom], id: \.self) { Text($0).tag($0) }
            }
            if selection(model.profile.sourceLanguage) == LianxinLanguageRules.custom {
                TextField("说话语言名称（最多20字）", text: customSource).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .source)
            }
            Toggle("同时生成译文", isOn: Binding(get: { model.profile.translationEnabled == true }, set: { model.updateLanguage(enabled: $0) }))
            if model.profile.translationEnabled == true {
                Picker("翻译成", selection: Binding(get: { model.profile.translationLanguage == LianxinLanguageRules.custom ? LianxinLanguageRules.custom : selection(LianxinLanguageRules.target(model.profile)) }, set: { model.updateLanguage(target: $0) })) {
                    ForEach(LianxinLanguageRules.choices.filter { $0 != LianxinLanguageRules.source(model.profile) } + [LianxinLanguageRules.custom], id: \.self) { Text($0).tag($0) }
                }
                if model.profile.translationLanguage == LianxinLanguageRules.custom || selection(model.profile.translationLanguage) == LianxinLanguageRules.custom {
                    TextField("译文语言名称（最多20字）", text: customTarget).textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .target)
                }
            }
        }.padding(14).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .disabled(model.busy)
    }
    private var customSource: Binding<String> { Binding(get: { model.profile.sourceLanguage == LianxinLanguageRules.custom ? "" : (model.profile.sourceLanguage ?? "") }, set: { model.updateLanguage(source: $0.isEmpty ? LianxinLanguageRules.custom : String($0.prefix(20))) }) }
    private var customTarget: Binding<String> { Binding(get: { model.profile.translationLanguage == LianxinLanguageRules.custom ? "" : (model.profile.translationLanguage ?? "") }, set: { model.updateLanguage(target: $0.isEmpty ? LianxinLanguageRules.custom : String($0.prefix(20))) }) }
}
