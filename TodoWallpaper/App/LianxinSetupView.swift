// Target Membership：仅App。分步向导使用系统浏览器和PasteButton。
import SwiftUI

struct LianxinSetupView: View {
    @ObservedObject var model: LianxinModel
    @State private var choosing = false
    @State private var draftKey = ""
    @State private var revealsKey = false
    @Environment(\.openURL) private var openURL
    private var finalAddress: String { (try? LianxinSetupRules.endpoint(model.profile.endpoint)) ?? "请填写有效的HTTPS地址" }
    var body: some View {
        Group {
            if model.connected && !choosing {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已连接：\(model.provider.name) · \(model.profile.model)").font(.headline)
                    Button("更换服务商") { choosing = true }
                    Button("重新测试") { Task { await model.testConnection() } }
                    Button("清除密钥", role: .destructive) { _ = model.saveKey("") }
                    if let notice = model.connectionNotice { Text(notice).font(.caption) }
                }.disabled(model.busy)
            } else { wizard }
        }
    }
    private var wizard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(model.connected ? "已连接：\(model.provider.name) · \(model.profile.model)" : "连接AI，跟着做就好", systemImage: model.connected ? "checkmark.circle.fill" : "wand.and.stars")
                .font(.headline)
            Button("没有密钥？先体验") { model.exampleMode = true; model.generate() }
                .frame(minHeight: 44)
            HStack {
                Text("1. 选服务商：\(model.provider.name)").font(.subheadline)
                Spacer()
                Button(choosing ? "收起" : "更换") { choosing.toggle() }.frame(minHeight: 44)
            }
            if choosing || model.profile.providerID == nil && model.profile.endpoint.isEmpty {
                ForEach(LianxinProviderPreset.all) { preset in
                    Button {
                        Task { await model.selectProvider(preset.id); draftKey = ""; revealsKey = false; choosing = false }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name).font(.headline)
                                Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.provider.id == preset.id { Image(systemName: "checkmark.circle.fill") }
                        }.padding(12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
            }
            if model.provider.id != "custom", let url = URL(string: model.provider.keyPage) {
                Text("2. 获取密钥").font(.subheadline)
                Button { openURL(url) } label: { Label("获取密钥", systemImage: "safari").frame(minHeight: 44) }.buttonStyle(.bordered)
                Text("在官方页面登录或注册，找到 API Key，创建并复制。\n回到这里粘贴；聊天会员不一定包含API额度。")
                    .font(.caption).foregroundStyle(.secondary)
                Text(model.provider.detail).font(.caption).foregroundStyle(.secondary)
            }
            if model.provider.id == "custom" {
                Text("2. 按服务商说明填写").font(.subheadline)
                TextField("域名、Base URL或完整接口地址", text: $model.profile.endpoint)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            }
            Text("最终聊天地址：\(finalAddress)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if model.profile.endpoint.lowercased().hasPrefix("http://") { Text("需要 https，请向服务商确认安全地址。").font(.caption).foregroundStyle(.red) }
            Text("3. 粘贴密钥").font(.subheadline)
            HStack {
                Group {
                    if revealsKey { TextField("粘贴新密钥", text: $draftKey) }
                    else { SecureField("粘贴新密钥", text: $draftKey) }
                }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                Button { revealsKey.toggle() } label: { Image(systemName: revealsKey ? "eye.slash" : "eye").frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel(revealsKey ? "隐藏密钥" : "显示新输入的密钥")
            }
            HStack {
                PasteButton(payloadType: String.self) { values in
                    if let value = values.first { draftKey = LianxinSetupRules.cleanKey(value) }
                }
                Button("保存密钥") {
                    if model.saveKey(draftKey) { draftKey = ""; revealsKey = false }
                }.frame(minHeight: 44).disabled(draftKey.isEmpty)
            }
            if model.keySaved {
                HStack {
                    Text("已保存 ✓ 尾号 \(model.keySuffix)").font(.caption)
                    Spacer()
                    Button("删除密钥", role: .destructive) { _ = model.saveKey("") }.font(.caption).frame(minHeight: 44)
                }
            }
            Text("4. 测试连接并选择模型").font(.subheadline)
            if !model.availableModels.isEmpty {
                Picker("模型", selection: Binding(get: { model.profile.model }, set: { value in Task { await model.chooseModel(value) } })) {
                    ForEach(Array(Set(model.availableModels + [model.profile.model])).sorted(), id: \.self) { Text($0).tag($0) }
                }.pickerStyle(.menu)
            } else if model.provider.id == "custom" || model.provider.modelsEndpoint == nil {
                TextField("模型名称（已预填，可修改）", text: $model.profile.model).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textFieldStyle(.roundedBorder)
            } else { Text("推荐模型：\(model.profile.model)").font(.caption) }
            Button { Task { await model.testConnection() } } label: {
                Label("测试连接", systemImage: "network").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.borderedProminent).disabled(!model.keySaved)
            Text("测试会访问模型列表；没有可用列表时发送极短请求，可能产生少量费用。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.connectionNotice { Text(message).font(.footnote).textSelection(.enabled) }
            if model.connected { Label("已连接：\(model.provider.name) · \(model.profile.model)", systemImage: "checkmark.circle.fill").font(.footnote) }
            if model.connected {
                Button("完成设置") { Task { await model.finishSetup() } }.buttonStyle(.borderedProminent).frame(minHeight: 44)
            }
            Text("由你的服务商按用量计费，本 App 不收费，也不会上传你的照片。")
                .font(.caption).foregroundStyle(.secondary)

        }
        .disabled(model.busy)
        .onChange(of: model.profile.providerID) { _, _ in draftKey = ""; revealsKey = false }
    }
}
