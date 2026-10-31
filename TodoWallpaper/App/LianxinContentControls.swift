// Target Membership：仅App；两个编辑器共用相同选项，各自绑定独立的样式槽位。
import SwiftUI

struct LianxinContentControls: View {
    @Binding var value: LianxinDisplayStyle
    var wallpaper = false
    var hasTranslation = true
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("显示署名行", isOn: $value.showsSignature)
            Picker("文字对齐", selection: $value.centered) { Text("左对齐").tag(false); Text("居中").tag(true) }.pickerStyle(.segmented)
            Picker("最大行数", selection: Binding(get: { value.maximumLines ?? -1 }, set: { value.maximumLines = $0 < 0 ? nil : $0 })) {
                Text("自动").tag(-1); ForEach(1...4, id: \.self) { Text("\($0) 行").tag($0) }; Text("不限").tag(0)
            }.pickerStyle(.menu)
            Picker("翻译显示方式", selection: $value.translationDisplay) {
                ForEach(LianxinTranslationDisplay.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.menu)
            if !hasTranslation && value.translationDisplay == .translation { Text("还没有译文，请在连心开启翻译并生成。").font(.caption).foregroundStyle(.secondary) }
            Toggle("在小组件/壁纸上显示创作标注", isOn: $value.showsCreationLabel)
            if wallpaper {
                Text("默认不限，按面板高度完整折行。若选择1–4行导致省略，需改为不限或缩短话语后导出。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
struct LianxinTranslationControls: View {
    @Binding var value: LianxinDisplayStyle
    var body: some View {
        PreciseSlider(title: "译文字号比例", value: $value.translationScale, range: 0.5...1, standard: 0.85, precision: 2)
        PreciseSlider(title: "译文不透明度", value: $value.translationOpacity, range: 0...1, standard: 0.8, precision: 2)
    }
}
