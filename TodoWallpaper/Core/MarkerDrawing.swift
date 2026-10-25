import Foundation
import CoreGraphics
import CoreText

enum MarkerDrawing {
    static func extent(marker: TodoMarker, style: MarkerStyle, completed: Bool) -> Double {
        let result = style.resolved(marker, completed: completed).marker
        return result.kind == .none ? 0 : result.kind == .emoji ? style.emojiSize : style.size
    }
    static func cgColor(_ color: WallpaperColor) -> CGColor {
        CGColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
    static func emojiLine(_ string: String, size: CGFloat) -> CTLine {
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, size, nil)
        let text = NSAttributedString(string: string, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        return CTLineCreateWithAttributedString(text as CFAttributedString)
    }
    static func draw(marker: TodoMarker, completed: Bool, style: MarkerStyle, textColor: WallpaperColor,
                     rect: CGRect, context: CGContext) {
        let result = style.resolved(marker, completed: completed)
        guard result.marker.kind != .none else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.setAlpha(result.opacity)
        if result.marker.kind == .emoji {
            let line = emojiLine(result.marker.emoji, size: rect.height)
            var ascent: CGFloat = 0, descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: rect.midX - width / 2, y: rect.midY - (ascent - descent) / 2)
            CTLineDraw(line, context)
            return
        }
        let kind = result.marker.kind
        let stroke = result.checked ? style.completedColor : style.followsTextColor ? textColor : style.stroke
        var fill = result.checked ? style.completedColor : style.followsTextColor ? textColor : style.fill
        if kind == .bordered && style.followsTextColor && !result.checked { fill.alpha *= 0.15 }
        let width: CGFloat = kind == .thin ? 0.7 : CGFloat(style.lineWidth)
        let inner = rect.insetBy(dx: width / 2, dy: width / 2)
        let radius: CGFloat = kind == .square ? 3 : inner.width / 2
        let path = CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if kind == .filled || kind == .bordered {
            context.setFillColor(cgColor(fill)); context.addPath(path); context.fillPath()
        }
        context.setStrokeColor(cgColor(stroke)); context.setLineWidth(width)
        context.addPath(path); context.strokePath()
        if result.checked {
            context.setStrokeColor(kind == .filled ? CGColor(gray: 1, alpha: 1) : cgColor(stroke))
            context.move(to: CGPoint(x: rect.minX + rect.width * 0.23, y: rect.midY))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.3))
            context.addLine(to: CGPoint(x: rect.minX + rect.width * 0.78, y: rect.minY + rect.height * 0.72))
            context.strokePath()
        }
    }
}
