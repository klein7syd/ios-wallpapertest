import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Target Membership：仅独立 macOS 原生分析检查；不加入 App 或 Widget target。
@main
enum PhotoAnalysisChecks {
    private struct StoredEnvelope: Codable {
        let schemaVersion: Int
        let request: PhotoAnalysisRequest
        let analyses: [String: ImageAnalysis]
    }
    private final class BatchProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var revisions = 0
        private var reloads: [[PhotoAnalysisRequest]] = []
        private var mainThreadObserved = false
        func record(_ reload: Bool, cache: AppearanceStore) {
            let snapshot = reload ? cache.knownRequests() : []
            lock.lock(); defer { lock.unlock() }
            mainThreadObserved = mainThreadObserved || Thread.isMainThread
            if reload { reloads.append(snapshot) } else { revisions += 1 }
        }
        func snapshot() -> (revisions: Int, reloads: [[PhotoAnalysisRequest]], mainThreadObserved: Bool) {
            lock.lock(); defer { lock.unlock() }
            return (revisions, reloads, mainThreadObserved)
        }
    }
    private actor StartGate {
        private var released = false
        private var continuation: CheckedContinuation<Void, Never>?
        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func release() {
            released = true
            continuation?.resume(); continuation = nil
        }
    }

    /// 直接生成按顶部到下部排列的像素，避免用被测合成代码生成方向参考。
    private static func fixture(directory: URL, width: Int, height: Int,
                                pixel: (Int, Int) -> UInt8) throws -> String {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for row in 0..<height { for column in 0..<width {
            let value = pixel(column, row), offset = (row * width + column) * 4
            bytes[offset] = value; bytes[offset + 1] = value; bytes[offset + 2] = value
        } }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw AppearanceError.unreadable
        }
        let name = "widget-photo-\(UUID().uuidString).jpg"
        let url = try WidgetPhotoReference.url(for: name, in: directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw AppearanceError.unreadable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw AppearanceError.unreadable }
        return name
    }

    private static func mean(_ output: PhotoAnalysisOutput, _ anchor: TextAnchor) throws -> Double {
        guard let value = output.analyses[anchor] else { throw AppearanceError.unreadable }
        return value.meanLuma
    }

    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("photo-analysis-checks-\(UUID())", isDirectory: true)
        let suite = "org.todowallpaper.photo-analysis-checks.\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite), let externalDefaults = UserDefaults(suiteName: suite) else {
            throw AppearanceError.unreadable
        }
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        var checks = 0
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else {
                throw NSError(domain: "PhotoAnalysisChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            checks += 1
        }

        let vertical = try fixture(directory: directory, width: 256, height: 256) { _, row in row < 128 ? 255 : 0 }
        let horizontal = try fixture(directory: directory, width: 512, height: 256) { column, _ in column < 256 ? 255 : 0 }
        let band = try fixture(directory: directory, width: 512, height: 256) { column, _ in (192..<320).contains(column) ? 255 : 0 }
        let black = try fixture(directory: directory, width: 1536, height: 1024) { _, _ in 0 }
        let service = PhotoAnalysisService.shared

        let verticalRequest = PhotoAnalysisRequest(photoName: vertical)
        let direction = try await service.analyze(verticalRequest, directory: directory)
        try require(direction.analyses.count == TextAnchor.allCases.count, "一次实际合成必须产出三个锚点")
        try require(try mean(direction, .top) > 0.95 && mean(direction, .bottom) < 0.05,
                    "独立上白下黑图片的 top/bottom 分析方向不能颠倒")
        let centerMean = try mean(direction, .center)
        try require(centerMean > 0.4 && centerMean < 0.6, "居中锚点包含上下两种亮度")
        try require((direction.analyses[.center]?.contrast ?? -1) > 0.95
                    && (direction.analyses[.top]?.contrast ?? 1) < 0.1 && (direction.analyses[.bottom]?.contrast ?? 1) < 0.1,
                    "中心黑白交界有高对比度，纯色顶部和底部保持低对比度")

        let left = try await service.analyze(PhotoAnalysisRequest(photoName: horizontal, crop: PhotoCrop(panX: 1)), directory: directory)
        let right = try await service.analyze(PhotoAnalysisRequest(photoName: horizontal, crop: PhotoCrop(panX: -1)), directory: directory)
        try require(try mean(left, .center) > 0.95 && mean(right, .center) < 0.05,
                    "横向裁剪须与实际照片一致：正 panX 显示左侧，负 panX 显示右侧")
        let zoomTop = try await service.analyze(PhotoAnalysisRequest(photoName: vertical, crop: PhotoCrop(zoom: 2, panY: 1)), directory: directory)
        let zoomBottom = try await service.analyze(PhotoAnalysisRequest(photoName: vertical, crop: PhotoCrop(zoom: 2, panY: -1)), directory: directory)
        try require(try mean(zoomTop, .center) > 0.95 && mean(zoomBottom, .center) < 0.05,
                    "放大后纵向裁剪须与顶部原点坐标一致")

        let square = try await service.analyze(PhotoAnalysisRequest(photoName: band, canvasAspect: 1), directory: directory)
        let wide = try await service.analyze(PhotoAnalysisRequest(photoName: band, canvasAspect: 2), directory: directory)
        let squareMean = try mean(square, .center), wideMean = try mean(wide, .center)
        try require(abs(squareMean - 0.5) < 0.06 && abs(wideMean - 0.25) < 0.06 && squareMean - wideMean > 0.18,
                    "真实宽高比必须先参与裁剪，不能把所有 Widget 都当作方形分析")

        let transparentLight = try await service.analyze(PhotoAnalysisRequest(photoName: black, opacity: 0), directory: directory)
        let transparentDark = try await service.analyze(PhotoAnalysisRequest(photoName: black, opacity: 0, darkBackground: true), directory: directory)
        let halfLight = try await service.analyze(PhotoAnalysisRequest(photoName: black, opacity: 0.5), directory: directory)
        let halfDark = try await service.analyze(PhotoAnalysisRequest(photoName: black, opacity: 0.5, darkBackground: true), directory: directory)
        try require(abs(try mean(transparentLight, .center) - 1) < 0.01 && abs(try mean(transparentDark, .center) - 0.09) < 0.015,
                    "透明照片必须分别显露实际白色和 0.09 深色底色")
        try require(abs(try mean(halfLight, .center) - 0.5) < 0.025 && abs(try mean(halfDark, .center) - 0.045) < 0.015,
                    "不透明度必须在采样前与当前底色复合")
        try require(max(halfLight.thumbnailWidth, halfLight.thumbnailHeight) <= 128
                    && min(halfLight.thumbnailWidth, halfLight.thumbnailHeight) > 0,
                    "已落盘 1536px 图片的解码结果最长边不能超过 128px")
        for result in [direction, left, right, zoomTop, zoomBottom, square, wide, transparentLight, transparentDark, halfLight, halfDark] {
            try require(!result.ranOnMainThread, "从 MainActor 提交的实际解码、合成与采样必须在后台执行")
            try require(result.analyses.values.allSatisfy { $0.meanLuma.isFinite && $0.contrast.isFinite && (0...1).contains($0.meanLuma) && (0...1).contains($0.contrast) },
                        "所有锚点输出有限且归一化的原始亮度与对比度")
        }

        let opaqueLight = PhotoAnalysisRequest(photoName: band, darkBackground: false)
        let opaqueDark = PhotoAnalysisRequest(photoName: band, darkBackground: true)
        try require(opaqueLight.cacheID == opaqueDark.cacheID && opaqueLight == opaqueDark,
                    "完全不透明的照片在深浅主题下共用规范化请求及缓存")
        let variants = [opaqueLight,
            PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 2)),
            PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(panX: 1)),
            PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(panY: 1)),
            PhotoAnalysisRequest(photoName: band, opacity: 0.5),
            PhotoAnalysisRequest(photoName: band, opacity: 0.5, darkBackground: true),
            PhotoAnalysisRequest(photoName: band, canvasAspect: 2),
            PhotoAnalysisRequest(photoName: vertical)]
        try require(Set(variants.map(\.cacheID)).count == variants.count, "照片名、全部裁剪参数、透明度、有效底色和实际比例都必须进入缓存键")
        try require(PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(panX: -0.0)).cacheID == opaqueLight.cacheID,
                    "等价的正负零参数不能制造重复缓存")
        let roundtrip = try JSONDecoder().decode(PhotoAnalysisRequest.self, from: JSONEncoder().encode(variants[5]))
        try require(roundtrip == variants[5] && roundtrip.cacheID == variants[5].cacheID, "待算请求序列化后保持所有有效上下文")
        for invalid in [PhotoAnalysisRequest(photoName: "../outside.jpg"),
                        PhotoAnalysisRequest(photoName: band, opacity: .nan),
                        PhotoAnalysisRequest(photoName: band, canvasAspect: 0)] {
            var rejected = false
            do { try invalid.validate() } catch AppearanceError.invalidStyle { rejected = true }
            try require(rejected, "路径穿越、非有限透明度和非法画布比例必须被请求校验拒绝")
        }
        let legacy = try JSONDecoder().decode(ImageAnalysis.self, from: JSONSerialization.data(withJSONObject:
            ["meanLuma": 0.2, "contrast": 0.3, "suggestedScrim": 0.8]))
        let legacyEncoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]
        try require(legacy.meanLuma == 0.2 && legacy.contrast == 0.3 && legacyEncoded?["suggestedScrim"] == nil,
                    "旧分析值可以解码，但新的缓存不能写回绑定旧文字颜色的建议值")

        let cache = AppearanceStore(defaults: defaults), external = AppearanceStore(defaults: externalDefaults)
        defaults.set(try JSONEncoder().encode(legacy), forKey: "readable.analysis.\(band).top")
        let absentAnalysis = cache.analysis(for: opaqueLight, anchor: .top)
        try require(absentAnalysis == nil && ReadableSettings().autoScrim(analysis: absentAnalysis) == 0.4,
                    "缺少裁剪、底色和比例信息的旧缓存不能冒充当前画面的分析")
        let first = Dictionary(uniqueKeysWithValues: TextAnchor.allCases.map { ($0, ImageAnalysis(meanLuma: 0.1, contrast: 0.2)) })
        let second = Dictionary(uniqueKeysWithValues: TextAnchor.allCases.map { ($0, ImageAnalysis(meanLuma: 0.8, contrast: 0.3)) })
        cache.setAnalysis(first, for: opaqueLight)
        try require(cache.analysis(for: opaqueLight, anchor: .center)?.meanLuma == 0.1, "缓存写入后读取对应请求")
        cache.setAnalysis(second, for: opaqueLight)
        try require(cache.analysis(for: opaqueLight, anchor: .center)?.meanLuma == 0.8, "本进程写入必须同步使旧内存分析失效")
        external.setAnalysis(first, for: opaqueLight)
        cache.clearMemoryCache()
        try require(cache.analysis(for: opaqueLight, anchor: .center)?.meanLuma == 0.1,
                    "Provider 边界清空内存后必须能读到外部更新")
        for variant in variants where variant.photoName == band { cache.setAnalysis(first, for: variant) }
        let missing = PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 3, panX: 0.4), opacity: 0.7, canvasAspect: 1.923)
        cache.registerMissing(missing); cache.registerMissing(missing)
        try require(cache.pendingRequests().filter { $0.cacheID == missing.cacheID }.count == 1,
                    "实际比例缺失只登记去重请求，不在 Widget 同步分析")
        cache.setAnalysis(second, for: missing)
        try require(!cache.pendingRequests().contains(where: { $0.cacheID == missing.cacheID }), "补算完成后删除对应待算记录")
        let pending = PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 4), canvasAspect: 1.71)
        cache.registerMissing(pending)
        let other = PhotoAnalysisRequest(photoName: vertical)
        cache.setAnalysis(second, for: other)
        cache.removeAnalysis(for: band)
        try require(variants.filter { $0.photoName == band }.allSatisfy { request in TextAnchor.allCases.allSatisfy { cache.analysis(for: request, anchor: $0) == nil } }
                    && cache.analysis(for: missing, anchor: .center) == nil,
                    "移除照片必须删除所有裁剪、明暗和实际比例的内存及持久化分析")
        try require(!cache.pendingRequests().contains(where: { $0.photoName == band }) && !cache.knownRequests().contains(where: { $0.photoName == band })
                    && defaults.object(forKey: "readable.analysis.\(band).top") == nil,
                    "移除照片同时清理旧键、待算记录和全部上下文元数据")
        try require(cache.analysis(for: other, anchor: .center)?.meanLuma == 0.8, "删除一个图片的分析不能影响其他图片")

        // 真实跨进程通道使用每请求独立的原子文件；下面两实例共用实际目录，而非 Defaults 替身。
        let requestDirectory = directory.appendingPathComponent("SharedAnalysis/AnalysisRequests", isDirectory: true)
        let analysisDirectory = requestDirectory.deletingLastPathComponent().appendingPathComponent("AnalysisCache", isDirectory: true)
        let fileCache = AppearanceStore(defaults: defaults, requestDirectory: requestDirectory)
        let fileExternal = AppearanceStore(defaults: externalDefaults, requestDirectory: requestDirectory)
        let resultURL = analysisDirectory.appendingPathComponent(opaqueLight.cacheID + ".json")
        try require(fileCache.setAnalysis(first, for: opaqueLight), "生产文件后端成功原子写入完整分析")
        let storedEnvelope = try JSONDecoder().decode(StoredEnvelope.self, from: Data(contentsOf: resultURL))
        try require(storedEnvelope.schemaVersion == 1 && storedEnvelope.request == opaqueLight
                    && Set(storedEnvelope.analyses.keys) == Set(TextAnchor.allCases.map(\.rawValue)),
                    "单文件封套绑定完整请求、版本和三个锚点，不能只发布部分分析")
        try require(fileCache.analysis(for: opaqueLight, anchor: .center)?.meanLuma == 0.1,
                    "实际文件后端可以暖入当前进程缓存")
        try require(fileExternal.setAnalysis(second, for: opaqueLight), "另一实例原子更新同一结果文件")
        fileCache.clearMemoryCache()
        try require(fileCache.analysis(for: opaqueLight, anchor: .center)?.meanLuma == 0.8,
                    "真实文件目录中的外部更新在 Provider clearMemoryCache 后可见")
        try require(fileCache.cachedAnalysis(for: opaqueLight, anchor: .top)?.meanLuma == 0.8
                    && fileCache.cachedAnalysis(for: opaqueLight, anchor: .bottom)?.meanLuma == 0.8,
                    "读取一次完整封套即暖入全部锚点，后续 body 仅访问内存")

        let corruptRequest = PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 1.5), canvasAspect: 1.88)
        let corruptURL = analysisDirectory.appendingPathComponent(corruptRequest.cacheID + ".json")
        let corruptBytes = Data("not-json".utf8)
        try corruptBytes.write(to: corruptURL, options: .atomic)
        try require(fileCache.analysis(for: corruptRequest, anchor: .center) == nil,
                    "损坏封套安全回退缺失，不向正文返回部分或旧数据")
        try require(try Data(contentsOf: corruptURL) == corruptBytes, "读取损坏缓存不删除原始证据")
        let rawAnalyses = Dictionary(uniqueKeysWithValues: first.map { ($0.key.rawValue, $0.value) })
        let futureEnvelope = StoredEnvelope(schemaVersion: 99, request: corruptRequest, analyses: rawAnalyses)
        let futureAnalysisBytes = try JSONEncoder().encode(futureEnvelope)
        try futureAnalysisBytes.write(to: corruptURL, options: .atomic)
        fileCache.clearMemoryCache()
        try require(fileCache.analysis(for: corruptRequest, anchor: .center) == nil
                    && ReadableSettings().autoScrim(analysis: fileCache.cachedAnalysis(for: corruptRequest, anchor: .center)) == 0.4,
                    "未来版本分析封套不能绕过版本门禁，仍使用安全自动回退")
        try require(try Data(contentsOf: corruptURL) == futureAnalysisBytes, "读取未来版本缓存不能覆盖文件")
        let wrongContext = StoredEnvelope(schemaVersion: 1, request: opaqueLight, analyses: rawAnalyses)
        try JSONEncoder().encode(wrongContext).write(to: corruptURL, options: .atomic)
        fileCache.clearMemoryCache()
        try require(fileCache.analysis(for: corruptRequest, anchor: .center) == nil,
                    "文件名与封套请求不匹配时不能复用另一裁剪或比例的结果")
        let invalidAnalyses = Dictionary(uniqueKeysWithValues: TextAnchor.allCases.map { ($0.rawValue, ImageAnalysis(meanLuma: 1.5, contrast: 0.2)) })
        try JSONEncoder().encode(StoredEnvelope(schemaVersion: 1, request: corruptRequest, analyses: invalidAnalyses))
            .write(to: corruptURL, options: .atomic)
        fileCache.clearMemoryCache()
        try require(fileCache.analysis(for: corruptRequest, anchor: .top) == nil,
                    "封套里的越界原始值不能污染运行时蒙层计算")

        for variant in variants where variant.photoName == band {
            try require(fileCache.setAnalysis(first, for: variant), "文件后端保存独立上下文变体")
        }
        let pendingA = PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 3), canvasAspect: 1.7)
        let pendingB = PhotoAnalysisRequest(photoName: band, crop: PhotoCrop(zoom: 4), canvasAspect: 2.2)
        fileCache.registerMissing(pendingA); fileExternal.registerMissing(pendingB)
        try require(Set(fileCache.pendingRequests().map(\.cacheID)).isSuperset(of: [pendingA.cacheID, pendingB.cacheID]),
                    "两个实例登记不同实际比例请求时使用独立文件，不相互覆盖")
        try require(FileManager.default.fileExists(atPath: requestDirectory.appendingPathComponent(pendingA.cacheID + ".json").path),
                    "Provider 缺失登记确实写入 App 可见的请求文件")
        defaults.set(try JSONEncoder().encode(legacy), forKey: "readable.analysis.\(band).top")
        try require(fileCache.setAnalysis(second, for: other), "其他图片也可在同一文件后端独立缓存")
        let versionBeforeRemoval = fileCache.imageVersion(for: band)
        fileCache.removeAnalysis(for: band)
        fileExternal.clearMemoryCache()
        let remainingResults = (try? FileManager.default.contentsOfDirectory(at: analysisDirectory, includingPropertiesForKeys: nil)) ?? []
        let remainingPending = (try? FileManager.default.contentsOfDirectory(at: requestDirectory, includingPropertiesForKeys: nil)) ?? []
        try require(!remainingResults.contains(where: { $0.lastPathComponent.hasPrefix(band + ".") })
                    && !remainingPending.contains(where: { $0.lastPathComponent.hasPrefix(band + ".") })
                    && !fileCache.knownRequests().contains(where: { $0.photoName == band })
                    && !fileCache.pendingRequests().contains(where: { $0.photoName == band }),
                    "移除照片清理实际目录中的全部结果变体、上下文与待算文件")
        try require(defaults.object(forKey: "readable.analysis.\(band).top") == nil
                    && fileExternal.analysis(for: opaqueLight, anchor: .top) == nil
                    && fileExternal.analysis(for: other, anchor: .center)?.meanLuma == 0.8,
                    "真实删除也清理旧 Defaults，且不影响另一图片的结果")
        try require(!fileCache.setAnalysis(first, for: opaqueLight, expectedVersion: versionBeforeRemoval)
                    && !FileManager.default.fileExists(atPath: resultURL.path),
                    "图片移除后，持有旧 imageVersion 的在途结果不能复活分析文件")
        let currentVersion = fileCache.imageVersion(for: band)
        try require(currentVersion > versionBeforeRemoval
                    && fileCache.setAnalysis(first, for: opaqueLight, expectedVersion: currentVersion),
                    "新的有效请求可使用当前版本写入，旧任务拒绝不锁死后续分析")
        fileCache.registerMissing(pendingA)
        fileCache.cleanOrphanAnalysis(existing: [vertical])
        try require(fileCache.cachedPhotoNames() == [vertical]
                    && fileCache.analysis(for: opaqueLight, anchor: .center) == nil
                    && !fileCache.pendingRequests().contains(where: { $0.photoName == band }),
                    "孤立分析清理接口同时清理结果与请求，只保留提供的现存图片集合")

        let batchRequestDirectory = directory.appendingPathComponent("BatchAnalysis/AnalysisRequests", isDirectory: true)
        let batchCache = AppearanceStore(defaults: defaults, requestDirectory: batchRequestDirectory)
        var albumStyle = WidgetAppearance()
        let now = Date(), yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86_400)
        albumStyle.backdrop = .photo; albumStyle.backgroundPhotoName = horizontal
        albumStyle.photoRotation = WidgetAlbumRotation(title: "今日优先原生检查", photos: [horizontal, vertical], anchor: yesterday)
        albumStyle.backgroundPhotoOpacity = 0.5
        let actualAspect = 1.83
        let actualRequest = albumStyle.analysisRequest(photoName: horizontal, canvasAspect: actualAspect, darkBackground: false)
        batchCache.registerMissing(actualRequest)
        let batchProgress = BatchProgress()
        try await service.runBatch(style: albumStyle, systemDark: false, invalidating: false,
            directory: directory, cache: batchCache) { batchProgress.record($0, cache: batchCache) }
        let firstBatchEvents = batchProgress.snapshot()
        let expectedAspects = Set(WidgetPreviewFamily.allCases.map { $0.width / $0.height } + [actualAspect])
        let firstBatchRequests = batchCache.knownRequests()
        try require(firstBatchEvents.revisions == 2 * 2 * expectedAspects.count && firstBatchEvents.reloads.count == 2,
                    "相册所有图片、三种预览和实际比例以及有效深浅底色都串行分析，Widget 刷新只合并两次")
        try require(firstBatchEvents.reloads.first?.allSatisfy({ $0.photoName == vertical }) == true
                    && firstBatchEvents.reloads.first?.count == 2 * expectedAspects.count,
                    "今日图片即使不是相册第一张，也必须先完成全部变体并通知刷新")
        try require(!firstBatchEvents.mainThreadObserved && firstBatchRequests.count == 2 * 2 * expectedAspects.count
                    && batchCache.pendingRequests().isEmpty,
                    "批次分析与结果发布在后台完成，并消费 Widget 真实比例缺失请求")
        let oldCropRequest = albumStyle.analysisRequest(photoName: horizontal, canvasAspect: actualAspect, darkBackground: false)
        albumStyle.backgroundCrop = PhotoCrop(zoom: 2, panX: 1)
        let cropProgress = BatchProgress()
        try await service.runBatch(style: albumStyle, systemDark: false, invalidating: true,
            directory: directory, cache: batchCache) { cropProgress.record($0, cache: batchCache) }
        let changedBatchRequests = batchCache.knownRequests()
        try require(changedBatchRequests.count == 2 * 2 * expectedAspects.count
                    && changedBatchRequests.allSatisfy { $0.crop == albumStyle.photoCrop }
                    && batchCache.analysis(for: oldCropRequest, anchor: .center) == nil,
                    "相册裁剪改变后两张图的全部旧上下文都失效，不能只重算当前照片")
        try require([horizontal, vertical].allSatisfy { name in
            changedBatchRequests.contains { $0.photoName == name && $0.canvasAspect == actualAspect }
        }, "重算须保留并重新计算先前由 Widget 登记的真实画布比例")
        let newCropRequest = albumStyle.analysisRequest(photoName: horizontal, canvasAspect: actualAspect, darkBackground: false)
        try require((batchCache.analysis(for: newCropRequest, anchor: .center)?.meanLuma ?? -1) > 0.95,
                    "批次新结果确实应用放大与向左图像内容移动的裁剪，而非只更换缓存键")
        albumStyle.backgroundPhotoOpacity = 1
        let opaqueProgress = BatchProgress()
        try await service.runBatch(style: albumStyle, systemDark: true, invalidating: true,
            directory: directory, cache: batchCache) { opaqueProgress.record($0, cache: batchCache) }
        let opaqueBatchRequests = batchCache.knownRequests()
        try require(opaqueProgress.snapshot().revisions == 2 * expectedAspects.count
                    && opaqueBatchRequests.count == 2 * expectedAspects.count
                    && opaqueBatchRequests.allSatisfy { $0.opacity == 1 && !$0.darkBackground }
                    && batchCache.analysis(for: newCropRequest, anchor: .center) == nil,
                    "相册透明度改变使全部旧变体失效，完全不透明时两种底色合并为一份结果")

        let batchGate = StartGate(), cancelledProgress = BatchProgress()
        let preservedBatchIDs = Set(opaqueBatchRequests.map(\.cacheID))
        let cancelledBatchStyle = albumStyle
        let cancelledBatch = Task {
            await batchGate.wait()
            try await service.runBatch(style: cancelledBatchStyle, systemDark: false, invalidating: true,
                directory: directory, cache: batchCache) { cancelledProgress.record($0, cache: batchCache) }
        }
        cancelledBatch.cancel(); await batchGate.release()
        var batchCancellationObserved = false
        do { try await cancelledBatch.value } catch is CancellationError { batchCancellationObserved = true }
        try require(batchCancellationObserved && cancelledProgress.snapshot().revisions == 0
                    && Set(batchCache.knownRequests().map(\.cacheID)) == preservedBatchIDs,
                    "已取消批次不能先清理有效缓存、发布结果或请求 Widget 刷新")

        let gate = StartGate()
        let cancelled = Task {
            await gate.wait()
            return try await service.analyze(verticalRequest, directory: directory)
        }
        cancelled.cancel(); await gate.release()
        var cancellationObserved = false
        do { _ = try await cancelled.value } catch is CancellationError { cancellationObserved = true }
        try require(cancellationObserved, "取消的任务进入生产服务后必须抛 CancellationError，不能返回旧画面结果")
        let afterCancellation = try await service.analyze(verticalRequest, directory: directory)
        try require(try mean(afterCancellation, .top) > 0.95 && !afterCancellation.ranOnMainThread, "取消一个任务不能阻断后续后台串行分析")
        print("PASS: \(checks) 原生图片分析检查：ImageIO 128px、三锚点、裁剪/透明度/底色/比例、串行相册今日优先、批次取消、原子文件封套、版本保护与缓存失效。")
    }
}
