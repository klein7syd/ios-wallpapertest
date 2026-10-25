import SwiftUI
import WidgetKit

/// The app preview and Widget extension render the same rows and capacity rules.
/// Preview buttons are deliberately disabled; real Widget buttons keep App Intents.
struct TodoWidgetContent: View {
    let document: TodoDocument?
    let appearance: TodoAppearance
    let error: String?
    let family: WidgetPreviewFamily
    var interactive = true
    @Environment(\.dynamicTypeSize) private var typeSize
    private var style: WidgetAppearance { appearance.widget }
    private var foreground: Color { style.followsSystemText ? .primary : style.textColor.swiftColor }
    var body: some View {
        VStack(alignment: .leading, spacing: style.compact ? min(3, style.spacing) : style.spacing) {
            if let document {
                let pending = document.items.filter { !$0.isCompleted }
                let shown = style.rows(document.items, capacity: family.rowLimit(appearance: style, accessibility: typeSize.isAccessibilitySize))
                HStack {
                    Text("待办").font(.headline)
                    Spacer(minLength: 4)
                    Text("\(pending.count) 未完成").font(.caption2).lineLimit(1).minimumScaleFactor(0.8).opacity(0.7)
                }
                if document.items.isEmpty {
                    Spacer(minLength: 0)
                    Text("还没有待办").font(.subheadline)
                    Text("在 App 中记下第一件事").font(.caption).opacity(0.7)
                } else {
                    ForEach(shown) { item in task(item) }
                    if shown.isEmpty { Text("全部完成").font(.subheadline) }
                }
                Spacer(minLength: 0)
                Text(document.items.count > shown.count ? "另有 \(document.items.count - shown.count) 项 · 点标记操作" : "点任务可完成或恢复")
                    .font(.caption2).opacity(0.7).lineLimit(1)
            } else {
                Text("Todo Wallpaper").font(.headline)
                Text(error ?? "请先打开 App 完成迁移").font(.caption).lineLimit(family == .large ? 8 : 4)
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(foreground)
    }
    @ViewBuilder private func task(_ item: TodoItem) -> some View {
        if interactive {
            Button(intent: SetTodoCompletionIntent(taskID: item.id, completed: !item.isCompleted)) { row(item) }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
                .invalidatableContent()
        } else { row(item) }
    }
    private func row(_ item: TodoItem) -> some View {
        HStack(alignment: .center, spacing: min(12, style.markerStyle.gap)) {
            TodoMarkerView(marker: appearance.marker(for: item, widgetContext: true), completed: item.isCompleted,
                style: style.markerStyle, textColor: foreground, maximumSize: family == .small ? 20 : 24)
            Text(item.title)
                .font(Font(NativeTypography.font(family: style.font, weight: style.weight, size: style.fontSize)))
                .strikethrough(item.isCompleted).opacity(item.isCompleted ? 0.6 : 1)
                .lineLimit(family == .large && !style.compact ? 2 : 1)
                .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
        }
        .padding(.vertical, style.compact ? 0 : 2).contentShape(Rectangle())
    }
}
