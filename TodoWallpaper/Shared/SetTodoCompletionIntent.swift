import Foundation
import AppIntents
import WidgetKit

struct SetTodoCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "完成或恢复待办"
    static var description = IntentDescription("直接修改共享待办，不打开主 App。")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "任务标识") var taskID: String
    @Parameter(title: "完成状态") var completed: Bool

    init() { taskID = ""; completed = true }
    init(taskID: UUID, completed: Bool) { self.taskID = taskID.uuidString; self.completed = completed }

    func perform() async throws -> some IntentResult {
        defer { WidgetCenter.shared.reloadTimelines(ofKind: TodoWidgetConstants.kind) }
        guard let id = UUID(uuidString: taskID) else { throw TodoDataError.missingItem }
        _ = try TodoSharedStorage.widgetRepository().setCompleted(id: id, completed: completed)
        return .result()
    }
}
