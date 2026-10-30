import Foundation
import CoreFoundation

/// 只负责图片分析结果的读写；可读性设置本身存在 WidgetAppearance 里。
final class AppearanceStore: @unchecked Sendable {
    static let shared = AppearanceStore(requestDirectory: (try? TodoSharedStorage.sharedDirectory())?.appendingPathComponent("AnalysisRequests", isDirectory: true))
    static let requestNotification = "org.todowallpaper.analysis-request-v2"
    private enum Key {
        static let analysisPrefix = "readable.analysis.v2."
        static let legacyPrefix = "readable.analysis."
        static let pendingPrefix = "readable.analysis-request.v2."
        static let contextPrefix = "readable.analysis-context.v2."
    }
    private struct FileEntry: Codable {
        var schemaVersion = 1
        let request: PhotoAnalysisRequest
        let analyses: [String: ImageAnalysis]
    }
    private let defaults: UserDefaults
    private let requestDirectory: URL?
    private var analysisDirectory: URL? { requestDirectory?.deletingLastPathComponent().appendingPathComponent("AnalysisCache", isDirectory: true) }
    // NSLock 只保护短内存访问；原子文件 IO 在锁外执行，主线程只读取已暖缓存。
    private var cache: [String: ImageAnalysis] = [:]
    private var imageVersions: [String: Int] = [:]
    private var memoryRevision = 0
    private let lock = NSLock()
    private let fileLock = NSLock()

