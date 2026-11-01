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

@MainActor
final class LianxinModel: ObservableObject {
    @Published var profile = LianxinProfile() { didSet {
        if loaded && (oldValue.idolName != profile.idolName || oldValue.groupName != profile.groupName) { profile.understood = nil; profile.confidence = nil; profile.researchSources = nil; researchNotice = nil }
        if loaded && oldValue != profile { inputRevision += 1; scheduleInputSave(); scheduleSync() }
    } }
    @Published var key = ""
    @Published private(set) var photo: UIImage?
    @Published private(set) var loaded = false
    @Published private(set) var loading = false
    @Published private(set) var canRecoverProfile = false
    @Published private(set) var isGenerating = false
    @Published private(set) var photoSyncPending = false
    private var credentialReadFailed = false
    private var loadTask: Task<Void, Never>?
    private var preparationTask: Task<Void, Never>?
    private var inputRevision: UInt64 = 0
    private var committingGeneration = false
    private var lastPublished: LianxinPublication?
    private struct ContentEdit {
        let lines: [LianxinLine]
        let idol: String
        let group: String?
        let example: Bool?
    }
    @Published private var contentHistory: [ContentEdit] = []
    var canUndoContentEdit: Bool { !contentHistory.isEmpty && !busy }
    private func rememberContentEdit() {
        guard !profile.resolvedLines.isEmpty else { return }
        contentHistory.append(ContentEdit(lines: profile.resolvedLines, idol: profile.messageIdol, group: profile.messageGroup, example: profile.exampleContent))
        if contentHistory.count > 10 { contentHistory.removeFirst() }
    }
    func editLines(_ lines: [LianxinLine]) {
        guard loaded, !busy, !lines.isEmpty, lines != profile.resolvedLines else { return }
        rememberContentEdit(); profile.setLines(lines)
    }
    func undoContentEdit() {
        guard loaded, !busy, let old = contentHistory.popLast() else { return }
        var next = profile
        next.setLines(old.lines); next.messageIdol = old.idol; next.messageGroup = old.group
        next.messageIdentityCaptured = true; next.exampleContent = old.example
        profile = next; notice = "已恢复上一版话语"
    }
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var researchNotice: String?
    @Published private(set) var availableModels: [String] = []
    @Published private(set) var keySaved = false
    @Published var connectionNotice: String?
    weak var styleStore: TodoStore?
    @Published private(set) var currentContent: LianxinPublication?
    @Published private(set) var syncedAt: Date?
    @Published private(set) var syncError: String?
    var publication: LianxinPublication { currentContent ?? LianxinPublication(idol: "连心", text: "", photo: nil, date: .distantPast) }
    private var draftContent: LianxinPublication {
        LianxinPublication(idol: profile.messageIdol.isEmpty ? profile.idolName : profile.messageIdol, text: profile.message, photo: nil, date: .distantPast, example: profile.exampleContent, translation: profile.translationEnabled == true ? profile.translation : nil,
            signatureSubtitle: profile.messageGroup, lines: profile.resolvedLines.map { LianxinLine(text: $0.text, translation: profile.translationEnabled == true ? $0.translation : nil) })
    }
    private var syncTask: Task<Void, Never>?
    private let storage = LianxinStorage()
    private let service: any AIServiceProtocol
    private let research: any LianxinPublicResearching
    private var generation: Task<Void, Never>?
    private var generationID = UUID()

    private let connection: any LianxinConnectionService
    init(service: any AIServiceProtocol = LianxinAPIService(), connection: any LianxinConnectionService = LianxinAPIService(), research: any LianxinPublicResearching = LianxinPublicResearchService.shared) {
        self.service = service; self.connection = connection; self.research = research
    }
    var provider: LianxinProviderPreset { LianxinProviderPreset.preset(profile.providerID) }
    private var credentialAccount: String { LianxinSetupRules.account(provider.id) }
    private var signature: String { provider.id + "|" + profile.endpoint + "|" + profile.model }
    var connected: Bool { LianxinWritingRules.connected(profile: profile, hasKey: !key.isEmpty) }
    var configurationComplete: Bool { connected }
    var keySuffix: String { String(key.suffix(4)) }


