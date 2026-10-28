import SwiftUI
import WidgetKit
import CoreText
import UIKit

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
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var hostScheme
    private var foreground: Color {
        if renderingMode != .fullColor { return .primary }
        let requested = style.followsSystemText ? ((style.isExplicitlyDark ?? (hostScheme == .dark)) ? WallpaperColor() : WallpaperColor(red: 0, green: 0, blue: 0)) : style.textColor
        return safeColor(requested)
    }
    private var background: WallpaperColor { TextLegibility.widgetBase(style, dark: style.isExplicitlyDark ?? (hostScheme == .dark)) }
    private var textNeedsShadow: Bool { renderingMode == .fullColor && (style.backdrop == .photo || style.materialEnabled || style.backdrop == .solid && style.panelColor.alpha < 0.9) }
    private func safeColor(_ color: WallpaperColor) -> Color {
        if renderingMode != .fullColor { return .primary }
        return TextLegibility.readable(color, on: background).swiftColor
    }
    private var textShadow: Color {
        // Only light text gets a drop shadow. Giving dark text a white shadow
        // smears a halo around the glyphs on light backgrounds - that is the
        // "shadow turned white and blurrier" regression reported after 1029.
        guard renderingMode == .fullColor, textNeedsShadow else { return .clear }
        let requested = style.followsSystemText
            ? ((style.isExplicitlyDark ?? (hostScheme == .dark)) ? WallpaperColor() : WallpaperColor(red: 0, green: 0, blue: 0))
            : style.textColor
        let resolved = TextLegibility.readable(requested, on: background)
        // 浅字配深影、深字配浅影，两边都压低不透明度：
        // 原来只给浅字加黑影，黄色这类高亮色会出硬边，深绿这类低亮色又完全没有景深。
        // 只用黑色投影，强度跟文字亮度挂钩：亮字（黄、白）重一点，暗字几乎不加。
        let l = TextLegibility.luminance(resolved)
        return .black.opacity(0.10 + 0.32 * l)
    }
    private var heading: WidgetHeaderAppearance { style.heading }
    private var headingFont: CTFont { NativeTypography.font(family: heading.font, weight: heading.weight, size: heading.fontSize * headerUnit / 17) }
    private var fontSize: Double { style.fontSize * bodyUnit / 15 }
    private var titleFont: CTFont { NativeTypography.font(family: style.font, weight: style.weight, size: fontSize) }
    private var lineHeight: Double {
        let key = "\(style.font.rawValue):\(style.weight.rawValue):\(fontSize):\((document?.items.prefix(10).map(\.title) ?? []).joined(separator: "\u{1f}"))" as NSString
        if let cached = WidgetMeasureCache.heights.object(forKey: key) { return cached.doubleValue }
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
        let result = ceil(height) + 1
        WidgetMeasureCache.heights.countLimit = 96
        WidgetMeasureCache.heights.setObject(NSNumber(value: result), forKey: key)
        return result
    }
    var body: some View {
        GeometryReader { geometry in
            let items = document?.items ?? []
            let headingMetrics = headerMetrics(width: geometry.size.width, height: geometry.size.height, items: items)
            let metrics = WidgetLayoutMetrics.make(items: items,
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
                                    .overlay(alignment: .bottom) {
                                        if style.separatesRows && index < shown.count - 1 {
                                            // 画在行底部，不参与布局：每行间距才会完全一致。
                                            Rectangle().fill(foreground.opacity(0.35))
                                                .frame(height: 0.5)
                                                .padding(.leading, metrics.markerWidth + metrics.gap)
                                        }
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
                    .foregroundStyle(heading.followsTextColor ? foreground : safeColor(heading.color))
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: layout.titleWidth, height: layout.titleHeight, alignment: .topLeading)
                    .offset(x: layout.titleX, y: layout.titleY)
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
        .frame(height: layout.height, alignment: .topLeading).clipped()
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
        VStack(alignment: .leading, spacing: 2) {
            StrokedText(text: item.title, font: titleFont,
                        fill: UIColor(item.isCompleted && style.textCompletion == .color ? safeColor(style.completionColor) : foreground),
                        stroke: style.textOutline == true ? strokeColor : nil,
                        strike: item.isCompleted && style.textCompletion.strikes,
                        lineLimit: metrics.lineLimit)
                .opacity(item.isCompleted && style.textCompletion.fades ? 0.55 : 1)
            if let schedule = item.schedule {
                Text(schedule.label).font(.system(size: max(10, fontSize * 0.68))).lineLimit(1).opacity(0.75)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: metrics.rowHeight).clipped()

    }
    private var strokeColor: UIColor {
        let requested = style.followsSystemText
            ? ((style.isExplicitlyDark ?? (hostScheme == .dark)) ? WallpaperColor() : WallpaperColor(red: 0, green: 0, blue: 0))
            : style.textColor
        let resolved = TextLegibility.readable(requested, on: background)
        return TextLegibility.luminance(resolved) > 0.5 ? .black : .white
    }
}

/// SwiftUI Text 会忽略 strokeWidth 属性，描边必须交给 UILabel 渲染。
struct StrokedText: UIViewRepresentable {
    let text: String
    let font: CTFont
    let fill: UIColor
    let stroke: UIColor?
    let strike: Bool
    let lineLimit: Int

    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        let attrs = NSMutableAttributedString(string: text)
        let full = NSRange(location: 0, length: attrs.length)
        attrs.addAttribute(.font, value: font as UIFont, range: full)
        attrs.addAttribute(.foregroundColor, value: fill, range: full)
        if let stroke {
            attrs.addAttribute(.strokeWidth, value: -4.0, range: full)
            attrs.addAttribute(.strokeColor, value: stroke, range: full)
        }
        if strike {
            attrs.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
        }
        label.numberOfLines = lineLimit
        label.attributedText = attrs
    }
}

private enum WidgetMeasureCache { static let heights = NSCache<NSString, NSNumber>() }
