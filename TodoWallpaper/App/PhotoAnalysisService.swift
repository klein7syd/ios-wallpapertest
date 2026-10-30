import Foundation
import CoreGraphics
import ImageIO
import CoreFoundation

// Target Membership：仅 App；macOS 原生分析检查编译同一实现，不引入 UIKit。
struct PhotoAnalysisOutput: Sendable {
    let analyses: [TextAnchor: ImageAnalysis]
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let ranOnMainThread: Bool
}

private final class PhotoAnalysisCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}

actor PhotoAnalysisService {
    static let shared = PhotoAnalysisService()
    private let queue = DispatchQueue(label: "org.todowallpaper.photo-analysis", qos: .utility)

    func removeAnalysis(for names: [String], cache: AppearanceStore) async {
        await withCheckedContinuation { continuation in
            queue.async { names.forEach { cache.removeAnalysis(for: $0) }; continuation.resume() }
        }
    }

    func runBatch(style: WidgetAppearance, systemDark: Bool, invalidating: Bool, directory: URL,
                  cache: AppearanceStore, preferredPhotoName: String? = nil, preferredAspect: Double? = nil,
                  progress: @escaping @Sendable (Bool) -> Void) async throws {
        try Task.checkCancellation()
        let cancellation = PhotoAnalysisCancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                queue.async {
                    do {
                        try Self.batch(style: style, systemDark: systemDark, invalidating: invalidating,
                            directory: directory, cache: cache, preferredPhotoName: preferredPhotoName, preferredAspect: preferredAspect,
                            cancellation: cancellation, progress: progress)
                        continuation.resume()
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    private nonisolated static func batch(style: WidgetAppearance, systemDark: Bool, invalidating: Bool, directory: URL,
                                          cache: AppearanceStore, preferredPhotoName: String?, preferredAspect: Double?, cancellation: PhotoAnalysisCancellation,
                                          progress: @Sendable (Bool) -> Void) throws {
        try cancellation.check()
        var names = style.photoRotation?.enabled == true ? style.photoRotation?.photos ?? [] : []
        if let name = style.backgroundPhotoName, !names.contains(name) { names.append(name) }
        if let today = style.photoName(at: .now) { names.removeAll { $0 == today }; names.insert(today, at: 0) }
        if let preferredPhotoName, let index = names.firstIndex(of: preferredPhotoName), index > 1 {
            names.remove(at: index); names.insert(preferredPhotoName, at: 1)
        }
        var aspects = WidgetPreviewFamily.allCases.map { $0.width / $0.height }
        let known = cache.knownRequests() + cache.pendingRequests()
        for request in known where names.contains(request.photoName) && !aspects.contains(request.canvasAspect) { aspects.append(request.canvasAspect) }
        if let preferredAspect, preferredAspect.isFinite, preferredAspect > 0 {
            aspects.removeAll { $0 == preferredAspect }; aspects.insert(preferredAspect, at: 0)
        }
        if invalidating { for name in names { try cancellation.check(); cache.removeAnalysis(for: name) } }
        let backgrounds = style.theme == .system && style.photoOpacity < 1 ? [systemDark, !systemDark] : [style.isExplicitlyDark ?? systemDark]
        var seen = Set<String>(), changed = false
        for (index, name) in names.enumerated() {
            for aspect in aspects { for dark in backgrounds {
                try cancellation.check()
                let request = style.analysisRequest(photoName: name, canvasAspect: aspect, darkBackground: dark)
                guard seen.insert(request.cacheID).inserted else { continue }
                if cache.contains(request) { cache.removePending(request); continue }
                let version = cache.imageVersion(for: name)
                do {
                    let output = try process(request, directory: directory, cancellation: cancellation)
                    try cancellation.check()
                    let sourceURL = try WidgetPhotoReference.url(for: name, in: directory)
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
                    let saved = cache.setAnalysis(output.analyses, for: request, expectedVersion: version)
                    try cancellation.check()
                    if saved { changed = true; progress(false) }
                } catch is CancellationError { throw CancellationError() }
                catch { continue }
            } }
            // 今天图片与整个批次各请求一次 Widget 刷新，不按 60×比例×底色反复刷新。
            if index == 0 && changed { progress(true); changed = false }
        }
        if changed { progress(true) }
    }

    func analyze(_ request: PhotoAnalysisRequest, directory: URL) async throws -> PhotoAnalysisOutput {
        try Task.checkCancellation()
        let cancellation = PhotoAnalysisCancellation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    do { continuation.resume(returning: try Self.process(request, directory: directory, cancellation: cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
    private nonisolated static func process(_ request: PhotoAnalysisRequest, directory: URL,
                                            cancellation: PhotoAnalysisCancellation) throws -> PhotoAnalysisOutput {
        try cancellation.check(); try request.validate()
        return try autoreleasepool {
            let url = try WidgetPhotoReference.url(for: request.photoName, in: directory)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 128,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary), let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw AppearanceError.unreadable }
            try cancellation.check()
            let side = 32
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw AppearanceError.unreadable }
            let base = request.darkBackground ? 0.09 : 1.0
            context.setFillColor(red: base, green: base, blue: base, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let canvas = CGSize(width: request.canvasAspect, height: 1)
            let frame = request.crop.frame(source: CGSize(width: thumbnail.width, height: thumbnail.height), canvas: canvas)
            context.saveGState()
            context.scaleBy(x: CGFloat(side) / canvas.width, y: CGFloat(side))
            context.setAlpha(request.opacity); context.interpolationQuality = .high
            context.draw(thumbnail, in: CGRect(x: frame.minX, y: 1 - frame.maxY, width: frame.width, height: frame.height))
            context.restoreGState()
            var analyses: [TextAnchor: ImageAnalysis] = [:]
            for anchor in TextAnchor.allCases {
                try cancellation.check()
                let rows: Range<Int>
                switch anchor {
                case .top: rows = 0..<Int(Double(side) * 0.4)
                case .center: rows = Int(Double(side) * 0.3)..<Int(Double(side) * 0.7)
                case .bottom: rows = Int(Double(side) * 0.6)..<side
                }
                var sum = 0.0, squares = 0.0
                for row in rows { for column in 0..<side {
                    let index = (row * side + column) * 4
                    let luma = (0.2126 * Double(pixels[index]) + 0.7152 * Double(pixels[index + 1]) + 0.0722 * Double(pixels[index + 2])) / 255
                    sum += luma; squares += luma * luma
                } }
                let count = Double(rows.count * side), mean = sum / count
                let contrast = min(1, max(0, squares / count - mean * mean).squareRoot() / 0.35)
                analyses[anchor] = ImageAnalysis(meanLuma: mean, contrast: contrast)
            }
            try cancellation.check()
            return PhotoAnalysisOutput(analyses: analyses, thumbnailWidth: thumbnail.width, thumbnailHeight: thumbnail.height,
                ranOnMainThread: Thread.isMainThread)
        }
    }
}

/// 公开 Darwin 通知仅用于提示有原子请求文件；App 启动/前台仍主动补取，避免丢通知。
final class PhotoAnalysisRequestObserver {
    private let callback: @Sendable () -> Void
    init(callback: @escaping @Sendable () -> Void) {
        self.callback = callback
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<PhotoAnalysisRequestObserver>.fromOpaque(observer).takeUnretainedValue().callback()
            }, AppearanceStore.requestNotification as CFString, nil, .deliverImmediately)
    }
    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(rawValue: AppearanceStore.requestNotification as CFString), nil)
    }
}
