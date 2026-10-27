import Foundation

/// In-memory editing history. It never stores tasks, credentials or image bytes.
/// A continuous gesture owns a group; discrete controls remain separate steps.
struct EditorHistory<Value: Equatable> {
    struct Step: Equatable {
        let before: Value
        var after: Value
        let group: UUID?
    }
    private(set) var current: Value?
    private(set) var steps: [Step] = []
    private var group: UUID?
    let limit: Int
    init(limit: Int = 50) { self.limit = max(1, limit) }
    var previous: Step? { steps.last }
    var canUndo: Bool { !steps.isEmpty }
    mutating func synchronize(_ value: Value) {
        guard value != current else { return }
        current = value; steps.removeAll(); group = nil
    }
    mutating func beginInteraction() { group = UUID() }
    mutating func endInteraction() { group = nil }
    mutating func observe(_ next: Value) {
        guard let before = current else { current = next; return }
        guard next != before else { return }
        if let group, let last = steps.last, last.group == group, last.after == before {
            steps[steps.count - 1].after = next
            if steps.last?.before == next { steps.removeLast() }
        } else {
            steps.append(Step(before: before, after: next, group: group))
            if steps.count > limit { steps.removeFirst(steps.count - limit) }
        }
        current = next
    }
    /// Call only after the caller has successfully applied the previous state.
    mutating func acceptUndo(_ step: Step) {
        guard steps.last == step else { return }
        steps.removeLast(); current = step.before; group = nil
    }
}

enum EditorStandards {
    static let advancedKey = "editor.advancedControls.v1"
    static let previewScaleKey = "editor.wallpaperPreviewScale.v1"
    static let wallpaperScale: ClosedRange<Double> = (10.0 / 18)...(38.0 / 18)
    static let widgetScale: ClosedRange<Double> = 0.8...(20.0 / 15)
    static func fraction(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite, range.upperBound > range.lowerBound else { return 0 }
        return min(1, max(0, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }
    static func marker(_ current: MarkerStyle, scale: Double) -> MarkerStyle {
        var next = current
        let s = min(wallpaperScale.upperBound, max(wallpaperScale.lowerBound, scale.isFinite ? scale : 1))
        next.size = 18 * s; next.emojiSize = 22 * s; next.gap = 10 * s
        next.lineWidth = 1.5 * s; next.verticalOffset = 0
        return next
    }
    static func widget(_ current: WidgetAppearance, scale: Double) -> WidgetAppearance {
        var next = current
        let s = min(widgetScale.upperBound, max(widgetScale.lowerBound, scale.isFinite ? scale : 1))
        next.fontSize = 15 * s; next.spacing = 5 * s
        next.markerStyle = marker(current.markerStyle, scale: s)
        return next
    }
}

/// Hysteresis prevents chatter at the standard point while keeping motion continuous
/// outside a narrow 4-point track region. Numeric entry remains exact and unsnapped.
struct StandardDetent {
    private(set) var isLatched = false
    mutating func reset() { isLatched = false }
    mutating func value(_ proposed: Double, standard: Double, range: ClosedRange<Double>, trackWidth: Double) -> Double {
        let bounded = proposed.isFinite ? min(range.upperBound, max(range.lowerBound, proposed)) : standard
        let unitsPerPoint = (range.upperBound - range.lowerBound) / max(80, trackWidth - 28)
        let distance = abs(bounded - standard)
        isLatched = distance <= unitsPerPoint * (isLatched ? 7 : 4)
        return isLatched ? standard : bounded
    }
}

struct TodoMarkerUpdate {
    let id: UUID
    let expected: TodoMarker?
    let marker: TodoMarker?
}
