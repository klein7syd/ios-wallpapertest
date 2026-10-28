import SwiftUI
import EventKit
import UIKit

private enum CalendarSource: String, CaseIterable, Identifiable, Sendable {
    case events = "日历日程", reminders = "提醒事项"
    var id: String { rawValue }
}
private enum CalendarImportError: LocalizedError {
    case permission, dateRange, unavailable
    var errorDescription: String? {
        switch self {
        case .permission: return "未获得读取权限。可在系统设置中允许日历完整访问或提醒事项访问。"
        case .dateRange: return "请选择先后正确、最长 90 天的日期范围。"
        case .unavailable: return "暂时无法读取，请稍后重试。"
        }
    }
}

/// All EventKit work stays off the main actor. Reading never saves/deletes an
/// EKEvent/EKReminder; imported tasks are explicit local snapshots.
private actor CalendarReader {
    private let events = EKEventStore()
    func read(source: CalendarSource, start: Date, end: Date, includeCompleted: Bool) async throws -> [TodoImportCandidate] {
        if source == .events {
            guard end >= start, let days = Calendar.current.dateComponents([.day], from: start, to: end).day, days <= 90 else { throw CalendarImportError.dateRange }
            guard try await events.requestFullAccessToEvents() else { throw CalendarImportError.permission }
            let predicate = events.predicateForEvents(withStart: start, end: end, calendars: nil)
            let formatter = DateFormatter(); formatter.dateStyle = .short; formatter.timeStyle = .short
            return events.events(matching: predicate).filter { $0.status != .canceled }.compactMap { event in
                let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return nil }
                let date = event.startDate ?? start
                formatter.timeStyle = event.isAllDay ? .none : .short
                let label = formatter.string(from: date)
                let occurrence = event.hasRecurrenceRules ? String((event.occurrenceDate ?? date).timeIntervalSince1970) : "single"
                return TodoImportCandidate(id: TodoImportIdentity.make(source: "event", calendar: event.calendar.calendarIdentifier,
                    item: event.calendarItemIdentifier, occurrence: occurrence),
                    title: String(title.prefix(200)), detail: "\(event.calendar.title) · \(label)",
                    isCompleted: false, sortDate: date, schedule: TodoSchedule(date: date, includesTime: !event.isAllDay))
            }.sorted { $0.sortDate < $1.sortDate }
        }
        guard try await events.requestFullAccessToReminders() else { throw CalendarImportError.permission }
        let predicate = events.predicateForReminders(in: nil)
        let found: [TodoImportCandidate] = try await withCheckedThrowingContinuation { continuation in
            events.fetchReminders(matching: predicate) { reminders in
                guard let reminders else { continuation.resume(throwing: CalendarImportError.unavailable); return }
                let candidates = reminders.filter { includeCompleted || !$0.isCompleted }.compactMap { reminder -> TodoImportCandidate? in
                    let title = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !title.isEmpty else { return nil }
                    // dueDateComponents 不带 calendar 时 .date 会返回 nil，这里补上当前日历
                    let dueDate = reminder.dueDateComponents.flatMap { components -> Date? in
                        if let date = components.date { return date }
                        var fixed = components
                        fixed.calendar = Calendar.current
                        return fixed.date
                    }
                    return TodoImportCandidate(id: TodoImportIdentity.make(source: "reminder", calendar: reminder.calendar.calendarIdentifier,
                        item: reminder.calendarItemIdentifier), title: String(title.prefix(200)), detail: reminder.calendar.title,
                        isCompleted: reminder.isCompleted, sortDate: dueDate ?? .distantFuture,
                        schedule: dueDate.map { TodoSchedule(date: $0, includesTime: reminder.dueDateComponents?.hour != nil) })
                }
                continuation.resume(returning: candidates)
            }
        }
        return found.sorted { $0.sortDate == $1.sortDate ? $0.title < $1.title : $0.sortDate < $1.sortDate }

    }
}

struct CalendarImportView: View {
    @ObservedObject var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var source = CalendarSource.events
    @State private var start = Calendar.current.startOfDay(for: .now)
    @State private var end = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: .now)) ?? .now
    @State private var includeCompleted = false
    @State private var candidates: [TodoImportCandidate] = []
    @State private var selected = Set<UUID>()
    @State private var loading = false
    @State private var didRead = false
    @State private var error: String?
    @State private var limited = false
    private let reader = CalendarReader()
    private var existing: Set<UUID> { Set(store.items.map(\.id)) }
    private var importable: [TodoImportCandidate] { candidates.filter { !existing.contains($0.id) } }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("来源", selection: $source) { ForEach(CalendarSource.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                    if source == .events {
                        DatePicker("起始日期", selection: $start, displayedComponents: .date)
                        DatePicker("结束日期（不含）", selection: $end, displayedComponents: .date)
                    } else { Toggle("包含已完成提醒事项", isOn: $includeCompleted) }
                    Button { read() } label: {
                        if loading { ProgressView("正在读取…") } else { Label("读取\(source.rawValue)", systemImage: "calendar") }
                    }.disabled(loading)
                } footer: { Text("仅导入你选择的内容，不修改系统日历或提醒事项，也不持续同步。") }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    }
                }
                if didRead {
                    Section {
                        if candidates.isEmpty { Text("没有可导入的内容") }
                        else {
                            Button(selected.isEmpty ? "选择全部未导入项" : "取消选择") {
                                selected = selected.isEmpty ? Set(importable.map(\.id)) : []
                            }
                            ForEach(candidates) { item in
                                Button {
                                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: existing.contains(item.id) ? "checkmark.circle.fill" : selected.contains(item.id) ? "checkmark.circle" : "circle")
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.title).foregroundStyle(.primary).lineLimit(3)
                                            Text(existing.contains(item.id) ? "已导入 · \(item.detail)" : item.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.frame(minHeight: 44)
                                }.buttonStyle(.plain).disabled(existing.contains(item.id))
                            }
                        }
                    } header: { Text("选择要导入的项目") } footer: {
                        if limited { Text("本次展示前 500 项，请缩小日历范围或分批处理。") }
                    }
                }
            }
            .navigationTitle("从 Apple 导入").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(loading) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入 \(selected.subtracting(existing).count) 项") { importSelected() }
                        .disabled(selected.subtracting(existing).isEmpty || loading || store.loadError != nil)
                }
            }
            .onChange(of: source) { _, _ in clear() }
            .onChange(of: start) { _, _ in clear() }
            .onChange(of: end) { _, _ in clear() }
            .onChange(of: includeCompleted) { _, _ in clear() }
            .interactiveDismissDisabled(loading)
        }
    }
    private func clear() { candidates = []; selected = []; didRead = false; error = nil }
    private func read() {
        loading = true; error = nil
        let requestedSource = source, requestedStart = start, requestedEnd = end, requestedCompleted = includeCompleted
        Task {
            defer { loading = false }
            do {
                let result = try await reader.read(source: requestedSource, start: requestedStart, end: requestedEnd, includeCompleted: requestedCompleted)
                guard source == requestedSource, start == requestedStart, end == requestedEnd, includeCompleted == requestedCompleted else { return }
                // Some calendars return duplicate recurrence records; deduplicate by stable identity.
                var seen = Set<UUID>()
                let unique = result.filter { seen.insert($0.id).inserted }
                candidates = Array(unique.prefix(500)); limited = unique.count > 500; selected = []; didRead = true
            } catch { self.error = error.localizedDescription }
        }
    }
    private func importSelected() {
        do { try store.importItems(importable.filter { selected.contains($0.id) }.map { $0.item() }); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
