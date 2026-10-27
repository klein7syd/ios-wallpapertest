import Foundation

/// Only generated relative names may cross into the extension's shared directory.
enum WidgetPhotoReference {
    static func isValid(_ name: String) -> Bool {
        guard name.hasPrefix("widget-photo-"), name.hasSuffix(".jpg") else { return false }
        let token = String(name.dropFirst("widget-photo-".count).dropLast(4))
        return UUID(uuidString: token) != nil
    }
    static func directory(in shared: URL) -> URL { shared.appendingPathComponent("WidgetPhotos", isDirectory: true) }
    static func url(for name: String, in shared: URL) throws -> URL {
        guard isValid(name) else { throw AppearanceError.invalidStyle }
        return directory(in: shared).appendingPathComponent(name)
    }
}
