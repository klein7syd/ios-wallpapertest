# 0.4.3 · 常规导航、标准排版与撤销

Base: 0.4.2 / 1015. This change follows the user's request to retire the circular editor Dock. Physical signing, installation and iPhone acceptance remain separate from CI.

## Behavior

- The ordinary four-tab SwiftUI TabView remains mounted: 待办 / 壁纸 / 小组件 / 关于. There is no circular page-switch entrance or separate editor root.
- Wallpaper and Widget use the same native segmented tool picker, with a compact menu at accessibility sizes. Wallpaper allocates a small bounded inspector beneath the fixed canvas; collapsing settings or opening full screen gives the canvas more room. Widget retains its pinned preview.
- 关于 → 高级编辑选项 is a device-local persistent switch, off by default. It reveals independent sizes, spacing, line widths, alignment and exact positions in both editors. Switching it never resets saved styles, drafts or photos.
- Standard mode offers 排版缩放. Intentionally changing it applies the standard proportions for text, marker size, spacing and padding rather than retaining arbitrary ratios from advanced controls. Wallpaper crop, relative position, canvas and output resolution remain unchanged. Widget preserves Emoji choices, themes and completion policies. Existing custom metrics remain intact until the user deliberately adjusts a scale/control.
- Every slider requires an explicit standard value. A visible dot below the track locates it; tapping the dot or the accessible 标准 button restores it. Numeric entry and continuous adjustment remain available.
- Wallpaper and Widget have toolbar Undo buttons. A slider drag, number-entry session, photo/panel gesture or continuous color adjustment forms one editing step. History is bounded to 50 states in memory. It covers wallpaper settings/photos/markers, copying wallpaper style into Widget, Widget styles and per-task marker edits. It does not undo real task completion, titles, task deletion or task order, export files already shared, or images already saved to Photos. Restarting the App clears session history.
- Undo restores photos by validated local file reference, not by keeping full image copies in memory. It uses the existing draft saving path. A failed restore retains its undo entry. Per-task marker undo edits the current task's marker only; it retains its current title/completion/order and never resurrects a deleted task. An external task-membership change safely rebases Widget history.

## Compatibility and checks

App `org.todowallpaper.app`, Widget `org.todowallpaper.app.widget`, App Group `group.org.todowallpaper.app` remain unchanged. Task/appearance/draft JSON schema and fields, migration and backup, renderer, App Intents and proven Windows R1 signing scripts remain unchanged. Two formerly protected presentation files (WallpaperSettings helper and WallpaperEditorModel restore method) are intentionally edited; the other protected persistence, rendering type, capability and R1 sources remain hash-checked.

Checks include grouped/no-op/bounded undo, failure retention, external rebase, standard node coordinates, coordinated scaling, original custom draft decoding, fixed preview/keyboard allocation, existing repository/migration/4K/fonts/Emoji checks and actual iOS Simulator session/photo restore. Simulator screenshots cover standard/advanced Wallpaper, standard/text/advanced Widget, About and maximum system text. No automated touch or physical iPhone result is inferred.

CI evidence and the final build number are recorded after the real workflow completes. The delivered IPA is unsigned and still needs the existing Windows R1 signing/install flow. Stop for user device feedback.
