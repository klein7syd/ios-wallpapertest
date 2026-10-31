// Target Membership：仅App；角色核对必须主动点按并逐字段确认。
import SwiftUI

struct LianxinRoleView: View {
    @ObservedObject var model: LianxinModel
    @State private var aliasCount = 1
    private enum Field: Hashable { case name, group, user, alias(Int), position, fan, personality, catchphrase, example(Int), notes, review(String) }
    @FocusState private var focused: Field?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            roleCard
            if model.pendingRole != nil { reviewCard }
        }
        .textFieldStyle(LianxinFieldStyle())
        .onAppear { aliasCount = min(5, max(1, model.profile.otherNames?.count ?? 0)) }
        .onChange(of: model.profile.otherNames?.count) { _, count in aliasCount = max(aliasCount, min(5, count ?? 0)) }
    }
    private var roleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("角色").font(.headline)
            TextField("名字（必填，最多100字）", text: required(\.idolName)).focused($focused, equals: .name)
            recent(model.profile.recentNames ?? [], path: \.idolName)
            TextField("团体/队名（可选）", text: optional(\.groupName, 100)).focused($focused, equals: .group)
            Text("团体可不填；不填时同名成员可能被混淆，生成的话会不够贴合。")
                .font(.caption).foregroundStyle(.secondary)
            recentGroups
            TextField("你的称呼（最多100字）", text: required(\.userName)).focused($focused, equals: .user)
            Label("贴合度：" + LianxinRoleRules.fit(model.profile).rawValue, systemImage: "person.text.rectangle")
                .font(.subheadline)
            if let suggestion = LianxinRoleRules.suggestion(model.profile) { Text(suggestion).font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("让话更像 TA") { details.padding(.top, 12) }
            Text("只填公开形象信息。请勿填写住址、联系方式、私人行程、感情、健康或金钱信息。")
                .font(.caption).foregroundStyle(.secondary)
            Button("核对 TA") { focused = nil; model.checkRole() }
                .buttonStyle(.bordered).frame(minHeight: 44).disabled(!model.connected || model.exampleMode || model.busy || model.profile.idolName.isEmpty)
            Text("可选：主动点击才向你自己的 AI 发出一次请求；结果需你确认。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .disabled(model.busy)
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<aliasCount, id: \.self) { index in
                TextField("其他写法 \(index + 1)（最多30字）", text: array(\.otherNames, index: index, limit: 30)).focused($focused, equals: .alias(index))
            }
            if aliasCount < 5 { Button("添加其他写法") { aliasCount += 1 }.frame(minHeight: 44) }
            TextField("定位，如主唱/队长（最多30字）", text: optional(\.position, 30)).focused($focused, equals: .position)
            TextField("粉丝名/应援名（最多30字）", text: optional(\.fanName, 30)).focused($focused, equals: .fan)
            TextField("性格与说话习惯（最多200字）", text: optional(\.personality, 200), axis: .vertical).lineLimit(2...5).focused($focused, equals: .personality)
            TextField("口头禅/称呼粉丝的方式（最多100字）", text: optional(\.catchphrases, 100), axis: .vertical).lineLimit(2...4).focused($focused, equals: .catchphrase)
            Text("示例话语 · 只学习语气，不会被照抄").font(.caption).foregroundStyle(.secondary)
            ForEach(0..<3, id: \.self) { index in
                TextField("示例话语 \(index + 1)（最多100字）", text: array(\.exampleLines, index: index, limit: 100), axis: .vertical).lineLimit(2...4).focused($focused, equals: .example(index))
            }
            TextField("其他补充（最多300字）", text: optional(\.notes, 300), axis: .vertical).lineLimit(2...6).focused($focused, equals: .notes)
        }
    }
    private var reviewCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我理解的是：").font(.headline)
            TextField("名字", text: review(\.member, 100)).focused($focused, equals: .review("member"))
            TextField("团体", text: review(\.group, 100)).focused($focused, equals: .review("group"))
            ForEach(0..<5, id: \.self) { index in
                TextField("其他写法 \(index + 1)", text: reviewAlias(index)).focused($focused, equals: .review("alias\(index)"))
            }
            TextField("定位", text: review(\.position, 30)).focused($focused, equals: .review("position"))
            TextField("粉丝名", text: review(\.fanName, 30)).focused($focused, equals: .review("fan"))
            TextField("补充（最多100字）", text: review(\.notes, 100), axis: .vertical).lineLimit(2...4).focused($focused, equals: .review("notes"))
            Toggle("这是我想的角色", isOn: Binding(get: { model.pendingRole?.recognized == true }, set: { model.pendingRole?.recognized = $0 }))
            Picker("核对结果把握", selection: Binding(get: { model.pendingRole?.confidence ?? "low" }, set: { model.pendingRole?.confidence = $0 })) {
                Text("高").tag("high"); Text("中").tag("medium"); Text("低").tag("low")
            }
            Text("AI 的知识可能过时或不了解较新、较小众的成员，请核对；不对请直接修改或补充团体。")
                .font(.caption).foregroundStyle(.secondary)
            Button("确认并保存") { focused = nil; Task { await model.confirmRole() } }
                .buttonStyle(.borderedProminent).frame(minHeight: 44)
                .disabled(model.pendingRole?.reviewable != true || LianxinRoleRules.clean(model.pendingRole?.member).isEmpty)
            Button("不对，重新填写") { model.pendingRole = nil; focused = .group }.frame(minHeight: 44)
        }.padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
    private func required(_ path: WritableKeyPath<LianxinProfile, String>) -> Binding<String> {
        Binding(get: { model.profile[keyPath: path] }, set: { model.profile[keyPath: path] = String($0.prefix(100)) })
    }
    private func optional(_ path: WritableKeyPath<LianxinProfile, String?>, _ limit: Int) -> Binding<String> {
        Binding(get: { model.profile[keyPath: path] ?? "" }, set: { model.profile[keyPath: path] = String($0.prefix(limit)) })
    }
    private func array(_ path: WritableKeyPath<LianxinProfile, [String]?>, index: Int, limit: Int) -> Binding<String> {
        Binding(get: { let values = model.profile[keyPath: path] ?? []; return values.indices.contains(index) ? values[index] : "" }, set: { text in
            var values = model.profile[keyPath: path] ?? []; while values.count <= index { values.append("") }
            values[index] = String(text.prefix(limit)); model.profile[keyPath: path] = values
        })
    }
    private func review(_ path: WritableKeyPath<LianxinRoleResult, String>, _ limit: Int) -> Binding<String> {
        Binding(get: { model.pendingRole?[keyPath: path] ?? "" }, set: { model.pendingRole?[keyPath: path] = String($0.prefix(limit)) })
    }
    private func reviewAlias(_ index: Int) -> Binding<String> {
        Binding(get: { let values = model.pendingRole?.otherNames ?? []; return values.indices.contains(index) ? values[index] : "" }, set: { text in
            guard var value = model.pendingRole else { return }; while value.otherNames.count <= index { value.otherNames.append("") }
            value.otherNames[index] = String(text.prefix(30)); model.pendingRole = value
        })
    }
    private func recent(_ values: [String], path: WritableKeyPath<LianxinProfile, String>) -> some View {
        ScrollView(.horizontal) { HStack { ForEach(values, id: \.self) { name in Button(name) { model.profile[keyPath: path] = name }.font(.caption).frame(minHeight: 44).buttonStyle(.bordered) } } }.scrollIndicators(.hidden)
    }
    private var recentGroups: some View {
        ScrollView(.horizontal) { HStack { ForEach(model.profile.recentGroups ?? [], id: \.self) { group in Button(group) { model.profile.groupName = group }.font(.caption).frame(minHeight: 44).buttonStyle(.bordered) } } }.scrollIndicators(.hidden)
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