    init(defaults: UserDefaults = AppGroup.defaults, requestDirectory: URL? = nil) {
        self.defaults = defaults; self.requestDirectory = requestDirectory
    }
    private func key(_ request: PhotoAnalysisRequest, _ anchor: TextAnchor) -> String {
        Key.analysisPrefix + request.cacheID + "." + anchor.rawValue
    }
    private func entryURL(_ directory: URL, _ request: PhotoAnalysisRequest) -> URL {
        directory.appendingPathComponent(request.cacheID + ".json")
    }
    private func readEntry(_ url: URL) -> FileEntry? {
        guard let data = try? Data(contentsOf: url), let entry = try? JSONDecoder().decode(FileEntry.self, from: data),
              entry.schemaVersion == 1, (try? entry.request.validate()) != nil,
              TextAnchor.allCases.allSatisfy({ anchor in
                  guard let value = entry.analyses[anchor.rawValue] else { return false }
                  return value.meanLuma.isFinite && (0...1).contains(value.meanLuma)
                      && value.contrast.isFinite && (0...1).contains(value.contrast)
              }) else { return nil }
        return entry
    }
    func cachedAnalysis(for request: PhotoAnalysisRequest, anchor: TextAnchor) -> ImageAnalysis? {
        lock.lock(); defer { lock.unlock() }; return cache[key(request, anchor)]
    }
    /// Provider 与后台批次可暖缓存；View.body 必须只调用 cachedAnalysis。
    func analysis(for request: PhotoAnalysisRequest, anchor: TextAnchor) -> ImageAnalysis? {
        guard (try? request.validate()) != nil else { return nil }
        let cacheKey = key(request, anchor)
        lock.lock(); let cached = cache[cacheKey], revision = memoryRevision; lock.unlock()
        if let cached { return cached }
        var loaded: [String: ImageAnalysis] = [:]
        fileLock.lock()
        if let directory = analysisDirectory {
            guard let entry = readEntry(entryURL(directory, request)), entry.request.cacheID == request.cacheID else { fileLock.unlock(); return nil }
            for part in TextAnchor.allCases { loaded[key(request, part)] = entry.analyses[part.rawValue] }
        } else {
            guard let data = defaults.data(forKey: cacheKey), let decoded = try? JSONDecoder().decode(ImageAnalysis.self, from: data) else { fileLock.unlock(); return nil }
            loaded[cacheKey] = decoded
        }
        fileLock.unlock()
        lock.lock(); defer { lock.unlock() }
        guard revision == memoryRevision else { return cache[cacheKey] }
        for (name, value) in loaded { cache[name] = value }
        return cache[cacheKey]
    }
    func contains(_ request: PhotoAnalysisRequest) -> Bool {
        TextAnchor.allCases.allSatisfy { analysis(for: request, anchor: $0) != nil }
    }
    @discardableResult
    func setAnalysis(_ analyses: [TextAnchor: ImageAnalysis], for request: PhotoAnalysisRequest, expectedVersion: Int? = nil) -> Bool {
        guard (try? request.validate()) != nil, TextAnchor.allCases.allSatisfy({ anchor in
            guard let value = analyses[anchor] else { return false }
            return value.meanLuma.isFinite && (0...1).contains(value.meanLuma) && value.contrast.isFinite && (0...1).contains(value.contrast)
        }) else { return false }
        let version = imageVersion(for: request.photoName)
        guard expectedVersion == nil || expectedVersion == version else { return false }
        fileLock.lock(); defer { fileLock.unlock() }
        guard imageVersion(for: request.photoName) == version else { return false }
        var writtenFile: (URL, Data)?
        if let directory = analysisDirectory {
            let entry = FileEntry(request: request, analyses: Dictionary(uniqueKeysWithValues: analyses.map { ($0.key.rawValue, $0.value) }))
            guard let data = try? JSONEncoder().encode(entry) else { return false }
            let url = entryURL(directory, request)
            guard write(data, to: url) else { return false }; writtenFile = (url, data)
        } else {
            for (anchor, analysis) in analyses {
                guard let data = try? JSONEncoder().encode(analysis) else { continue }; defaults.set(data, forKey: key(request, anchor))
            }
            if let data = try? JSONEncoder().encode(request) { defaults.set(data, forKey: Key.contextPrefix + request.cacheID) }
        }
        lock.lock()
        guard imageVersions[request.photoName, default: 0] == version else {
            lock.unlock()
            if let (url, bytes) = writtenFile, (try? Data(contentsOf: url)) == bytes { try? FileManager.default.removeItem(at: url) }
            return false
        }
        memoryRevision += 1
        for anchor in TextAnchor.allCases { cache[key(request, anchor)] = analyses[anchor] }
        lock.unlock()
        removePendingLocked(request)
        return true
    }
    func imageVersion(for imageID: String) -> Int {
        lock.lock(); defer { lock.unlock() }; return imageVersions[imageID, default: 0]
    }
    func clearMemoryCache() { lock.lock(); memoryRevision += 1; cache.removeAll(); lock.unlock() }
    /// 删除图片时同时删除旧键、全部裁剪/底色/比例变体以及待算请求；版本拒绝在途旧结果回写。
    func removeAnalysis(for imageID: String) {
        let prefixes = [Key.analysisPrefix + imageID + ".", Key.legacyPrefix + imageID + ".", Key.pendingPrefix + imageID + ".", Key.contextPrefix + imageID + "."]
        fileLock.lock(); defer { fileLock.unlock() }
        lock.lock(); imageVersions[imageID, default: 0] += 1; memoryRevision += 1
        cache = cache.filter { name, _ in !prefixes.contains(where: name.hasPrefix) }; lock.unlock()
        for name in defaults.dictionaryRepresentation().keys where prefixes.contains(where: name.hasPrefix) { defaults.removeObject(forKey: name) }
        for directory in [analysisDirectory, requestDirectory].compactMap({ $0 }) {
            for url in files(directory) where url.lastPathComponent.hasPrefix(imageID + ".") { try? FileManager.default.removeItem(at: url) }
        }
    }
    /// 只由 Provider 边界登记，原子文件发布成功后通知 App；View.body 不写入或分析。
    func registerMissing(_ request: PhotoAnalysisRequest) {
        guard (try? request.validate()) != nil, !contains(request), let data = try? JSONEncoder().encode(request) else { return }
        fileLock.lock()
        let isNew: Bool
        if let directory = requestDirectory {
            let url = entryURL(directory, request)
            isNew = !FileManager.default.fileExists(atPath: url.path)
            guard write(data, to: url) else { fileLock.unlock(); return }
        } else {
            let name = Key.pendingPrefix + request.cacheID
            isNew = defaults.data(forKey: name) == nil
            defaults.set(data, forKey: name)
        }
        fileLock.unlock()
        if isNew { CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: Self.requestNotification as CFString), nil, nil, true) }
    }
    func pendingRequests() -> [PhotoAnalysisRequest] {
        fileLock.lock(); defer { fileLock.unlock() }
        if let directory = requestDirectory {
            return files(directory).compactMap { url in
                guard let data = try? Data(contentsOf: url), let request = try? JSONDecoder().decode(PhotoAnalysisRequest.self, from: data),
                      (try? request.validate()) != nil else { return nil }; return request
            }
        }
        return defaultRequests(prefix: Key.pendingPrefix)
    }
    func knownRequests() -> [PhotoAnalysisRequest] {
        fileLock.lock(); defer { fileLock.unlock() }
        if let directory = analysisDirectory { return files(directory).compactMap { readEntry($0)?.request } }
        return defaultRequests(prefix: Key.contextPrefix)
    }
    private func defaultRequests(prefix: String) -> [PhotoAnalysisRequest] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }.sorted().compactMap { name in
            guard let data = defaults.data(forKey: name), let request = try? JSONDecoder().decode(PhotoAnalysisRequest.self, from: data),
                  (try? request.validate()) != nil else { return nil }; return request
        }
    }
    func removePending(_ request: PhotoAnalysisRequest) { fileLock.lock(); defer { fileLock.unlock() }; removePendingLocked(request) }
    private func removePendingLocked(_ request: PhotoAnalysisRequest) {
        if let directory = requestDirectory { try? FileManager.default.removeItem(at: entryURL(directory, request)) }
        defaults.removeObject(forKey: Key.pendingPrefix + request.cacheID)
    }
    func cachedPhotoNames() -> Set<String> {
        fileLock.lock(); defer { fileLock.unlock() }
        let candidates = [analysisDirectory, requestDirectory].compactMap { $0 }.flatMap { files($0).map(\.lastPathComponent) }
            + Array(defaults.dictionaryRepresentation().keys)
        return Set(candidates.compactMap { name in
            guard let start = name.range(of: "widget-photo-"), let end = name.range(of: ".jpg", range: start.lowerBound..<name.endIndex) else { return nil }
            let value = String(name[start.lowerBound..<end.upperBound])
            return WidgetPhotoReference.isValid(value) ? value : nil
        })
    }
    func cleanOrphanAnalysis(existing: Set<String>) { for name in cachedPhotoNames().subtracting(existing) { removeAnalysis(for: name) } }
    private func files(_ directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func write(_ data: Data, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
            return true
        } catch { return false }
    }
}

