// Target Membership：仅App。公开os_signpost；基准夹具仅编译入CI Simulator Debug。
import SwiftUI
import UIKit
import os
import QuartzCore
import CoreFoundation
import ImageIO
import UniformTypeIdentifiers

struct EditorModeSample: Codable {
    let page: String
    let target: String
    let phase: String
    let milliseconds: Double
    let longestMainBusyMilliseconds: Double
    let totalMainBusyMilliseconds: Double
    let counters: [String: Int]
    let stages: [String: Double]
    let error: String?
}

@MainActor
final class EditorModePerformance: NSObject {
    static let shared = EditorModePerformance()
    static let log = OSLog(subsystem: "org.todowallpaper.app", category: .pointsOfInterest)
    static let benchmarking = ProcessInfo.processInfo.arguments.contains("--native-mode-performance")
    static var counters: [String: Int] = [:]
    static var stageTimes: [String: Double] = [:]
    static func count(_ name: String) { if benchmarking { counters[name, default: 0] += 1 } }
    static func beginStage(_ name: StaticString) -> (OSSignpostID, Double) {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return (id, CACurrentMediaTime())
    }
    static func endStage(_ name: StaticString, _ value: (OSSignpostID, Double)) {
        os_signpost(.end, log: log, name: name, signpostID: value.0)
        if benchmarking { stageTimes[String(describing: name), default: 0] += (CACurrentMediaTime() - value.1) * 1000 }
    }
    static func toggle(page: AppPage, current: String, set: (String) -> Void) {
        let target = current == "lianxin" ? "todo" : "lianxin"
        shared.begin(page: page, target: target)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        set(target)
    }
    var readiness: ((AppPage, String) -> Bool)?
    var phase = "warm"
    private(set) var samples: [EditorModeSample] = []
    private var page = AppPage.widget
    private var target = "todo"
    private var started: Double?
    private var signpost: OSSignpostID?
    private var displayLink: CADisplayLink?
    private var observer: CFRunLoopObserver?
    private var busyStart: Double?
    private var busySignpost: OSSignpostID?
    private var longestBusy = 0.0
    private var totalBusy = 0.0
    private var presented = false
    private var stableFrames = 0
    private var initialCounters: [String: Int] = [:]
    private var initialStages: [String: Double] = [:]
    private func begin(page: AppPage, target: String) {
        guard Self.benchmarking || os_signpost_enabled(Self.log) else { return }
        if started != nil { finish(error: "superseded") }
        self.page = page; self.target = target; started = CACurrentMediaTime()
        presented = false; stableFrames = 0; longestBusy = 0; totalBusy = 0
        initialCounters = Self.counters; initialCounters["widget_source_decodes"] = WidgetPhotoCache.sourceDecodeCount
        initialStages = Self.stageTimes
        let id = OSSignpostID(log: Self.log); signpost = id
        os_signpost(.begin, log: Self.log, name: "EditorModeSwitch", signpostID: id, "%{public}@ %{public}@", page.rawValue as NSString, target as NSString)
        observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { [weak self] _, activity in
            MainActor.assumeIsolated {
                if activity == .afterWaiting { self?.beginBusy() }
                else if activity == .beforeWaiting { self?.endBusy() }
            }
        }
        if let observer { CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes) }
        beginBusy()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        displayLink = link; link.add(to: .main, forMode: .common)
    }
    func presented(page: AppPage, mode: String) {
        guard started != nil, self.page == page, target == mode else { return }
        presented = true
    }
    private func beginBusy() {
        guard started != nil, busyStart == nil else { return }
        busyStart = CACurrentMediaTime(); let id = OSSignpostID(log: Self.log); busySignpost = id
        os_signpost(.begin, log: Self.log, name: "MainRunLoopBusy", signpostID: id)
    }
    private func endBusy() {
        guard let start = busyStart else { return }
        let duration = (CACurrentMediaTime() - start) * 1000
        longestBusy = max(longestBusy, duration); totalBusy += duration
        if let id = busySignpost { os_signpost(.end, log: Self.log, name: "MainRunLoopBusy", signpostID: id) }
        busyStart = nil; busySignpost = nil
    }
    @objc private func tick() {
        guard let started else { return }
        if CACurrentMediaTime() - started > 8 { finish(error: "editor_ready_timeout"); return }
        if presented && (readiness?(page, target) ?? true) { stableFrames += 1 } else { stableFrames = 0 }
        if stableFrames >= 2 { finish(error: nil) }
    }
    private func finish(error: String?) {
        guard let start = started else { return }
        endBusy()
        let elapsed = (CACurrentMediaTime() - start) * 1000
        if let id = signpost { os_signpost(.end, log: Self.log, name: "EditorModeSwitch", signpostID: id) }
        var counters = Self.counters; counters["widget_source_decodes"] = WidgetPhotoCache.sourceDecodeCount
        for (key, value) in counters { counters[key] = value - (initialCounters[key] ?? 0) }
        var stages = Self.stageTimes
        for (key, value) in stages { stages[key] = value - (initialStages[key] ?? 0) }
        samples.append(EditorModeSample(page: page.rawValue, target: target, phase: phase, milliseconds: elapsed,
            longestMainBusyMilliseconds: longestBusy, totalMainBusyMilliseconds: totalBusy, counters: counters, stages: stages, error: error))
        if samples.count > 128 { samples.removeFirst(samples.count - 128) }
        started = nil; signpost = nil; displayLink?.invalidate(); displayLink = nil
        if let observer { CFRunLoopObserverInvalidate(observer) }; observer = nil
    }
}

