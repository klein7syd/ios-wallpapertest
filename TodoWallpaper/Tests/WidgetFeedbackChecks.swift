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
        try require(WidgetTextCompletion.allCases.count == 6 && WidgetTextCompletion.strike.strikes && !WidgetTextCompletion.strike.fades && !WidgetTextCompletion.keep.strikes && WidgetTextCompletion.hidden.hidesCompleted,
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
        try require(ReadableRules.coverHeight(400, ratio: 0.45, extraInset: -12) == 180,
                    "Negative content inset cannot enlarge the photo scrim")
        try require(ReadableRules.coverHeight(400, ratio: 0.45, extraInset: 12) == 192,
                    "Positive content inset extends the photo scrim")
        for light in [false, true] {
            let easy = ReadableRules.scrim(meanLuma: light ? 0.1 : 0.9, contrast: 0.5, isLightText: light)
            let difficult = ReadableRules.scrim(meanLuma: light ? 0.9 : 0.1, contrast: 0.5, isLightText: light)
            try require(difficult > easy, "Black and white scrims both strengthen toward the background that reduces text contrast")
        }
        try require(abs(ReadableRules.scrim(meanLuma: 0.6, contrast: 0.5, isLightText: false) - 0.3625) < 0.000000001,
                    "White scrim follows the specified (0.8 - mean) / 0.8 mapping exactly")
        var readable = ReadableSettings()
        let legacyAnalysis = try JSONDecoder().decode(ImageAnalysis.self, from: JSONSerialization.data(withJSONObject:
            ["meanLuma": 0.15, "contrast": 0.4, "suggestedScrim": 0.8]))
        let changedLegacy = ImageAnalysis(meanLuma: 0.15, contrast: 0.4)
        try require(readable.autoScrim(analysis: legacyAnalysis, isLightText: false) == readable.autoScrim(analysis: changedLegacy, isLightText: false),
                    "Legacy cached suggestion never overrides runtime text-tone analysis")
        let decodedAnalysis = try JSONDecoder().decode(ImageAnalysis.self, from: JSONEncoder().encode(legacyAnalysis))
        let encodedAnalysis = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyAnalysis)) as? [String: Any]
        try require(decodedAnalysis.meanLuma == legacyAnalysis.meanLuma && decodedAnalysis.contrast == legacyAnalysis.contrast
                    && decodedAnalysis.suggestedScrim == nil && encodedAnalysis?["suggestedScrim"] == nil,
                    "Existing image-analysis JSON remains decodable and new caches store only raw analysis")
        var strengths: [Double] = []
        for strength in ReadabilityIntensity.allCases {
            readable.intensity = strength
            strengths.append(readable.autoScrim(analysis: legacyAnalysis, isLightText: false))
        }
        try require(strengths[0] < strengths[1] && strengths[1] < strengths[2], "All three runtime scrim intensities remain distinct")
        for fullColor in [false, true] { for accessory in [false, true] {
            try require(ReadableRules.permitsEffects(isFullColor: fullColor, isAccessory: accessory) == (fullColor && !accessory),
                        "Tinted and lock-screen content cannot receive photo scrims or shadows")
        } }
        try require(ReadableRules.insetRange(anchor: .center, canvasHeight: 350, textHeight: 90) == -130...130,
                    "Centered short content can move across the available canvas")
        try require(ReadableRules.insetRange(anchor: .center, canvasHeight: 138, textHeight: 120) == -40...40,
                    "Centered dense content retains the minimum movement range")
        try require(ReadableRules.inset(500, anchor: .center, canvasHeight: 350, textHeight: 90) == 130
                    && ReadableRules.inset(130, anchor: .top, canvasHeight: 350, textHeight: 90) == 40,
                    "Slider, anchor changes and rendering share the same inset clamp")
        var outside = TodoAppearance()
        outside.widget.readableAnchor = .top; outside.widget.readableEdgeInset = -40
        let legacyInset = try JSONDecoder().decode(TodoAppearance.self, from: JSONEncoder().encode(outside))
        try legacyInset.validate()
        try require(legacyInset.widget.readableEdgeInset == -40 && legacyInset.clampedForEditing().widget.readableEdgeInset == -12,
                    "Previously valid negative inset files still load while new editing uses the narrower safe range")
        outside.widget.readableAnchor = .center; outside.widget.readableEdgeInset = 130
        try outside.validate()
        outside.widget.fontSize = 50; outside.widget.textColor.red = 1.2
        outside.widget.markerStyle.gap = -2; outside.widget.backgroundCrop = PhotoCrop(zoom: 8, panX: .nan)
        let repaired = outside.clampedForEditing()
        try repaired.validate()
        try require(repaired.widget.fontSize == 20 && repaired.widget.textColor.red == 1
                    && repaired.widget.markerStyle.gap == 0 && repaired.widget.photoCrop.zoom == 4
                    && repaired.widget.photoCrop.panX == 0 && repaired.widget.readableEdgeInset == 130,
                    "Numeric repair keeps finite centered positions while normalizing nested editing values")
        outside.schemaVersion = 99; outside.defaultMarker = TodoMarker(kind: .emoji, emoji: "invalid")
        try require(outside.clampedForEditing().schemaVersion == 99 && outside.clampedForEditing().defaultMarker.emoji == "invalid",
                    "Numeric repair cannot silently replace schema or semantic marker input")
        print("PASS: Widget feedback — legacy appearance and analysis, direct completion, marker sizing, row budgets, tone-aware scrims, effect exclusions, dynamic insets and safe numeric normalization.")
    }
}
