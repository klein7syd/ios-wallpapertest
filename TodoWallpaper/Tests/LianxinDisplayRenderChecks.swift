// Target Membership：独立macOS原生检查；生产CoreText/CG布局与可导出判定。
import Foundation
import CoreGraphics
import CoreText
import CoreImage

enum LianxinDisplayRenderChecks {
    static func run(out: URL, fixture: URL) async throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "LianxinDisplayRenderChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let content = LianxinPublication(idol: "成员", text: String(String(repeating: "中文과한국어今天也辛苦啦", count: 20).prefix(200)), photo: nil, date: .distantPast,
            translation: String(String(repeating: "한국어와中文今天好好休息。", count: 20).prefix(200)), signatureSubtitle: "公开团体")
        var settings = WallpaperSettings(); settings.size = WallpaperSize(width: 480, height: 1920); settings.canvasAspect = 0.25
        settings.panelWidth = 0.44; settings.padding = 8; settings.fontSize = 12
        settings.automaticHeight = false; settings.panelHeight = 0.94; settings.maximumLines = 1; settings.blurRadius = 0
        var display = settings.lianxinDisplay
        var look = TodoAppearance(); let oldTodo = look
        look.lianxinWallpaperMarker = TodoMarker(kind: .square)
        look.lianxinWallpaperMarkerStyle = MarkerStyle(); look.lianxinWallpaperMarkerStyle?.size = 18
        let context = CIContext(options: [.cacheIntermediates: false])
        for mode in LianxinTranslationDisplay.allCases {
            display.translationDisplay = mode; settings.lianxinDisplayStyle = display
            let rendered = try WallpaperRenderer.render(settings: settings, items: [], photoURL: nil, ciContext: context, appearance: look, content: content)
            let layout = rendered.layout
            try require(!layout.lianxinOverflow && layout.rows.count == 1, "窄面板足够高时200字双语完整显示")
            let row = layout.rows[0]
            try require(row.block.lines.count > 1 && !row.block.truncated, "不使用待办每项1行上限")
            try require((mode == .both) == (row.secondary != nil), "三种显示方式控制次要行")
            try require(row.marker.kind == (mode == .translation ? .none : .square), "标记只在原文前")
            if let secondary = row.secondary {
                try require(abs(CTFontGetSize(secondary.font) - settings.fontSize * 0.85) < 0.001 && row.secondaryTop >= row.top + row.block.height, "译文字号比例与下方位置")
                try require(row.secondaryTop + secondary.height <= layout.panel.maxY, "译文不越面板")
            }
            try require(layout.headings.count == 2 && layout.supplements.count == 1, "成员标题、团体摘要和独立署名")
            var movedSettings = settings; movedSettings.customPosition = true; movedSettings.panelX = 0.65; movedSettings.panelY = 0.6
            let moved = layout.positioned(using: movedSettings)
            try require(moved.revision == layout.revision && abs((moved.rows[0].secondaryTop - row.secondaryTop) - (moved.panel.minY - layout.panel.minY)) < 0.001, "拖动保留字形缓存与次要行相对位置")
            try WallpaperRenderer.writePNG(rendered.image, to: out.appendingPathComponent("lianxin-display-" + mode.rawValue + ".png"), expected: settings.size, creationDescription: "AI 创作 · 连心")
        }
        display.translationDisplay = .both; display.maximumLines = 1; settings.lianxinDisplayStyle = display
        let capped = try WallpaperRenderer.layout(settings: settings, items: [], appearance: look, content: content)
        try require(capped.lianxinLineOverflow && capped.lianxinIssue?.localizedDescription.contains("改为不限") == true, "手选行数截断仍阻止不完整导出并给出正确下一步")
        display.maximumLines = 0; settings.lianxinDisplayStyle = display
        for size in [10.0, 18, 32] {
            var scaled = settings; scaled.fontSize = size
            let layout = try WallpaperRenderer.layout(settings: scaled, items: [], appearance: look, content: content)
            try require(layout.rows.allSatisfy { row in row.top + row.block.height <= layout.panel.maxY && (row.secondary.map { row.secondaryTop + $0.height <= layout.panel.maxY } ?? true) }, "字号放大时宁可报告放不下，行不能越界")
        }
        let imageName = "marker-image-" + UUID().uuidString + ".png"
        let markerURL = try MarkerImageReference.url(for: imageName, in: out)
        try FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: markerURL)
        for marker in [TodoMarker(kind: .none), TodoMarker(kind: .emoji, emoji: "🌙"), TodoMarker(kind: .image, imageName: imageName)] {
            look.lianxinWallpaperMarker = marker
            let rendered = try WallpaperRenderer.render(settings: settings, items: [], photoURL: nil, previewWidth: 390, ciContext: context, appearance: look, assetDirectory: out, content: content)
            try require(rendered.layout.rows.first?.marker.kind == marker.kind, "真实渲染无/Emoji/图片标记")
        }
        try require(look.widget == oldTodo.widget && look.defaultMarker == oldTodo.defaultMarker, "连心壁纸标记不修改待办样式")
        var originalStyle = WidgetAppearance(); originalStyle.lianxinDisplayStyle = LianxinDisplayStyle(translationDisplay: .original)
        try require(originalStyle.lianxinDisplay.translationDisplay != settings.lianxinDisplay.translationDisplay, "小组件/壁纸翻译样式独立")
        let roundTrip = try JSONDecoder().decode(WallpaperSettings.self, from: JSONEncoder().encode(settings))
        try require(roundTrip == settings && WallpaperSettings().lianxinDisplay.maximumLines == 0, "新旧草稿兼容且壁纸默认不限")
        print("PASS: 连心生产壁纸双语/200字/窄面板、标题摘要、标记、字号放大、次要行位置、缓存身份与独立样式。")
    }
}
