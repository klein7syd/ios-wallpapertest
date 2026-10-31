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
    var effectsFamily: WidgetFamily?
    @ScaledMetric(relativeTo: .body) private var bodyUnit = 15.0
    @ScaledMetric(relativeTo: .headline) private var headerUnit = 17.0
    @ScaledMetric(relativeTo: .caption2) private var footerUnit = 11.0
    private var style: WidgetAppearance { appearance.widget }
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetFamily) private var hostFamily
    @Environment(\.colorScheme) private var hostScheme
    private var tone: ReadableTone {
        ReadableTone.resolve(style: style, scheme: hostScheme, renderingMode: renderingMode, family: effectsFamily ?? hostFamily)
    }
    private var foreground: Color {
        tone.textColor
    }
    private var background: WallpaperColor { TextLegibility.widgetBase(style, dark: style.isExplicitlyDark ?? (hostScheme == .dark)) }
    private var settings: ReadableSettings { style.readable }
    /// 用户选什么颜色就渲染什么颜色，不再按底色改写
    private func safeColor(_ color: WallpaperColor) -> Color {
        if renderingMode != .fullColor { return .primary }
        return color.swiftColor
    }
    /// 由主文字最终颜色选择黑/白阴影；着色与锁屏环境统一禁用效果。
    private var textIsLight: Bool { tone.enabled && tone.isLightText }
    private var contentAlignment: Alignment {
        switch settings.anchor {
        case .top: return .topLeading
        case .center: return .center
        case .bottom: return .bottomLeading
        }
    }
    private var heading: WidgetHeaderAppearance { style.heading }
    private var headingFont: CTFont { NativeTypography.font(family: heading.font, weight: heading.weight, size: heading.fontSize * headerUnit / 17) }
    private var fontSize: Double { style.fontSize * bodyUnit / 15 }
    private var titleFont: CTFont { NativeTypography.font(family: style.font, weight: style.weight, size: fontSize) }
    var body: some View {
        GeometryReader { geometry in
            let items = document?.items ?? []
            let layout = WidgetContentLayout.make(document: document, appearance: appearance, family: family,
                width: geometry.size.width, height: geometry.size.height,
                bodyUnit: bodyUnit, headerUnit: headerUnit, footerUnit: footerUnit)
            let headingMetrics = layout.header, metrics = layout.metrics, shown = layout.shown
            let inset = layout.inset
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
                                task(item, metrics: metrics, row: metrics.rows[index])
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
                if metrics.showsFooter {
                    Text(items.count > shown.count ? "另有 \(items.count - shown.count) 项" : "点任务可完成或恢复")
                        .font(.system(size: footerUnit)).opacity(0.7).lineLimit(1)
                    .readableText(isLightText: textIsLight, intensity: settings.intensity,
                                  enabled: tone.enabled)
                        .frame(height: metrics.footerHeight).padding(.top, metrics.spacing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: contentAlignment)
            .foregroundStyle(foreground).clipped()
            .padding(.top, settings.anchor == .top ? inset : 0)
            .padding(.bottom, settings.anchor == .bottom ? inset : 0)
            .offset(y: settings.anchor == .center ? inset : 0)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: contentAlignment)
            .preference(key: ReadableGeometryPreference.self,
                        value: layout.geometry)
        }
    }
    private func header(items: [TodoItem], layout: WidgetHeaderLayout) -> some View {
        ZStack(alignment: .topLeading) {
            if heading.visibleTitle {
                Text(heading.text).font(Font(headingFont))
                    .foregroundStyle(heading.followsTextColor ? foreground : safeColor(heading.color))
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.leading)
                    .readableText(isLightText: textIsLight, intensity: settings.intensity,
                                  enabled: tone.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: layout.titleWidth, height: layout.titleHeight, alignment: .topLeading)
                    .offset(x: layout.titleX, y: layout.titleY)
                    .onTapGesture { if !interactive { onPreviewHeader?() } }
                    .accessibilityLabel("小组件标题：\(heading.text)")
            }
            if heading.showsSummary {
                Text("\(items.filter { !$0.isCompleted }.count) 未完成")
                    .font(.system(size: footerUnit)).opacity(0.7).lineLimit(1).minimumScaleFactor(0.7)
                    .readableText(isLightText: textIsLight, intensity: settings.intensity,
                                  enabled: tone.enabled)
                    .frame(width: layout.summaryWidth, height: layout.height, alignment: .topTrailing)
                    .offset(x: layout.summaryX)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: layout.height, alignment: .topLeading).clipped()
    }
    @ViewBuilder private func task(_ item: TodoItem, metrics: WidgetLayoutMetrics, row: WidgetRowMetrics) -> some View {
        if interactive {
            Button(intent: SetTodoCompletionIntent(taskID: item.id, completed: !item.isCompleted)) {
                HStack(alignment: .top, spacing: metrics.gap) { mark(item, metrics: metrics, row: row); title(item, metrics: metrics, row: row) }
                    .frame(height: row.height, alignment: .top).contentShape(Rectangle())
            }
            .buttonStyle(.plain).invalidatableContent()
            .accessibilityLabel(item.isCompleted ? "恢复：\(item.title)" : "完成：\(item.title)")
        } else {
            HStack(alignment: .top, spacing: metrics.gap) {
                Button { onPreviewMarker?(item.id) } label: {
                    mark(item, metrics: metrics, row: row).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("编辑\(item.title)的标记")
                .accessibilityIdentifier("preview.marker.\(item.id.uuidString)")
                Button { onPreviewToggle?(item.id) } label: { title(item, metrics: metrics, row: row).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("仅预览\(item.isCompleted ? "恢复" : "完成")：\(item.title)")
                    .accessibilityIdentifier("preview.toggle.\(item.id.uuidString)")
            }.frame(height: row.height, alignment: .top).contentShape(Rectangle())
        }
    }
    private func mark(_ item: TodoItem, metrics: WidgetLayoutMetrics, row: WidgetRowMetrics) -> some View {
        TodoMarkerView(marker: appearance.marker(for: item, widgetContext: true), completed: item.isCompleted,
            style: style.markerStyle, textColor: foreground)
            .readableText(isLightText: textIsLight, intensity: settings.intensity, enabled: tone.enabled)
            .frame(width: metrics.markerWidth, height: max(metrics.lineHeight, MarkerDrawing.extent(marker: appearance.marker(for: item, widgetContext: true), style: style.markerStyle, completed: item.isCompleted) + abs(style.markerStyle.verticalOffset) * 2), alignment: .center)
            .background {
                if !interactive && selectedTaskID == item.id {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor.opacity(0.12))
                }
            }
    }
    private func title(_ item: TodoItem, metrics: WidgetLayoutMetrics, row: WidgetRowMetrics) -> some View {
        // 标题与日期共用同一份颜色与淡出，避免日期不跟随完成效果
        let rowColor = item.isCompleted && style.textCompletion == .color ? safeColor(style.completionColor) : foreground
        let rowFade = item.isCompleted && style.textCompletion.fades ? 0.55 : 1
        return VStack(alignment: .leading, spacing: 2) {
            Text(item.title).font(Font(titleFont))
                .strikethrough(item.isCompleted && style.textCompletion.strikes)
                .opacity(rowFade)
                .foregroundStyle(rowColor)
                .lineLimit(row.lineLimit).multilineTextAlignment(.leading)
                .readableText(isLightText: textIsLight, intensity: settings.intensity,
                              enabled: tone.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let schedule = item.schedule {
                // 日期不划线；淡出与标题一致
                Text(schedule.label).font(.system(size: max(10, fontSize * 0.68))).lineLimit(1)
                    .opacity(0.75 * rowFade)
                    .foregroundStyle(rowColor)
                    .readableText(isLightText: textIsLight, intensity: settings.intensity,
                                  enabled: tone.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).frame(height: row.height, alignment: .top).clipped()

    }
}

/// App + Widget 共用的轻量内容度量；背景与文字须使用同一自然高度与有效偏移。
struct WidgetContentLayout {
    let header: WidgetHeaderLayout
    let metrics: WidgetLayoutMetrics
    let shown: [TodoItem]
    let geometry: ReadableContentGeometry
    let inset: Double

    static func make(document: TodoDocument?, appearance: TodoAppearance, family: WidgetPreviewFamily,
                     width: Double, height: Double, bodyUnit: Double, headerUnit: Double, footerUnit: Double) -> WidgetContentLayout {
        let items = document?.items ?? [], style = appearance.widget, settings = style.readable
        let fontSize = style.fontSize * bodyUnit / 15
        let font = NativeTypography.font(family: style.font, weight: style.weight, size: fontSize)
        let lineHeight = measuredLineHeight(document: document, style: style, fontSize: fontSize, font: font)
        let heading = style.heading
        let headingFont = NativeTypography.font(family: heading.font, weight: heading.weight, size: heading.fontSize * headerUnit / 17)
        let title = measure(heading.text, font: headingFont)
        let summary = measure("\(items.filter { !$0.isCompleted }.count) 未完成",
            font: NativeTypography.font(family: .system, weight: .regular, size: footerUnit))
        let header = WidgetHeaderLayout.make(style: heading, width: width, maximumHeight: height * 0.6,
            measuredTitleWidth: title.width, titleLineHeight: title.height,
            measuredSummaryWidth: summary.width, summaryHeight: summary.height)
        let edge = ReadableRules.inset(settings.edgeInset, anchor: settings.anchor, canvasHeight: height, textHeight: 0)
        let metrics = WidgetLayoutMetrics.make(items: items, appearance: appearance, family: family, width: width,
            height: max(0, height - (settings.anchor == .center ? 0 : abs(edge))), fontLineHeight: lineHeight,
            headerHeight: header.height, footerHeight: ceil(footerUnit * 1.3), font: font,
            dateLineHeight: measure("日期", font: NativeTypography.font(family: .system, weight: .regular, size: max(10, fontSize * 0.68))).height)
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let shown = metrics.rows.compactMap { byID[$0.id] }
        let rows: Double
        if document == nil || shown.isEmpty && !items.isEmpty { rows = ceil(footerUnit * 1.3) }
        else if items.isEmpty { rows = lineHeight }
        else { rows = metrics.usedHeight }
        let textHeight = (header.height > 0 ? header.height + metrics.spacing : 0) + rows
            + (metrics.showsFooter ? metrics.footerHeight + metrics.spacing : 0)
        let geometry = ReadableContentGeometry(canvasHeight: height, textHeight: textHeight)
        return WidgetContentLayout(header: header, metrics: metrics, shown: shown, geometry: geometry,
            inset: ReadableRules.inset(settings.edgeInset, anchor: settings.anchor, canvasHeight: height, textHeight: textHeight))
    }
    private static func measure(_ text: String, font: CTFont) -> (width: Double, height: Double) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]) as CFAttributedString)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        return (ceil(width) + 1, ceil(ascent + descent + leading) + 1)
    }
    private static func measuredLineHeight(document: TodoDocument?, style: WidgetAppearance, fontSize: Double, font: CTFont) -> Double {
        let key = "\(style.font.rawValue):\(style.weight.rawValue):\(fontSize):\((document?.items.prefix(10).map(\.title) ?? []).joined(separator: "\u{1f}"))" as NSString
        if let cached = WidgetMeasureCache.heights.object(forKey: key) { return cached.doubleValue }
        var height = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        for item in document?.items.prefix(10) ?? [] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: item.title,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]) as CFAttributedString)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            height = max(height, ascent + descent + leading)
        }
        let result = ceil(height) + 1
        WidgetMeasureCache.heights.countLimit = 96
        WidgetMeasureCache.heights.setObject(NSNumber(value: result), forKey: key)
        return result
    }
}
private enum WidgetMeasureCache { static let heights = NSCache<NSString, NSNumber>() }
