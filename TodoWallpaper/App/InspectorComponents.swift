import SwiftUI

/// Both editors use the system's selection animation and one compact tool row.
struct EditorToolPicker<Selection: Hashable & Identifiable>: View {
    let choices: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    var compact = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if compact || typeSize.isAccessibilitySize {
                HStack {
                    Menu {
                        ForEach(choices) { item in Button(title(item)) { selection = item } }
                    } label: {
                        HStack(spacing: 8) {
                            Text(title(selection)).font(.subheadline).lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                        }.fixedSize(horizontal: true, vertical: false).frame(minHeight: 44)
                    }.accessibilityLabel("设置类别：\(title(selection))")
                    Spacer(minLength: 0)
                }
            } else {
                Picker("设置类别", selection: $selection) {
                    ForEach(choices) { Text(title($0)).tag($0) }
                }.pickerStyle(.segmented).frame(minHeight: 44)
            }
        }
    }
}

/// A single, bounded scroll surface. The material background does not clip drawing;
/// clipping belongs here and at the panel edge, including during content replacement.
struct InspectorViewport<Content: View>: View {
    let pageID: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 0).id("inspector-top")
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 18)
            }
            .scrollClipDisabled(false)
            .scrollDismissesKeyboard(.interactively)
            .clipped()
            .onChange(of: pageID) { _, _ in
                // Switching a tool or detail page starts at its own beginning.
                // Ordinary slider changes never change identity or scroll position.
                withTransaction(Transaction(animation: nil)) { reader.scrollTo("inspector-top", anchor: .top) }
            }
        }
        .clipped()
    }
}

