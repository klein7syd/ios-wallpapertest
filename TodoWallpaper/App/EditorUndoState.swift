import SwiftUI

struct EditorInteractionContext {
    var begin: (String) -> Void = { _ in }
    var end: () -> Void = { }
    var pulse: (String) -> Void = { _ in }
}
private struct EditorInteractionKey: EnvironmentKey {
    static let defaultValue = EditorInteractionContext()
}
extension EnvironmentValues {
    var editorInteraction: EditorInteractionContext {
        get { self[EditorInteractionKey.self] }
        set { self[EditorInteractionKey.self] = newValue }
    }
}

/// Each editor owns a small session. Applying an undo uses its existing save path.
@MainActor
final class EditorUndoState<Value: Equatable>: ObservableObject {
    private var history = EditorHistory<Value>()
    @Published private var hasUndo = false
    @Published private(set) var isRestoring = false
    private var activeKey: String?
    private var settle: Task<Void, Never>?
    var retainedValuesChanged: ([Value]) -> Void = { _ in }
    var retainedValues: [Value] { history.retainedValues }
    var canUndo: Bool { hasUndo && !isRestoring }
    private func updateAvailability() {
        if hasUndo != history.canUndo { hasUndo = history.canUndo }
        retainedValuesChanged(history.retainedValues)
    }
    func synchronize(_ value: Value) {
        settle?.cancel(); settle = nil; activeKey = nil
        history.endInteraction(); history.synchronize(value); updateAvailability()
    }
    func observe(_ value: Value) { if !isRestoring { history.observe(value); updateAvailability() } }
    func finish(_ value: Value) {
        settle?.cancel(); settle = nil
        observe(value); history.endInteraction(); activeKey = nil
    }
    func context(read: @escaping () -> Value) -> EditorInteractionContext {
        EditorInteractionContext(begin: { [weak self] key in
            guard let self else { return }
            self.finish(read()); self.activeKey = key; self.history.beginInteraction()
        }, end: { [weak self] in self?.finish(read()) }, pulse: { [weak self] key in
            guard let self else { return }
            if self.activeKey != key {
                self.finish(read()); self.activeKey = key; self.history.beginInteraction()
            }
            self.settle?.cancel()
            self.settle = Task {
                do { try await Task.sleep(for: .milliseconds(500)); try Task.checkCancellation() }
                catch { return }
                self.finish(read())
            }
        })
    }
    func undo(read: () -> Value, apply: (Value, Value) async throws -> Void) async throws {
        guard !isRestoring else { return }
        finish(read())
        guard let step = history.previous else { return }
        isRestoring = true
        defer { isRestoring = false }
        try await apply(step.before, step.after)
        history.acceptUndo(step)
        // Any external changes during the asynchronous restore form a new baseline.
        history.synchronize(read()); updateAvailability()
    }
}
