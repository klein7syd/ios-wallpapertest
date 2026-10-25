import SwiftUI

extension WallpaperColor {
    var swiftColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

struct TodoMarkerView: View {
    let marker: TodoMarker
    let completed: Bool
    var style = MarkerStyle()
    var textColor: Color = .primary
    var maximumSize: Double = 28
    private var result: (marker: TodoMarker, opacity: Double, checked: Bool) { style.resolved(marker, completed: completed) }
    private var extent: Double { min(maximumSize, MarkerDrawing.extent(marker: marker, style: style, completed: completed)) }
    var body: some View {
        Group {
            if result.marker.kind == .emoji {
                Text(verbatim: result.marker.emoji).font(.system(size: extent))
                    .frame(width: extent, height: extent).minimumScaleFactor(0.7)
            } else if result.marker.kind != .none {
                let filled = result.marker.kind == .filled || result.marker.kind == .bordered
                let stroke = result.checked ? style.completedColor.swiftColor : style.followsTextColor ? textColor : style.stroke.swiftColor
                let fill = result.checked ? style.completedColor.swiftColor : style.followsTextColor ? textColor : style.fill.swiftColor
                ZStack {
                    RoundedRectangle(cornerRadius: result.marker.kind == .square ? 3 : extent / 2)
                        .fill(filled ? fill.opacity(result.marker.kind == .bordered && style.followsTextColor && !result.checked ? 0.15 : 1) : Color.clear)
                    RoundedRectangle(cornerRadius: result.marker.kind == .square ? 3 : extent / 2)
                        .strokeBorder(stroke, lineWidth: result.marker.kind == .thin ? style.lineWidth * 0.45 : min(style.lineWidth, 3))
                    if result.checked {
                        Image(systemName: "checkmark").font(.system(size: extent * 0.6, weight: .semibold))
                            .foregroundStyle(result.marker.kind == .filled ? Color.white : stroke)
                    }
                }.frame(width: extent, height: extent)
            }
        }.opacity(result.opacity)
            .offset(y: min(maximumSize / 4, max(-maximumSize / 4, style.verticalOffset)))
            .accessibilityHidden(true)
    }
}
