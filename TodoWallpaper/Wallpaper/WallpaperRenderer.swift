import Foundation
import CoreGraphics
import CoreText
import CoreImage
import ImageIO
import UniformTypeIdentifiers

struct WallpaperPhotoInfo: Sendable {
    let width: Int
    let height: Int
    var label: String { "\(width) × \(height)" }
}
struct WallpaperTextBlock {
    let lines: [CTLine]
    let font: CTFont
    let ascent: CGFloat
    let height: CGFloat
    let lineAdvance: CGFloat
    let truncated: Bool
}
struct WallpaperRow {
    let item: TodoItem
    let block: WallpaperTextBlock
    let top: CGFloat
    let marker: TodoMarker
    let markerTop: CGFloat
    let markerSize: CGFloat
}
struct WallpaperSupplement {
    let block: WallpaperTextBlock
    let top: CGFloat
}
struct WallpaperLayout {
    let canvas: CGSize
    let panel: CGRect
    let markerColumn: CGFloat
    let textWidth: CGFloat
    let rows: [WallpaperRow]
    let hiddenCount: Int
    let footer: WallpaperTextBlock?
    let footerTop: CGFloat
    let emptyText: WallpaperTextBlock?
    let emptyTop: CGFloat
    var supplements: [WallpaperSupplement] = []
    var lianxinOverflow = false
}
struct WallpaperRendered {
    let image: CGImage
    let layout: WallpaperLayout
    let sourceInfo: WallpaperPhotoInfo?
    let sourceIsSoft: Bool
}

/// Shared by preview, PNG export and executable macOS rendering checks.
/// Core Text shapes Unicode and Core Image blurs the cropped background. No screenshot
/// enlargement, SwiftUI material snapshot, saturation filter or web content is used.
enum WallpaperRenderer {
    static let logicalWidth: CGFloat = 390

    static func color(_ value: WallpaperColor, opacity: Double = 1) -> CGColor {
        CGColor(srgbRed: value.red, green: value.green, blue: value.blue, alpha: value.alpha * opacity)
    }

    static func effectiveTextColor(_ settings: WallpaperSettings) -> WallpaperColor {
        // In an almost opaque panel the background is known. Protect a mistaken
        // black-on-black or white-on-white choice without altering saved colors.
        guard settings.glassOpacity >= 0.75 else { return settings.textColor }
        return TextLegibility.readable(settings.textColor, on: settings.darkGlass ? WallpaperColor(red: 0, green: 0, blue: 0) : WallpaperColor())
    }

    static func font(_ settings: WallpaperSettings, size: CGFloat? = nil) -> CTFont {
        NativeTypography.font(family: settings.font, weight: settings.weight, size: size ?? CGFloat(settings.fontSize))
    }

