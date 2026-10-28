import SwiftUI
import UIKit

/// 阴影对比页：4 种背景 × 8 种配方，肉眼选一个字母
struct ShadowCompareView: View {
    @State private var showScrim = true
    @State private var scrim: Double = 0.4

    private var currentPhoto: UIImage? {
        guard let appearance = try? AppearanceRepository(directory: TodoSharedStorage.sharedDirectory()).load(),
              let image = WidgetPhotoCache.image(named: appearance.widget.photoName(at: .now)) else { return nil }
        return UIImage(cgImage: image)
    }

    private var backgrounds: [(String, UIImage?)] {
        var list: [(String, UIImage?)] = [("当前照片", currentPhoto)]
        list.append(("彩色噪点", TestImageFactory.all().first { $0.name == "彩色噪点" }?.image))
        list.append(("纯白", TestImageFactory.all().first { $0.name == "纯白" }?.image))
        list.append(("纯黑", TestImageFactory.all().first { $0.name == "纯黑" }?.image))
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("叠加蒙层", isOn: $showScrim)
                HStack {
                    Text(String(format: "蒙层 %.2f", scrim)).font(.caption.monospacedDigit())
                    Slider(value: $scrim, in: 0...0.8, step: 0.05)
                }

                section(title: "白色文字（黑色阴影）", recipes: ShadowRecipes.light, lightText: true)
                section(title: "黑色文字（白色光晕）", recipes: ShadowRecipes.dark, lightText: false)
            }
            .padding()
        }
        .navigationTitle("阴影对比")
    }

    @ViewBuilder
    private func section(title: String, recipes: [ShadowRecipe], lightText: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(recipes) { recipe in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recipe.id).font(.title3.bold())
                        Text(recipe.name).font(.caption2).foregroundStyle(.secondary)
                        Text(recipe.summary).font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                    .frame(width: 56, alignment: .leading)

                    ForEach(backgrounds, id: \.0) { item in
                        sample(background: item.1, recipe: recipe, lightText: lightText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sample(background: UIImage?, recipe: ShadowRecipe, lightText: Bool) -> some View {
        ZStack {
            if let background {
                Image(uiImage: background).resizable().scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }
            if showScrim {
                ScrimView(anchor: .bottom, strength: scrim, heightRatio: 0.5,
                          color: lightText ? .black : .white)
            }
            // 走真实的 ReadableLayer / TextStyleModifier 路径
            ReadableLayer(isLightText: lightText, intensity: .standard, recipe: recipe) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("占位标题").font(.system(size: 13, weight: .semibold))
                    Text("这里是副标题").font(.system(size: 9, weight: .medium)).opacity(0.85)
                }
                .foregroundStyle(lightText ? Color.white : Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(6)
            }
        }
        .frame(width: 76, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
