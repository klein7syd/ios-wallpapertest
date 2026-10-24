import Foundation
import Combine

@MainActor
final class TodoStore: ObservableObject {
    @Published private(set) var items: [TodoItem] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var loadError: String?
    private let repository: TodoRepository

    init(repository: TodoRepository = TodoRepository(directoryURL: TodoRepository.defaultDirectory)) {
        self.repository = repository
    }

    func reload() {
        do { accept(try repository.load()) }
        catch { loadError = error.localizedDescription }
    }

    func add(title: String) throws { accept(try repository.add(title: title)) }
    func rename(id: UUID, title: String) throws { accept(try repository.rename(id: id, title: title)) }
    func setCompleted(id: UUID, completed: Bool) throws { accept(try repository.setCompleted(id: id, completed: completed)) }
    func delete(ids: Set<UUID>) throws { accept(try repository.delete(ids: ids)) }
    func move(from offsets: IndexSet, to destination: Int) throws {
        let ids = try TodoOrder.moving(items.map(\.id), from: offsets, to: destination)
        accept(try repository.reorder(ids: ids))
    }

    private func accept(_ document: TodoDocument) {
        items = document.items
        hasLoaded = true
        loadError = nil
    }
}
