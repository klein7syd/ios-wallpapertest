// Target Membership：App + Widget。复用待办同一度量、次要行、标记、标题和可读性层。
import SwiftUI
import WidgetKit

struct LianxinWidgetContent: View {
    let content: LianxinPublication?
    let style: WidgetAppearance
    let family: WidgetPreviewFamily
    var effectsFamily: WidgetFamily? = nil
    private var value: LianxinPublication { content ?? LianxinPublication(idol: "连心", text: "打开连心，写下一句话。", photo: nil, date: .distantPast) }
    private var display: LianxinDisplayStyle { style.lianxinDisplay }
    var body: some View {
        TodoWidgetContent(document: TodoDocument(items: LianxinPresentation.items(value, style: display)), appearance: LianxinPresentation.look(content: value, style: style),
            error: nil, family: family, interactive: false, textAlignment: display.centered ? .center : .leading, effectsFamily: effectsFamily,
            secondaryText: LianxinPresentation.secondaryTexts(value, style: display), summaryText: LianxinPresentation.subtitle(custom: style.lianxinCustomSubtitle, fallback: value.signatureSubtitle),
            annotations: LianxinPresentation.annotations(value, style: display), maximumLinesOverride: display.maximumLines == 0 ? Int.max : nil,
            secondaryScale: display.translationScale, secondaryOpacity: display.translationOpacity, alignsMarkerToFirstLine: false)
            .allowsHitTesting(false)
    }
}

// 背景也复用同一内容度量，居中蒙层不会因译文/署名高度与正文错位。
struct LianxinWidgetBackground: View {
    let content: LianxinPublication?
    let style: WidgetAppearance
    let family: WidgetPreviewFamily
    var date: Date = .now
    var preparedPhoto: CGImage?
    var preparedOnly = false
    var analyses: [String: ImageAnalysis]?
    var effectsFamily: WidgetFamily?
    var canvasAspect: Double?
    var margins = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    var body: some View {
        let value = content ?? LianxinPublication(idol: "连心", text: "打开连心，写下一句话。", photo: nil, date: .distantPast)
        let display = style.lianxinDisplay
        let readable = ReadableResolver.scrim(style: style, date: date, scheme: scheme, renderingMode: mode, family: effectsFamily ?? .systemSmall,
            canvasAspect: canvasAspect ?? family.width / family.height, preparedAnalyses: analyses)
        WidgetBackgroundView(style: style, date: date, preparedPhoto: preparedPhoto, preparedOnly: preparedOnly,
            scrim: readable.value, scrimAnchor: style.readable.anchor, scrimHeightRatio: style.readable.heightRatio,
            scrimColor: readable.color, scrimExtraInset: style.readable.edgeInset,
            contentDocument: TodoDocument(items: LianxinPresentation.items(value, style: display)), contentAppearance: LianxinPresentation.look(content: value, style: style),
            contentFamily: family, contentMargins: margins, effectsFamily: effectsFamily,
            contentSecondaryText: LianxinPresentation.secondaryTexts(value, style: display), contentSummaryText: LianxinPresentation.subtitle(custom: style.lianxinCustomSubtitle, fallback: value.signatureSubtitle),
            contentAnnotations: LianxinPresentation.annotations(value, style: display), contentMaximumLines: display.maximumLines == 0 ? Int.max : nil,
            contentSecondaryScale: display.translationScale, alignsMarkerToFirstLine: false)
    }
}
