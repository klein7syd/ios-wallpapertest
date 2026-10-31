import Foundation
import CoreText

// 每个任务独立分配文字行数和高度；编辑预览与扩展共用。
struct WidgetRowMetrics: Equatable {
    let id: UUID
    let lineLimit: Int
    let height: Double
    let dateHeight: Double
    var secondaryLineLimit = 0
    var secondaryHeight = 0.0
    var textTopInset = 0.0
}
struct WidgetLayoutMetrics: Equatable {
    let rows: [WidgetRowMetrics]
    var rowHeight: Double { rows.map(\.height).max() ?? 0 }
    let markerWidth: Double
    let gap: Double
    let lineHeight: Double
    let headerHeight: Double
    let footerHeight: Double
    let separatorHeight: Double
    let spacing: Double
    var capacity: Int { rows.count }
    var lineLimit: Int { rows.map(\.lineLimit).max() ?? 1 }
    let showsFooter: Bool
    let availableRowHeight: Double
    var usedHeight: Double { rows.reduce(0) { $0 + $1.height } + Double(max(0, rows.count - 1)) * spacing }
    static func make(items: [TodoItem], appearance: TodoAppearance, family: WidgetPreviewFamily,
                     width: Double, height: Double, fontLineHeight: Double,
                     headerHeight: Double, footerHeight: Double, font: CTFont? = nil,
                     dateLineHeight: Double? = nil, secondaryText: [UUID: String] = [:],
                     secondaryScale: Double = 0.85, maximumLinesOverride: Int? = nil, alignsMarkerToFirstLine: Bool = false) -> WidgetLayoutMetrics {
        let style = appearance.widget
        let candidates = style.rows(items, capacity: style.maximumItems)
        let marks = candidates.map { MarkerDrawing.extent(marker: appearance.marker(for: $0, widgetContext: true), style: style.markerStyle, completed: $0.isCompleted) }
        let marker = marks.max() ?? 0
        let gap = marker > 0 ? style.markerStyle.gap : 0
        let vertical = marker > 0 ? abs(style.markerStyle.verticalOffset) * 2 : 0
        let spacing = max(0, style.spacing)
        // 负行距只移除装饰留白，不压缩字形自身所需高度。
        let padding = style.compact ? 0 : max(0, min(4, spacing * 0.8) + max(-2, min(0, style.spacing) * 0.2))
        let header = min(max(0, height), max(0, headerHeight))
        let afterHeader = max(0, height - header - (header > 0 ? spacing : 0))
        let line = max(1, fontLineHeight)
        let date = dateLineHeight ?? max(11, line * 0.65)
        let actualFont = font ?? NativeTypography.font(family: style.font, weight: style.weight, size: style.fontSize)
        let secondaryFont = NativeTypography.font(family: style.font, weight: style.weight, size: CTFontGetSize(actualFont) * secondaryScale)
        let secondaryLines = candidates.map { item in secondaryText[item.id].map { WidgetTitleMeasure.lineHeight($0, font: secondaryFont) } ?? 0 }
        let secondaryGap = max(0, style.spacing) / 2
        func textTop(_ index: Int) -> Double { alignsMarkerToFirstLine && marks[index] > 0 ? max(0, (marks[index] + vertical - line) / 2) : 0 }
        func extraHeight(_ index: Int, _ lines: Int) -> Double { lines > 0 ? secondaryLines[index] * Double(lines) + secondaryGap : 0 }
        func rowHeight(_ index: Int, _ lines: Int, _ secondary: Int = 0) -> Double {
            max(marks[index] + (marks[index] > 0 ? vertical : 0), textTop(index) + line * Double(lines) + extraHeight(index, secondary) + (candidates[index].schedule == nil ? 0 : date + 2)) + padding
        }
        let minimum = candidates.isEmpty ? line : rowHeight(0, 1)
        let footerFits = style.footerVisible && afterHeader >= minimum + footerHeight + spacing
        let footer = footerFits ? footerHeight : 0
        let rowSpace = max(0, afterHeader - (footerFits ? footer + spacing : 0))
        let limit = max(1, maximumLinesOverride ?? style.maximumTitleLines ?? (family == .small ? 2 : 3))
        let columnWidth = max(1, width - marker - gap)
        var rows: [WidgetRowMetrics] = [], used = 0.0
        for (index, item) in candidates.enumerated() {
            let needed = WidgetTitleMeasure.lines(item.title, font: actualFont, width: columnWidth)
            var lines = min(limit, needed)
            let secondaryNeeded = secondaryText[item.id].map { WidgetTitleMeasure.lines($0, font: secondaryFont, width: columnWidth) } ?? 0
            var secondary = min(limit, secondaryNeeded)
            let remaining = rowSpace - used - (rows.isEmpty ? 0 : spacing)
            while lines > 0 && rowHeight(index, lines, secondary) > remaining + 0.00001 {
                if secondary > 1 && (secondary >= lines || lines == 1) { secondary -= 1 }
                else { lines -= 1 }
            }
            guard lines > 0 else { break }
            let row = WidgetRowMetrics(id: item.id, lineLimit: lines, height: rowHeight(index, lines, secondary), dateHeight: item.schedule == nil ? 0 : date + 2,
                secondaryLineLimit: secondary, secondaryHeight: extraHeight(index, secondary), textTopInset: textTop(index))
            used += row.height + (rows.isEmpty ? 0 : spacing); rows.append(row)
            if lines < min(limit, needed) || secondary < min(limit, secondaryNeeded) { break }
        }
        return WidgetLayoutMetrics(rows: rows, markerWidth: marker, gap: gap, lineHeight: line,
            headerHeight: header, footerHeight: footer, separatorHeight: 0, spacing: spacing,
            showsFooter: footerFits, availableRowHeight: rowSpace)
    }
}

