import Foundation
import Combine
import WidgetKit

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadError: String?
    @Published private(set) var canRecover = false
    private var repository: TodoRepository?
    private let usesSharedStorage: Bool

    init(repository: TodoRepository? = nil) {
        self.repository = repository
        usesSharedStorage = repository == nil
    }

    func reload() {
        do {
            if usesSharedStorage { repository = try TodoSharedStorage.appRepository() }
            accept(try activeRepository().load())
        } catch {
            loadError = error.localizedDescription
            canRecover = usesSharedStorage && TodoSharedStorage.canRecover()
        }
    }

    func add(title: String) throws { accept(try activeRepository().add(title: title)) }
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
