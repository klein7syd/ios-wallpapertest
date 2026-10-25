import SwiftUI

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

struct InspectorHeading: View {
    let title: String
    @Binding var advanced: Bool
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button {
                advanced.toggle()
            } label: {
                Label(advanced ? "返回常用" : "更多", systemImage: advanced ? "arrow.uturn.backward" : "slider.horizontal.3")
                    .font(.subheadline)
            }
            .buttonStyle(.plain).frame(minHeight: 44)
            .accessibilityIdentifier("inspector.details")
        }
    }
}