// 字体名称/字号/字重描述、完整标题和列宽共同组成有界缓存键。
enum WidgetTitleMeasure {
    private static let cache = NSCache<NSString, NSNumber>()
    static func lineHeight(_ text: String, font: CTFont) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]) as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return ceil(max(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font), ascent + descent + leading)) + 1
    }
    static func lines(_ text: String, font: CTFont, width: Double) -> Int {
        let key = "\(CTFontCopyPostScriptName(font)):\(CTFontGetSize(font)):\(CTFontCopyTraits(font)):\(width):\(text)" as NSString
        if let value = cache.object(forKey: key) { return value.intValue }
        let attributed = NSAttributedString(string: text.isEmpty ? " " : text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let setter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        // 列宽减1pt，给CoreText与SwiftUI的换行边界留容差。
        let measuredWidth = max(1, width - 1)
        let size = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
            CGSize(width: measuredWidth, height: .greatestFiniteMagnitude), nil)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: measuredWidth, height: ceil(size.height) + 1), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let count = max(1, CFArrayGetCount(CTFrameGetLines(frame)))
        cache.countLimit = 512; cache.setObject(NSNumber(value: count), forKey: key)
        return count
    }
}

/// Local try-out state; it cannot write a completion into the task repository.
struct WidgetPreviewState {
    private(set) var completions: [UUID: Bool] = [:]
    private var changedAt: [UUID: Date] = [:]
    mutating func toggle(_ item: TodoItem, now: Date = .now) {
        completions[item.id] = !(completions[item.id] ?? item.isCompleted)
        changedAt[item.id] = now
    }
    mutating func reset() { completions = [:]; changedAt = [:] }
    func items(_ source: [TodoItem]) -> [TodoItem] {
        source.map { item in
            guard let completed = completions[item.id] else { return item }
            var copy = item; copy.isCompleted = completed
            copy.updatedAt = changedAt[item.id] ?? item.updatedAt
            return copy
        }
    }
}
