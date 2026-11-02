import SwiftUI

/// Both editors use the system's selection animation and one compact tool row.
struct EditorToolPicker<Selection: Hashable & Identifiable>: View {
    let choices: [Selection]
    @Binding var selection: Selection
    let title: (Selection) -> String
    var compact = false
    var icon: ((Selection) -> String)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
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
            } else if compact {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(choices) { item in
                                Button { selection = item } label: {
                                    HStack(spacing: 6) {
                                        if let icon { Image(systemName: icon(item)) }
                                        Text(title(item))
                                    }.font(.subheadline.weight(selection == item ? .semibold : .regular))
                                        .padding(.horizontal, 14).frame(minHeight: 44)
                                        .foregroundStyle(selection == item ? Color.accentColor : Color.primary)
                                        .background(selection == item ? Color.accentColor.opacity(0.12) : Color(uiColor: .tertiarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }.buttonStyle(.plain).id(item.id)
                                    .accessibilityAddTraits(selection == item ? .isSelected : [])
                            }
                        }
                    }.scrollIndicators(.hidden)
                        .onChange(of: selection) { _, value in reader.scrollTo(value.id, anchor: .center) }
                        .onAppear { reader.scrollTo(selection.id, anchor: .center) }
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


// Target Membership：App；参数分组标题提供阅读层级，不改变控件身份或滚动容器。
struct InspectorGroupTitle: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline).foregroundStyle(.primary)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// Target Membership：仅App。两个编辑器明确显示当前内容，切换仍由原有常驻会话处理。
struct EditorContentMenu: View {
    let mode: ContentMode
    let select: (ContentMode) -> Void
    var body: some View {
        Menu {
            ForEach(ContentMode.allCases, id: \.rawValue) { value in
                Button { if value != mode { select(value) } } label: {
                    Label(value == .todo ? "待办内容" : "连心内容", systemImage: value == mode ? "checkmark" : value == .todo ? "checklist" : "heart")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode == .todo ? "checklist" : "heart")
                Text(mode == .todo ? "待办" : "连心")
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }.font(.subheadline.weight(.medium)).frame(minHeight: 44)
        }.accessibilityLabel("内容来源：" + (mode == .todo ? "待办" : "连心"))
    }
}

// 选择器的标题保持可见，避免多组分段按钮只能凭选项猜用途。
struct InspectorChoice<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
            content()
        }
    }
}
