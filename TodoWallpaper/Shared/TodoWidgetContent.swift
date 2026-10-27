import SwiftUI
import WidgetKit
import CoreText

/// Actual Widget and app preview use identical geometry and completion visuals.
/// Only the action routing differs: App Intent on the Home Screen, local try-out in preview.
struct TodoWidgetContent: View {
    let document: TodoDocument?
    let appearance: TodoAppearance
    let error: String?
    let family: WidgetPreviewFamily
    var interactive = true
    var onPreviewToggle: ((UUID) -> Void)?
    var onPreviewMarker: ((UUID) -> Void)?
    var selectedTaskID: UUID?
    var onPreviewHeader: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var bodyUnit = 15.0
    @ScaledMetric(relativeTo: .headline) private var headerUnit = 17.0
    @ScaledMetric(relativeTo: .caption2) private var footerUnit = 11.0
    private var style: WidgetAppearance { appearance.widget }
    private var foreground: Color { style.followsSystemText ? .primary : style.textColor.swiftColor }
    private var heading: WidgetHeaderAppearance { style.heading }
    private var headingFont: CTFont { NativeTypography.font(family: heading.font, weight: heading.weight, size: heading.fontSize * headerUnit / 17) }
    private var fontSize: Double { style.fontSize * bodyUnit / 15 }
    private var titleFont: CTFont { NativeTypography.font(family: style.font, weight: style.weight, size: fontSize) }
    private var lineHeight: Double {
        let font = titleFont
        var height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        // Include CJK/Emoji fallback metrics, not just the Latin font's ascender.
        for item in document?.items.prefix(10) ?? [] {
            let text = NSAttributedString(string: item.title, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let line = CTLineCreateWithAttributedString(text as CFAttributedString)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            height = max(height, ascent + descent + leading)
        }
        return ceil(height) + 1
    }
    var body: some View {
        GeometryReader { geometry in
            let items = document?.items ?? []
            let headingMetrics = headerMetrics(width: geometry.size.width, height: geometry.size.height, items: items)
            let metrics = WidgetLayoutMetrics.make(items: style.rows(items, capacity: style.maximumItems),
                appearance: appearance, family: family, width: geometry.size.width, height: geometry.size.height,
                fontLineHeight: lineHeight, headerHeight: headingMetrics.height, footerHeight: ceil(footerUnit * 1.3))
            let shown = metrics.capacity > 0 ? style.rows(items, capacity: metrics.capacity) : []
            VStack(alignment: .leading, spacing: 0) {
                if headingMetrics.height > 0 {
                    header(items: items, layout: headingMetrics)
                    Color.clear.frame(height: metrics.spacing)
                }
                if document == nil {
                    Text(error ?? "请先打开 App 完成迁移").font(.system(size: footerUnit)).lineLimit(3)
                } else if items.isEmpty {
                    Text("暂无待办").font(.system(size: fontSize)).lineLimit(1)
                } else if shown.isEmpty {
                    Text(metrics.capacity == 0 ? "请使用更大组件" : "全部完成")
                        .font(.system(size: footerUnit)).lineLimit(1)
                } else {
                    VStack(alignment: .leading, spacing: metrics.spacing) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                            VStack(spacing: 0) {
                                task(item, metrics: metrics)
                                if style.separatesRows && index < shown.count - 1 {
                                    Divider().padding(.leading, metrics.markerWidth + metrics.gap)
                                        .padding(.vertical, 4).frame(height: metrics.separatorHeight)
                                }
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
                if metrics.showsFooter {
                    Text(items.count > shown.count ? "另有 \(items.count - shown.count) 项" : "点任务可完成或恢复")
                        .font(.system(size: footerUnit)).opacity(0.7).lineLimit(1)
                        .frame(height: metrics.footerHeight).padding(.top, metrics.spacing)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .foregroundStyle(foreground).clipped()
        }
    }
    private func measure(_ text: String, font: CTFont) -> (width: Double, height: Double) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]) as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (ceil(width) + 1, ceil(ascent + descent + leading) + 1)
    }
    private func headerMetrics(width: Double, height: Double, items: [TodoItem]) -> WidgetHeaderLayout {
        let title = measure(heading.text, font: headingFont)
        let summary = measure("\(items.filter { !$0.isCompleted }.count) 未完成",
            font: NativeTypography.font(family: .system, weight: .regular, size: footerUnit))
        return .make(style: heading, width: width, maximumHeight: height * 0.6,
            measuredTitleWidth: title.width, titleLineHeight: title.height,
            measuredSummaryWidth: summary.width, summaryHeight: summary.height)
    }
    private func header(items: [TodoItem], layout: WidgetHeaderLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if heading.visibleTitle {
                Text(heading.text).font(Font(headingFont))
                    .foregroundStyle(heading.followsTextColor ? foreground : heading.color.swiftColor)
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
                    .frame(width: layout.titleWidth, height: layout.titleHeight, alignment: .topLeading)
                    .offset(x: layout.titleX, y: heading.topInset)
                    .onTapGesture { if !interactive { onPreviewHeader?() } }
                    .accessibilityLabel("小组件标题：\(heading.text)")
            }
            if heading.showsSummary {
                Text("\(items.filter { !$0.isCompleted }.count) 未完成")
                    .font(.system(size: footerUnit)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: layout.summaryWidth, height: layout.height, alignment: .topTrailing)
                    .offset(x: layout.summaryX)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.height).clipped()
    }
    @ViewBuilder private func task(_ item: TodoItem, metrics: WidgetLayoutMetrics) -> some View {
        if interactive {
            Button(intent: SetTodoCompletionIntent(taskID: item.id, completed: !item.isCompleted)) {
                HStack(spacing: metrics.gap) { mark(item, metrics: metrics); title(item, metrics: metrics) }
                    .frame(height: metrics.rowHeight).contentShape(Rectangle())
            }
            .buttonStyle(.plain).invalidatableContent()
            .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
        } else {
            HStack(spacing: metrics.gap) {
                Button { onPreviewMarker?(item.id) } label: {
                    mark(item, metrics: metrics).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("编辑\(item.title)的标记")
                .accessibilityIdentifier("preview.marker.\(item.id.uuidString)")
                Button { onPreviewToggle?(item.id) } label: { title(item, metrics: metrics).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("仅预览\(item.isCompleted ? "恢复" : "完成")：\(item.title)")
                    .accessibilityIdentifier("preview.toggle.\(item.id.uuidString)")
            }.frame(height: metrics.rowHeight).contentShape(Rectangle())
        }
    }
    private func mark(_ item: TodoItem, metrics: WidgetLayoutMetrics) -> some View {
        TodoMarkerView(marker: appearance.marker(for: item, widgetContext: true), completed: item.isCompleted,
            style: style.markerStyle, textColor: foreground)
            .frame(width: metrics.markerWidth, height: metrics.rowHeight)
            .background {
                if !interactive && selectedTaskID == item.id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12))
                }
            }
    }
    private func title(_ item: TodoItem, metrics: WidgetLayoutMetrics) -> some View {
        Text(item.title).font(Font(titleFont))
            .strikethrough(item.isCompleted && style.textCompletion.strikes)
            .opacity(item.isCompleted && style.textCompletion.fades ? 0.55 : 1)
            .foregroundStyle(item.isCompleted && style.textCompletion == .color ? style.completionColor.swiftColor : foreground)
            .lineLimit(metrics.lineLimit).multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.rowHeight)
            .clipped()
    }
}
