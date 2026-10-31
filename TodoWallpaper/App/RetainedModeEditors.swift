// Target Membership：仅App。首次进入才构建，之后保留各模式的预览和撤销会话。
import SwiftUI

struct RetainedModeEditors<Content: View>: View {
    let selection: ContentMode
    let pageIsActive: Bool
    @ViewBuilder let content: (ContentMode, Bool) -> Content
    @State private var visited: Set<ContentMode> = []

    var body: some View {
        ZStack {
            ForEach(ContentMode.allCases, id: \.self) { mode in
                if visited.contains(mode) || selection == mode {
                    content(mode, pageIsActive && selection == mode)
                        .opacity(selection == mode ? 1 : 0)
                        .allowsHitTesting(pageIsActive && selection == mode)
                        .accessibilityHidden(!pageIsActive || selection != mode)
                        .zIndex(selection == mode ? 1 : 0)
                }
            }
        }
        .animation(nil, value: selection)
        .onAppear { visited.insert(selection) }
        .onChange(of: selection) { _, mode in visited.insert(mode) }
    }
}
