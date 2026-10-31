// Target Membership：独立 macOS 原生检查；运行生产 CoreText 布局与 PNG 导出。
import Foundation
import CoreText
import ImageIO

enum LianxinWallpaperChecks {
    static func run(out: URL) async throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "LianxinWallpaperChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var settings = WallpaperSettings()
        settings.panelWidth = 0.44; settings.padding = 8; settings.fontSize = 16
        settings.maximumLines = 1; settings.automaticHeight = false; settings.panelHeight = 0.94
        settings.size = WallpaperSize(width: 480, height: 1040)
        settings.blurRadius = 0
        let service = WallpaperRenderService()
        for title in [String(repeating: "认真照顾自己今天也要开心", count: 20), String(repeating: "今天辛苦啦오늘도 수고했어。", count: 16)] {
            let content = LianxinPublication(idol: "测试角色", text: String(title.prefix(200)), photo: nil, date: .distantPast)
            let items = WallpaperContentSource.lianxin(content).items
            let tall = try WallpaperRenderer.layout(settings: settings, items: items, content: content)
            try require(!tall.lianxinOverflow && tall.hiddenCount == 0 && tall.rows.count == 1, "窄面板足够高时完整容纳200字中文/中韩混排")
            try require(tall.rows[0].block.lines.count > 4 && !tall.rows[0].block.truncated, "不受待办每项1行或4行上限影响")
            try require(tall.rows[0].top + tall.rows[0].block.height <= tall.panel.maxY && tall.supplements.allSatisfy { $0.top + $0.block.height <= tall.panel.maxY }, "正文、署名不超面板")
            let url = try await service.export(settings: settings, items: items, photoURL: nil, directory: out, content: content)
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] else { throw WallpaperError.encodingFailed }
            try require(png[kCGImagePropertyPNGDescription] as? String == "AI 创作 · 连心", "无可见标注时导出PNG仍含Description元数据")
            var short = settings; short.panelHeight = 0.12
            let overflow = try WallpaperRenderer.layout(settings: short, items: items, content: content)
            try require(overflow.lianxinOverflow, "高度不够明确报告放不下")
            do {
                _ = try await service.export(settings: short, items: items, photoURL: nil, directory: out, content: content)
                throw NSError(domain: "LianxinWallpaperChecks", code: 2)
            } catch WallpaperError.contentOverflow { }
        }
        try require(WallpaperError.contentOverflow.localizedDescription == "文字超出面板，请增大面板高度、减小字号或缩短话语", "溢出提示原因与下一步")
        var old = WidgetAppearance(); old.systemMaterial = true
        let decoded = try JSONDecoder().decode(WidgetAppearance.self, from: JSONEncoder().encode(old))
        try require(decoded.systemMaterial == true && !decoded.materialEnabled && decoded.lianxinShowsCreationLabel != true, "旧玻璃true兼容但不生效，创作标注默认关闭")
        print("PASS: 连心窄面板200字/中韩完整折行、署名独立、溢出禁止导出、PNG创作元数据、旧材质兼容。")
    }
}
