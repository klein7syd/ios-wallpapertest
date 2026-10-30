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
    private var appearanceStorageError: String?
    private let appearanceRepository: AppearanceRepository?
    private var repository: TodoRepository?
    private var appearanceTask: Task<Void, Never>?
    private var appearanceDirty = false
    private var defersAppearanceSave = false
    private let usesSharedStorage: Bool

    init(repository: TodoRepository? = nil, appearanceRepository: AppearanceRepository? = nil) {
        self.repository = repository
        self.appearanceRepository = appearanceRepository
        usesSharedStorage = repository == nil
    }

    func reload() {
        do {
            if usesSharedStorage { repository = try TodoSharedStorage.appRepository() }
            accept(try activeRepository().load())
            reloadAppearance()
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
        appearance = accepted
        appearanceDirty = true
        appearanceTask?.cancel()
        if !defersAppearanceSave { scheduleAppearanceSave() }
        return true
    }
    func beginAppearanceInteraction() {
        defersAppearanceSave = true
        appearanceTask?.cancel(); appearanceTask = nil
    }
    func endAppearanceInteraction() {
        defersAppearanceSave = false
        if appearanceDirty { scheduleAppearanceSave() }
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
        guard appearanceDirty else { return }
        appearanceTask?.cancel(); appearanceTask = nil
        do { try saveAppearance(appearance) } catch { recordAppearanceStorageError(error) }
    }
    func saveAppearance(_ value: TodoAppearance) throws {
        try activeAppearanceRepository().save(value)
        appearance = value; appearanceDirty = false; appearanceStorageError = nil; appearanceError = nil
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
    }
    func reloadAppearance() {
        guard usesSharedStorage || appearanceRepository != nil else { return }
        do { appearance = try activeAppearanceRepository().load(); appearanceStorageError = nil; appearanceError = nil }
        catch { recordAppearanceStorageError(error) }
    }
    func recoverAppearance() throws {
        try activeAppearanceRepository().recover()
        reloadAppearance()
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
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
    private func activeAppearanceRepository() throws -> AppearanceRepository {
        if let appearanceRepository { return appearanceRepository }
        return try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory())
    }
    private func recordAppearanceStorageError(_ error: Error) {
        appearanceStorageError = error.localizedDescription
        appearanceError = appearanceStorageError
    }

    private func accept(_ document: TodoDocument) {
        items = document.items
        hasLoaded = true
        loadError = nil
        canRecover = false
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
    }
}
