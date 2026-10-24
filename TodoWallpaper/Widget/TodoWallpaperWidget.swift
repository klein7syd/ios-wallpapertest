import SwiftUI
import WidgetKit

struct TodoWidgetEntry: TimelineEntry {
    let date: Date
    let document: TodoDocument?
    let error: String?
}

struct TodoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoWidgetEntry {
        let now = Date()
        return TodoWidgetEntry(date: now, document: TodoDocument(items: [
            TodoItem(id: UUID(), title: "记下重要的小事", isCompleted: false, createdAt: now, updatedAt: now)
        ]), error: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodoWidgetEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoWidgetEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .never))
    }
    private func read() -> TodoWidgetEntry {
        do { return TodoWidgetEntry(date: .now, document: try TodoSharedStorage.widgetRepository().load(), error: nil) }
        catch { return TodoWidgetEntry(date: .now, document: nil, error: error.localizedDescription) }
    }
}

struct TodoWidgetView: View {
    let entry: TodoWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.dynamicTypeSize) private var typeSize

    private var rowLimit: Int {
        if typeSize.isAccessibilitySize { return family == .systemLarge ? 4 : 1 }
        return family == .systemLarge ? 6 : family == .systemMedium ? 3 : 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let document = entry.document {
                let pending = document.items.filter { !$0.isCompleted }
                let completed = document.items.filter(\.isCompleted)
                let recent = completed.max(by: { $0.updatedAt < $1.updatedAt })
                let showCompleted = recent != nil && (rowLimit > 1 || pending.isEmpty)
                let pendingSlots = max(0, rowLimit - (showCompleted ? 1 : 0))
                let shown = Array(pending.prefix(pendingSlots))
                HStack {
                    Text("待办").font(.headline)
                    Spacer(minLength: 4)
                    Text("\(pending.count) 待办 · \(completed.count) 完成")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                if document.items.isEmpty {
                    Spacer(minLength: 0)
                    Text("还没有待办").font(.subheadline)
                    Text("在 App 中记下第一件事").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(shown) { item in taskButton(item) }
                    if showCompleted, let recent { taskButton(recent) }
                    Spacer(minLength: 0)
                    Text(pending.count > shown.count ? "另有 \(pending.count - shown.count) 项未完成" : pending.isEmpty ? "全部完成 · 可点勾选恢复" : "点圆圈即可完成")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Todo Wallpaper").font(.headline)
                Text(entry.error ?? "请先打开 App 完成迁移")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(family == .systemLarge ? 8 : 4)
                Spacer(minLength: 0)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private func taskButton(_ item: TodoItem) -> some View {
        Button(intent: SetTodoCompletionIntent(taskID: item.id, completed: !item.isCompleted)) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(item.isCompleted ? Color.green : Color.accentColor)
                Text(item.title).font(.subheadline).strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(family == .systemLarge ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
        .invalidatableContent()
    }
}

@main
struct TodoWallpaperWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodoWidgetConstants.kind, provider: TodoWidgetProvider()) { entry in
            TodoWidgetView(entry: entry)
        }
        .configurationDisplayName("Todo Wallpaper")
        .description("直接完成待办，与 App 共享同一份数据。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