    static func text(_ title: String, width: CGFloat, settings: WallpaperSettings,
                     opacity: Double = 1, size: CGFloat? = nil, maxLines: Int? = nil) -> WallpaperTextBlock {
        let chosenFont = font(settings, size: size)
        let attributed = NSAttributedString(string: title, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): chosenFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(effectiveTextColor(settings), opacity: opacity)
        ])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
        let length = attributed.length
        let limit = maxLines ?? settings.maximumLines
        var offset = 0
        var lines: [CTLine] = []
        var truncated = false
        while offset < length && lines.count < limit {
            let suggested = CTTypesetterSuggestLineBreak(typesetter, offset, Double(max(1, width)))
            let fallback = (title as NSString).rangeOfComposedCharacterSequence(at: offset).length
            let count = min(length - offset, suggested > 0 ? suggested : fallback)
            if lines.count == limit - 1 && offset + count < length {
                let tail = attributed.attributedSubstring(from: NSRange(location: offset, length: length - offset))
                let flat = NSMutableAttributedString(attributedString: tail)
                _ = flat.mutableString.replaceOccurrences(of: "\n", with: " ", range: NSRange(location: 0, length: flat.length))
                let candidate = CTLineCreateWithAttributedString(flat as CFAttributedString)
                let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…",
                    attributes: attributed.attributes(at: offset, effectiveRange: nil)) as CFAttributedString)
                lines.append(CTLineCreateTruncatedLine(candidate, Double(max(1, width)), .end, token) ?? token)
                truncated = true
                offset = length
            } else {
                lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: offset, length: count)))
                offset += count
            }
        }
        // Measure fallback glyphs as well (Chinese, emoji, combining marks).
        var ascent = CTFontGetAscent(chosenFont), descent = CTFontGetDescent(chosenFont)
        var leading = CTFontGetLeading(chosenFont)
        for line in lines {
            var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &a, &d, &l)
            ascent = max(ascent, a); descent = max(descent, d); leading = max(leading, l)
        }
        let natural = ceil(ascent + descent + leading)
        let advance: CGFloat = natural + CGFloat(settings.lineSpacing)
        return WallpaperTextBlock(lines: lines, font: chosenFont, ascent: ascent,
            height: lines.isEmpty ? 0 : natural + CGFloat(lines.count - 1) * advance,
            lineAdvance: advance, truncated: truncated)
    }

    static func layout(settings raw: WallpaperSettings, items: [TodoItem], appearance: TodoAppearance = TodoAppearance(), content: LianxinPublication? = nil) throws -> WallpaperLayout {
        let settings = try raw.validated()
        let canvas = CGSize(width: logicalWidth, height: settings.logicalHeight)
        let margin: CGFloat = 8
        let panelWidth: CGFloat = canvas.width * CGFloat(settings.panelWidth)
        let padding: CGFloat = min(CGFloat(settings.padding), max(8, (panelWidth - 50) / 2))
        let visibleItems = Array(settings.filtered(items).prefix(settings.maximumItems))
        let markerStyle = appearance.markerStyle
        let markerWidth = visibleItems.map { MarkerDrawing.extent(marker: settings.marker(for: $0, appearance: appearance), style: markerStyle, completed: false) }.max() ?? 0
        let markerColumn: CGFloat = markerWidth > 0 ? CGFloat(markerWidth + markerStyle.gap) : 0
        let textWidth: CGFloat = max(12, panelWidth - 2 * padding - markerColumn)
        let itemSpacing = CGFloat(settings.itemSpacing)
        let filtered = settings.filtered(items)
        let candidates = Array(filtered.prefix(settings.maximumItems))
        var blocks: [(TodoItem, WallpaperTextBlock)] = []
        for item in candidates {
            // 连心只受面板实际高度限制，不使用待办每项行数上限。
            blocks.append((item, text(item.title, width: textWidth, settings: settings, maxLines: content == nil ? nil : max(1, item.title.utf16.count))))
        }
        var supplementBlocks: [WallpaperTextBlock] = []
        if let content {
            if appearance.widget.lianxinShowsSignature != false {
                supplementBlocks.append(text(content.idol, width: textWidth, settings: settings, opacity: 0.8, size: min(13, settings.fontSize), maxLines: 8))
            }
            if settings.lianxinShowsCreationLabel == true {
                supplementBlocks.append(text(content.contentLabel, width: textWidth, settings: settings, opacity: 0.7, size: min(11, settings.fontSize), maxLines: 8))
            }
        }
        let supplementHeight = supplementBlocks.reduce(CGFloat.zero) { $0 + $1.height + 4 }
        let empty = filtered.isEmpty ? text(items.isEmpty ? "还没有待办" : "今天的待办都完成了",
            width: panelWidth - 2 * padding, settings: settings, maxLines: 3) : nil
        let reserveFooter = text("另有 \(max(1, filtered.count)) 项未显示", width: panelWidth - 2 * padding,
            settings: settings, opacity: 0.7, size: min(13, settings.fontSize), maxLines: 2)
        func rowMetrics(_ pair: (TodoItem, WallpaperTextBlock)) -> (height: CGFloat, textOffset: CGFloat, markerOffset: CGFloat, extent: CGFloat) {
            let extent = CGFloat(MarkerDrawing.extent(marker: settings.marker(for: pair.0, appearance: appearance), style: markerStyle, completed: false))
            let lineHeight = pair.1.ascent + CTFontGetDescent(pair.1.font)
            let textOffset = max(0, (extent - lineHeight) / 2) + max(0, -CGFloat(markerStyle.verticalOffset))
            let markerOffset = max(0, (lineHeight - extent) / 2) + max(0, CGFloat(markerStyle.verticalOffset))
            return (max(pair.1.height + textOffset, extent + markerOffset), textOffset, markerOffset, extent)
        }
        var allHeight: CGFloat = 0
        for pair in blocks { allHeight += rowMetrics(pair).height }
        allHeight += CGFloat(max(0, blocks.count - 1)) * itemSpacing
        let contentHeight: CGFloat = (empty?.height ?? allHeight) + supplementHeight
        let footerHeight: CGFloat = filtered.count > candidates.count ? reserveFooter.height + 12 : 0
        let naturalHeight: CGFloat = contentHeight + padding * 2 + footerHeight
        let requestedHeight: CGFloat = settings.automaticHeight ? naturalHeight : canvas.height * CGFloat(settings.panelHeight)
        let height: CGFloat = min(canvas.height - margin * 2, max(padding * 2 + 28, requestedHeight))
        let desiredX: CGFloat = CGFloat(settings.customPosition ? settings.panelX : 0.5) * canvas.width
        let desiredY: CGFloat = CGFloat(settings.customPosition ? settings.panelY : 0.5) * canvas.height
        let x = min(canvas.width - panelWidth - margin, max(margin, desiredX - panelWidth / 2))
        let y = min(canvas.height - height - margin, max(margin, desiredY - height / 2))
        let panel = CGRect(x: x, y: y, width: panelWidth, height: height)
        let usable = max(0, height - 2 * padding)
        var rows: [WallpaperRow] = []
        var used: CGFloat = 0
        for (index, pair) in blocks.enumerated() {
            let spacing: CGFloat = rows.isEmpty ? 0 : itemSpacing
            let reserve: CGFloat = (filtered.count > index + 1 ? reserveFooter.height + 12 : 0) + supplementHeight
            let metrics = rowMetrics(pair)
            guard used + spacing + metrics.height + reserve <= usable + 0.01 else { break }
            used += spacing
            let top = panel.minY + padding + used
            rows.append(WallpaperRow(item: pair.0, block: pair.1, top: top + metrics.textOffset,
                marker: settings.marker(for: pair.0, appearance: appearance), markerTop: top + metrics.markerOffset, markerSize: metrics.extent))
            used += metrics.height
        }
        let hidden = max(0, filtered.count - rows.count)
        var footer = hidden > 0 && reserveFooter.height <= usable ?
            text(rows.isEmpty ? "面板空间不足，另有 \(hidden) 项" : "另有 \(hidden) 项未显示",
                 width: panelWidth - 2 * padding, settings: settings, opacity: 0.7,
                 size: min(13, settings.fontSize), maxLines: 2) : nil
        if let candidate = footer, candidate.height > usable {
            footer = text("另有 \(hidden) 项", width: panelWidth - 2 * padding,
                settings: settings, opacity: 0.7, size: 11, maxLines: 1)
        }
        let fittedEmpty = empty.map { block in
            block.height <= usable ? block : text("暂无可显示事项", width: panelWidth - 2 * padding,
                settings: settings, size: 11, maxLines: 1)
        }
        var supplements: [WallpaperSupplement] = []
        for block in supplementBlocks where hidden == 0 {
            used += 4
            supplements.append(WallpaperSupplement(block: block, top: panel.minY + padding + used)); used += block.height
        }
        return WallpaperLayout(canvas: canvas, panel: panel, markerColumn: markerColumn, textWidth: textWidth, rows: rows,
            hiddenCount: hidden, footer: content == nil ? footer : nil, footerTop: panel.maxY - padding - (footer?.height ?? 0),
            emptyText: fittedEmpty, emptyTop: panel.minY + padding, supplements: supplements,
            lianxinOverflow: content != nil && (hidden > 0 || rows.isEmpty || blocks.contains { $0.1.truncated } || supplementBlocks.contains { $0.truncated }))
    }

    static func photoInfo(at url: URL) throws -> WallpaperPhotoInfo {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? NSNumber,
              let h = props[kCGImagePropertyPixelHeight] as? NSNumber,
              w.intValue > 0, h.intValue > 0 else { throw WallpaperError.unreadablePhoto }
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation) ?
            WallpaperPhotoInfo(width: h.intValue, height: w.intValue) : WallpaperPhotoInfo(width: w.intValue, height: h.intValue)
    }

    static func backgroundRect(source: CGSize, canvas: CGSize, settings: WallpaperSettings) -> CGRect {
        let scale: CGFloat = max(canvas.width / source.width, canvas.height / source.height) * CGFloat(settings.backgroundZoom)
        let w = source.width * scale, h = source.height * scale
        return CGRect(x: (canvas.width - w) / 2 + CGFloat(settings.backgroundPanX) * (w - canvas.width) / 2,
                      y: (canvas.height - h) / 2 + CGFloat(settings.backgroundPanY) * (h - canvas.height) / 2,
                      width: w, height: h)
    }

    static func bitmap(width: Int, height: Int) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        else { throw WallpaperError.renderingFailed }
        context.interpolationQuality = .high
        return context
    }

    static func native(_ rect: CGRect, height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func render(settings raw: WallpaperSettings, items: [TodoItem], photoURL: URL?,
                       previewWidth: Int? = nil, ciContext: CIContext, appearance: TodoAppearance = TodoAppearance(), assetDirectory: URL? = nil, content: LianxinPublication? = nil) throws -> WallpaperRendered {
        let settings = try raw.validated()
        let layout = try layout(settings: settings, items: items, appearance: appearance, content: content)
        let pixelWidth = min(settings.size.width, previewWidth ?? settings.size.width)
        let pixelHeight = previewWidth == nil ? settings.size.height :
            Int((Double(pixelWidth) / settings.aspectRatio).rounded())
        let scale = max(CGFloat(pixelWidth) / logicalWidth, CGFloat(pixelHeight) / layout.canvas.height)
        let canvasOffset = CGPoint(x: (CGFloat(pixelWidth) - layout.canvas.width * scale) / 2,
                                   y: (CGFloat(pixelHeight) - layout.canvas.height * scale) / 2)
        let background = try bitmap(width: pixelWidth, height: pixelHeight)
        background.translateBy(x: canvasOffset.x, y: canvasOffset.y)
        background.scaleBy(x: scale, y: scale)
        let canvasRect = CGRect(origin: .zero, size: layout.canvas)
        // Transparent source PNGs also receive an opaque wallpaper backdrop.
        background.setFillColor(CGColor(gray: 0.12, alpha: 1))
        background.fill(canvasRect)
        var sourceInfo: WallpaperPhotoInfo?
        var soft = false
        if let photoURL {
            let info = try photoInfo(at: photoURL)
            sourceInfo = info
            let needed = max(Double(pixelWidth) / Double(info.width),
                             Double(pixelHeight) / Double(info.height)) * settings.backgroundZoom
            let targetLongEdge = min(6144, max(1, Int(ceil(Double(max(info.width, info.height)) * needed))))
            guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: targetLongEdge,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
            let frame = backgroundRect(source: CGSize(width: image.width, height: image.height),
                                       canvas: layout.canvas, settings: settings)
            background.draw(image, in: native(frame, height: layout.canvas.height))
            let fullNeed = max(Double(settings.size.width) / Double(info.width),
                               Double(settings.size.height) / Double(info.height)) * settings.backgroundZoom
            soft = fullNeed > 1.01 || Double(max(info.width, info.height)) * fullNeed > 6144
        } else {
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let gradient = CGGradient(colorsSpace: space,
                    colors: [CGColor(gray: 0.30, alpha: 1), CGColor(gray: 0.08, alpha: 1)] as CFArray,
                    locations: [0, 1]) else { throw WallpaperError.renderingFailed }
            background.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvasRect.maxY), end: .zero, options: [])
        }
        guard let backgroundImage = background.makeImage() else { throw WallpaperError.renderingFailed }
        let context = try bitmap(width: pixelWidth, height: pixelHeight)
        context.draw(backgroundImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.translateBy(x: canvasOffset.x, y: canvasOffset.y)
        context.scaleBy(x: scale, y: scale)
        let panel = native(layout.panel, height: layout.canvas.height)
        let radius: CGFloat = min(CGFloat(settings.cornerRadius), min(panel.width, panel.height) / 2)
        let path = CGPath(roundedRect: panel, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.addPath(path); context.clip()
        if settings.blurRadius > 0 {
            let input = CIImage(cgImage: backgroundImage)
            let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: CGFloat(settings.blurRadius) * scale]).cropped(to: input.extent)
            guard let blurImage = ciContext.createCGImage(blurred, from: input.extent)
            else { throw WallpaperError.renderingFailed }
            context.saveGState()
            context.scaleBy(x: 1 / scale, y: 1 / scale)
            context.translateBy(x: -canvasOffset.x, y: -canvasOffset.y)
            context.draw(blurImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            context.restoreGState()
        }
        context.setFillColor(CGColor(gray: settings.darkGlass ? 0 : 1, alpha: settings.glassOpacity))
        context.fill(panel)
        if settings.highlight > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
           let highlight = CGGradient(colorsSpace: space,
                colors: [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: settings.highlight)] as CFArray,
                locations: [0, 1]) {
            context.drawLinearGradient(highlight, start: CGPoint(x: panel.midX, y: panel.minY),
                end: CGPoint(x: panel.midX, y: panel.maxY), options: [])
        }
        context.restoreGState()
        if settings.borderOpacity > 0 {
            context.setStrokeColor(CGColor(gray: 1, alpha: settings.borderOpacity)); context.setLineWidth(0.8)
            context.addPath(CGPath(roundedRect: panel.insetBy(dx: 0.4, dy: 0.4),
                cornerWidth: max(0, radius - 0.4), cornerHeight: max(0, radius - 0.4), transform: nil))
            context.strokePath()
        }
        context.saveGState(); context.addPath(path); context.clip()
        drawContent(layout: layout, settings: settings, appearance: appearance, context: context, assetDirectory: assetDirectory)
        context.restoreGState()
        guard let image = context.makeImage() else { throw WallpaperError.renderingFailed }
        return WallpaperRendered(image: image, layout: layout, sourceInfo: sourceInfo, sourceIsSoft: soft)
    }

    static func drawContent(layout: WallpaperLayout, settings: WallpaperSettings,
                            appearance: TodoAppearance, context: CGContext, assetDirectory: URL? = nil) {
        context.saveGState()
        let panel = native(layout.panel, height: layout.canvas.height)
        context.clip(to: panel)
        let padding: CGFloat = min(CGFloat(settings.padding), max(8, (panel.width - 50) / 2))
        let textColor = effectiveTextColor(settings)
        for row in layout.rows {
            let placement = rowPlacement(row, layout: layout, settings: settings)
            let rect = CGRect(x: placement.markerX, y: layout.canvas.height - row.markerTop - row.markerSize,
                              width: row.markerSize, height: row.markerSize)
            MarkerDrawing.draw(marker: row.marker, completed: false, style: appearance.markerStyle,
                               textColor: textColor, rect: rect, context: context, assetDirectory: assetDirectory)
            drawText(row.block, in: context, x: placement.textX, top: row.top,
                width: placement.textWidth, canvasHeight: layout.canvas.height, alignment: settings.alignment)
        }
        if let empty = layout.emptyText {
            drawText(empty, in: context, x: panel.minX + padding, top: layout.emptyTop,
                width: panel.width - 2 * padding, canvasHeight: layout.canvas.height, alignment: settings.alignment)
        }
        if let footer = layout.footer {
            drawText(footer, in: context, x: panel.minX + padding, top: layout.footerTop,
                width: panel.width - 2 * padding, canvasHeight: layout.canvas.height, alignment: settings.alignment)
        }
        for supplement in layout.supplements {
            drawText(supplement.block, in: context, x: panel.minX + padding, top: supplement.top,
                width: panel.width - 2 * padding, canvasHeight: layout.canvas.height, alignment: settings.alignment)
        }
        context.restoreGState()
    }

    /// Align the marker and its text as a group. Aligning text alone inside a
    /// shrinking column cancels gap changes in trailing alignment.
    static func rowPlacement(_ row: WallpaperRow, layout: WallpaperLayout, settings: WallpaperSettings)
        -> (markerX: CGFloat, textX: CGFloat, textWidth: CGFloat) {
        let padding = min(CGFloat(settings.padding), max(8, (layout.panel.width - 50) / 2))
        let measured = row.block.lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        let textWidth = min(layout.textWidth, max(1, ceil(measured)))
        let inner = layout.panel.width - 2 * padding
        let groupWidth = layout.markerColumn + textWidth
        let start = layout.panel.minX + padding + max(0, inner - groupWidth) * settings.alignment.flush
        return (start, start + layout.markerColumn, textWidth)
    }

    private static func drawText(_ block: WallpaperTextBlock, in context: CGContext, x: CGFloat,
                                 top: CGFloat, width: CGFloat, canvasHeight: CGFloat,
                                 alignment: WallpaperAlignment, strike: Bool = false, strikeColor: CGColor? = nil) {
        context.saveGState()
        context.clip(to: CGRect(x: x, y: canvasHeight - top - block.height, width: width, height: block.height).insetBy(dx: -2, dy: -2))
        defer { context.restoreGState() }
        context.textMatrix = .identity
        for (index, line) in block.lines.enumerated() {
            let offset = CGFloat(CTLineGetPenOffsetForFlush(line, alignment.flush, Double(width)))
            let baseline = canvasHeight - top - block.ascent - CGFloat(index) * block.lineAdvance
            context.textPosition = CGPoint(x: x + offset, y: baseline); CTLineDraw(line, context)
            if strike, let strikeColor {
                let lineWidth = min(width, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
                context.setStrokeColor(strikeColor); context.setLineWidth(0.9)
                let y = baseline + CTFontGetXHeight(block.font) / 2
                context.move(to: CGPoint(x: x + offset, y: y))
                context.addLine(to: CGPoint(x: x + offset + lineWidth, y: y)); context.strokePath()
            }
        }
    }

    static func writePNG(_ image: CGImage, to url: URL, expected: WallpaperSize, creationDescription: String? = nil) throws {
        guard image.width == expected.width && image.height == expected.height else { throw WallpaperError.dimensionsMismatch }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw WallpaperError.encodingFailed }
        // New pixels only: do not copy source GPS/EXIF metadata.
        let properties = creationDescription.map { [kCGImagePropertyPNGDictionary: [kCGImagePropertyPNGDescription: $0]] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { throw WallpaperError.encodingFailed }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == expected.width,
              (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue == expected.height
        else { throw WallpaperError.dimensionsMismatch }
    }
}

struct WallpaperLivePhoto: @unchecked Sendable {
    let image: CGImage
    let info: WallpaperPhotoInfo
}
actor WallpaperRenderService {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func loadPhoto(at url: URL) throws -> WallpaperLivePhoto {
        let info = try WallpaperRenderer.photoInfo(at: url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1536,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw WallpaperError.unreadablePhoto }
        return WallpaperLivePhoto(image: image, info: info)
    }
    func liveBlur(photo: WallpaperLivePhoto, settings: WallpaperSettings) throws -> WallpaperLivePhoto {
        try Task.checkCancellation()
        let image = photo.image
        let factor = min(1, 768 / Double(max(image.width, image.height)))
        let source = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: factor, y: factor))
        let rect = WallpaperRenderer.backgroundRect(source: CGSize(width: image.width, height: image.height),
            canvas: CGSize(width: 390, height: settings.logicalHeight), settings: settings)
        let sourceScale = rect.width / Double(image.width)
        let radius = settings.blurRadius / max(0.0001, sourceScale) * factor
        let result = source.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius]).cropped(to: source.extent)
        guard let output = context.createCGImage(result, from: result.extent) else { throw WallpaperError.renderingFailed }
        return WallpaperLivePhoto(image: output, info: photo.info)
    }
    func preview(settings: WallpaperSettings, items: [TodoItem], photoURL: URL?, appearance: TodoAppearance = TodoAppearance(), assetDirectory: URL? = nil, content: LianxinPublication? = nil) throws -> WallpaperRendered {
        try Task.checkCancellation()
        return try autoreleasepool {
            try WallpaperRenderer.render(settings: settings, items: items, photoURL: photoURL,
                                         previewWidth: 1000, ciContext: context, appearance: appearance, content: content)
        }
    }
    func export(settings: WallpaperSettings, items: [TodoItem], photoURL: URL?, directory: URL, appearance: TodoAppearance = TodoAppearance(), content: LianxinPublication? = nil) throws -> URL {
        try Task.checkCancellation()
        defer { context.clearCaches() }
        return try autoreleasepool {
            let rendered = try WallpaperRenderer.render(settings: settings, items: items, photoURL: photoURL, ciContext: context, appearance: appearance, content: content)
            if rendered.layout.lianxinOverflow { throw WallpaperError.contentOverflow }
            try Task.checkCancellation()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("TodoWallpaper-\(settings.size.width)x\(settings.size.height)-\(UUID()).png")
            do { try WallpaperRenderer.writePNG(rendered.image, to: url, expected: settings.size, creationDescription: content.map { $0.contentLabel + " · 连心" }) }
            catch { try? FileManager.default.removeItem(at: url); throw error }
            return url
        }
    }
}
