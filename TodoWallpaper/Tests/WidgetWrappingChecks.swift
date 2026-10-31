// Target Membership：独立 macOS 原生检查。
import Foundation
import CoreText

enum WidgetWrappingChecks {
    static func run() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "WidgetWrappingChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let texts = ["短标题", "这是需要两行显示的中文待办内容", String(repeating: "五行中文长标题需要完整显示", count: 8), String(repeating: "abcdefghijk", count: 30), String(repeating: "🧑🏽‍💻❤️📚", count: 15)]
        let now = Date()
        var cases = 0
        for family in WidgetPreviewFamily.allCases {
            for scale in [1.0, 1.6, 2.5] {
                for compact in [false, true] {
                    for limit in [nil, 1, 2, 3, 4] as [Int?] {
                        var appearance = TodoAppearance()
                        appearance.widget.maximumTitleLines = limit; appearance.widget.compact = compact
                        appearance.widget.maximumItems = 10; appearance.widget.showsFooter = false
                        try appearance.validate()
                        let font = NativeTypography.font(family: .system, weight: .regular, size: 15 * scale)
                        let line = ceil(CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)) + 1
                        let items = texts.enumerated().map { index, text in
                            TodoItem(id: UUID(), title: text, isCompleted: false, createdAt: now, updatedAt: now,
                                schedule: index % 2 == 0 ? TodoSchedule(date: now, includesTime: false) : nil)
                        }
                        let m = WidgetLayoutMetrics.make(items: items, appearance: appearance, family: family, width: family.width - 32,
                            height: family.height - 32, fontLineHeight: line, headerHeight: 0, footerHeight: 15, font: font)
                        try require(m.capacity == m.rows.count && m.usedHeight <= m.availableRowHeight + 0.001, "容量与累计行高不溢出")
                        var used = 0.0
                        for (index, row) in m.rows.enumerated() {
                            let needed = WidgetTitleMeasure.lines(items[index].title, font: font, width: family.width - 32 - m.markerWidth - m.gap)
                            try require(row.lineLimit >= 1 && row.lineLimit <= min(needed, limit ?? (family == .small ? 2 : 3)), "逐项最大行数")
                            try require(row.height >= line * Double(row.lineLimit) + row.dateHeight, "标题与日期完整高度")
                            used += row.height + (index == 0 ? 0 : m.spacing)
                            try require(used <= m.availableRowHeight + 0.001, "每项底边均在组件内")
                            if index < m.rows.count - 1 { try require(row.lineLimit == min(needed, limit ?? (family == .small ? 2 : 3)), "只有最后一项可因高度缩行") }
                        }
                        cases += 1
                    }
                }
            }
        }
        var appearance = TodoAppearance(); appearance.widget.showsFooter = false; appearance.widget.maximumTitleLines = 4
        let font = NativeTypography.font(family: .system, weight: .regular, size: 15)
        func metrics(_ title: String, height: Double) -> WidgetLayoutMetrics {
            WidgetLayoutMetrics.make(items: [TodoItem(id: UUID(), title: title, isCompleted: false, createdAt: now, updatedAt: now)],
                appearance: appearance, family: .large, width: 150, height: height, fontLineHeight: 20, headerHeight: 0, footerHeight: 15, font: font)
        }
        try require(WidgetTitleMeasure.lines("短", font: font, width: 100) == 1, "短标题一行")
        try require(WidgetTitleMeasure.lines(String(repeating: "长", count: 200), font: font, width: 100) >= 5, "长中文真实测量至少五行")
        try require(metrics(texts[2], height: 45).rows.first?.lineLimit == 2, "末项缩为两行")
        try require(metrics(texts[2], height: 10).capacity == 0, "一行放不下即停止")
        try require((metrics("短", height: 300).rows.first?.height ?? 999) < (metrics(texts[2], height: 300).rows.first?.height ?? 0), "长短标题不同高度")
        for value in [nil, 1, 2, 3, 4] as [Int?] {
            appearance.widget.maximumTitleLines = value
            let decoded = try JSONDecoder().decode(TodoAppearance.self, from: JSONEncoder().encode(appearance))
            try decoded.validate(); try require(decoded.widget.maximumTitleLines == value, "旧nil/1/2及新3/4往返")
        }
        print("PASS: \(cases) multiline budgets: Chinese/English/Emoji/date, all sizes, Dynamic Type, compact, auto and limits1–4; no row overflow.")
    }
}
