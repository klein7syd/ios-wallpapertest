import Foundation
import ImageIO
import UniformTypeIdentifiers

actor WidgetPhotoStore {
    func importMarker(_ data: Data, sharedDirectory: URL? = nil) throws -> String {
        guard data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
        let shared = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        try FileManager.default.createDirectory(at: MarkerImageReference.directory(in: shared), withIntermediateDirectories: true)
        let name = "marker-image-\(UUID().uuidString).png"
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { throw WallpaperError.encodingFailed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        try (output as Data).write(to: MarkerImageReference.url(for: name, in: shared), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return name
    }
    func importPhoto(_ data: Data, sharedDirectory: URL? = nil) throws -> String {
        guard data.count <= 80 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1536,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
        let shared = try sharedDirectory ?? TodoSharedStorage.sharedDirectory()
        let directory = WidgetPhotoReference.directory(in: shared)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "widget-photo-\(UUID().uuidString).jpg"
        let url = try WidgetPhotoReference.url(for: name, in: shared)
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { throw WallpaperError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        try (output as Data).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Retain older references for session undo. No Photos album writes.
        return name
    }
}
