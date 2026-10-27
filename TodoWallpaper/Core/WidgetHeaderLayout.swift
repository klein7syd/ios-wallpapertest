import Foundation

struct WidgetHeaderLayout: Equatable {
    let height: Double
    let titleX: Double
    let titleWidth: Double
    let titleHeight: Double
    let titleY: Double
    let summaryX: Double
    let summaryWidth: Double
    static func make(style: WidgetHeaderAppearance, width: Double, maximumHeight: Double,
                     measuredTitleWidth: Double, titleLineHeight: Double,
                     measuredSummaryWidth: Double, summaryHeight: Double) -> WidgetHeaderLayout {
        let width = max(0, width)
        let summary = style.showsSummary ? min(width * (style.visibleTitle ? 0.48 : 1), max(0, measuredSummaryWidth)) : 0
        let region = max(0, width - summary - (style.visibleTitle && summary > 0 ? 6 : 0))
        let titleWidth = style.visibleTitle ? min(region, max(0, measuredTitleWidth)) : 0
        // Reserve the complete glyph line(s) before allocating decorative inset.
        // A large inset must not take height away from a title's ink box.
        let titleHeight = style.visibleTitle ? min(max(0, maximumHeight),
            titleLineHeight * (measuredTitleWidth > region ? 2 : 1)) : 0
        let titleY = min(style.topInset, max(0, maximumHeight - titleHeight))
        let height = min(maximumHeight, max(style.visibleTitle ? titleY + titleHeight : 0,
            style.showsSummary ? summaryHeight : 0))
        return WidgetHeaderLayout(height: max(0, height), titleX: max(0, region - titleWidth) * style.horizontalPosition,
            titleWidth: titleWidth, titleHeight: titleHeight, titleY: titleY,
            summaryX: width - summary, summaryWidth: summary)
    }
}
