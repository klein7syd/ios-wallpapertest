import SwiftUI
import WidgetKit

struct ProbeEntry: TimelineEntry {
    let date: Date
    let state: SharedProbeState?
    let error: String?
    let build: String
}

struct ProbeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ProbeEntry {
        ProbeEntry(date: .now, state: SharedProbeState(), error: nil, build: "预览")
    }
    func getSnapshot(in context: Context, completion: @escaping (ProbeEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : read())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ProbeEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .never))
    }
    private func read() -> ProbeEntry {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        do {
            return ProbeEntry(date: .now, state: try SharedProbeStore().read(), error: nil, build: build)
        } catch {
            return ProbeEntry(date: .now, state: nil, error: error.localizedDescription, build: build)
        }
    }
}

struct ProbeWidgetView: View {
    let entry: ProbeEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("原生待办验证").font(.caption).bold()
                Spacer(minLength: 0)
                Text("b\(entry.build)").font(.caption2).foregroundStyle(.secondary)
            }
            if let state = entry.state {
                Button(intent: SetProbeTaskCompletionIntent(completed: !state.isCompleted)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: state.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(state.isCompleted ? .green : .blue)
                        Text(state.title).font(.subheadline)
                            .strikethrough(state.isCompleted).lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(state.isCompleted ? "恢复待办" : "完成待办")
                Text(state.isCompleted ? "已完成 · 点击恢复" : "未完成 · 点击完成")
                    .font(.caption).invalidatableContent()
                Text("r\(state.revision) · \(state.lastWriter)")
                    .font(.caption2).foregroundStyle(.secondary).invalidatableContent()
            } else {
                Text("共享容器不可用").font(.subheadline).foregroundStyle(.red)
                Text(entry.error ?? "请检查签名权限")
                    .font(.caption2).lineLimit(4)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

@main
struct NativeProbeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ProbeConstants.widgetKind, provider: ProbeProvider()) { entry in
            ProbeWidgetView(entry: entry)
        }
        .configurationDisplayName("原生能力验证")
        .description("验证 App Groups 与无需打开 App 的待办操作。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
