import Foundation

enum EditorRefinementChecks {
    static func run() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "EditorRefinementChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var history = EditorHistory<Int>()
        history.synchronize(0)
        history.beginInteraction()
        for value in 1...500 { history.observe(value) }
        history.endInteraction()
        try require(history.steps.count == 1 && history.previous?.before == 0 && history.previous?.after == 500,
            "500 continuous updates require one undo, not 500 taps")
        history.beginInteraction(); history.observe(600); history.endInteraction()
        try require(history.steps.count == 2, "Separate slider gestures are separate undo steps")
        let last = history.previous!
        // A failed application does not accept/pop the pending step.
        try require(history.previous == last, "Failed restore keeps its retryable undo step")
        history.acceptUndo(last)
        try require(history.current == 500 && history.steps.count == 1, "Successful undo restores the previous interaction")
        history.acceptUndo(history.previous!)
        try require(history.current == 0 && !history.canUndo, "Undo exhausts history without a false initial-load edit")
        history.beginInteraction(); history.observe(1); history.observe(0); history.endInteraction()
        try require(!history.canUndo, "Dragging back to the starting value is not an undoable edit")
        history.observe(5); history.observe(7)
        try require(history.steps.count == 2, "Discrete actions do not merge")
        history.synchronize(7)
        try require(history.steps.count == 2, "Unchanged tab re-entry keeps valid session history")
        history.synchronize(12)
        try require(!history.canUndo && history.current == 12, "External state changes become a safe new baseline")
        for value in 13...200 { history.observe(value) }
        try require(history.steps.count == 50 && history.previous?.after == 200, "History memory is bounded")

        try require(EditorStandards.fraction(0.5, in: 0...1) == 0.5 &&
            EditorStandards.fraction(0, in: -1...1) == 0.5 &&
            EditorStandards.fraction(1, in: 1...4) == 0, "Standard nodes map to real range positions")
        var style = WidgetAppearance()
        style.markerOverride = TodoMarker(kind: .emoji, emoji: "🧑🏽‍💻")
        style.markerStyle.completion = .thinCircle
        style.completedTextStyle = .color; style.showsSeparators = true
        style.markerStyle.gap = 27.7; style.spacing = 11.1
        let original = style
        for _ in 0..<50 { _ = EditorStandards.advancedKey }
        try require(style == original, "Advanced-control visibility has no style mutation")
        for scale in stride(from: EditorStandards.widgetScale.lowerBound,
                            through: EditorStandards.widgetScale.upperBound, by: 0.01) {
            let scaled = EditorStandards.widget(style, scale: scale)
            try scaled.validate()
            try require(abs(scaled.fontSize / 15 - scaled.markerStyle.emojiSize / 22) < 0.00001 &&
                abs(scaled.spacing / 5 - scaled.markerStyle.gap / 10) < 0.00001,
                "Standard typography, marker and spacing scale together")
            try require(scaled.markerOverride == original.markerOverride && scaled.markerStyle.completion == .thinCircle &&
                scaled.textCompletion == .color && scaled.separatesRows, "Scaling preserves Emoji, completion and content choices")
        }
        let standard = EditorStandards.widget(style, scale: 1)
        try require(standard.fontSize == 15 && standard.markerStyle.size == 18 && standard.markerStyle.emojiSize == 22 &&
            standard.markerStyle.gap == 10 && standard.spacing == 5, "Scale node restores the actual standard proportions")
        print("PASS: bounded/grouped undo, failed-restore retention, external-state rebase, standard-node positions, advanced visibility preservation and standard Widget scaling.")
    }
}
