import Foundation

enum FeedbackRepairChecks {
    static func run() throws {
        func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "FeedbackRepairChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var detent = StandardDetent()
        try require(detent.value(0.508, standard: 0.5, range: 0...1, trackWidth: 300) == 0.5, "Standard node captures nearby drag")
        try require(detent.value(0.52, standard: 0.5, range: 0...1, trackWidth: 300) == 0.5, "Detent hysteresis prevents chatter")
        try require(detent.value(0.54, standard: 0.5, range: 0...1, trackWidth: 300) == 0.54, "Slider can leave detent")
        try require(detent.value(0.52, standard: 0.5, range: 0...1, trackWidth: 300) == 0.52, "Outside capture region remains continuous")
        detent.reset()
        try require(detent.value(-100, standard: 0, range: 0...45, trackWidth: 280) == 0, "Endpoint standard is reachable")
        try require(detent.value(99, standard: 0, range: 0...45, trackWidth: 280) == 45, "Overshoot remains bounded")

        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TodoAppearance())) as! [String: Any]
        var widget = old["widget"] as! [String: Any]
        for key in ["header", "backgroundPhotoName"] { widget.removeValue(forKey: key) }
        old["widget"] = widget
        let legacy = try JSONDecoder().decode(TodoAppearance.self, from: JSONSerialization.data(withJSONObject: old))
        try require(legacy.widget.heading == WidgetHeaderAppearance() && legacy.widget.backgroundPhotoName == nil,
            "Old appearance restores default title/statistics and no photo")
        var look = legacy
        look.defaultMarker = TodoMarker(kind: .emoji, emoji: "🌸")
        look.widget.header = WidgetHeaderAppearance(text: "今天的小目标", color: WallpaperColor(red: 1, green: 0, blue: 0),
            fontSize: 25, horizontalPosition: 0.5, topInset: 8)
        look.widget.backgroundPhotoName = "widget-photo-\(UUID().uuidString).jpg"
        look.widget.backdrop = .photo
        try look.validate()
        let roundtrip = try JSONDecoder().decode(TodoAppearance.self, from: JSONEncoder().encode(look))
        try require(roundtrip == look, "Header/photo survive appearance serialization")
        try require(EditorStandards.widget(look.widget, scale: 1.1).heading == look.widget.heading,
            "Body layout scaling does not overwrite custom title")
        try require(!WidgetPhotoReference.isValid("../secret.jpg") && !WidgetPhotoReference.isValid("widget-photo-../x.jpg"),
            "Widget image reference cannot escape its private directory")
        for family in WidgetPreviewFamily.allCases {
            for x in [0.0, 0.5, 1.0] {
                var heading = look.widget.heading; heading.horizontalPosition = x
                let layout = WidgetHeaderLayout.make(style: heading, width: family.width - 32, maximumHeight: family.height / 2,
                    measuredTitleWidth: 480, titleLineHeight: 30, measuredSummaryWidth: 74, summaryHeight: 16)
                try require(layout.titleX >= 0 && layout.titleX + layout.titleWidth <= layout.summaryX - 5.9,
                    "Title/summary never overlap in \(family.id)")
                heading.showsSummary = false
                let hidden = WidgetHeaderLayout.make(style: heading, width: family.width - 32, maximumHeight: family.height / 2,
                    measuredTitleWidth: 90, titleLineHeight: 30, measuredSummaryWidth: 74, summaryHeight: 16)
                try require(hidden.summaryWidth == 0 && hidden.titleWidth == 90 && hidden.titleX + hidden.titleWidth <= family.width - 32,
                    "Summary toggle frees title position budget")
                heading.showsTitle = false
                let empty = WidgetHeaderLayout.make(style: heading, width: 138, maximumHeight: 80,
                    measuredTitleWidth: 90, titleLineHeight: 30, measuredSummaryWidth: 74, summaryHeight: 16)
                try require(empty.height == 0, "Both heading elements hidden reserve no space")
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("feedback-import-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = TodoRepository(directoryURL: root)
        _ = try repository.add(title: "原来的待办", marker: TodoMarker(kind: .emoji, emoji: "❤️"))
        let original = try repository.load().items[0]
        let visibleTask = TodoItem(id: UUID(), title: "画布中的任务", marker: TodoMarker(kind: .emoji, emoji: "📚"),
            isCompleted: false, createdAt: .now, updatedAt: .now)
        let overflowTask = TodoItem(id: UUID(), title: "面板以外的任务", isCompleted: false, createdAt: .now, updatedAt: .now)
        var hidden = original; hidden.isCompleted = true
        for preferred in [nil, hidden.id, overflowTask.id, visibleTask.id] {
            try require(MarkerEditorTarget.selected(items: [hidden, visibleTask, overflowTask], visibleIDs: [visibleTask.id],
                preferredID: preferred)?.id == visibleTask.id, "Wallpaper edits the actual visible row, never a hidden completed/overflow task")
        }
        try require(MarkerEditorTarget.selected(items: [hidden, overflowTask], visibleIDs: [visibleTask.id], preferredID: visibleTask.id) == nil,
            "Missing/empty canvas never resurrects a task as an editing target")
        let sourceID = TodoImportIdentity.make(source: "event", calendar: "fixture-calendar", item: "fixture-event", occurrence: "2026-10-27")
        let repeatID = TodoImportIdentity.make(source: "event", calendar: "fixture-calendar", item: "fixture-event", occurrence: "2026-10-27")
        let nextOccurrence = TodoImportIdentity.make(source: "event", calendar: "fixture-calendar", item: "fixture-event", occurrence: "2026-10-28")
        try require(sourceID == repeatID && sourceID != nextOccurrence && sourceID != TodoImportIdentity.make(source: "reminder", calendar: "fixture-calendar", item: "fixture-event"),
            "Calendar/reminder IDs are stable and recurring dates stay separate")
        let imported = TodoItem(id: sourceID, title: "导入的日程", isCompleted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        _ = try repository.importItems([imported, imported])
        var changed = imported; changed.title = "不能覆盖的较新源标题"; changed.isCompleted = true
        _ = try repository.importItems([changed, original])
        let after = try repository.load()
        try require(after.items == [original, imported], "Repeated import preserves all original fields, IDs, order, Emoji and completion")
        let bytes = try Data(contentsOf: repository.fileURL)
        do {
            _ = try repository.updateMarkers([TodoMarkerUpdate(id: original.id, expected: nil, marker: TodoMarker())])
            throw NSError(domain: "ExpectedMarkerConflict", code: 1)
        } catch TodoDataError.missingItem { }
        try require(try Data(contentsOf: repository.fileURL) == bytes, "Conflicting undo writes nothing")
        _ = try repository.updateMarkers([TodoMarkerUpdate(id: original.id, expected: original.marker, marker: nil),
            TodoMarkerUpdate(id: imported.id, expected: nil, marker: TodoMarker(kind: .emoji, emoji: "📚"))])
        let restored = try repository.load()
        try require(restored.items.map(\.id) == after.items.map(\.id) && restored.items[0].marker == nil && restored.items[1].marker?.emoji == "📚",
            "Multiple marker undos share one atomic transaction")
        let trimmedID = TodoImportIdentity.make(source: "reminder", calendar: "fixture", item: "trimmed")
        let padded = TodoItem(id: trimmedID, title: "  来源末尾空白  ", isCompleted: false,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let normalized = try repository.importItems([padded])
        try require(normalized.items.last?.title == "来源末尾空白", "Source title boundary whitespace normalizes just like manual add")
        var invalid = imported; invalid.title = ""
        let beforeInvalid = try Data(contentsOf: repository.fileURL)
        do { _ = try repository.importItems([invalid]); throw NSError(domain: "ExpectedInvalidImport", code: 1) }
        catch TodoDataError.invalidTitle { }
        try require(try Data(contentsOf: repository.fileURL) == beforeInvalid, "Bad import preserves current task data")
        print("PASS: standard detents, compatible title/photo defaults, bounded header positions, local import identities/idempotence and atomic marker undo conflicts.")
    }
}
