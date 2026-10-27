import Foundation
import CoreGraphics

enum PhotoRepairChecks {
    static func run() throws {
        func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "PhotoRepairChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let old = try JSONDecoder().decode(TodoMarker.self, from: Data(#"{"kind":"emoji","emoji":"🧑🏽‍💻"}"#.utf8))
        try require(old.imageName == nil && old.emoji == "🧑🏽‍💻", "Old marker decodes without an image field")
        let name = "marker-image-\(UUID().uuidString).png"
        let marker = TodoMarker(kind: .image, imageName: name)
        try marker.validate()
        try require(MarkerImageReference.isValid(name) && !MarkerImageReference.isValid("../secret.png") && !MarkerImageReference.isValid("marker-image-../x.png"), "Generated image names reject path traversal")
        let controls = MarkerControlVisibility(kind: .image)
        try require(controls.image && !controls.shape && !controls.emoji && !controls.stroke && !controls.fill, "Image markers have image controls, never shape colors")
        var style = MarkerStyle(); style.completion = .dim
        try require(style.resolved(marker, completed: true).marker.imageName == name && style.resolved(marker, completed: true).opacity == 0.4, "Image completion can dim the original image")
        style.completion = .replace; style.completionEmoji = "❤️"
        try require(style.resolved(marker, completed: true).marker.emoji == "❤️", "Image completion uses the saved custom Emoji")
        style.completion = .thinCircle
        try require(style.resolved(marker, completed: true).marker.kind == .thin, "Image completion supports a fine checked circle")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("photo-repair-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = TodoRepository(directoryURL: root)
        let created = try repo.add(title: "自定义图片", marker: marker)
        let id = created.items[0].id
        _ = try repo.setCompleted(id: id, completed: true)
        let loaded = try repo.load()
        try require(loaded.items[0].id == id && loaded.items[0].marker == marker && loaded.items[0].isCompleted, "Intent writes preserve image reference and stable task ID")
        var look = TodoAppearance(); look.defaultMarker = marker; look.widget.maximumTitleLines = 1; look.widget.spacing = 40
        try look.validate()
        let store = AppearanceRepository(directory: root); try store.save(look)
        try require(try store.load() == look, "Image markers and expanded spacing persist across repository instances")
        let rows = loaded.items
        look.widget.spacing = 0; look.widget.maximumTitleLines = nil
        let tight = WidgetLayoutMetrics.make(items: rows, appearance: look, family: .large, width: 332, height: 350, fontLineHeight: 20, headerHeight: 28, footerHeight: 15)
        look.widget.spacing = 5
        let normal = WidgetLayoutMetrics.make(items: rows, appearance: look, family: .large, width: 332, height: 350, fontLineHeight: 20, headerHeight: 28, footerHeight: 15)
        try require(tight.rowHeight < normal.rowHeight && tight.lineLimit == 1 && tight.spacing == 0, "Minimum row spacing removes forced second line and all decorative row padding")
        for inset in [0.0, 8, 16, 24] {
            let heading = WidgetHeaderAppearance(text: "今天的计划", fontSize: 24, topInset: inset)
            let layout = WidgetHeaderLayout.make(style: heading, width: 332, maximumHeight: 82.8, measuredTitleWidth: 130, titleLineHeight: 30, measuredSummaryWidth: 64, summaryHeight: 15)
            try require(layout.titleHeight == 30 && layout.titleY + layout.titleHeight <= layout.height && layout.titleY == inset, "Inset reserves full title height before adding top whitespace")
        }
        let black = WallpaperColor(red: 0, green: 0, blue: 0)
        var widget = WidgetAppearance(); widget.theme = .light; widget.backdrop = .solid; widget.panelColor = black
        let background = TextLegibility.widgetBase(widget, dark: false)
        let visible = TextLegibility.readable(black, on: background)
        try require(TextLegibility.contrast(visible, background) >= 7 && visible != black, "A custom black panel cannot hide black text even in system light mode")
        var intentionalAlpha = black; intentionalAlpha.alpha = 0.2
        try require(TextLegibility.readable(intentionalAlpha, on: background).alpha == 0.2, "Contrast protection preserves the user opacity slider")
        let red = WallpaperColor(red: 0.8, green: 0.1, blue: 0.2)
        try require(TextLegibility.readable(red, on: WallpaperColor()) == red, "Adequately contrasting custom colors remain unchanged")
        print("PASS: legacy/image marker data, path validation, image completion policies, Intent preservation, shared appearance, tighter rows, full title inset and light-mode contrast.")
    }
}
