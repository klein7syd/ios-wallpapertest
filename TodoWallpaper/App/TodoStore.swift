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
    private var repository: TodoRepository?
    private var appearanceTask: Task<Void, Never>?
    private let usesSharedStorage: Bool

    init(repository: TodoRepository? = nil) {
        self.repository = repository
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
    func updateMarkers(_ changes: [TodoMarkerUpdate]) throws {
        guard !changes.isEmpty else { return }
        accept(try activeRepository().updateMarkers(changes))
    }
    func edit(id: UUID, title: String, marker: TodoMarker?) throws { accept(try activeRepository().edit(id: id, title: title, marker: marker)) }
    func setAppearance(_ value: TodoAppearance) {
        guard value != appearance else { return }
        do { try value.validate() } catch { appearanceError = error.localizedDescription; return }
        appearance = value
        appearanceTask?.cancel()
        appearanceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                try Task.checkCancellation()
                try saveAppearance(value)
            } catch is CancellationError { }
            catch { appearanceError = error.localizedDescription }
        }
    }
    func flushAppearance() {
        guard appearanceTask != nil else { return }
        appearanceTask?.cancel(); appearanceTask = nil
        do { try saveAppearance(appearance) } catch { appearanceError = error.localizedDescription }
    }
    func saveAppearance(_ value: TodoAppearance) throws {
        try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).save(value)
        appearance = value; appearanceError = nil
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
    }
    func reloadAppearance() {
        guard usesSharedStorage else { return }
        do { appearance = try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).load(); appearanceError = nil }
        catch { appearanceError = error.localizedDescription }
    }
    func recoverAppearance() throws {
        try AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).recover()
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

    private func accept(_ document: TodoDocument) {
        items = document.items
        hasLoaded = true
        loadError = nil
        canRecover = false
        WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind)
    }
}
