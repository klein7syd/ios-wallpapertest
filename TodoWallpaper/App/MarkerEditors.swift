import SwiftUI
import UIKit

struct MarkerChoiceEditor: View {
    @Binding var choice: TodoMarker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("标记类型", selection: $choice.kind) {
                ForEach(MarkerKind.allCases) { Text($0.title).tag($0) }
            }
            if choice.kind == .emoji {
                EmojiEntry(value: $choice.emoji)
                Button("清除标记", role: .destructive) { choice.kind = .none }
            }
        }
    }
}
struct EmojiEntry: View {
    @Binding var value: String
    @State private var input = ""
    private let common = ["❤️", "⭐", "🔥", "🎵", "🌸", "🌙", "🐱", "📚", "🎯", "✅", "💪", "🧑🏽‍💻", "👨‍👩‍👧‍👦"]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("用系统 Emoji 键盘输入", text: $input)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.title2).submitLabel(.done)
                Button { input = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel("清除输入")
            }
            .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(common, id: \.self) { emoji in
                        Button { input = emoji } label: { Text(verbatim: emoji).font(.title2) }.buttonStyle(.plain)
                    }
                }
            }
            if !EmojiInput.isValid(input) {
                Text("请输入一个完整 Emoji。当前保存：\(value)；无效或空输入不会覆盖它。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { input = value }
        .onChange(of: value) { _, next in if EmojiInput.isValid(next), next != input { input = next } }
        .onChange(of: input) { _, next in
            if EmojiInput.isValid(next) { value = next }
            else if next.utf8.count > 128 { input = "" }
        }
    }
}
struct PreciseSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    private var bounded: Binding<Double> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, value)) },
                set: { value = $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0)) : range.lowerBound })
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer(minLength: 6)
                TextField(title, value: bounded, format: .number.precision(.fractionLength(0...3)))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    .font(.subheadline.monospacedDigit()).frame(width: 80)
            }
            Slider(value: bounded, in: range).accessibilityLabel(title)
        }
    }
}
struct StyleColorControl: View {
    let title: String
    @Binding var value: WallpaperColor
    private let palette: [WallpaperColor] = [
        WallpaperColor(), WallpaperColor(red: 0, green: 0, blue: 0),
        WallpaperColor(red: 0.92, green: 0.3, blue: 0.42), WallpaperColor(red: 0.97, green: 0.78, blue: 0.36),
        WallpaperColor(red: 0.52, green: 0.76, blue: 0.63), WallpaperColor(red: 0.5, green: 0.67, blue: 0.9),
        WallpaperColor(red: 0.75, green: 0.6, blue: 0.87)
    ]
    private var color: Binding<Color> {
        Binding(get: { value.swiftColor }, set: { next in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            if UIColor(next).getRed(&r, green: &g, blue: &b, alpha: &a) {
                value = WallpaperColor(red: r, green: g, blue: b, alpha: a)
            }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                ColorPicker("系统取色器", selection: color, supportsOpacity: true).labelsHidden()
            }
            HStack(spacing: 12) {
                ForEach(palette.indices, id: \.self) { index in
                    Button { var next = palette[index]; next.alpha = value.alpha; value = next } label: {
                        Circle().fill(palette[index].swiftColor).overlay(Circle().stroke(.gray.opacity(0.5), lineWidth: 1))
                            .frame(width: 26, height: 26)
                    }.buttonStyle(.plain).accessibilityLabel("快捷颜色 \(index + 1)")
                }
            }
            PreciseSlider(title: "透明度", value: $value.alpha, range: 0...1)
            DisclosureGroup("精细 RGB") {
                PreciseSlider(title: "红", value: $value.red, range: 0...1)
                PreciseSlider(title: "绿", value: $value.green, range: 0...1)
                PreciseSlider(title: "蓝", value: $value.blue, range: 0...1)
            }.font(.caption)
        }
    }
}
struct MarkerStyleEditor: View {
    @Binding var style: MarkerStyle
    var body: some View {
        VStack(spacing: 14) {
            PreciseSlider(title: "图形大小", value: $style.size, range: 8...48)
            PreciseSlider(title: "Emoji 大小", value: $style.emojiSize, range: 8...48)
            PreciseSlider(title: "标记与文字间距", value: $style.gap, range: 0...32)
            PreciseSlider(title: "垂直对齐偏移", value: $style.verticalOffset, range: -16...16)
            Picker("完成时", selection: $style.completion) {
                ForEach(MarkerCompletion.allCases) { Text($0.title).tag($0) }
            }
            if style.completion == .replace { EmojiEntry(value: $style.completionEmoji) }
            DisclosureGroup("圆圈与方框外观") {
                VStack(spacing: 12) {
                    PreciseSlider(title: "描边粗细", value: $style.lineWidth, range: 0.3...6)
                    Toggle("填充和描边跟随文字色", isOn: $style.followsTextColor)
                    if !style.followsTextColor {
                        StyleColorControl(title: "填充色", value: $style.fill)
                        StyleColorControl(title: "描边色", value: $style.stroke)
                    }
                    StyleColorControl(title: "完成状态色", value: $style.completedColor)
                }.padding(.top, 10)
            }
        }
    }
}