    func load() async {
        EditorModePerformance.count("profile_load_calls")
        guard !loaded else { return }
        if let loadTask { await loadTask.value; return }
        loading = true
        let task = Task { @MainActor in
            let span = EditorModePerformance.beginStage("LoadLianxin")
            defer { EditorModePerformance.endStage("LoadLianxin", span); loading = false }
            EditorModePerformance.count("profile_disk_reads")
            do {
                let saved = try await storage.load()
                var restored = saved.profile
                if restored.messageIdentityCaptured != true {
                    if restored.messageIdol.isEmpty { restored.messageIdol = restored.idolName }
                    restored.messageGroup = restored.groupName; restored.messageIdentityCaptured = true
                }
                profile = restored; photo = saved.photo.flatMap { UIImage(data: $0) }
                photoSyncPending = restored.pendingPhotoSync == true
                if saved.missingPhoto { notice = "底图暂时无法读取，文字资料已保留。请重新选择照片或移除底图。" }
                if let directory = try? mediaDirectory() { currentContent = try? await storage.currentContent(directory: directory) }
                lastPublished = currentContent
                loaded = true; canRecoverProfile = false; error = nil
                inputRevision += 1
                scheduleInputSave(); scheduleSync()
                credentialReadFailed = true
                await retryCredentials()
            } catch {
                canRecoverProfile = await storage.canRecover()
                self.error = "连心资料读取失败，原文件已保留且暂停自动保存。请重试读取，或从上次资料恢复。"
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }
    func recoverProfile() async {
        guard !loaded, !loading, canRecoverProfile else { return }
        do { try await storage.recover(); await load() }
        catch { self.error = "恢复失败，原资料与备份均已保留，请稍后重试。" }
    }
    func retryCredentials() async {
        guard loaded, credentialReadFailed, !busy else { return }
        do {
            try LianxinCredentialMigration.migrate(profile: profile, store: LianxinSystemCredentials())
            key = try LianxinKeychain.read(account: credentialAccount); keySaved = !key.isEmpty
            credentialReadFailed = false
            connectionNotice = nil
        } catch {
            connectionNotice = "密钥暂时无法读取，请解锁设备后重试读取密钥。"
        }
    }
    private func persistCurrent() async throws {
        inputSaveTask?.cancel()
        let value = profile, revision = inputRevision
        try await storage.save(value, revision: revision)
    }

    func saveSettings() async -> Bool {
        guard loaded, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            //这里只保存普通配置；密钥由saveKey单独写入钥匙串。
            if !profile.endpoint.isEmpty { profile.endpoint = try LianxinSetupRules.endpoint(profile.endpoint) }
            try await persistCurrent()
            notice = "已保存"
            return true
        } catch { self.error = "设置未能完整保存，请重试。"; return false }
    }

    private var inputSaveTask: Task<Void, Never>?
    private func scheduleInputSave() {
        inputSaveTask?.cancel()
        guard loaded else { return }
        let value = profile, revision = inputRevision
        inputSaveTask = Task {
            do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation(); try await storage.save(value, revision: revision) }
            catch is CancellationError { }
            catch { self.error = "输入暂未保存，请重试。" }
        }
    }
    func saveInputsNow() async {
        guard loaded else { return }
        if committingGeneration, let generation { await generation.value; return }
        do { try await persistCurrent() } catch { self.error = "输入未保存，请重试。" }
    }
    private func mediaDirectory() throws -> URL {
        if let store = styleStore { return try store.mediaDirectory() }
        return try TodoSharedStorage.sharedDirectory()
    }
    func wallpaperPhotoData() async throws -> Data? {
        if let store = styleStore, store.appearance.lianxin != nil {
            guard let name = store.appearance.lianxin?.photoName(at: .now) else { return nil }
            if name == profile.sharedPhotoName, let original = try? await storage.photoData(profile.photoName, original: true) { return original }
            return try await storage.sharedPhotoData(name: name, directory: mediaDirectory())
        }
        return try await storage.photoData(profile.photoName, original: true)
    }
    func syncBackdrop() async throws {
        guard loaded, let store = styleStore else { throw LianxinError.storage }
        let selectedName = profile.photoName
        let data = try await storage.photoData(selectedName)
        var sharedName: String?
        var transaction: UUID?
        let directory = try mediaDirectory()
        if let data {
            let batch = try await WidgetPhotoStore.shared.beginBatch(sharedDirectory: directory)
            transaction = batch
            do { sharedName = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: directory, transactionID: batch) }
            catch { await WidgetPhotoStore.shared.rollbackBatch(batch, sharedDirectory: directory); throw error }
        }
        do {
            // 等待导入时用户可能调节样式，始终合并最新样式，而非覆盖旧快照。
            var root = store.appearance; root.initializeLianxin()
            root.lianxin?.backgroundPhotoName = sharedName
            root.lianxin?.backdrop = sharedName == nil ? .system : .photo
            root.lianxin?.photoRotation = nil; root.lianxin?.backgroundCrop = PhotoCrop()
            try store.saveAppearance(root)
        } catch {
            if let transaction { await WidgetPhotoStore.shared.rollbackBatch(transaction, sharedDirectory: directory) }
            throw error
        }
        if let transaction { try await WidgetPhotoStore.shared.commitBatch(transaction, sharedDirectory: directory) }
        profile.sharedPhotoName = sharedName
        profile.pendingPhotoSync = false
        try await persistCurrent()
        photoSyncPending = false
    }
    func retryPhotoSync() async {
        guard loaded, !busy, photoSyncPending else { return }
        busy = true; defer { busy = false }
        do { try await syncBackdrop(); notice = "底图已同步" }
        catch { self.error = "照片已保留，底图仍未同步。请稍后重试。" }
    }

    func prepareStyle(_ store: TodoStore) async {
        EditorModePerformance.count("prepare_style_calls")
        guard loaded else { return }
        styleStore = store
        if let preparationTask { await preparationTask.value; return }
        guard store.appearance.lianxin == nil else { return }
        let task = Task { @MainActor in
            let span = EditorModePerformance.beginStage("PrepareLianxinStyle")
            defer { EditorModePerformance.endStage("PrepareLianxinStyle", span) }
            EditorModePerformance.count("style_initializations")
            do {
                let legacyPhoto = try? await storage.photoData(profile.photoName)
                let publishedPhoto = currentContent?.photo
                var name: String?
                if let data = legacyPhoto ?? publishedPhoto { name = try await WidgetPhotoStore.shared.importPhoto(data, sharedDirectory: mediaDirectory()) }
                // 在途等待之后再次检查，不能覆盖其他入口已经建立的样式。
                guard store.appearance.lianxin == nil else { return }
                var root = store.appearance; root.initializeLianxin(photoName: name)
                try store.saveAppearance(root)
                profile.sharedPhotoName = name
            } catch { self.error = "连心样式初始化失败，请重试。" }
        }
        preparationTask = task; await task.value; preparationTask = nil
    }
    func selectProvider(_ id: String) async {
        guard loaded, !busy else { return }
        let next = LianxinProviderPreset.preset(id)
        guard next.id != provider.id else { await retryCredentials(); return }
        var updated = profile
        var configurations = updated.providerConfigurations ?? [:]
        configurations[provider.id] = LianxinProviderConfiguration(endpoint: profile.endpoint, model: profile.model,
            connectedSignature: profile.connectedSignature, setupFinished: profile.setupFinished)
        let saved = configurations[next.id]
        updated.providerID = next.id; updated.providerConfigurations = configurations
        updated.endpoint = saved?.endpoint ?? next.endpoint; updated.model = saved?.model ?? next.model
        updated.connectedSignature = saved?.connectedSignature; updated.setupFinished = saved?.setupFinished ?? false
        profile = updated
        availableModels = []; connectionNotice = nil; key = ""; keySaved = false
        credentialReadFailed = true
        await retryCredentials()
    }
    func saveKey(_ input: String) -> Bool {
        guard loaded, !busy else { return false }
        let cleaned = LianxinSetupRules.cleanKey(input)
        guard cleaned.count <= 4096, cleaned.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            connectionNotice = "密钥中还有空格或换行，请重新完整复制。"; return false
        }
        do {
            try LianxinKeychain.save(cleaned, account: credentialAccount)
            credentialReadFailed = false; key = cleaned; keySaved = !cleaned.isEmpty; profile.connectedSignature = nil; profile.setupFinished = false; availableModels = []; connectionNotice = nil
            return true
        } catch { connectionNotice = "密钥未保存，请解锁设备并检查签名后重试。"; return false }
    }
    func testConnection() async {
        guard loaded, !busy, !Task.isCancelled else { return }
        let previousSignature = profile.connectedSignature
        busy = true; connectionNotice = nil
        defer { busy = false }
        do {
            profile.endpoint = try LianxinSetupRules.endpoint(profile.endpoint)
            guard !key.isEmpty else { throw LianxinError.invalidKey }
            let models = try await connection.test(profile: profile, key: key, provider: provider)
            try Task.checkCancellation()
            availableModels = models
            if profile.model.isEmpty { profile.model = models.first ?? provider.model }
            profile.connectedSignature = signature
            try await persistCurrent()
            connectionNotice = "✓ 当前模型已完成生成测试。其他模型的权限仍需单独测试。"
        } catch is CancellationError {
            profile.connectedSignature = previousSignature
            connectionNotice = "测试已取消，可以修改后再试。"
        } catch let failure as URLError where failure.code == .cancelled {
            profile.connectedSignature = previousSignature
            connectionNotice = "测试已取消，可以修改后再试。"
        } catch {
            profile.connectedSignature = nil
            connectionNotice = (error as? LianxinError)?.localizedDescription ?? LianxinError.network.localizedDescription
        }
    }
    func finishSetup() async -> Bool {
        guard connected, !busy else { return false }
        let previous = profile.setupFinished
        profile.setupFinished = true
        if await saveSettings() { return true }
        profile.setupFinished = previous
        return false
    }
    func chooseModel(_ value: String) async {
        guard loaded, !busy, value != profile.model else { return }
        profile.model = value
        // 模型改变后需再次测试，避免沿用其他模型的成功状态。
        profile.connectedSignature = nil
        profile.setupFinished = false; connectionNotice = nil
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
            updated.pendingPhotoSync = true
            try Task.checkCancellation()
            inputSaveTask?.cancel(); inputRevision += 1
            try await storage.save(updated, revision: inputRevision)
            privatePhotoCommitted = true
            profile = updated; photo = image; photoSyncPending = true
            try await syncBackdrop()
            await storage.removePhoto(oldName)
        } catch {
            if !privatePhotoCommitted { await storage.removePhoto(importedName) }
            if privatePhotoCommitted { self.error = "照片已保留，共享底图暂未更新。可点“重试底图同步”，无需重新选图。"; return }
            if !(error is CancellationError) { self.error = "底图未能保存，原来的照片已保留。" }
        }
    }

    func generate() {
        guard loaded, !busy else { return }
        profile = LianxinLanguageRules.normalized(profile)
        let input = profile
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do { _ = try LianxinAPIService.request(profile: input, key: secret) }
        catch { self.error = error.localizedDescription; return }
        busy = true; isGenerating = true; notice = nil
        let id = UUID(); generationID = id
        generation = Task {
            defer { if generationID == id { busy = false; isGenerating = false; committingGeneration = false; generation = nil; if researchNotice?.hasPrefix("正在") == true { researchNotice = nil } } }
            do {
                researchNotice = "正在查找公开 Wiki 资料…"
                var enriched = input
                enriched.researchSources = await research.lookup(name: input.idolName, group: LianxinRoleRules.clean(input.groupName))
                try Task.checkCancellation()
                guard generationID == id else { return }
                researchNotice = enriched.researchSources?.isEmpty == false ? "已找到公开参考资料；粉丝整理可能有误，仅参考公开形象。" : "暂未取得可核对的资料，可能是网络不可达、名字有歧义或没有条目；将按你的补充创作。"
                let raw = try await service.generate(profile: enriched, key: secret)
                let result = LianxinGeneratedBatch.parse(raw, count: input.requestedCount, translated: input.translationEnabled == true)
                guard !result.lines.isEmpty else { notice = result.notice ?? "没有生成可用话语，请重试。"; return }
                try Task.checkCancellation()
                guard generationID == id else { return }
                var updated = enriched
                updated.setLines(result.lines); updated.understood = result.understood; updated.confidence = result.confidence
                updated.messageIdol = input.idolName.isEmpty ? "连心" : input.idolName
                updated.messageGroup = LianxinRoleRules.clean(input.groupName).isEmpty ? nil : input.groupName
                updated.messageIdentityCaptured = true
                updated.exampleContent = false
                updated.connectedSignature = signature
                LianxinRoleRules.remember(&updated)
                // 进入原子提交后不再允许“取消”，避免磁盘已提交但界面仍称取消。
                isGenerating = false; committingGeneration = true
                inputSaveTask?.cancel(); inputRevision += 1
                try await storage.save(updated, revision: inputRevision)
                rememberContentEdit()
                profile = updated
                notice = result.notice
            } catch is CancellationError { }
            catch let failure as URLError where failure.code == .cancelled { }
            catch {
                guard generationID == id else { return }
                // 不直接显示网络底层描述或服务端正文，以免回显密钥和提示词。
                self.error = (error as? LianxinError)?.localizedDescription ?? "生成未完成，请检查网络和接口后重试。原有话语已保留。"
            }
        }
    }

    func cancel() {
        guard isGenerating else { return }
        generation?.cancel()
        notice = "已取消生成，原有话语保留。"
    }

    func updateLanguage(source: String? = nil, target: String? = nil, enabled: Bool? = nil) {
        var next = profile
        if let source { next.sourceLanguage = source }
        if let target { next.translationLanguage = target }
        if let enabled { next.translationEnabled = enabled }
        profile = LianxinLanguageRules.normalized(next)
    }

    private func sameContent(_ first: LianxinPublication?, _ second: LianxinPublication) -> Bool {
        guard let first else { return false }
        return first.resolvedLines == second.resolvedLines && first.idol == second.idol && first.example == second.example
            && first.signatureSubtitle == second.signatureSubtitle
    }
    func scheduleSync() {
        guard loaded else { return }
        let draft = draftContent
        guard (try? draft.validate()) != nil else { syncTask?.cancel(); return }
        if !sameContent(currentContent, draft) {
            currentContent = LianxinPublication(idol: draft.idol, text: draft.text, photo: nil, date: .now,
                example: draft.example, translation: draft.translation, signatureSubtitle: draft.signatureSubtitle, lines: draft.lines)
        }
        // 私有输入、壁纸样式和相同内容不会重写共享文件或扰动拖动事务。
        guard !sameContent(lastPublished, draft) else { syncTask?.cancel(); syncError = nil; return }
        syncTask?.cancel()
        let content = publication
        syncTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation()
                lastPublished = nil
                try await storage.publish(content, directory: mediaDirectory())
                try Task.checkCancellation()
                lastPublished = content
                WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind)
                syncedAt = .now; syncError = nil
            } catch is CancellationError { }
            catch { syncError = "内容暂未同步，请重试。桌面保留上一份有效内容。" }
        }
    }

}

struct LianxinSystemCredentials: LianxinCredentialStore {
    func read(account: String) throws -> String { try LianxinKeychain.read(account: account) }
    func save(_ key: String, account: String) throws { try LianxinKeychain.save(key, account: account) }
}
