import AppIntents
import WidgetKit

struct SetProbeTaskCompletionIntent: AppIntent {
    static var title: LocalizedStringResource = "完成或恢复测试待办"
    static var description = IntentDescription("在共享容器中修改测试待办，无需打开主 App。")
    static var openAppWhenRun = false

    @Parameter(title: "完成状态") var completed: Bool

    init() { completed = false }
    init(completed: Bool) { self.completed = completed }

    func perform() async throws -> some IntentResult {
        _ = try SharedProbeStore().setCompleted(completed, source: "widget")
        WidgetCenter.shared.reloadTimelines(ofKind: ProbeConstants.widgetKind)
        return .result()
    }
}
