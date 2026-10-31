import Foundation
import Combine
import WidgetKit

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var canRecover = false
    @Published private(set) var appearance = TodoAppearance()
    @Published private(set) var appearanceError: String?
    @Published private(set) var analysisRevision = 0
    @Published private(set) var isAppearanceInteracting = false
    private var appearanceStorageError: String?
    private let appearanceRepository: AppearanceRepository?
    private var repository: TodoRepository?
    private var appearanceTask: Task<Void, Never>?
    private var appearanceDirty = false
    private var defersAppearanceSave = false
    private let usesSharedStorage: Bool
    private let analysisDirectory: URL?
    private let analysisCache: AppearanceStore
    private var analysisTask: Task<Void, Never>?
    private var analysisGeneration = 0
    private var analysisSystemDark = false
    private var analysisNeedsInvalidation = false
    private var rescanAnalysisPending = false
    private var analysisObserver: PhotoAnalysisRequestObserver?
    private var analysisPreferredName: String?
    private var analysisPreferredAspect: Double?
    private var assetRetainers: [String: Set<String>] = [:]
    private var startupCollectionScheduled = false

    init(repository: TodoRepository? = nil, appearanceRepository: AppearanceRepository? = nil,
         analysisDirectory: URL? = nil, analysisCache: AppearanceStore = .shared) {
        self.repository = repository
        self.appearanceRepository = appearanceRepository
        usesSharedStorage = repository == nil
        self.analysisDirectory = analysisDirectory; self.analysisCache = analysisCache
        if usesSharedStorage {
            analysisObserver = PhotoAnalysisRequestObserver { [weak self] in
                Task { @MainActor [weak self] in self?.resumePhotoAnalysis() }
            }
        }
    }

    func reload() {
        do {
            if usesSharedStorage {
                let snapshot = try TodoSharedStorage.appSnapshot()
                repository = snapshot.repository; accept(snapshot.document)
            } else { accept(try activeRepository().load()) }
            reloadAppearance()
            if !startupCollectionScheduled { startupCollectionScheduled = true; collectPhotoAssets() }
        } catch {
            loadError = error.localizedDescription
            canRecover = usesSharedStorage && TodoSharedStorage.canRecover()
        }
    }

    func add(title: String, marker: TodoMarker? = nil) throws { accept(try activeRepository().add(title: title, marker: marker)) }
    func importItems(_ items: [TodoItem]) throws { accept(try activeRepository().importItems(items)) }
    func saveTask(id: UUID?, title: String, marker: TodoMarker?, schedule: TodoSchedule?) throws {
        accept(try activeRepository().saveTask(id: id, title: title, marker: marker, schedule: schedule))
    }
    func updateMarkers(_ changes: [TodoMarkerUpdate]) throws {
        guard !changes.isEmpty else { return }
        accept(try activeRepository().updateMarkers(changes))
    }
    func edit(id: UUID, title: String, marker: TodoMarker?) throws { accept(try activeRepository().edit(id: id, title: title, marker: marker)) }
    @discardableResult
    func setAppearance(_ value: TodoAppearance) -> Bool {
        var accepted = value
        do { try accepted.validate() }
        catch {
            accepted = value.clampedForEditing()
            do { try accepted.validate() }
            catch { appearanceError = appearanceStorageError ?? error.localizedDescription; return false }
        }
        appearanceError = appearanceStorageError
        guard accepted != appearance else { return true }
        let previous = appearance.widget
        appearance = accepted
        appearanceDirty = true
        appearanceTask?.cancel()
        if !defersAppearanceSave { scheduleAppearanceSave() }
        schedulePhotoAnalysis(invalidating: analysisContextChanged(previous, accepted.widget))
        return true
    }
    func beginAppearanceInteraction() {
        defersAppearanceSave = true
        isAppearanceInteracting = true
        cancelPhotoAnalysis()
        appearanceTask?.cancel(); appearanceTask = nil
    }
    func endAppearanceInteraction() {
        defersAppearanceSave = false
        isAppearanceInteracting = false
        if appearanceDirty { scheduleAppearanceSave() }
        schedulePhotoAnalysis()
    }
    private func scheduleAppearanceSave() {
        appearanceTask?.cancel()
        let value = appearance
        appearanceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(800))
                try Task.checkCancellation()
                try saveAppearance(value)
            } catch is CancellationError { }
            catch { recordAppearanceStorageError(error) }
        }
    }
    func flushAppearance() {
        defersAppearanceSave = false
        if isAppearanceInteracting { isAppearanceInteracting = false; schedulePhotoAnalysis() }
        guard appearanceDirty else { return }
        appearanceTask?.cancel(); appearanceTask = nil
        do { try saveAppearance(appearance) } catch { recordAppearanceStorageError(error) }
    }
    func saveAppearance(_ value: TodoAppearance) throws {
        try activeAppearanceRepository().save(value)
        let previous = appearance.widget
        appearance = value; appearanceDirty = false; appearanceStorageError = nil; appearanceError = nil
        if previous != value.widget { schedulePhotoAnalysis(invalidating: analysisContextChanged(previous, value.widget)) }
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind)
    }
    func reloadAppearance() {
        guard usesSharedStorage || appearanceRepository != nil else { return }
        do {
            appearance = try activeAppearanceRepository().load(); appearanceStorageError = nil; appearanceError = nil
            resumePhotoAnalysis()
        }
        catch { recordAppearanceStorageError(error) }
    }
    func recoverAppearance() throws {
        try activeAppearanceRepository().recover()
        reloadAppearance()
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind)
    }
    func rename(id: UUID, title: String) throws { accept(try activeRepository().rename(id: id, title: title)) }
    func setCompleted(id: UUID, completed: Bool) throws { accept(try activeRepository().setCompleted(id: id, completed: completed)) }
    func delete(ids: Set<UUID>) throws { accept(try activeRepository().delete(ids: ids)) }
    func move(from offsets: IndexSet, to destination: Int) throws {
        let ids = try TodoOrder.moving(items.map(\.id), from: offsets, to: destination)
        accept(try activeRepository().reorder(ids: ids))
    }

    func recoverFromBackup() throws {
        guard usesSharedStorage else { throw TodoDataError.recoveryUnavailable }
        try TodoSharedStorage.recover()
        reload()
        if let loadError { throw NSError(domain: "TodoStorage", code: 1, userInfo: [NSLocalizedDescriptionKey: loadError]) }
    }

    private func activeRepository() throws -> TodoRepository {
        guard let repository else { throw TodoDataError.migrationRequired }
        return repository
    }
    // 生产返回App Group；显式注入的原生检查仓库返回同一媒体目录，不引入私有回退。
    func mediaDirectory() throws -> URL { try activeAppearanceRepository().directory }
    private func activeAppearanceRepository() throws -> AppearanceRepository {
        if let appearanceRepository { return appearanceRepository }
        return try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory())
    }
    private func recordAppearanceStorageError(_ error: Error) {
        appearanceStorageError = error.localizedDescription
        appearanceError = appearanceStorageError
    }
    func retainPhotoAssets(_ names: Set<String>, owner: String) { assetRetainers[owner] = names }
    func collectPhotoAssets() {
        guard usesSharedStorage, hasLoaded, loadError == nil, appearanceStorageError == nil else { return }
        flushAppearance()
        guard !appearanceDirty, appearanceStorageError == nil else { return }
        let retained = assetRetainers.values.reduce(PhotoAssetReferences.appearance(appearance).union(PhotoAssetReferences.items(items))) { $0.union($1) }
        Task(priority: .utility) {
            do { _ = try await WidgetPhotoStore.shared.collect(retaining: retained) }
            catch { /* 权威数据或备份不可读时整体跳过，保留图片等待恢复。 */ }
        }
    }
    func updateAnalysisSystemTheme(dark: Bool) {
        guard dark != analysisSystemDark else { return }
        analysisSystemDark = dark
        schedulePhotoAnalysis(invalidating: appearance.widget.theme == .system && appearance.widget.photoOpacity < 1)
    }
    func prioritizePhotoAnalysis(photoName: String?, canvasAspect: Double) {
        guard photoName != analysisPreferredName || canvasAspect != analysisPreferredAspect else { return }
        analysisPreferredName = photoName; analysisPreferredAspect = canvasAspect
        schedulePhotoAnalysis()
    }
    func resumePhotoAnalysis() {
        if analysisTask != nil { rescanAnalysisPending = true; return }
        schedulePhotoAnalysis(debounce: false)
    }
    func forgetPhotoAnalysis(_ names: [String]) {
        cancelPhotoAnalysis()
        let cache = analysisCache
        Task(priority: .utility) { await PhotoAnalysisService.shared.removeAnalysis(for: names, cache: cache) }
    }
    private func cancelPhotoAnalysis() {
        analysisGeneration += 1; analysisTask?.cancel(); analysisTask = nil
    }
    private func analysisContextChanged(_ previous: WidgetAppearance, _ next: WidgetAppearance) -> Bool {
        previous.photoCrop != next.photoCrop || previous.photoOpacity != next.photoOpacity
            || (previous.theme != next.theme && next.photoOpacity < 1)
    }
    private func analysisNames(_ style: WidgetAppearance) -> [String] {
        guard style.backdrop == .photo, !style.materialEnabled else { return [] }
        var names = style.photoRotation?.enabled == true ? style.photoRotation?.photos ?? [] : []
        if let name = style.backgroundPhotoName, !names.contains(name) { names.append(name) }
        if let today = style.photoName(at: .now) { names.removeAll { $0 == today }; names.insert(today, at: 0) }
        return names
    }
    private func schedulePhotoAnalysis(invalidating: Bool = false, debounce: Bool = true) {
        guard usesSharedStorage || analysisDirectory != nil else { return }
        cancelPhotoAnalysis()
        analysisNeedsInvalidation = analysisNeedsInvalidation || invalidating
        let style = appearance.widget, extraStyle = appearance.lianxin
        let names = analysisNames(appearance.widget) + (appearance.lianxin.map(analysisNames) ?? [])
        guard !isAppearanceInteracting, !names.isEmpty else { return }
        let generation = analysisGeneration, invalidate = analysisNeedsInvalidation
        let cache = analysisCache, explicitDirectory = analysisDirectory, systemDark = analysisSystemDark
        let preferredName = analysisPreferredName, preferredAspect = analysisPreferredAspect
        analysisTask = Task(priority: .utility) { [weak self] in
            var succeeded = false
            do {
                if debounce { try await Task.sleep(for: .milliseconds(400)) }
                try Task.checkCancellation()
                let directory = try explicitDirectory ?? TodoSharedStorage.sharedDirectory()
                try await PhotoAnalysisService.shared.runBatch(style: style, systemDark: systemDark,
                    invalidating: invalidate, directory: directory, cache: cache,
                    preferredPhotoName: preferredName, preferredAspect: preferredAspect) { [weak self] reloadWidget in
                    Task { @MainActor [weak self] in
                        guard let self, self.analysisGeneration == generation else { return }
                        if reloadWidget { WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind) }
                        else { self.analysisRevision += 1 }
                    }
                }
                if let extraStyle {
                    try await PhotoAnalysisService.shared.runBatch(style: extraStyle, systemDark: systemDark,
                        invalidating: false, directory: directory, cache: cache,
                        preferredPhotoName: preferredName, preferredAspect: preferredAspect) { [weak self] reloadWidget in
                        Task { @MainActor [weak self] in
                            guard let self, self.analysisGeneration == generation else { return }
                            if reloadWidget { WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind) }
                            else { self.analysisRevision += 1 }
                        }
                    }
                }
                succeeded = true
            } catch is CancellationError { }
            catch { /* 不把分析失败写成样式校验错误；缺失分析继续安全回退。 */ }
            guard let self, self.analysisGeneration == generation else { return }
            if succeeded { self.analysisNeedsInvalidation = false; self.analysisRevision += 1 }
            self.analysisTask = nil
            if self.rescanAnalysisPending {
                self.rescanAnalysisPending = false
                self.schedulePhotoAnalysis(debounce: false)
            }
        }
    }

    private func accept(_ document: TodoDocument) {
        items = document.items
        hasLoaded = true
        loadError = nil
        canRecover = false
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
        WidgetCenter.shared.reloadTimelines(ofKind: LianxinPublication.kind)
    }
}
