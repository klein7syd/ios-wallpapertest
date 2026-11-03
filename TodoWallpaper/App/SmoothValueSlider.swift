import SwiftUI
import UIKit

// 原生滑块独立跟手，每个显示帧发布最新值，释放时提交最终值。
// CADisplayLink只取最新采样，不排队重放过期触控。
struct SmoothValueSlider: UIViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(value: $value, editing: onEditingChanged) }
    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider()
        slider.addTarget(context.coordinator, action: #selector(Coordinator.begin), for: .touchDown)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.end), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        return slider
    }
    func updateUIView(_ view: UISlider, context: Context) {
        context.coordinator.value = $value; context.coordinator.editing = onEditingChanged
        view.minimumValue = Float(range.lowerBound); view.maximumValue = Float(range.upperBound)
        if !view.isTracking && !context.coordinator.active { view.value = Float(value) }
    }
    static func dismantleUIView(_ view: UISlider, coordinator: Coordinator) { coordinator.end() }
    final class Coordinator: NSObject {
        var value: Binding<Double>
        var editing: (Bool) -> Void
        private(set) var active = false
        private var pending: Double?
        private var link: CADisplayLink?
        private let proxy = FrameProxy()
        init(value: Binding<Double>, editing: @escaping (Bool) -> Void) { self.value = value; self.editing = editing; super.init(); proxy.owner = self }
        @objc func begin() {
            guard !active else { return }
            active = true
            editing(true)
            let display = CADisplayLink(target: proxy, selector: #selector(FrameProxy.frame))
            display.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            display.add(to: .main, forMode: .common); link = display
        }
        @objc func changed(_ slider: UISlider) {
            pending = Double(slider.value)
            if !slider.isTracking { flush() } // VoiceOver and keyboard adjustments.
        }
        func publishPreview() {
            // 合并同一显示帧内的触控采样，不等待手指停顿。
            guard pending != nil else { return }
            flush()
        }

        func flush() {
            guard let next = pending else { return }
            pending = nil
            if Float(value.wrappedValue) != Float(next) {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { value.wrappedValue = next }
            }
        }
        @objc func end() {
            flush(); link?.invalidate(); link = nil
            if active { active = false; editing(false) }
        }
    }
    private final class FrameProxy: NSObject {
        weak var owner: Coordinator?
        @objc func frame() { owner?.publishPreview() }
    }
}
