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
