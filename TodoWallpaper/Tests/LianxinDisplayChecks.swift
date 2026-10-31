// Target Membership：独立macOS原生检查；使用生产次要行度量与样式模型。
import Foundation
import CoreText

enum LianxinDisplayChecks {
    static func run() throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw NSError(domain: "LianxinDisplayChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let content = LianxinPublication(idol: "成员", text: String(String(repeating: "中文과한국어🌙", count: 30).prefix(200)), photo: nil, date: .distantPast,
            translation: String(String(repeating: "한국어와中文 translated text ", count: 15).prefix(200)), signatureSubtitle: "公开团体")
        var count = 0
        for family in WidgetPreviewFamily.allCases {
            for scale in [1.0, 1.6, 2.82] {
                for mode in LianxinTranslationDisplay.allCases {
                    for limit in [nil, 0, 1, 2, 3, 4] as [Int?] {
                        var style = WidgetAppearance(); var display = LianxinDisplayStyle()
                        display.translationDisplay = mode; display.maximumLines = limit; style.lianxinDisplayStyle = display
                        style.lianxinMarker = TodoMarker(kind: .emoji, emoji: "🌙"); style.markerStyle.emojiSize = 48
                        let presentation = LianxinPresentation(content, style: display)
                        let look = LianxinPresentation.look(content: content, style: style)
                        let font = NativeTypography.font(family: .system, weight: .regular, size: 15 * scale)
                        let line = WidgetTitleMeasure.lineHeight(presentation.primary, font: font)
                        let secondary = presentation.secondary.map { [presentation.item.id: $0] } ?? [:]
                        let metrics = WidgetLayoutMetrics.make(items: [presentation.item], appearance: look, family: family,
                            width: family.width - 32, height: family.height - 32, fontLineHeight: line, headerHeight: 0, footerHeight: 0,
                            font: font, secondaryText: secondary, secondaryScale: display.translationScale,
                            maximumLinesOverride: limit == 0 ? Int.max : nil, alignsMarkerToFirstLine: true)
                        try require(metrics.usedHeight <= metrics.availableRowHeight + 0.001, "次要行累计高度不越界")
                        for row in metrics.rows {
                            try require(row.height <= family.height - 32 && row.height >= row.textTopInset + line * Double(row.lineLimit) + row.secondaryHeight, "正文/译文/大标记首行对齐完整计高")
                            try require((mode == .both) == (row.secondaryLineLimit > 0), "只有原文+译文有次要行")
                            if let limit, limit > 0 { try require(row.lineLimit <= limit && row.secondaryLineLimit <= limit, "最大1/2/3/4行生效") }
                        }
                        try require(mode != .translation || metrics.markerWidth == 0, "仅译文不画标记")
                        count += 1
                    }
                }
            }
        }
        var style = WidgetAppearance()
        try require(style.lianxinDisplay.translationDisplay == .both && style.lianxinDisplay.translationScale == 0.85 && style.lianxinDisplay.translationOpacity == 0.8, "三种显示默认及译文比例/透明度")
        style.markerOverride = TodoMarker(kind: .square)
        try require(LianxinPresentation.look(content: content, style: style).widget.markerOverride?.kind == MarkerKind.none, "旧继承待办标记不改变连心默认无标记")
        for kind in [MarkerKind.none, .square, .emoji, .image] {
            let name = "marker-image-" + UUID().uuidString + ".png"
            style.lianxinMarker = TodoMarker(kind: kind, emoji: "🌙", imageName: kind == .image ? name : nil)
            let look = LianxinPresentation.look(content: content, style: style)
            try look.validate()
            try require(look.marker(for: LianxinPresentation(content, style: style.lianxinDisplay).item, widgetContext: true).kind == kind, "连心形状/Emoji/图片/无标记")
        }
        var header = WidgetHeaderAppearance(); header.fontSize = 22; header.horizontalPosition = 0.5
        try require(LianxinPresentation.header(header, customTitle: nil, member: "成员", subtitle: "团体").text == "成员", "标题默认成员")
        try require(LianxinPresentation.header(header, customTitle: "  ", member: "成员", subtitle: nil).text == "成员", "标题清空回退成员")
        try require(LianxinPresentation.header(header, customTitle: "自己的标题", member: "成员", subtitle: nil).text == "自己的标题", "手动标题优先")
        try require(!LianxinPresentation.header(header, customTitle: nil, member: "成员", subtitle: nil).showsSummary, "无团体不显示待办数量")
        var root = TodoAppearance(); let todo = root
        root.initializeLianxin(); root.lianxin?.lianxinDisplayStyle = LianxinDisplayStyle(translationDisplay: .translation)
        let image = "marker-image-" + UUID().uuidString + ".png"
        root.lianxinWallpaperMarker = TodoMarker(kind: .image, imageName: image)
        try require(root.widget == todo.widget && root.defaultMarker == todo.defaultMarker && PhotoAssetReferences.appearance(root).contains(image), "待办隔离与壁纸标记图片保留")
        let roundTrip = try JSONDecoder().decode(TodoAppearance.self, from: JSONEncoder().encode(root))
        try require(roundTrip == root, "新样式JSON往返")
        var legacy = WidgetAppearance(); legacy.maximumTitleLines = 4; legacy.lianxinShowsSignature = false; legacy.lianxinCentered = true; legacy.lianxinShowsCreationLabel = true
        let old = try JSONDecoder().decode(WidgetAppearance.self, from: JSONEncoder().encode(legacy))
        try require(old.lianxinDisplay.maximumLines == 4 && !old.lianxinDisplay.showsSignature && old.lianxinDisplay.centered && old.lianxinDisplay.showsCreationLabel, "旧样式字段含义保留")
        print("PASS: \(count)组连心次要行/200字中韩/窄宽度/DynamicType/行数预算，标记、标题回退、三种译文、旧样式与待办隔离。")
    }
}
