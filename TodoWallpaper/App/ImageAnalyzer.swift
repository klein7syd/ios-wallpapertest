import UIKit

enum ImageAnalyzer {
    /// 缩到 32×32 再算，几毫秒出结果
    static func analyzeImage(_ image: UIImage, anchor: TextAnchor) -> ImageAnalysis {
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

        // CGContext 原点在左下角：y = 0 是图片底部
        context.draw(cgImage, in: CGRect(origin: .zero, size: size))

        let rows: Range<Int>
        switch anchor {
        case .bottom: rows = 0..<Int(Double(side) * 0.4)
        case .top:    rows = Int(Double(side) * 0.6)..<side
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
                // 直接用 sRGB 近似，不转线性：判断"要不要压暗"足够
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
        }

        guard !lumas.isEmpty else { return .fallback }

        let mean = lumas.reduce(0, +) / Double(lumas.count)
        let variance = lumas.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lumas.count)
        let contrast = min(1, variance.squareRoot() / 0.35)

        return ImageAnalysis(meanLuma: mean,
                             contrast: contrast,
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
}