#if TODO_UI_CHECKS
enum ModePerformanceFixture {
    static var directory: URL { FileManager.default.temporaryDirectory.appendingPathComponent("native-mode-performance", isDirectory: true) }
    @MainActor static func makeStore() -> TodoStore {
        let repository = TodoRepository(directoryURL: directory)
        if (try? repository.load().items.isEmpty) == true {
            _ = try? repository.add(title: "整理今天的安排")
            _ = try? repository.add(title: "阅读과한국어，记得照顾自己")
            _ = try? repository.add(title: String(String(repeating: "长待办测试，慢慢完成今天的计划。", count: 16).prefix(200)))
        }
        let cache = AppearanceStore(analysisDirectory: directory.appendingPathComponent("AnalysisCache"), requestDirectory: directory.appendingPathComponent("AnalysisRequests"))
        return TodoStore(repository: repository, appearanceRepository: AppearanceRepository(directory: directory), analysisDirectory: directory, analysisCache: cache)
    }
    private static func image(seed: UInt32) throws -> Data {
        let width = 2400, height = 3600
        let bitmap = try WallpaperRenderer.bitmap(width: width, height: height)
        guard let data = bitmap.data else { throw WallpaperError.renderingFailed }
        var random = seed
        for y in 0..<height {
            let row = data.advanced(by: y * bitmap.bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                random = random &* 1664525 &+ 1013904223
                let noise = Int((random >> 24) & 31)
                row[x * 4] = UInt8((x * 175 / width + noise + Int(seed % 40)) % 256)
                row[x * 4 + 1] = UInt8((y * 175 / height + noise + 40) % 256)
                row[x * 4 + 2] = UInt8((x * 40 / width + y * 90 / height + noise + 70) % 256)
                row[x * 4 + 3] = 255
            }
        }
        guard let image = bitmap.makeImage() else { throw WallpaperError.renderingFailed }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else { throw WallpaperError.encodingFailed }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        return encoded as Data
    }
    @MainActor static func run(store: TodoStore, lianxin: LianxinModel, todo: WallpaperEditorModel, heart: WallpaperEditorModel,
                              getMode: @escaping () -> String, setMode: @escaping (String) -> Void, selectPage: @escaping (AppPage) -> Void) async {
        let output = URL.documentsDirectory.appendingPathComponent("mode-performance", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            store.reload(); await lianxin.load(); await lianxin.prepareStyle(store)
            let first = try await Task.detached(priority: .utility) { try image(seed: 7) }.value
            let second = try await Task.detached(priority: .utility) { try image(seed: 61) }.value
            let todoPhoto = try await WidgetPhotoStore.shared.importPhoto(first, sharedDirectory: directory)
            var profile = lianxin.profile
            profile.idolName = "测试成员"; profile.userName = "测试读者"; profile.groupName = "虚构团体"
            profile.message = String(String(repeating: "今天也辛苦啦，中文과한국어。", count: 16).prefix(200))
            profile.translation = String(String(repeating: "오늘도 수고했어요，今天好好休息。", count: 16).prefix(200))
            profile.translationEnabled = true; profile.exampleContent = true
            lianxin.profile = profile
            await lianxin.setPhoto(second)
            var root = store.appearance
            root.widget.backdrop = .photo; root.widget.backgroundPhotoName = todoPhoto; root.widget.backgroundCrop = PhotoCrop()
            try store.saveAppearance(root)
            await todo.start(items: store.items, appearance: store.appearance)
            try await todo.importPhotoData(first)
            let trace = EditorModePerformance.shared
            trace.readiness = { page, mode in
                if page == .widget { return store.hasLoaded && (mode != "lianxin" || lianxin.loaded && store.appearance.lianxin != nil) }
                let model = mode == "lianxin" ? heart : todo
                return model.ready && !model.busy && model.layout != nil
            }
            setMode("todo"); selectPage(.widget)
            try await Task.sleep(for: .seconds(1))
            try Data("ready".utf8).write(to: output.appendingPathComponent("ready"), options: .atomic)
            // Instruments attach后由CI写go，准备图片不计入任何切换数据。
            for _ in 0..<900 {
                if FileManager.default.fileExists(atPath: output.appendingPathComponent("go").path) { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard FileManager.default.fileExists(atPath: output.appendingPathComponent("go").path) else { throw WallpaperError.renderingFailed }
            for page in [AppPage.widget, .wallpaper] {
                selectPage(page); setMode("todo"); try await Task.sleep(for: .milliseconds(700))
                for index in 0..<22 {
                    let previous = trace.samples.count
                    trace.phase = index == 0 ? "cold" : "warm"
                    EditorModePerformance.toggle(page: page, current: getMode(), set: setMode)
                    for _ in 0..<450 {
                        if trace.samples.count > previous { break }
                        try await Task.sleep(for: .milliseconds(20))
                    }
                    guard trace.samples.count == previous + 1, trace.samples.last?.error == nil else { throw WallpaperError.renderingFailed }
                    try await Task.sleep(for: .milliseconds(120))
                }
            }
            struct Report: Encodable {
                let result = "passed"
                let scope = "iOS Simulator Debug, same production mode-button action invoked programmatically, two displayed frames after editor readiness; not physical touch. Main busy intervals are CFRunLoop non-wait wall time, including scheduler effects."
                let photoWidth = 2400, photoHeight = 3600
                let sourceBytes: [Int]
                let samples: [EditorModeSample]
            }
            try JSONEncoder().encode(Report(sourceBytes: [first.count, second.count], samples: trace.samples)).write(to: output.appendingPathComponent("metrics.json"), options: .atomic)
        } catch {
            let report = ["result": "failed", "error": String(describing: error)]
            try? JSONEncoder().encode(report).write(to: output.appendingPathComponent("metrics.json"), options: .atomic)
        }
    }
}
#endif