/// App Group 常量集中在这里
enum AppGroup {
    static var identifier: String { TodoSharedStorage.groupID }
    static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// 旧版本把可读性设置存在 UserDefaults，这里做一次性迁移
enum ReadableSettingsMigration {
    private enum Key {
        static let anchor = "readable.anchor"
        static let intensity = "readable.intensity"
        static let scrimOverride = "readable.scrimOverride"
        static let shadowPreset = "readable.shadowPreset"
        static let scrimHeightRatio = "readable.scrimHeightRatio"
    }

    static func take() -> ReadableSettings? {
        let defaults = AppGroup.defaults
        let hasLegacy = defaults.string(forKey: Key.anchor) != nil
            || defaults.string(forKey: Key.intensity) != nil
            || defaults.object(forKey: Key.scrimOverride) != nil
        guard hasLegacy else { return nil }

        var settings = ReadableSettings()
        if let raw = defaults.string(forKey: Key.anchor), let value = TextAnchor(rawValue: raw) { settings.anchor = value }
        if let raw = defaults.string(forKey: Key.intensity), let value = ReadabilityIntensity(rawValue: raw) { settings.intensity = value }
        if let raw = defaults.string(forKey: Key.shadowPreset), let value = ShadowPreset(rawValue: raw) { settings.shadowPreset = value }
        if let value = defaults.object(forKey: Key.scrimOverride) as? Double { settings.scrimOverride = value }
        let ratio = defaults.double(forKey: Key.scrimHeightRatio)
        if ratio > 0 { settings.heightRatio = ratio }

        for key in [Key.anchor, Key.intensity, Key.scrimOverride, Key.shadowPreset, Key.scrimHeightRatio] {
            defaults.removeObject(forKey: key)
        }
        return settings
    }
}
