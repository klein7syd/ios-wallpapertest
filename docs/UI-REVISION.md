# Native UI feedback revision · 0.4.1

Base: `7b29bae4ebfdb42fa34a898bb76e0a9094df27a1`, previous delivered App 0.4.0 / 1010. The user reports another iPhone test and requests an interface revision, not new product features.

## Presentation architecture

- Four native TabView roots: Todo, Wallpaper, Widget, About. Widget is the full editor; duplicate pushed entrances removed.
- `AppNavigationState` explicitly tracks selected root, active wallpaper tool and inspector visibility. In ordinary mode the system Tab Bar is visible. Selecting a tool hides it with public SwiftUI `toolbar(_:for:)`; the editor Dock supplies a 44pt circular page menu and the five tools. Restoring the full tabs or selecting any page clears editing state. No private API or overlay over the system Tab Bar.
- Wallpaper canvas and controls are sibling layout regions. Expanded panel height adapts to available safe-area/keyboard height, retaining canvas space. The Dock remains present when settings collapse. Only entering/exiting/collapsing the Dock animates; tool contents replace directly.
- Reusable `InspectorViewport` has one bounded vertical ScrollView and explicit scroll/outer clipping. Common and advanced controls are separate pages, not nested DisclosureGroups. Tool/detail changes reset the page's top anchor; changing a value does not change view identity or scroll position.
- 28pt continuous outer panel, 16pt tool/choice surfaces, 44pt navigation/touch targets. No extra decorative shadow or thick panel outline. Sliders remain continuous; display precision is tailored to point/ratio/coordinate values.

## Conditional and visual controls

`MarkerControlVisibility` selects actual controls by marker kind. Emoji exposes its own size/gap and advanced alignment/completion; outlined shapes expose stroke and no fill; filled shapes prioritize fill with border settings under More; no marker exposes no style controls. Color-following hides independent shape colors. Replacement Emoji/completed color appear only for their selected completion policy. Existing dormant numbers/colors are not cleared.

`MarkerChoiceEditor` uses the actual shared SwiftUI shape/Emoji renderer in horizontal, selected-state cards, with VoiceOver labels. Reused in Wallpaper, Widget/global defaults and per-task editing. The seven existing marker kinds are preserved; no extra stored marker enum cases or data schema are introduced. Free Emoji keyboard input and validation remain.

Photo crop controls require a photo. Manual height requires automatic height off; X/Y requires custom position on. Text completion style requires completed items visible. Color editing uses quick swatches, native ColorPicker (including its precise color input) and a single opacity slider, without custom RGB DisclosureGroups.

## Pinned Widget preview

The root VStack owns the fixed preview and category bar; only the lower InspectorViewport scrolls. Small/medium/large keep reference family aspect ratios and scale down in a bounded upper area. `TodoWidgetContent` is shared by preview and the actual extension, retaining row capacity, real items, markers and line limits. The extension still wraps rows in `Button(intent: SetTodoCompletionIntent(...))`; app preview is noninteractive. This is a layout preview, not a claim of identical system margins, host background or device interactivity.

Custom background alpha is shown over an app-only transparency grid; the grid never enters the extension. Alpha changes only the supplied bottom color, not iOS host material. Actual system light/dark/tinted/clear presentation and refresh scheduling remain controlled by iOS. No screenshot-based transparency was added.

## Floating-text report: findings and limit of evidence

The old editor combined a bottom ZStack overlay, a fixed 184pt scroll viewport, dynamically expanding DisclosureGroups, implicit collapse animation and a material shaped background without clipping the whole panel. The canvas also reserved only 132pt for a taller inspector. These are concrete clipping/space-allocation risks found in source. The Widget preview was inside a scrolling Form.

This revision removes that structure: siblings allocate actual space, a single viewport clips descendants, the outer continuous shape clips the complete inspector, detail controls replace rather than shrink nested groups, and content replacement is independent from Dock animation. The UIKit wallpaper glyph layer also clips its own bounds.

The cloud workspace cannot reproduce the user's physical iPhone scrolling. Therefore the exact device-specific failure mechanism and complete visual fix are **not established by source checks or CI**. Repeated details/back/scroll, panel collapse/reopen, keyboard/sheet dismissal and safe-area testing are mandatory in [the device checklist](../TodoWallpaper/DEVICE-TEST.md). No XCTest UI/simulator interaction is claimed.

## Data, rendering and signing

One small marker behavior correction keeps an explicitly hidden marker hidden even if the saved completion policy is “replace with Emoji”; the policy itself is preserved. There are no new stored fields.

No installation IDs, App Group configuration, task/document/appearance/draft schemas, task IDs, source photos, repository/migration/backup code, weighted fonts, production PNG renderer, App Intent implementation or Windows R1 scripts are changed. The new navigation/detail state is transient UI state; it is not written into tasks or drafts. `UI-PROTECTED-SOURCES.json` records the preserved source checksums (Windows text scripts normalized to LF for comparison).

Existing production repository/migration/native PNG checks continue. New executable Swift state checks cover root/Dock transitions, repeat switching/collapse, marker-control capabilities, dormant-value compatibility, reduced-height allocation and family ratios/capacities. A separate source-architecture guard checks containment, clipping, shared preview/extension rows, public navigation, no duplicate entrances and protected sources. These checks do not prove iPhone scrolling, frame rate, signing, Photos permission, safe areas or Widget interaction.

Build and device evidence is recorded after the real workflow in `VALIDATION.json`. The output is an **unsigned** ARM64 device IPA including the Widget, plus unchanged R1 Windows scripts. Do not uninstall the previous App; use the same iPASide account and installation identity. No Release is created. Stop after this delivery for iPhone feedback.
