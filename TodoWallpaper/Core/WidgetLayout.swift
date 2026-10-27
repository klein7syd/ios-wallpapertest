import Foundation

/// Fixed Widget space is a budget. Large markers/fonts reduce rows, never silently
/// clamp a slider's effect. Both the extension and its interactive preview use this.
struct WidgetLayoutMetrics: Equatable {
    let rowHeight: Double
    let markerWidth: Double
    let gap: Double
    let lineHeight: Double
    let headerHeight: Double
    let footerHeight: Double
    let separatorHeight: Double
    let spacing: Double
    let capacity: Int
    let lineLimit: Int
    let showsFooter: Bool
    let availableRowHeight: Double
    static func make(items: [TodoItem], appearance: TodoAppearance, family: WidgetPreviewFamily,
                     width: Double, height: Double, fontLineHeight: Double,
                     headerHeight: Double, footerHeight: Double) -> WidgetLayoutMetrics {
        let style = appearance.widget
        let marks = items.map { MarkerDrawing.extent(marker: appearance.marker(for: $0, widgetContext: true), style: style.markerStyle, completed: $0.isCompleted) }
        let marker = marks.max() ?? 0
        let gap = marker > 0 ? style.markerStyle.gap : 0
        let vertical = marker > 0 ? abs(style.markerStyle.verticalOffset) * 2 : 0
        let spacing = style.spacing
        let separator = style.separatesRows ? 9.0 : 0
        let header = min(max(0, height), max(0, headerHeight))
        let afterHeader = max(0, height - header - (header > 0 ? spacing : 0))
        let dateHeight = items.contains(where: { $0.schedule != nil }) ? max(11, fontLineHeight * 0.65) + 2 : 0
        let padding = style.compact ? 0.0 : min(4, spacing * 0.8)
        let minimumRow = max(marker + vertical, fontLineHeight + dateHeight) + padding
        let footerFits = style.footerVisible && afterHeader >= minimumRow + footerHeight + spacing
        let footer = footerFits ? footerHeight : 0
        let rowSpace = max(0, afterHeader - (footerFits ? footer + spacing : 0))
        let proposedLines = style.maximumTitleLines ?? (family == .large && !style.compact && spacing > 2 && fontLineHeight < 30 ? 2 : 1)
        let lines = proposedLines == 2 && rowSpace >= max(marker + vertical, fontLineHeight * 2 + dateHeight) + padding ? 2 : 1
        let row = max(marker + vertical, fontLineHeight * Double(lines) + dateHeight) + padding
        let raw = row > 0 ? Int(max(0, (rowSpace + spacing + separator) / (row + spacing + separator)).rounded(.down)) : 0
        return WidgetLayoutMetrics(rowHeight: row, markerWidth: marker, gap: gap, lineHeight: fontLineHeight,
            headerHeight: header, footerHeight: footer, separatorHeight: separator, spacing: spacing,
            capacity: min(style.maximumItems, max(0, raw)), lineLimit: lines,
            showsFooter: footerFits, availableRowHeight: rowSpace)
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
