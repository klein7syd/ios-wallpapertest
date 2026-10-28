import UIKit

enum ImageAnalyzer {
    /// 直接分析一张已经合成好的图
    static func analyzeImage(_ image: UIImage, anchor: TextAnchor) -> ImageAnalysis {
        analyze(rendered: image, anchor: anchor)
    }

    /// 按裁剪、缩放、透明度合成后的结果分析（选图/裁剪后调用）
    static func analyzePhoto(_ image: UIImage, crop: PhotoCrop, opacity: Double,
                             darkBackground: Bool, anchor: TextAnchor) -> ImageAnalysis {
        let canvas = CGSize(width: 48, height: 48)
        let rendered = UIGraphicsImageRenderer(size: canvas).image { context in
            (darkBackground ? UIColor.black : UIColor.white).setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let source = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            let frame = crop.frame(source: source, canvas: canvas)
            // UIKit 渲染上下文原点在左上角，裁剪框是左上角坐标系，直接用
            image.draw(in: frame, blendMode: .normal, alpha: max(0, min(1, opacity)))
        }
        return analyze(rendered: rendered, anchor: anchor)
    }

    static func analyze(rendered image: UIImage, anchor: TextAnchor) -> ImageAnalysis {
        let side = 32
        let size = CGSize(width: side, height: side)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let tiny = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = tiny.cgImage else { return .fallback }

        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &pixels,
            width: side, height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return .fallback }

        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        // 像素缓冲区第 0 行是图片顶部：bottom 取最后 40%，top 取前 40%
        let rows: Range<Int>
        switch anchor {
        case .bottom: rows = Int(Double(side) * 0.6)..<side
        case .top:    rows = 0..<Int(Double(side) * 0.4)
        case .center: rows = Int(Double(side) * 0.3)..<Int(Double(side) * 0.7)
        }

        var lumas: [Double] = []
        lumas.reserveCapacity(rows.count * side)

        for y in rows {
            for x in 0..<side {
                let index = (y * side + x) * 4
                let r = Double(pixels[index]) / 255
                let g = Double(pixels[index + 1]) / 255
                let b = Double(pixels[index + 2]) / 255
                // sRGB 近似，不转线性
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
        }

        guard !lumas.isEmpty else { return .fallback }

        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let variance = lumas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lumas.count)
        let contrast = min(1, variance.squareRoot() / 0.35)

        return ImageAnalysis(meanLuma: mean, contrast: contrast,
                             suggestedScrim: suggestedScrim(meanLuma: mean, contrast: contrast))
    }

    /// 观感映射，调手感只改这一个函数
    static func suggestedScrim(meanLuma: Double, contrast: Double) -> Double {
        var value = 0.25
        value += 0.25 * min(1, meanLuma / 0.8)
        value += 0.10 * contrast
        if meanLuma < 0.25 {
            value = min(value, 0.15)
        }
        return min(0.55, max(0.2, value))
    }

    /// 三个锚点一次算完
    static func analyzeAllAnchors(_ image: UIImage, crop: PhotoCrop?, opacity: Double,
                                  darkBackground: Bool) -> [TextAnchor: ImageAnalysis] {
        var result: [TextAnchor: ImageAnalysis] = [:]
        for anchor in TextAnchor.allCases {
            if let crop {
                result[anchor] = analyzePhoto(image, crop: crop, opacity: opacity,
                                              darkBackground: darkBackground, anchor: anchor)
            } else {
                result[anchor] = analyzeImage(image, anchor: anchor)
            }
        }
        return result
    }
}
