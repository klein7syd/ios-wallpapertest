import Foundation
import CoreGraphics

struct PhotoCrop: Codable, Equatable, Sendable {
    var zoom: Double = 1
    var panX: Double = 0
    var panY: Double = 0
    func validate() throws {
        guard zoom.isFinite, panX.isFinite, panY.isFinite,
              (1...4).contains(zoom), (-1...1).contains(panX), (-1...1).contains(panY) else { throw AppearanceError.invalidStyle }
    }
    func frame(source: CGSize, canvas: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return .zero }
        let scale = max(canvas.width / source.width, canvas.height / source.height) * zoom
        let width = source.width * scale, height = source.height * scale
        return CGRect(x: (canvas.width - width) / 2 + panX * (width - canvas.width) / 2,
                      y: (canvas.height - height) / 2 + panY * (height - canvas.height) / 2,
                      width: width, height: height)
    }
    mutating func pan(by translation: CGSize, source: CGSize, canvas: CGSize) {
        let rect = frame(source: source, canvas: canvas)
        if rect.width > canvas.width + 0.01 { panX = min(1, max(-1, panX + 2 * translation.width / (rect.width - canvas.width))) }
        if rect.height > canvas.height + 0.01 { panY = min(1, max(-1, panY + 2 * translation.height / (rect.height - canvas.height))) }
    }
}
struct WidgetAlbumRotation: Codable, Equatable, Sendable {
    var title: String
    var photos: [String]
    var anchor: Date
    var enabled = true
    func validate() throws {
        guard title.count <= 100, !photos.isEmpty, photos.count <= 60,
              Set(photos).count == photos.count, photos.allSatisfy(WidgetPhotoReference.isValid),
              anchor.timeIntervalSince1970.isFinite else { throw AppearanceError.invalidStyle }
    }
    func photo(at date: Date, calendar: Calendar = .current) -> String? {
        guard !photos.isEmpty else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor), to: calendar.startOfDay(for: date)).day ?? 0
        return photos[((days % photos.count) + photos.count) % photos.count]
    }
}
extension WidgetAppearance {
    var photoCrop: PhotoCrop { backgroundCrop ?? PhotoCrop() }
    var photoOpacity: Double { backgroundPhotoOpacity ?? 1 }
    var materialEnabled: Bool { systemMaterial ?? false }
    var footerVisible: Bool { showsFooter ?? true }
    func photoName(at date: Date = .now) -> String? {
        if let album = photoRotation, album.enabled { return album.photo(at: date) }
        return backgroundPhotoName
    }
    var isExplicitlyDark: Bool? { theme == .system ? nil : theme == .dark }
}

enum WidgetDayTimeline {
    static func dates(now: Date, count: Int = 8, calendar: Calendar = .current) -> [Date] {
        [now] + (1..<max(1, count)).compactMap { calendar.date(byAdding: .day, value: $0, to: calendar.startOfDay(for: now)) }
    }
}
