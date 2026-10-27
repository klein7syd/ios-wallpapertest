import Foundation
import CoreGraphics

enum MediaInteractionChecks {
    static func run() throws {
        func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
            if try !value() { throw NSError(domain: "MediaInteractionChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        for size in [CGSize(width: 170, height: 170), CGSize(width: 364, height: 170), CGSize(width: 364, height: 382)] {
            for zoom in [1.0, 1.4, 4] { for x in [-1.0, 0, 1] { for y in [-1.0, 0, 1] {
                let crop = PhotoCrop(zoom: zoom, panX: x, panY: y)
                try crop.validate()
                let rect = crop.frame(source: CGSize(width: 1200, height: 1800), canvas: size)
                try require(rect.minX <= 0.001 && rect.minY <= 0.001 && rect.maxX >= size.width - 0.001 && rect.maxY >= size.height - 0.001,
                    "Crop covers the Widget canvas without stretching or empty edges")
                try require(abs(rect.width / rect.height - 2 / 3) < 0.00001, "Photo aspect is preserved")
                let large = crop.frame(source: CGSize(width: 1200, height: 1800), canvas: CGSize(width: size.width * 3, height: size.height * 3))
                try require(abs(large.minX - rect.minX * 3) < 0.001 && abs(large.width - rect.width * 3) < 0.001,
                    "Preview and actual Widget crop are coordinate invariant")
            } } }
        }
        var moved = PhotoCrop(zoom: 2)
        moved.pan(by: CGSize(width: 50_000, height: -50_000), source: CGSize(width: 1200, height: 1800), canvas: CGSize(width: 170, height: 170))
        try require(moved.panX == 1 && moved.panY == -1, "Direct gesture clamps to real image edges")
        for height in [250.0, 400, 680, 850] {
            let normal = EditorSizing.wallpaperInspectorHeight(available: height, expanded: true, advanced: true, previewScale: 1)
            let small = EditorSizing.wallpaperInspectorHeight(available: height, expanded: true, advanced: true, previewScale: 0.55)
            try require(small >= normal && small <= height - 109.9, "Smaller preview allocates real height to controls")
            if height >= 400 { try require(small > normal + 20, "Freed canvas area becomes settings area") }
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 15))!
        let names = (0..<3).map { _ in "widget-photo-\(UUID().uuidString).jpg" }
        let album = WidgetAlbumRotation(title: "Fixture album", photos: names, anchor: anchor)
        try album.validate()
        let dates = WidgetDayTimeline.dates(now: anchor, count: 8, calendar: calendar)
        try require(dates.count == 8 && dates[0] == anchor, "Timeline includes now and seven future local midnights")
        for (index, date) in dates.enumerated() {
            try require(album.photo(at: date, calendar: calendar) == names[index % 3], "Album rotates once per local calendar day including DST")
            if index > 0 { try require(calendar.component(.hour, from: date) == 0, "Rotation boundary is local midnight, not 24-hour offsets") }
        }
        try require(dates[2].timeIntervalSince(dates[1]) == 23 * 3600, "DST day stays a day despite 23 hours")
        var style = WidgetAppearance(); style.photoRotation = album; style.backgroundCrop = moved
        style.backgroundPhotoOpacity = 0.4; style.systemMaterial = true; style.showsFooter = false
        try style.validate()
        let decoded = try JSONDecoder().decode(WidgetAppearance.self, from: JSONEncoder().encode(style))
        try require(decoded == style && decoded.photoName(at: anchor) != nil, "Crop/opacity/album/material/footer persist together")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetAppearance())) as! [String: Any]
        for key in ["backgroundCrop","backgroundPhotoOpacity","photoRotation","systemMaterial","showsFooter"] { json.removeValue(forKey: key) }
        let legacyStyle = try JSONDecoder().decode(WidgetAppearance.self, from: JSONSerialization.data(withJSONObject: json))
        try require(legacyStyle.photoCrop == PhotoCrop() && legacyStyle.photoOpacity == 1 && !legacyStyle.materialEnabled && legacyStyle.footerVisible,
            "0.4.4 styles keep their old appearance")
        var look = TodoAppearance(); look.widget = style
        let item = TodoItem(id: UUID(), title: "旧待办", isCompleted: false, createdAt: Date(timeIntervalSince1970: 1_700_000_000), updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let withFooter = WidgetLayoutMetrics.make(items: [item], appearance: TodoAppearance(), family: .medium, width: 332, height: 138,
            fontLineHeight: 20, headerHeight: 24, footerHeight: 15)
        let without = WidgetLayoutMetrics.make(items: [item], appearance: look, family: .medium, width: 332, height: 138,
            fontLineHeight: 20, headerHeight: 24, footerHeight: 15)
        try require(withFooter.showsFooter && !without.showsFooter && without.footerHeight == 0, "Footer switch frees actual layout height")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("media-schedule-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = TodoRepository(directoryURL: root)
        _ = try repo.importItems([item])
        let scheduled = TodoSchedule(date: anchor, includesTime: true, timeZone: calendar.timeZone)
        try scheduled.validate()
        _ = try repo.saveTask(id: item.id, title: item.title, marker: TodoMarker(kind: .emoji, emoji: "❤️"), schedule: scheduled)
        _ = try repo.setCompleted(id: item.id, completed: true)
        _ = try repo.rename(id: item.id, title: "改标题保留日期")
        _ = try repo.edit(id: item.id, title: "改标记保留日期", marker: nil)
        var loaded = try repo.load().items[0]
        try require(loaded.id == item.id && loaded.schedule == scheduled && loaded.isCompleted, "Completion/title/marker operations preserve scheduled task identity and date")
        _ = try repo.saveTask(id: item.id, title: loaded.title, marker: loaded.marker, schedule: nil)
        loaded = try repo.load().items[0]
        try require(loaded.schedule == nil && loaded.id == item.id && loaded.isCompleted, "Turning date off restores an undated task without resetting state")
        let dateOnly = TodoSchedule(date: anchor, includesTime: false, timeZone: calendar.timeZone)
        try require(!dateOnly.includesTime && dateOnly.hour == nil && dateOnly.day == 7, "Date-only selection is distinct from a timed task")
        var oldItemJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
        oldItemJSON.removeValue(forKey: "schedule")
        let oldItem = try JSONDecoder().decode(TodoItem.self, from: JSONSerialization.data(withJSONObject: oldItemJSON))
        try require(oldItem.schedule == nil && oldItem.id == item.id, "Old task and old backup decoding remains compatible")
        print("PASS: all-family photo crops, real preview/inspector allocation, calendar-day/DST rotation, additive style/task fields, footer height and date CRUD/Intent-field preservation.")
    }
}
