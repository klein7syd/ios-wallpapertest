import SwiftUI
import UIKit

/// Interactive motion stays in Core Animation. No SwiftUI bindings, image decoding,
/// file writes or poster rendering occur between recognizer begin and end.
class PhotoMotionView: UIView, UIGestureRecognizerDelegate {
    let imageLayer = CALayer()
    let fallbackLayer = CAGradientLayer()
    private(set) var image: CGImage?
    var crop = PhotoCrop()
    var editingEnabled = true
    var onBegin: () -> Void = { }
    var onFinish: (PhotoCrop) -> Void = { _ in }
    private var active = Set<ObjectIdentifier>()
    private var initialCrop = PhotoCrop()
    private var cancelled = false
    var isTracking: Bool { !active.isEmpty }
    lazy var panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(panGesture(_:)))
    lazy var pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(pinchGesture(_:)))
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        fallbackLayer.colors = [UIColor(white: 0.30, alpha: 1).cgColor, UIColor(white: 0.08, alpha: 1).cgColor]
        layer.addSublayer(fallbackLayer); layer.addSublayer(imageLayer)
        imageLayer.contentsGravity = .resize
        panRecognizer.delegate = self; pinchRecognizer.delegate = self
        addGestureRecognizer(panRecognizer); addGestureRecognizer(pinchRecognizer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setPhoto(_ photo: CGImage?) {
        guard image !== photo else { return }
        image = photo; imageLayer.contents = photo
    }
    override func layoutSubviews() { super.layoutSubviews(); updateLayers() }
    func withoutLayerAnimation(_ work: () -> Void) {
        CATransaction.begin(); CATransaction.setDisableActions(true); work(); CATransaction.commit()
    }
    func updateLayers() {
        withoutLayerAnimation {
            fallbackLayer.frame = bounds
            if let image { imageLayer.frame = crop.frame(source: CGSize(width: image.width, height: image.height), canvas: bounds.size) }
        }
    }
    func begin(_ gesture: UIGestureRecognizer) {
        if active.isEmpty { initialCrop = crop; cancelled = false; onBegin() }
        active.insert(ObjectIdentifier(gesture))
    }
    func finish(_ gesture: UIGestureRecognizer) {
        if gesture.state == .cancelled || gesture.state == .failed { cancelled = true }
        active.remove(ObjectIdentifier(gesture))
        guard active.isEmpty else { return }
        if cancelled { crop = initialCrop; updateLayers() }
        onFinish(crop)
    }
    @objc func panGesture(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .began { begin(gesture) }
        if gesture.state == .changed || gesture.state == .began, let image {
            let translation = gesture.translation(in: self)
            crop.pan(by: CGSize(width: translation.x, height: translation.y), source: CGSize(width: image.width, height: image.height), canvas: bounds.size)
            gesture.setTranslation(.zero, in: self); updateLayers()
        }
        if [.ended, .cancelled, .failed].contains(gesture.state) { finish(gesture) }
    }
    @objc func pinchGesture(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began { begin(gesture) }
        if gesture.state == .changed || gesture.state == .began {
            crop.zoom = min(4, max(1, crop.zoom * Double(gesture.scale))); gesture.scale = 1; updateLayers()
        }
        if [.ended, .cancelled, .failed].contains(gesture.state) { finish(gesture) }
    }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { editingEnabled && image != nil }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
struct WidgetPhotoMotionSurface: UIViewRepresentable {
    let image: CGImage
    @Binding var crop: PhotoCrop
    let opacity: Double
    let background: UIColor
    @Environment(\.editorInteraction) private var interaction
    func makeUIView(context: Context) -> PhotoMotionView { PhotoMotionView() }
    func updateUIView(_ view: PhotoMotionView, context: Context) {
        guard !view.isTracking else { return }
        view.setPhoto(image); view.crop = crop
        view.fallbackLayer.colors = [background.cgColor, background.cgColor]
        view.imageLayer.opacity = Float(opacity)
        view.onBegin = { interaction.begin("widget.photo.crop") }
        view.onFinish = { next in crop = next; interaction.end() }
        view.updateLayers()
    }
}
