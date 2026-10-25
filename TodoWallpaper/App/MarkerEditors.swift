import SwiftUI
import UIKit

struct MarkerChoiceEditor: View {
    @Binding var choice: TodoMarker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MarkerKind.allCases) { kind in
                        Button { choice.kind = kind } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    if kind == .none {
                                        Image(systemName: "nosign").font(.title3).foregroundStyle(.secondary)
                                    } else {
                                        TodoMarkerView(marker: TodoMarker(kind: kind, emoji: choice.emoji), completed: false,
                                            style: MarkerStyle(size: 23, emojiSize: 27), textColor: .primary, maximumSize: 28)
                                    }
                                }.frame(height: 30)
                                Text(kind == .emoji ? "Emoji" : kind.title).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 64, height: 66)
                            .background(choice.kind == kind ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(choice.kind == kind ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1)
                            }
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain).foregroundStyle(.primary)
                        .accessibilityLabel(kind.title)
                        .accessibilityAddTraits(choice.kind == kind ? .isSelected : [])
                        .accessibilityIdentifier("marker.choice.\(kind.rawValue)")
                    }
                }.padding(.vertical, 2)
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
                Button { input = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
                    .accessibilityLabel("清除输入")
            }
            .padding(8).background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(common, id: \.self) { emoji in
                        Button { input = emoji } label: { Text(verbatim: emoji).font(.title2).frame(width: 44, height: 44) }.buttonStyle(.plain)
                    }
                }
            }
            if !EmojiInput.isValid(input) {
                Text("请输入一个完整 Emoji，当前保留 \(value)")
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
    var precision = 1
    private var bounded: Binding<Double> {
        Binding(get: { min(range.upperBound, max(range.lowerBound, value)) },
                set: { value = $0.isFinite ? min(range.upperBound, max(range.lowerBound, $0)) : range.lowerBound })
    }
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.subheadline)
                Spacer(minLength: 6)
                TextField(title, value: bounded, format: .number.precision(.fractionLength(0...precision)))
                    .keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing)
                    .font(.subheadline.monospacedDigit()).frame(width: 72, height: 44)
                    .accessibilityLabel("\(title)，精确输入")
            }
            Slider(value: bounded, in: range).accessibilityLabel(title)
        }
    }
}
struct StyleColorControl: View {
    let title: String
    @Binding var value: WallpaperColor
    var showsOpacity = true
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
            HStack(spacing: 0) {
                ForEach(palette.indices, id: \.self) { index in
                    Button { var next = palette[index]; next.alpha = value.alpha; value = next } label: {
                        Circle().fill(palette[index].swiftColor)
                            .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 0.5))
                            .frame(width: 25, height: 25)
                            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("快捷颜色 \(index + 1)")
                }
            }
            if showsOpacity { PreciseSlider(title: "不透明度", value: $value.alpha, range: 0...1, precision: 2) }
        }
    }
}
struct MarkerStyleEditor: View {
    @Binding var style: MarkerStyle
    let kind: MarkerKind
    var advanced = false
    private var controls: MarkerControlVisibility { MarkerControlVisibility(kind: kind) }
    private var completion: Binding<MarkerCompletion> {
        Binding(get: { kind == .emoji && style.completion == .checkShapes ? .keep : style.completion },
                set: { style.completion = $0 })
    }
    var body: some View {
        if controls.visible {
            VStack(alignment: .leading, spacing: 18) {
                if !advanced {
                    if controls.emoji { PreciseSlider(title: "Emoji 大小", value: $style.emojiSize, range: 8...48) }
                    else { PreciseSlider(title: "图形大小", value: $style.size, range: 8...48) }
                    PreciseSlider(title: "与文字间距", value: $style.gap, range: 0...32)
                    if controls.stroke { PreciseSlider(title: "描边粗细", value: $style.lineWidth, range: 0.3...6) }
                    if controls.shape {
                        Toggle("颜色跟随文字", isOn: $style.followsTextColor)
                    }
                    if !style.followsTextColor {
                        if controls.fill { StyleColorControl(title: "填充色", value: $style.fill) }
                        if controls.stroke { StyleColorControl(title: "描边色", value: $style.stroke) }
                    }
                } else {
                    if kind == .filled {
                        PreciseSlider(title: "边框粗细", value: $style.lineWidth, range: 0.3...6)
                        if !style.followsTextColor { StyleColorControl(title: "边框色", value: $style.stroke) }
                    }
                    PreciseSlider(title: "垂直对齐", value: $style.verticalOffset, range: -16...16)
                    Picker("完成时", selection: completion) {
                        ForEach(MarkerCompletion.allCases.filter { kind != .emoji || $0 != .checkShapes }) {
                            Text($0.title).tag($0)
                        }
                    }.pickerStyle(.menu)
                    if controls.completionEmoji(style.completion) {
                        EmojiEntry(value: $style.completionEmoji)
                        if !controls.emoji { PreciseSlider(title: "完成 Emoji 大小", value: $style.emojiSize, range: 8...48) }
                    }
                    if controls.completionColor(style.completion) {
                        StyleColorControl(title: "完成状态色", value: $style.completedColor)
                    }
                }
            }
        }
    }
}
