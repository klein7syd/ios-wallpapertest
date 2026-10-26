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


## Actual final evidence

Final **0.4.3 / 1017**, code commit `6ccd4901dc15d6f9c2aadc738ba909b7717606cf`, [Actions 40361177607](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40361177607), job 121706715269: **success**. Both App and Widget are unsigned ARM64 iOS-device bundles with their original IDs/group and `openAppWhenRun=false` App Intent metadata. No CI-probe entry point is embedded in the device binary. Zero Swift-source warnings.

87 source/protected-file checks, production CRUD/migration/concurrency/backup/legacy-data checks, grouped/no-op/bounded undo, failed-apply retention and external-state rebase passed. The standard-scale renderer and existing 4K/font/54 Emoji raster checks passed. Independently opened PNGs: modern1890×4096, classic2304×4096, standard layout1890×4096.

Actual iOS26.5 Simulator execution passed: one undo for120 continuous session updates; failed-apply retry; real private source-photo removal/restore and draft reload without Photos writes. The existing30 Widget font/space images, five text-completion pixel hashes and nine small-heart sizes passed. Actual app screenshots show the retained four-tab navigation, consistent tool pickers, standard-value dots and ordinary/advanced screens. Maximum system text remains on an independent scroll surface. These are simulated callback/render results, not automated finger taps or physical iPhone proof. The old blank offscreen marker-card ScrollView capture remains excluded from visual passes.

Two necessary CI runs, both successful:1016 validated the full revision; review found a PhotosPicker label main-actor warning and a toolbar grouping concern. Final1017 captures the label value on the main actor and groups Widget Undo/help controls. No further full build for evidence-only documentation.

Artifact `todo-wallpaper-0.4.3-17`, id12668528232, 17,606,263 bytes, SHA256 `91a5333bcce96fe362a1f3c5309de53c9f9c34a31402040faf484e25aedc2dc3`. Unsigned IPA SHA256 `cf4a7253a2402bcb5e863af88c0d272c98fb645a4d23d2ee583cc8e9d539284a`. Downloaded official ZIP retained unchanged; SHA256/CRC, actual bundle metadata, target pixels and original R1 script contents independently checked.

Windows signing/install, actual iPhone control taps, gesture grouping, scrolling, system Display Zoom, Widget actions and upgrade retention remain pending user feedback. Keep the existing App and cover-install with the original R1 flow. This revision stops here.
