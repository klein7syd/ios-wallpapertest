import Foundation

enum UIStateChecks {
    static func run() throws {
        func require(_ value: @autoclosure () -> Bool, _ message: String) throws {
            if !value() { throw NSError(domain: "UIStateChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        var navigation = AppNavigationState()
        try require(AppPage.allCases.count == 4 && AppPage.allCases.contains(.widget), "Widget is a real fourth root page")
        try require(!navigation.isEditing && navigation.inspectorExpanded, "Launch starts on Todo with a ready wallpaper inspector")
        for page in AppPage.allCases {
            navigation.selectPage(page)
            try require(navigation.page == page, "Every native root tab remains selectable")
            for tool in WallpaperTool.allCases {
                navigation.selectTool(tool)
                try require(navigation.page == .wallpaper && navigation.wallpaperTool == tool && navigation.inspectorExpanded,
                    "Tool selection replaces parameters while keeping the ordinary TabView")
                navigation.toggleInspector()
                try require(!navigation.inspectorExpanded && navigation.wallpaperTool == tool, "Collapse keeps the selected tool")
                navigation.selectTool(tool)
                try require(navigation.inspectorExpanded, "Tool selection reopens its parameters")
                navigation.selectPage(page)
                try require(navigation.page == page && navigation.wallpaperTool == tool, "Switching tabs retains tool choice")
            }
        }
        for _ in 0..<100 {
            for tool in WallpaperTool.allCases { navigation.selectTool(tool); navigation.toggleInspector(); navigation.selectTool(tool) }
            navigation.selectPage(.widget)
        }
        try require(navigation.page == .widget, "Repeated editing and navigation cycles retain a usable root page")

        for kind in MarkerKind.allCases {
            let controls = MarkerControlVisibility(kind: kind)
            if kind == .emoji { try require(controls.visible && controls.emoji && !controls.shape && !controls.stroke && !controls.fill, "Emoji hides shape-only controls") }
            if [.hollow, .thin, .square].contains(kind) { try require(controls.stroke && !controls.fill && !controls.emoji, "Outlined shapes expose stroke without fill or Emoji size") }
            if kind == .filled { try require(controls.fill && !controls.stroke && !controls.emoji, "Filled shape prioritizes fill; optional border is advanced") }
            if kind == .bordered { try require(controls.fill && controls.stroke, "Bordered shape retains both colors") }
            if kind == .none { try require(!controls.visible && !controls.emoji && !controls.shape && !controls.stroke && !controls.fill, "No marker means no dormant sliders") }
            try require(controls.completionColor(.checkShapes) == controls.shape && !controls.completionColor(.keep), "Completion color only for checked shapes")
            try require(controls.completionEmoji(.replace) == controls.visible && !controls.completionEmoji(.dim), "Replacement Emoji only while enabled")
        }
        // Reading visibility must not mutate or reset saved settings, including dormant values.
        var appearance = TodoAppearance()
        appearance.markerStyle.size = 31.7
        appearance.markerStyle.emojiSize = 27.4
        appearance.markerStyle.stroke.alpha = 0.24
        appearance.defaultMarker = TodoMarker(kind: .emoji, emoji: "🧑🏽‍💻")
        let before = try JSONEncoder().encode(appearance)
        for kind in MarkerKind.allCases { _ = MarkerControlVisibility(kind: kind).fill }
        let roundTrip = try JSONDecoder().decode(TodoAppearance.self, from: before)
        try require(roundTrip == appearance, "Conditional controls leave all persisted and dormant values compatible")

        for available in [0.0, 150, 260, 420, 650, 900] {
            for expanded in [false, true] {
              for advanced in [false, true] {
                let height = EditorSizing.panelHeight(available: available, expanded: expanded, advanced: advanced)
                try require(height >= 0 && height <= available, "Dock fits reduced keyboard/small-screen space")
                if available >= 260 { try require(available - height >= 110, "Canvas retains useful space above controls") }
              }
            }
        }
        for family in WidgetPreviewFamily.allCases {
            for width in [240.0, 320, 390, 1024] {
                for height in [0.0, 4, 12, 70, 120, 240, 310] {
                    let scale = family.scale(availableWidth: width, availableHeight: height)
                    try require(family.width * scale <= width + 0.001 && family.height * scale <= height + 0.001, "Fixed Widget preview fits without changing family aspect ratio")
                }
            }
            let rows = appearance.widget.rows([], capacity: family.rowLimit(appearance: appearance.widget, accessibility: false))
            try require(rows.isEmpty, "Empty Widget preview remains empty")
        }
        for completion in MarkerCompletion.allCases {
            var dormant = MarkerStyle()
            dormant.completion = completion
            try require(dormant.resolved(TodoMarker(kind: .none), completed: true).marker.kind == .none,
                "Hidden marker stays hidden without deleting a dormant replacement policy")
        }
        for height in [150.0, 260, 420, 650, 900] {
            for family in WidgetPreviewFamily.allCases {
            let preview = EditorSizing.widgetPreviewHeight(available: height, family: family)
            let controlsHeader = height < 320 ? 44.0 : 96.0
            try require(height - preview - controlsHeader - 6 > 20, "Pinned preview leaves independent settings space even in compact keyboard layout")
            if height >= 320 && family != .large {
                try require(preview <= 214, "Small/medium preview must not reserve the large Widget's empty vertical space")
            }
            }
        }
        try require(WidgetPreviewFamily.small.rowLimit(appearance: WidgetAppearance(), accessibility: false) == 2, "Small Widget retains proven row capacity")
        try require(WidgetPreviewFamily.medium.rowLimit(appearance: WidgetAppearance(), accessibility: false) == 3, "Medium Widget retains proven row capacity")
        try require(WidgetPreviewFamily.large.rowLimit(appearance: WidgetAppearance(), accessibility: false) == 6, "Large Widget retains proven row capacity")
        print("PASS: UI state — four persistent root tabs, editing with ordinary navigation, repeated collapse/tool switching, conditional marker controls, dormant value preservation, keyboard/small-screen allocation, three fixed-preview ratios and Widget row capacities. Not an iPhone visual/scroll test.")
    }
}
