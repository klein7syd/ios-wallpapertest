// Target Membership：仅 App。独立私有目录，避免小组件图片回收影响连心底图。
import SwiftUI
import Security
import WidgetKit
import Combine

enum LianxinKeychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "org.todowallpaper.lianxin", kSecAttrAccount as String: account]
    }
    static func read(account: String) throws -> String {
        var query = query(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw LianxinError.storage }
        return value
    }
    static func save(_ value: String, account: String) throws {
        let query = query(account)
        if value.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw LianxinError.storage }
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LianxinError.storage }
    }
}

actor LianxinStorage {
    private func directory() throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Lianxin", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func load() throws -> (LianxinProfile, Data?) {
        let root = try directory()
        let file = root.appendingPathComponent("profile-v1.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return (LianxinProfile(), nil) }
        let profile = try JSONDecoder().decode(LianxinProfile.self, from: Data(contentsOf: file))
        let photo: Data?
        if let name = profile.photoName {
            photo = try Data(contentsOf: WidgetPhotoReference.url(for: name, in: root))
        } else { photo = nil }
        return (profile, photo)
    }
    func save(_ profile: LianxinProfile) throws {
        try JSONEncoder().encode(profile).write(to: directory().appendingPathComponent("profile-v1.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func importPhoto(_ data: Data) async throws -> (String, Data) {
        let root = try directory()
        let name = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: root)
        do { try data.write(to: root.appendingPathComponent(name + ".source"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { removePhoto(name); throw error }
        return (name, try Data(contentsOf: WidgetPhotoReference.url(for: name, in: root)))
    }
    func photoData(_ name: String?, original: Bool = false) throws -> Data? {
        guard let name else { return nil }
        let root = try directory()
        let thumbnail = try WidgetPhotoReference.url(for: name, in: root)
        let source = root.appendingPathComponent(name + ".source")
        return try Data(contentsOf: original && FileManager.default.fileExists(atPath: source.path) ? source : thumbnail)
    }
    func publish(_ content: LianxinPublication, directory: URL) throws {
        try content.save(directory: directory)
    }
    func currentContent(directory: URL) throws -> LianxinPublication? { try LianxinPublication.load(directory: directory) }
    func removePhoto(_ name: String?) {
        guard let name, let root = try? directory(), let url = try? WidgetPhotoReference.url(for: name, in: root) else { return }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: root.appendingPathComponent(name + ".source"))
    }
}

@MainActor
final class LianxinModel: ObservableObject {
    @Published var profile = LianxinProfile() { didSet { if loaded && oldValue != profile { scheduleInputSave(); scheduleSync() } } }
    @Published var key = ""
    @Published private(set) var photo: UIImage?
    @Published private(set) var loaded = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published var exampleMode = false
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var keySaved = false
    @Published var connectionNotice: String?
    weak var styleStore: TodoStore?
    @Published private(set) var currentContent: LianxinPublication?
    @Published private(set) var syncedAt: Date?
    @Published private(set) var syncError: String?
    var publication: LianxinPublication { currentContent ?? draftContent }
    private var draftContent: LianxinPublication {
        LianxinPublication(idol: profile.messageIdol.isEmpty ? profile.idolName : profile.messageIdol, text: profile.message, photo: nil, date: .distantPast, example: profile.exampleContent)
    }
    private var syncTask: Task<Void, Never>?
    private var styleObserver: AnyCancellable?
    private let storage = LianxinStorage()
    private let service: any AIServiceProtocol
    private var generation: Task<Void, Never>?
    private var generationID = UUID()

    private let connection: any LianxinConnectionService
    init(service: any AIServiceProtocol = LianxinAPIService(), connection: any LianxinConnectionService = LianxinAPIService()) {
        self.service = service; self.connection = connection
    }
    var provider: LianxinProviderPreset { LianxinProviderPreset.preset(profile.providerID) }
    private var credentialAccount: String { LianxinSetupRules.account(provider.id) }
    private var signature: String { provider.id + "|" + profile.endpoint + "|" + profile.model }
    var connected: Bool { LianxinWritingRules.connected(profile: profile, hasKey: !key.isEmpty) }
    var configurationComplete: Bool { connected }
    var keySuffix: String { String(key.suffix(4)) }


    func load() async {
        guard !loaded else { return }
        do {
            let saved = try await storage.load()
            profile = saved.0; photo = saved.1.flatMap { UIImage(data: $0) }
            loaded = true
            if let directory = try? mediaDirectory() { currentContent = try? await storage.currentContent(directory: directory) }
            scheduleSync()
            do {
                try LianxinCredentialMigration.migrate(profile: profile, store: LianxinSystemCredentials())
                key = try LianxinKeychain.read(account: credentialAccount); keySaved = !key.isEmpty
            }
            catch { notice = "密钥暂时无法读取，请解锁设备后重试；其他连心资料仍可查看。" }
        } catch { self.error = "连心资料读取失败，原文件已保留。请稍后重新打开页面重试。" }
    }

    func saveSettings() async -> Bool {
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            // 不把密钥写入普通文件；资料保存失败时恢复原钥匙串值。
            if !profile.endpoint.isEmpty { profile.endpoint = try LianxinSetupRules.endpoint(profile.endpoint) }
            try await storage.save(profile)
            notice = "已保存"
            return true
        } catch { self.error = "设置未能完整保存，请重试。"; return false }
    }

    private var inputSaveTask: Task<Void, Never>?
    private func scheduleInputSave() {
        inputSaveTask?.cancel()
        let value = profile
        inputSaveTask = Task {
            do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation(); try await storage.save(value) }
            catch is CancellationError { }
            catch { self.error = "输入暂未保存，请重试。" }
        }
    }
    func saveInputsNow() async {
        inputSaveTask?.cancel()
        do { try await storage.save(profile) } catch { self.error = "输入未保存，请重试。" }
    }
    private func mediaDirectory() throws -> URL {
        if let store = styleStore { return try store.mediaDirectory() }
        return try TodoSharedStorage.sharedDirectory()
    }
    func wallpaperPhotoData() async throws -> Data? {
        if let store = styleStore, store.appearance.lianxin != nil {
            guard let name = store.appearance.lianxin?.photoName(at: .now) else { return nil }
            if name == profile.sharedPhotoName, let original = try await storage.photoData(profile.photoName, original: true) { return original }
            return try Data(contentsOf: WidgetPhotoReference.url(for: name, in: mediaDirectory()))
        }
        return try await storage.photoData(profile.photoName, original: true)
    }
    func syncBackdrop() async throws {
        guard let store = styleStore else { return }
        var root = store.appearance; root.initializeLianxin()
        if let data = try await storage.photoData(profile.photoName) {
            let name = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: mediaDirectory())
            root.lianxin?.backgroundPhotoName = name; root.lianxin?.backdrop = .photo
            root.lianxin?.photoRotation?.enabled = false; root.lianxin?.backgroundCrop = PhotoCrop()
            try store.saveAppearance(root)
            profile.sharedPhotoName = name
        } else {
            root.lianxin?.backgroundPhotoName = nil; root.lianxin?.photoRotation = nil; root.lianxin?.backdrop = .system
            try store.saveAppearance(root); profile.sharedPhotoName = nil
        }
        try await storage.save(profile)
    }

    func prepareStyle(_ store: TodoStore) async {
        styleStore = store
        if styleObserver == nil {
            styleObserver = store.$appearance.map(\.lianxin).removeDuplicates().dropFirst().sink { [weak self] _ in self?.scheduleSync() }
        }
        guard store.appearance.lianxin == nil else { return }
        do {
            var name: String?
            let legacyPhoto = try await storage.photoData(profile.photoName)
            let publishedPhoto = try LianxinPublication.load(directory: mediaDirectory())?.photo
            if let data = legacyPhoto ?? publishedPhoto { name = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: mediaDirectory()) }
            profile.sharedPhotoName = name
            var root = store.appearance; root.initializeLianxin(photoName: name)
            try store.saveAppearance(root)
        } catch { self.error = "连心样式初始化失败，请重试。" }
    }
    func selectProvider(_ id: String) async {
        guard !busy else { return }
        let next = LianxinProviderPreset.preset(id)
        guard next.id != profile.providerID else { return }
        let keepsLegacyCustom = next.id == "custom" && provider.id == "custom"
        profile.providerID = next.id
        if !keepsLegacyCustom { profile.endpoint = next.endpoint; profile.model = next.model }
        profile.connectedSignature = nil; availableModels = []; connectionNotice = nil; key = ""; keySaved = false
        do { key = try LianxinKeychain.read(account: credentialAccount); keySaved = !key.isEmpty }
        catch { connectionNotice = "密钥暂时无法读取，请解锁设备后重试。" }
    }
    func saveKey(_ input: String) -> Bool {
        guard !busy else { return false }
        let cleaned = LianxinSetupRules.cleanKey(input)
        guard cleaned.count <= 4096, cleaned.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            connectionNotice = "密钥中还有空格或换行，请重新完整复制。"; return false
        }
        do {
            try LianxinKeychain.save(cleaned, account: credentialAccount)
            key = cleaned; keySaved = !cleaned.isEmpty; profile.connectedSignature = nil; connectionNotice = nil
            return true
        } catch { connectionNotice = "密钥未保存，请解锁设备并检查签名后重试。"; return false }
    }
    func testConnection() async {
        guard !busy else { return }
        busy = true; connectionNotice = nil
        defer { busy = false }
        do {
            profile.endpoint = try LianxinSetupRules.endpoint(profile.endpoint)
            guard !key.isEmpty else { throw LianxinError.invalidKey }
            let models = try await connection.test(profile: profile, key: key, provider: provider)
            availableModels = models
            if profile.model.isEmpty { profile.model = models.first ?? provider.model }
            profile.connectedSignature = signature
            try await storage.save(profile)
            connectionNotice = "✓ 测试成功。模型列表不代表每个模型都已开通，生成时仍以服务商权限为准。"
            exampleMode = false
        } catch {
            profile.connectedSignature = nil
            connectionNotice = (error as? LianxinError)?.localizedDescription ?? LianxinError.network.localizedDescription
        }
    }
    func finishSetup() async {
        guard connected else { return }
        profile.setupFinished = true
        if !(await saveSettings()) { profile.setupFinished = false }
    }
    func chooseModel(_ value: String) async {
        profile.model = value
        // 模型改变后需再次测试，避免沿用其他模型的成功状态。
        profile.connectedSignature = nil
    }

    func setPhoto(_ data: Data?) async {
        guard loaded, !busy else { return }
        busy = true
        defer { busy = false }
        let oldName = profile.photoName
        var importedName: String?
        var privatePhotoCommitted = false
        do {
            var updated = profile
            var image: UIImage?
            if let data {
                let imported = try await storage.importPhoto(data)
                importedName = imported.0
                guard let decoded = UIImage(data: imported.1) else { throw LianxinError.storage }
                updated.photoName = imported.0; image = decoded
            } else { updated.photoName = nil }
            try Task.checkCancellation()
            try await storage.save(updated)
            privatePhotoCommitted = true
            profile = updated; photo = image
            try await syncBackdrop()
            await storage.removePhoto(oldName)
        } catch {
            if !privatePhotoCommitted { await storage.removePhoto(importedName) }
            if privatePhotoCommitted { self.error = "照片已保留，但共享样式尚未更新，请重新选择后重试。"; return }
            if !(error is CancellationError) { self.error = "底图未能保存，原来的照片已保留。" }
        }
    }

    func generate() {
        guard loaded, !busy else { return }
        let input = profile
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do { if !exampleMode { _ = try LianxinAPIService.request(profile: input, key: secret) } }
        catch { self.error = error.localizedDescription; return }
        busy = true; notice = nil
        let isExample = exampleMode
        let id = UUID(); generationID = id
        generation = Task {
            defer { if generationID == id { busy = false; generation = nil } }
            do {
                let text = try await LianxinGeneration.generate(example: isExample, profile: input, key: secret, service: service)
                try Task.checkCancellation()
                guard generationID == id else { return }
                var updated = input
                updated.message = text; updated.messageIdol = input.idolName.isEmpty ? "连心" : input.idolName
                updated.exampleContent = isExample
                if isExample { updated.exampleIndex = ((input.exampleIndex ?? 0) % 4) + 1 }
                else { updated.connectedSignature = signature }
                try await storage.save(updated)
                profile = updated
            } catch is CancellationError { }
            catch let failure as URLError where failure.code == .cancelled { }
            catch {
                guard generationID == id else { return }
                // 不直接显示网络底层描述或服务端正文，以免回显密钥和提示词。
                self.error = (error as? LianxinError)?.localizedDescription ?? "生成未完成，请检查网络和接口后重试。原有话语已保留。"
            }
        }
    }

    func cancel() { generation?.cancel() }

    func scheduleSync() {
        guard loaded else { return }
        syncTask?.cancel()
        let draft = draftContent
        guard (try? draft.validate()) != nil else { return } // 无效输入不覆盖上一份有效内容。
        if currentContent?.text != draft.text || currentContent?.idol != draft.idol || currentContent?.example != draft.example {
            currentContent = LianxinPublication(idol: draft.idol, text: draft.text, photo: nil, date: .now, example: draft.example)
        }
        let content = publication
        syncTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation()
                // 样式和照片引用先落盘；共享内容里没有接口、提示词或凭证。
                styleStore?.flushAppearance()
                if styleStore?.appearanceError != nil { throw LianxinError.storage }
                try await storage.publish(content, directory: mediaDirectory())
                try Task.checkCancellation()
                WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind)
                syncedAt = .now; syncError = nil
            } catch is CancellationError { }
            catch { syncError = "小组件暂未更新，请重试。上一份有效内容已保留。" }
        }
    }
}

struct LianxinSystemCredentials: LianxinCredentialStore {
    func read(account: String) throws -> String { try LianxinKeychain.read(account: account) }
    func save(_ key: String, account: String) throws { try LianxinKeychain.save(key, account: account) }
}
