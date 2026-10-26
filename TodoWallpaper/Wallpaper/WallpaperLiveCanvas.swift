import SwiftUI
import UIKit

/// GPU transformed photos + clipped blur/tint layers. The small vector glyph view
/// reuses production Core Text/marker layout, and never creates a poster bitmap.
struct WallpaperLiveCanvas: View {
    @ObservedObject var model: WallpaperEditorModel
    var editsBackground: Bool
    var editable = true
    @Environment(\.editorInteraction) private var interaction
    @State private var activeGestures = Set<String>()
    @State private var startPan: CGPoint?
    @State private var startCenter: CGPoint?
    @State private var startZoom: Double?
    @State private var guideX = false
    @State private var guideY = false
    var body: some View {
        GeometryReader { proxy in
            let ratio = CGFloat(model.settings.aspectRatio)
            let width = min(proxy.size.width, proxy.size.height * ratio)
            let height = width / ratio
            let scale = width / 390
            ZStack(alignment: .topLeading) {
                if let template = model.layout {
                    let layout = template.positioned(using: model.settings)
                    let panel = layout.panel
                    background(scale: scale)
                    ZStack(alignment: .topLeading) {
                        background(scale: scale)
                            .blur(radius: CGFloat(model.settings.blurRadius) * scale)
                            .offset(x: -panel.minX * scale, y: -panel.minY * scale)
                            .frame(width: panel.width * scale, height: panel.height * scale, alignment: .topLeading)
                        Rectangle().fill((model.settings.darkGlass ? Color.black : Color.white).opacity(model.settings.glassOpacity))
                        LinearGradient(colors: [.white.opacity(model.settings.highlight), .clear], startPoint: .top, endPoint: .bottom)
                        WallpaperGlyphView(settings: model.settings, appearance: model.appearance, items: model.items, layout: template, scale: scale)
                            .frame(width: panel.width * scale, height: panel.height * scale)
                    }
                    .frame(width: panel.width * scale, height: panel.height * scale, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(model.settings.cornerRadius) * scale))
                    .overlay {
                        RoundedRectangle(cornerRadius: CGFloat(model.settings.cornerRadius) * scale)
                            .strokeBorder(.white.opacity(model.settings.borderOpacity), lineWidth: 0.8 * scale)
                    }
                    .offset(x: panel.minX * scale, y: panel.minY * scale)
                    if guideX { Rectangle().fill(.white.opacity(0.7)).frame(width: 0.6, height: height).position(x: width / 2, y: height / 2) }
                    if guideY { Rectangle().fill(.white.opacity(0.7)).frame(width: width, height: 0.6).position(x: width / 2, y: height / 2) }
                } else { ProgressView("正在读取画布").frame(width: width, height: height) }
            }
            .frame(width: max(1, width), height: max(1, height), alignment: .topLeading)
            .clipped().contentShape(Rectangle())
            .gesture(drag(width: width, height: height))
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                guard editable, editsBackground, model.hasPhoto, !model.busy else { return }
                if startZoom == nil { begin("zoom"); startZoom = model.settings.backgroundZoom }
                model.settings.backgroundZoom = min(4, max(1, (startZoom ?? 1) * Double(value)))
            }.onEnded { _ in startZoom = nil; end("zoom") })
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            .transaction { $0.animation = nil }
        }
    }
    @ViewBuilder private func background(scale: CGFloat) -> some View {
        let canvas = CGSize(width: 390, height: model.settings.logicalHeight)
        if let live = model.livePhoto {
            let frame = WallpaperRenderer.backgroundRect(source: CGSize(width: live.info.width, height: live.info.height), canvas: canvas, settings: model.settings)
            Image(decorative: live.image, scale: 1).resizable().interpolation(.high)
                .frame(width: frame.width * scale, height: frame.height * scale)
                .position(x: frame.midX * scale, y: frame.midY * scale)
                .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
        } else {
            LinearGradient(colors: [Color(white: 0.30), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
                .frame(width: canvas.width * scale, height: canvas.height * scale)
        }
    }
    private func drag(width: CGFloat, height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1).onChanged { value in
            guard editable, !model.busy, width > 0, height > 0 else { return }
            if editsBackground {
                guard let live = model.livePhoto else { return }
                if startPan == nil { begin("pan"); startPan = CGPoint(x: model.settings.backgroundPanX, y: model.settings.backgroundPanY) }
                guard let startPan else { return }
                let canvas = CGSize(width: 390, height: model.settings.logicalHeight)
                let frame = WallpaperRenderer.backgroundRect(source: CGSize(width: live.info.width, height: live.info.height), canvas: canvas, settings: model.settings)
                if frame.width > 390.01 {
                    let next = startPan.x + value.translation.width * 390 / width / ((frame.width - 390) / 2)
                    model.settings.backgroundPanX = Double(min(1, max(-1, next)))
                }
                if frame.height > canvas.height + 0.01 {
                    let next = startPan.y + value.translation.height * 390 / width / ((frame.height - canvas.height) / 2)
                    model.settings.backgroundPanY = Double(min(1, max(-1, next)))
                }
            } else {
                guard let layout = model.layout?.positioned(using: model.settings) else { return }
                if startCenter == nil {
                    let hit = CGPoint(x: value.startLocation.x / width * 390, y: value.startLocation.y / height * layout.canvas.height)
                    guard layout.panel.contains(hit) else { return }
                    begin("panel")
                    startCenter = CGPoint(x: layout.panel.midX / 390, y: layout.panel.midY / layout.canvas.height)
                    model.settings.customPosition = true
                }
                guard let startCenter else { return }
                var x = startCenter.x + value.translation.width / width
                var y = startCenter.y + value.translation.height / height
                guideX = abs(x - 0.5) * width < 3; guideY = abs(y - 0.5) * height < 3
                if guideX { x = 0.5 }; if guideY { y = 0.5 }
                model.settings.panelX = Double(min(1, max(0, x))); model.settings.panelY = Double(min(1, max(0, y)))
            }
        }.onEnded { _ in
            startPan = nil; startCenter = nil; guideX = false; guideY = false
            end("pan"); end("panel")
        }
    }
    private func begin(_ key: String) {
        if activeGestures.isEmpty { interaction.begin("canvas") }
        activeGestures.insert(key)
    }
    private func end(_ key: String) {
        guard activeGestures.remove(key) != nil else { return }
        if activeGestures.isEmpty { interaction.end() }
    }
}
private struct WallpaperGlyphView: UIViewRepresentable {
    let settings: WallpaperSettings
    let appearance: TodoAppearance
    let items: [TodoItem]
    let layout: WallpaperLayout
    let scale: CGFloat
    func makeUIView(context: Context) -> GlyphUIView {
        let view = GlyphUIView(); view.isOpaque = false; view.backgroundColor = .clear
        view.clipsToBounds = true
        view.contentMode = .redraw; view.isUserInteractionEnabled = false; return view
    }
    func updateUIView(_ view: GlyphUIView, context: Context) {
        let changed = view.settings?.glyphKey != settings.glyphKey || view.appearance != appearance || view.items != items || view.scale != scale
        view.settings = settings; view.appearance = appearance; view.items = items; view.layout = layout; view.scale = scale
        if changed { view.setNeedsDisplay() }
    }
}
private final class GlyphUIView: UIView {
    var settings: WallpaperSettings?
    var appearance = TodoAppearance()
    var items: [TodoItem] = []
    var layout: WallpaperLayout?
    var scale: CGFloat = 1
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let settings, let layout else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -layout.panel.minX, y: -(layout.canvas.height - layout.panel.maxY))
        WallpaperRenderer.drawContent(layout: layout, settings: settings, appearance: appearance, context: context)
    }
}
