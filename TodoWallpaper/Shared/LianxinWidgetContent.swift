// Target Membership：App + Widget。画面标注默认关闭，复制/分享另有强制后缀。
import SwiftUI
import WidgetKit

struct LianxinWidgetContent: View {
    let content: LianxinPublication?
    let style: WidgetAppearance
    let family: WidgetPreviewFamily
    var effectsFamily: WidgetFamily? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var mode
    @ScaledMetric(relativeTo: .caption2) private var labelSize = 10.0
    private var tone: ReadableTone { ReadableTone.resolve(style: style, scheme: scheme, renderingMode: mode, family: effectsFamily ?? .systemSmall) }
    private var look: TodoAppearance {
        var value = TodoAppearance(); value.defaultMarker = TodoMarker(kind: .none); value.widget = style
        value.widget.markerOverride = TodoMarker(kind: .none); value.widget.maximumItems = 1
        value.widget.showsFooter = false; value.widget.completedTextStyle = .keep
        var header = style.heading
        header.text = String((content?.idol ?? "连心").prefix(40)); header.showsSummary = false
        value.widget.header = header
        return value
    }
    var body: some View {
        VStack(alignment: style.lianxinCentered == true ? .center : .leading, spacing: 3) {
            TodoWidgetContent(document: TodoDocument(items: [item]), appearance: look, error: nil, family: family, interactive: false, textAlignment: style.lianxinCentered == true ? .center : .leading, effectsFamily: effectsFamily)
                .allowsHitTesting(false)
            if style.lianxinShowsSignature != false {
                Text(content?.idol ?? "连心").font(.system(size: labelSize)).lineLimit(1)
                    .foregroundStyle(tone.textColor).readableText(isLightText: tone.isLightText, intensity: style.readable.intensity, enabled: tone.enabled)
            }
            if style.lianxinShowsCreationLabel == true {
            Text(content?.contentLabel ?? "AI 创作").font(.system(size: labelSize)).lineLimit(2)
                .foregroundStyle(tone.textColor).readableText(isLightText: tone.isLightText, intensity: style.readable.intensity, enabled: tone.enabled)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    private var item: TodoItem {
        TodoItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            title: content?.text ?? "打开连心，写下一句话。", marker: TodoMarker(kind: .none), isCompleted: false,
            createdAt: .distantPast, updatedAt: .distantPast)
    }
}
