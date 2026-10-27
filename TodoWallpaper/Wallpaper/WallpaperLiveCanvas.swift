import SwiftUI
import UIKit

/// The live canvas is a retained layer tree. Gesture callbacks move existing
/// textures and the panel; only a finished gesture commits one editor state.
struct WallpaperLiveCanvas: View {
    @ObservedObject var model: WallpaperEditorModel
    var editsBackground: Bool
    var editable = true
    @Environment(\.editorInteraction) private var interaction
    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * model.settings.aspectRatio)
            WallpaperLayerSurface(model: model, editsBackground: editsBackground, editable: editable, interaction: interaction)
                .frame(width: max(1, width), height: max(1, width / model.settings.aspectRatio))
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}
private struct WallpaperLayerSurface: UIViewRepresentable {
    @ObservedObject var model: WallpaperEditorModel
    let editsBackground: Bool
    let editable: Bool
    let interaction: EditorInteractionContext
    func makeUIView(context: Context) -> WallpaperLayerView { WallpaperLayerView() }
    func updateUIView(_ view: WallpaperLayerView, context: Context) {
        guard !view.isTracking else { return }
        view.settings = model.settings; view.template = model.layout
        view.backgroundMode = editsBackground; view.editingEnabled = editable && !model.busy
        view.setPhoto(model.livePhoto?.image)
        view.crop = PhotoCrop(zoom: model.settings.backgroundZoom, panX: model.settings.backgroundPanX, panY: model.settings.backgroundPanY)
        view.blurLayer.contents = model.liveBlurPhoto?.image ?? model.livePhoto?.image
        view.glyphs.configure(settings: model.settings, appearance: model.appearance, layout: model.layout)
        view.onBegin = { interaction.begin("canvas") }
        view.onFinish = { [weak view] crop in
            guard let view else { interaction.end(); return }
            var next = view.settings
            next.backgroundZoom = crop.zoom; next.backgroundPanX = crop.panX; next.backgroundPanY = crop.panY
            model.settings = next
            interaction.end()
        }
        view.updateLayers()
    }
}
private final class WallpaperLayerView: PhotoMotionView {
    var settings = WallpaperSettings()
    var template: WallpaperLayout?
    var backgroundMode = true
    let panel = UIView()
    let blurLayer = CALayer()
    let tintLayer = CALayer()
    let highlightLayer = CAGradientLayer()
    let glyphs = WallpaperGlyphUIView()
    private var panelStart: WallpaperSettings?
    override init(frame: CGRect) {
        super.init(frame: frame)
        panel.isUserInteractionEnabled = false; panel.clipsToBounds = true
        panel.layer.addSublayer(blurLayer); panel.layer.addSublayer(tintLayer); panel.layer.addSublayer(highlightLayer)
        panel.addSubview(glyphs); addSubview(panel)
        panel.layer.cornerCurve = .continuous; blurLayer.contentsGravity = .resize
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func updateLayers() {
        super.updateLayers()
        guard let template, bounds.width > 0 else { panel.isHidden = true; return }
        panel.isHidden = false
        let positioned = template.positioned(using: settings)
        let scale = bounds.width / 390
        let rect = positioned.panel.applying(CGAffineTransform(scaleX: scale, y: scale))
        withoutLayerAnimation {
            panel.frame = rect; panel.layer.cornerRadius = settings.cornerRadius * scale
            panel.layer.borderColor = UIColor.white.withAlphaComponent(settings.borderOpacity).cgColor
            panel.layer.borderWidth = 0.8 * scale
            blurLayer.isHidden = image == nil
            blurLayer.frame = imageLayer.frame.offsetBy(dx: -rect.minX, dy: -rect.minY)
            tintLayer.frame = panel.bounds
            tintLayer.backgroundColor = (settings.darkGlass ? UIColor.black : .white).withAlphaComponent(settings.glassOpacity).cgColor
            highlightLayer.frame = panel.bounds
            highlightLayer.colors = [UIColor.white.withAlphaComponent(settings.highlight).cgColor, UIColor.clear.cgColor]
            glyphs.frame = panel.bounds; glyphs.drawScale = scale
        }
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard editingEnabled else { return false }
        if backgroundMode { return image != nil }
        return gestureRecognizer === panRecognizer && panel.frame.contains(gestureRecognizer.location(in: self))
    }
    override func panGesture(_ gesture: UIPanGestureRecognizer) {
        if backgroundMode { super.panGesture(gesture); return }
        if gesture.state == .began { panelStart = settings; begin(gesture) }
        if gesture.state == .changed || gesture.state == .began, let template {
            let delta = gesture.translation(in: self)
            let rect = template.positioned(using: settings).panel
            settings.customPosition = true
            var x = rect.midX / 390 + delta.width / max(1, bounds.width)
            var y = rect.midY / template.canvas.height + delta.height / max(1, bounds.height)
            if abs(x - 0.5) * bounds.width < 3 { x = 0.5 }
            if abs(y - 0.5) * bounds.height < 3 { y = 0.5 }
            settings.panelX = min(1, max(0, x)); settings.panelY = min(1, max(0, y))
            gesture.setTranslation(.zero, in: self); updateLayers()
        }
        if [.ended, .cancelled, .failed].contains(gesture.state) {
            if gesture.state != .ended, let panelStart { settings = panelStart }
            finish(gesture); panelStart = nil
        }
    }
}
private final class WallpaperGlyphUIView: UIView {
    private var settings: WallpaperSettings?
    private var appearance = TodoAppearance()
    private var template: WallpaperLayout?
    var drawScale: CGFloat = 1 { didSet { if abs(oldValue - drawScale) > 0.0001 { setNeedsDisplay() } } }
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        isUserInteractionEnabled = false; clipsToBounds = true; contentMode = .redraw
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(settings: WallpaperSettings, appearance: TodoAppearance, layout: WallpaperLayout?) {
        let changed = self.settings?.glyphKey != settings.glyphKey || self.appearance.defaultMarker != appearance.defaultMarker ||
            self.appearance.markerStyle != appearance.markerStyle || self.template?.rows.map(\.item) != layout?.rows.map(\.item)
        self.settings = settings; self.appearance = appearance; template = layout
        if changed { setNeedsDisplay() }
    }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext(), let settings, let template else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: drawScale, y: -drawScale)
        context.translateBy(x: -template.panel.minX, y: -(template.canvas.height - template.panel.maxY))
        WallpaperRenderer.drawContent(layout: template, settings: settings, appearance: appearance, context: context)
    }
}
