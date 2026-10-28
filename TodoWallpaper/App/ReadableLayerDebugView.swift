import SwiftUI
import UIKit

enum TestImageFactory {
    struct Sample: Identifiable {
        let id = UUID()
        let name: String
        let image: UIImage
    }

    static func all() -> [Sample] {
        let size = CGSize(width: 600, height: 600)
        return [
            Sample(name: "纯白", image: solid(.white, size: size)),
            Sample(name: "纯黑", image: solid(.black, size: size)),
            Sample(name: "黑白条纹", image: stripes(size: size)),
            Sample(name: "彩色噪点", image: gradientNoise(size: size)),
            Sample(name: "上下分半", image: split(size: size))
        ]
    }

    /// 上半纯白、下半纯黑：验证采样方向
    private static func split(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height / 2))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2))
        }
    }

    private static func solid(_ color: UIColor, size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static func stripes(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let cell: CGFloat = size.width / 16
            for row in 0..<16 {
                for column in 0..<16 {
                    let isDark = (row + column) % 2 == 0
                    (isDark ? UIColor.black : UIColor.white).setFill()
                    context.fill(CGRect(x: CGFloat(column) * cell,
                                        y: CGFloat(row) * cell,
                                        width: cell, height: cell))
                }
            }
        }
    }

    private static func gradientNoise(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.systemOrange.cgColor, UIColor.systemBlue.cgColor, UIColor.systemPink.cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 0.5, 1]) {
                context.cgContext.drawLinearGradient(gradient,
                                                     start: CGPoint(x: 0, y: 0),
                                                     end: CGPoint(x: size.width, y: size.height),
                                                     options: [])
            }
            var seed: UInt64 = 0x9E3779B97F4A7C15
            for _ in 0..<4000 {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let x = CGFloat((seed >> 33) % UInt64(size.width))
                let y = CGFloat((seed >> 13) % UInt64(size.height))
                let alpha = CGFloat((seed >> 3) % 60) / 255
                (seed % 2 == 0 ? UIColor.white : UIColor.black).withAlphaComponent(alpha).setFill()
                context.fill(CGRect(x: x, y: y, width: 3, height: 3))
            }
        }
    }
}

struct ReadableLayerDebugView: View {
    @State private var scrim: Double = 0.4
    @State private var anchor: TextAnchor = .bottom
    @State private var preset: ShadowPreset = .standard
    @State private var heightRatio: Double = 0.45

    private let samples = TestImageFactory.all()
    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                control("锚点") {
                    Picker("锚点", selection: $anchor) {
                        ForEach(TextAnchor.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                control("阴影") {
                    Picker("阴影", selection: $preset) {
                        ForEach(ShadowPreset.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
                control(String(format: "Scrim %.2f", scrim)) {
                    Slider(value: $scrim, in: 0...0.8, step: 0.05)
                }
                control(String(format: "覆盖范围 %.2f", heightRatio)) {
                    Slider(value: $heightRatio, in: 0.2...0.9, step: 0.05)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(samples) { sample in
                        cell(sample: sample)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("可读性测试")
    }

    @ViewBuilder
    private func control<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func cell(sample: TestImageFactory.Sample) -> some View {
        let analysis = ImageAnalyzer.analyzeImage(sample.image, anchor: anchor)

        VStack(alignment: .leading, spacing: 6) {
            ReadableLayer(anchor: anchor,
                          scrim: scrim,
                          scrimHeightRatio: heightRatio,
                          shadowPreset: preset) {
                VStack(alignment: anchor == .center ? .center : .leading, spacing: 2) {
                    Text("占位标题").font(.system(size: 16, weight: .semibold))
                    Text("这里是占位副标题").font(.system(size: 12, weight: .medium)).opacity(0.85)
                }
                .foregroundStyle(.white)
            }
            .frame(height: 150)
            .environment(\.widgetRenderingMode, .fullColor)
            .background { Image(uiImage: sample.image).resizable().scaledToFill() }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Text(sample.name).font(.caption2).foregroundStyle(.secondary)
            Text(String(format: "L %.2f  C %.2f  → %.2f",
                        analysis.meanLuma, analysis.contrast, analysis.suggestedScrim))
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
