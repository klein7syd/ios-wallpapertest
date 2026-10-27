import Foundation
import CoreGraphics
import ImageIO

/// Only locally generated names cross process boundaries. Source Photos IDs,
/// absolute paths, metadata and user-provided filenames are never persisted here.
enum MarkerImageReference {
    private static let cache = NSCache<NSString, CGImage>()
    static func isValid(_ name: String) -> Bool {
        guard name.hasPrefix("marker-image-"), name.hasSuffix(".png") else { return false }
        return UUID(uuidString: String(name.dropFirst(13).dropLast(4))) != nil
    }
    static func directory(in shared: URL) -> URL { shared.appendingPathComponent("MarkerImages", isDirectory: true) }
    static func url(for name: String, in shared: URL) throws -> URL {
        guard isValid(name) else { throw AppearanceError.invalidStyle }
        return directory(in: shared).appendingPathComponent(name)
    }
    static func image(named name: String?, sharedDirectory: URL? = nil) -> CGImage? {
        guard let name, isValid(name), let shared = sharedDirectory ?? (try? TodoSharedStorage.sharedDirectory()),
              let url = try? url(for: name, in: shared) else { return nil }
        if let image = cache.object(forKey: url.path as NSString) { return image }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        cache.totalCostLimit = 4 * 1024 * 1024
        cache.setObject(image, forKey: url.path as NSString, cost: image.bytesPerRow * image.height)
        return image
    }
}
