import Foundation

enum WidgetFeedbackChecks {
    static func run() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "WidgetFeedbackChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let item = TodoItem(id: UUID(), title: "每项独立标记", marker: TodoMarker(kind: .emoji, emoji: "❤️"), isCompleted: false, createdAt: now, updatedAt: now)
        var look = TodoAppearance()
        var oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(look)) as! [String: Any]
        var oldWidget = oldObject["widget"] as! [String: Any]
        for key in ["completedTextStyle", "completedTextColor", "showsSeparators"] { oldWidget.removeValue(forKey: key) }
        oldObject["widget"] = oldWidget
        let legacy = try JSONDecoder().decode(TodoAppearance.self, from: JSONSerialization.data(withJSONObject: oldObject))
        try legacy.validate()
        try require(legacy.widget.textCompletion == .fadeStrike && !legacy.widget.separatesRows, "0.4.1 shared appearance loads with its old completion and separator behavior")
        var preview = WidgetPreviewState()
        preview.toggle(item, now: now.addingTimeInterval(10))
        try require(preview.items([item])[0].isCompleted && !item.isCompleted, "Preview completes a copy only")
        preview.toggle(item)
        try require(!preview.items([item])[0].isCompleted, "Preview restores its local state")
        preview.reset()
        try require(preview.items([item]) == [item], "Preview reset restores the untouched source document")
        var policy = MarkerStyle(); policy.completion = .thinCircle
        let done = policy.resolved(TodoMarker(kind: .emoji, emoji: "❤️"), completed: true)
        try require(done.marker.kind == .thin && done.checked, "Completed Emoji can turn into a checked thin circle")
        policy.completion = .replace; policy.completionEmoji = "🧑🏽‍💻"
        try policy.validate()
        try require(policy.resolved(TodoMarker(kind: .hollow), completed: true).marker.emoji == "🧑🏽‍💻", "Replacement is user-selected composed Emoji")
        try require(policy.resolved(TodoMarker(kind: .none), completed: true).marker.kind == .none, "Hidden markers stay hidden")
        try require(WidgetTextCompletion.allCases.count == 5 && WidgetTextCompletion.strike.strikes && !WidgetTextCompletion.strike.fades && !WidgetTextCompletion.keep.strikes,
                    "Independent completed-text policies")
        for size in stride(from: 8.0, through: 48.0, by: 0.5) {
            look.widget.markerStyle.emojiSize = size
            let metrics = WidgetLayoutMetrics.make(items: [item], appearance: look, family: .small,
                width: 138, height: 138, fontLineHeight: 18, headerHeight: 22, footerHeight: 15)
            try require(abs(metrics.markerWidth - size) < 0.00001, "Marker slider must not stop at 20/24")
        }
        for gap in stride(from: 0.0, through: 32.0, by: 0.5) {
            look.widget.markerStyle.gap = gap
            let metrics = WidgetLayoutMetrics.make(items: [item], appearance: look, family: .medium,
                width: 332, height: 138, fontLineHeight: 18, headerHeight: 22, footerHeight: 15)
            try require(metrics.gap == gap, "Gap slider must not stop at 12")
        }
        for family in WidgetPreviewFamily.allCases {
            for height in [100.0, 126, 138, 250, 350] {
                for line in [18.0, 24, 36, 52, 74] {
                    for size in [8.0, 20, 32, 48] {
                        for separators in [false, true] {
                            look.widget.markerStyle.emojiSize = size; look.widget.showsSeparators = separators
                            let m = WidgetLayoutMetrics.make(items: [item], appearance: look, family: family,
                                width: 112, height: height, fontLineHeight: line, headerHeight: max(22, line), footerHeight: max(15, line * 0.6))
                            let count = m.capacity
                            let used = Double(count) * m.rowHeight + Double(max(0, count - 1)) * (m.spacing + m.separatorHeight)
                            try require(used <= m.availableRowHeight + 0.00001, "Dynamic fonts/large markers/reduced logical size cannot overflow rows")
                            try require(m.markerWidth == size && m.gap == 32, "Fit by reducing rows, never by silent marker/gap clamps")
                        }
                    }
                }
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetFeedback-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TodoRepository(directoryURL: root)
        let added = try repository.add(title: item.title); let id = added.items[0].id
        _ = try repository.edit(id: id, title: item.title, marker: item.marker)
        _ = try repository.setCompleted(id: id, completed: true)
        let stored = try repository.load().items[0]
        try require(stored.id == id && stored.marker == item.marker && stored.isCompleted, "Per-task preview-editor marker survives real persistence and intent-equivalent completion")
        print("PASS: Widget feedback — legacy appearance, local-only preview completion/reset, custom Emoji and thin-circle completion, five text effects, full marker/gap slider ranges, Dynamic Type/reduced-space row budgets and persisted per-task marker/identity.")
    }
}
