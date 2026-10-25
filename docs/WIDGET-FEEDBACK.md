# Widget and compact Dock feedback revision · 0.4.2

Base: 0.4.1 / 1013. This revision follows eleven items of real iPhone feedback. Signing, installation and device acceptance for this new build are not inferred from any CI result.

## Visible behavior

1. Wallpaper editing uses a separate SwiftUI root instead of trying to hide a Tab Bar inside TabView. The system TabView is only mounted in ordinary navigation. The cached WallpaperEditorModel is owned by App and survives transitions. In edit mode a separate circular navigation entrance sits to the left of one current-tool capsule. The five tools are in that capsule's menu, not a second permanently expanded bar. Page switching and restoring normal tabs remain available. Native Liquid Glass is used on supported systems, with material fallback.
2. Wallpaper markers are decoration. Completion interaction controls are omitted; native live/PNG rendering ignores marker completion policies. Static completed text treatment and real task filtering remain available. Copying wallpaper visuals to Widget preserves the Widget's completion behavior and replacement Emoji.
3. Shared Widget layout no longer clips marker size at 20/24pt, gap at 12pt, stroke at 3pt or vertical offset at one quarter size. Requested marker size 8–48 and gap 0–32 actually reach the drawing/layout path. The Widget measures its available space and reduces the number of rows. Large fonts/markers may leave fewer visible tasks rather than drawing outside the Widget.
4. Marker rendering uses bounded native Core Text color glyphs in SwiftUI Canvas as well as PNG output. Ink bounds are fitted and centered, retaining complete Emoji graphemes and native colors, including small hearts. Actual raster tests and iOS Simulator output verify the path; real iPhone font artwork is still a device check.
5. Completed markers can preserve, dim, use the user's own replacement Emoji, check an original shape, or replace with a thin checked circle. Relevant size, line and color controls appear for the selected effect only.
6. Widget has no global-default editing scope. Its toggle is “继承壁纸标记”: type/Emoji inherit the existing wallpaper default, while size/gap/completion remain Widget settings. Existing JSON names/defaults are retained for compatibility. Per-task marker still has highest priority.
7. Pinned preview is actionable: tap a marker to select that real task and open marker settings; tap text to try completion/restore locally. Reset clears trial states. Trial completion never writes task completion to storage; choosing that task's marker does persist through the existing repository edit method. The preview obeys the configured completed-item filter.
8. Completed text supports unchanged, fade, strike, fade+strike (legacy default), and chosen color. Text and marker pages edit the same gap field, not duplicate values.
9. Per-task Emoji selection is available directly from the preview and via its task menu, reusing the established optional task marker. No task ID/order/completion is replaced by marker editing.
10. Optional separators start at the title column like a settings list. Their 4pt top/bottom spacing is fixed; there is no extra spacing slider.
11. Widget text uses ScaledMetric and available-height row budgets. Accessibility sizes use compact setting-category/Dock controls. Wallpaper composition itself remains in canvas coordinates, so changing system text does not unexpectedly reflow a saved wallpaper. Control UI follows system text settings.

## Compatibility and validation scope

Stable App/Widget/App Group identifiers, R1 installer and App Intent source remain unchanged. Todo fields and schema remain unchanged. Widget appearance has only optional additive completion-text/color/separator fields, with legacy defaults when missing. The new thinCircle marker policy is forward-compatible with this app+extension pair; do not downgrade to older binaries and rewrite settings containing a new enum case.

Production repository/migration/backup/4K/font/Emoji checks continue, supplemented by full slider-range budgets, preview-state isolation, old appearance decoding, thin-circle/custom Emoji policies, persisted per-task markers, small Emoji pixel bounds at 1x/3x, and identical static wallpaper images across interaction policies.

The CI Simulator Debug app alone includes NativeUIProbe. Its five Dynamic Type environments, real UIFontMetrics, 30 normal/reduced-size Widget outputs, five completed-text pixel comparisons and 8–48pt heart pixel outputs exercise the actual SwiftUI drawing code. Reduced size is an 85% logical-space stress test, **not proof of enabling real iPhone Display Zoom**. The script also attempts the Simulator's system content-size command and records whether it was accepted, plus actual app screenshots.

The probe source/flags are absent from the device Release build; IPA verification checks that the probe launch marker is not embedded. Simulator rendering and screenshots do not prove physical iPhone scrolling, touch behavior, signing, installation or Widget timeline/Intent execution. Those need the packaged device checklist and user feedback.

Actual build evidence will be recorded after CI. No PWA, AI, translation, cloud sync, custom image assets or new signing flow is added.

## Actual final evidence

Final **0.4.2 / 1015**, commit `a9d07f7fce1070dfcdd6c4689786981dc0803097`, [Actions 40199284647](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40199284647), job 121186801277: **success**. Both device bundles are ARM64 iOS device, original identifiers/group, no signature/profile, App Intent metadata `openAppWhenRun=false`. The CI probe launch marker is absent from the delivered device executable.

51 architecture/protected-file guards, production CRUD/migration/concurrency/backup, new compatibility/preview/range/row-budget checks, existing 4K/fonts/Emoji and 54 small native Emoji images at 1x/3x passed. There are zero Swift-source warnings. Actual PNG dimensions independently checked: 1890×4096 and 2304×4096.

iOS **26.5 Simulator**: nine actual heart outputs at 8/10/12/16/19/20/24/32/48pt fit their cell. Rendered ink widths at 3x were 20/26/31/41/50/53/65/88/132px, so growth continues beyond 24pt. Five completed-text effects have distinct actual pixel hashes. Thirty Widget images cover five Dynamic Type environments and normal/85% logical dimensions. UIKit body baseline15pt measured13/15/19.67/32.67/42.33 across the tested categories. The Simulator accepted the maximum system content-size command; actual app screenshots show the separate circle+current-tool Dock and the final single-line large-text settings menu. These are Simulator observations, not physical phone results.

The extra offscreen marker-card ScrollView snapshot was blank and **is excluded from visual passes**. Its larger card/number-field layout still needs the real control-page/manual accessibility check. No automated native tap sequence is claimed: preview routing is source/state tested, and real Widget App Intent taps remain on the phone checklist.

Two real CI runs, both successful: 1014 compiled and tested the first revision; reviewing its maximum-font screenshot found a crowded settings menu. Final1015 includes the corresponding compact-menu/card/numeric-field correction and repeats the declared checks. No further full builds for evidence-only documentation.

Artifact `todo-wallpaper-0.4.2-15`, id12601806039, 14,146,673 bytes, SHA256 `d8b754cfaf98dd81ba1d8405ff2a20d68c121c74708d984c3e7952daf84eebb5`. Unsigned IPA SHA256 `13bfc1afc66f981022a398ae0561f4bd632d48ca47884fec1d510577dece95d5`. The official ZIP was retained unchanged, downloaded and checked by SHA256/CRC; bundle metadata/platform/probe exclusion and original R1 scripts were independently verified (Windows line endings normalized).

**Windows signing/install, real iPhone system-font/Display Zoom, touches, scroll stability and Widget actions remain pending.** Use the unchanged R1 installer to cover the existing App, never uninstall it, then follow `TodoWallpaper/DEVICE-TEST.md`. Stop for user feedback.
