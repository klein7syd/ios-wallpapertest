// Target Membership：仅App。每次只处理一步，密钥只在内存与钥匙串之间流转。
import SwiftUI

struct LianxinSetupView: View {
    @ObservedObject var model: LianxinModel
    var onFinished: () -> Void
    private enum Step: Int { case provider, credential, model, connected }
    @State private var step = Step.provider
    @State private var started = false
    @State private var draftKey = ""
    @State private var endpoint = ""
    @State private var modelName = ""
    @State private var editingKey = false
    @State private var revealsKey = false
    @State private var manualModel = false
    @State private var showsDeleteKey = false
    @State private var showsModels = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var message: String?
    @State private var connectionTask: Task<Void, Never>?
    private enum Field: Hashable { case endpoint, key, model }
    @FocusState private var focused: Field?
    @Environment(\.openURL) private var openURL

    private var selectedModel: String { modelName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var testedSelection: Bool { model.connected && selectedModel == model.profile.model }
    private var finalAddress: String { (try? LianxinSetupRules.endpoint(endpoint)) ?? "填写后会在这里显示完整地址" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if step != .connected { progress }
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.title2.bold())
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Group {
                    switch step {
                    case .provider: providers
                    case .credential: credentials
                    case .model: models
                    case .connected: connectionSummary
                    }
                }.disabled(model.busy)
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                if let notice = model.connectionNotice, step != .provider {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
                if connectionTask != nil {
                    HStack {
                        ProgressView("正在测试连接…")
                        Spacer()
                        Button("取消测试") { connectionTask?.cancel() }.frame(minHeight: 44)
                    }
                }
                Text("由你的服务商按用量计费，本 App 不收费，也不会上传你的照片。密钥只保存在本机钥匙串。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground).onTapGesture { focused = nil })
        .safeAreaInset(edge: .bottom) {
            if step != .provider && focused == nil {
                navigation.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .buttonStyle(.plain)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = nil } } }
        .task {
            guard !started else { return }; started = true
            endpoint = model.profile.endpoint; modelName = model.profile.model
            editingKey = !model.keySaved
            step = model.connected ? .connected : model.keySaved && !endpoint.isEmpty ? .model : (model.profile.providerID != nil || !endpoint.isEmpty ? .credential : .provider)
        }
        .onDisappear { connectionTask?.cancel(); draftKey = ""; revealsKey = false }
        .onChange(of: modelName) { _, value in
            message = nil; model.connectionNotice = nil
            guard !model.busy, value.count <= 200 else { return }
            Task { await model.chooseModel(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
        .sheet(isPresented: $showsModels) {
            LianxinModelSelection(models: model.availableModels, recommended: model.provider.model, selection: $modelName)
        }
        .onChange(of: step) { _, _ in message = nil; model.connectionNotice = nil; focused = nil }
        .confirmationDialog("删除这个服务商的密钥？其他服务商的密钥会保留。", isPresented: $showsDeleteKey, titleVisibility: .visible) {
            Button("删除密钥", role: .destructive) {
                if model.saveKey("") { draftKey = ""; revealsKey = false; editingKey = true; step = .credential }
            }
        }
    }

    private var title: String {
        switch step {
        case .provider: return "先选你使用的服务商"
        case .credential: return "接入 " + model.provider.name
        case .model: return "选择模型，测试后完成"
        case .connected: return "AI 已连接"
        }
    }
    private var detail: String {
        switch step {
        case .provider: return "密钥要和服务商对应。不清楚选哪个？选择你已注册并开通 API 的平台。"
        case .credential: return "已有密钥就直接粘贴；没有的话，先到官方页面创建。"
        case .model: return "通常保留当前推荐模型就好。更换模型后，需要重新测试。"
        case .connected: return "当前连接已保存，可以回到连心生成话语。"
        }
    }
    private var progressLayout: AnyLayout { typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8)) }
    private var progress: some View {
        progressLayout {
            ForEach(0..<3, id: \.self) { index in
                Text(["1 服务商", "2 密钥", "3 模型与测试"][index]).font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(index == min(step.rawValue, 2) ? Color.accentColor.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
    private func primary(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.borderedProminent)
    }
    private var providers: some View {
        VStack(spacing: 10) {
            ForEach(LianxinProviderPreset.all) { preset in
                Button {
                    focused = nil; message = nil
                    Task {
                        await model.selectProvider(preset.id)
                        endpoint = model.profile.endpoint; modelName = model.profile.model
                        draftKey = ""; revealsKey = false; editingKey = !model.keySaved; manualModel = false
                        step = .credential
                    }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(preset.name).font(.headline).foregroundStyle(.primary)
                            Text(preset.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: preset.id == model.profile.providerID ? "checkmark.circle.fill" : "chevron.right").foregroundStyle(Color.accentColor)
                    }.padding(18).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
    }
    private var credentials: some View {
        VStack(spacing: 16) {
            card {
                HStack { Text(model.provider.name).font(.headline); Spacer(); Button("更换服务商") { step = .provider; message = nil } }
                if model.provider.id == "custom" {
                    Text("接口地址").font(.subheadline.weight(.medium))
                    TextField("粘贴 Base URL 或完整聊天接口", text: $endpoint).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .endpoint)
                    Text("最终地址：" + finalAddress).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    if endpoint.lowercased().hasPrefix("http://") { Text("需要 https，请向服务商确认安全地址。").font(.caption).foregroundStyle(.red) }
                } else if let url = URL(string: model.provider.keyPage) {
                    Button { focused = nil; openURL(url) } label: {
                        Label("前往官方页面获取密钥", systemImage: "safari").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered)
                    Text("登录后找到 API Key，创建并复制，再回到这里粘贴。聊天会员和 API 额度通常分开。").font(.caption).foregroundStyle(.secondary)
                }
            }
            card {
                Text("API 密钥").font(.headline)
                Text("发送到：" + ((URL(string: finalAddress)?.host) ?? model.provider.name)).font(.caption).foregroundStyle(.secondary)
                if !model.keySaved { Button("重新读取已保存的密钥") { Task { await model.retryCredentials() } }.font(.caption).frame(minHeight: 44) }
                if model.keySaved {
                    HStack {
                        Label("已保存 · 尾号 " + model.keySuffix, systemImage: "checkmark.shield").font(.subheadline)
                        Spacer()
                        Button(editingKey ? "取消更换" : "更换") { editingKey.toggle(); draftKey = ""; revealsKey = false }
                    }
                }
                if editingKey || !model.keySaved {
                    HStack(spacing: 8) {
                        Group {
                            if revealsKey { TextField("粘贴 API 密钥", text: $draftKey) }
                            else { SecureField("粘贴 API 密钥", text: $draftKey) }
                        }.textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .key)
                        Button { revealsKey.toggle() } label: {
                            Image(systemName: revealsKey ? "eye.slash" : "eye").frame(width: 44, height: 44)
                        }.accessibilityLabel(revealsKey ? "隐藏密钥" : "显示新输入的密钥")
                    }
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { draftKey = LianxinSetupRules.cleanKey(value) }
                    }
                    Text("点“继续”时保存新密钥；关闭页面不会保存尚未提交的密钥。").font(.caption).foregroundStyle(.secondary)
                }
                if model.keySaved { Button("删除这个服务商的密钥", role: .destructive) { showsDeleteKey = true }.font(.caption).frame(minHeight: 44) }
            }
        }
    }
    private var models: some View {
        card {
            Text("当前模型").font(.headline)
            if !model.availableModels.isEmpty && !manualModel && model.provider.id != "custom" {
                Button { showsModels = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 5) { Text("选择模型").font(.caption); Text(modelName).font(.body.monospaced()).multilineTextAlignment(.leading) }
                        Spacer(); Image(systemName: "chevron.up.chevron.down")
                    }.frame(minHeight: 44)
                }.buttonStyle(.bordered)
            } else if model.provider.id == "custom" || manualModel {
                TextField("填写服务商提供的模型名称", text: $modelName).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textFieldStyle(LianxinFieldStyle()).focused($focused, equals: .model)
            } else {
                Text(modelName).font(.body.monospaced()).textSelection(.enabled)
            }
            if model.provider.id != "custom" {
                Button(manualModel ? "使用推荐模型" : "手动填写其他模型") {
                    manualModel.toggle()
                    if !manualModel { modelName = model.provider.model }
                    message = nil
                }.font(.subheadline).frame(minHeight: 44)
            }
            if testedSelection {
                Label("连接测试通过", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Text("可以直接完成；也可以先选其他模型，再重新测试。").font(.caption).foregroundStyle(.secondary)
                Button("重新测试") { startTesting() }.frame(minHeight: 44)
            } else {
                Text(model.connected ? "模型已修改，请测试这次的选择。" : "测试通过后，就可以完成设置。").font(.caption).foregroundStyle(.secondary)
            }
            Text("模型选择自动保存在本机。测试会向当前模型发送极短请求，可能产生少量费用；只有测试成功才显示已连接。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var connectionSummary: some View {
        card {
            Label(model.provider.name, systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(.green)
            Text(model.profile.model).font(.body.monospaced()).textSelection(.enabled)
            Text("密钥已保存 · 尾号 " + model.keySuffix).font(.caption).foregroundStyle(.secondary)
            Divider()
            Button("更换模型") { modelName = model.profile.model; step = .model; message = nil }.frame(minHeight: 44)
            Button("修改密钥或接口") { endpoint = model.profile.endpoint; editingKey = !model.keySaved; step = .credential; message = nil }.frame(minHeight: 44)
            Button("更换服务商") { step = .provider; message = nil }.frame(minHeight: 44)
        }
    }
    @ViewBuilder private var navigation: some View {
        VStack(spacing: 10) {
            switch step {
            case .provider: EmptyView()
            case .credential:
                primary("继续：选择模型", action: continueToModel)
                    .disabled(model.busy || (!model.keySaved && LianxinSetupRules.cleanKey(draftKey).isEmpty))
                Button("上一步：服务商") { step = .provider; message = nil }.frame(minHeight: 44).disabled(model.busy)
            case .model:
                if testedSelection {
                    primary("完成设置，回到连心", action: finish).disabled(model.busy)
                } else {
                    primary("测试连接", action: startTesting).disabled(model.busy || selectedModel.isEmpty)
                }
                Button("上一步：密钥") { step = .credential; message = nil }.frame(minHeight: 44).disabled(model.busy)
            case .connected:
                primary("回到连心", action: onFinished).disabled(model.busy)
            }
        }.controlSize(.large).frame(maxWidth: .infinity)
            .buttonBorderShape(.roundedRectangle(radius: 18))
    }
    private func continueToModel() {
        focused = nil; message = nil; model.connectionNotice = nil
        do {
            let address = try LianxinSetupRules.endpoint(model.provider.id == "custom" ? endpoint : model.profile.endpoint)
            let cleaned = LianxinSetupRules.cleanKey(draftKey)
            if !draftKey.isEmpty && cleaned.isEmpty { message = "请粘贴完整密钥，或取消更换以使用已保存的密钥。"; return }
            if !cleaned.isEmpty && !model.saveKey(cleaned) { return }
            guard model.keySaved else { message = "请先粘贴这个服务商的密钥。"; return }
            model.profile.endpoint = address; endpoint = address
            draftKey = ""; revealsKey = false; editingKey = false; step = .model
        } catch { message = (error as? LianxinError)?.localizedDescription ?? "接口地址不完整，请核对后继续。" }
    }
    private func startTesting() {
        guard !model.busy, connectionTask == nil else { return }
        guard !selectedModel.isEmpty, selectedModel.count <= 200 else { message = "请填写正确的模型名称（最多200字）。"; return }
        focused = nil; message = nil
        connectionTask = Task { @MainActor in
            await model.chooseModel(selectedModel)
            await model.testConnection()
            connectionTask = nil
        }
    }
    private func finish() {
        focused = nil; message = nil
        Task {
            if await model.finishSetup() { onFinished() }
            else { message = "设置暂未保存，请稍后重试。"; model.error = nil }
        }
    }
}

// 大目录用原生搜索列表，避免把数百个模型塞进菜单。
private struct LianxinModelSelection: View {
    let models: [String]
    let recommended: String
    @Binding var selection: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss
    private var choices: [String] {
        let values = Set(models + [recommended, selection]).filter { !$0.isEmpty }
        return values.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }
            .sorted { left, right in
                if left == recommended { return right != recommended }
                if right == recommended { return false }
                return left < right
            }
    }
    var body: some View {
        NavigationStack {
            List(choices, id: \.self) { value in
                Button { selection = value; dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(value).foregroundStyle(.primary)
                            if value == recommended { Text("推荐").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        if value == selection { Image(systemName: "checkmark").accessibilityLabel("当前选择") }
                    }.frame(minHeight: 44)
                }
            }.searchable(text: $search, prompt: "搜索模型名称")
                .navigationTitle("选择模型").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
