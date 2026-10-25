# D3 + D4 · Emoji, ratio-first 4K and live native canvas

Scope follows the user's final 2026-10-25 instruction. 0.3.0 / 1005 received first real-iPhone testing: overall positive, with small preview, stepped movement and ineffective weights reported. This is feedback, not a blanket device pass for the new build.

Version 0.4.0. Main, Widget, App Group identities remain `org.todowallpaper.app`, `org.todowallpaper.app.widget`, `group.org.todowallpaper.app`. Native TabView keeps three tabs. R1 installer, resource seals, original validation project and App Intent implementation stay unchanged.

## Live editor

Large canvas with a compact, collapsible bottom inspector for Background / Panel / Text / Marker / Export. No long Form in the editor. Photos are decoded to a cached 2048px working image once on selection. SwiftUI moves/scales that texture and the masked backdrop/tint/highlight layers directly. A small UIKit glyph layer draws the same production Core Text lines and marker geometry; panel movement does not re-layout text or regenerate a full image. Fast geometry/tint/blur changes bypass glyph redraw; text changes reshape only text. High-precision bitmap preview is debounced 240ms after changes and available in full-screen comparison; export independently re-renders from the retained original at target pixels. No claim about actual iPhone frame rate before device feedback.

Quick color swatches, opacity/RGB controls stay inline; system ColorPicker is also provided and its presentation follows iOS. Numeric controls allow three decimal places, with direct panel dragging, center guides and one-output-pixel nudges. Background drag/pinch and slider changes never wait for a full Core Image poster.

## Weight and markers

Native weighted UIFont/NSFont system, serif and monospaced font APIs replace ineffective changes to a concrete regular-face CTFont descriptor. Core Text receives the weighted result. A weighted PingFang cascade is explicit for system/monospaced CJK; PingFang has no separate bold face, so bold can reuse semibold. Serif fallback follows installed system font capabilities; no artificial stroke bolding.

Shared models support hollow/filled/thin/bordered circle, square, arbitrary one-grapheme Emoji, or none. Emoji validation rejects plain text, multiple clusters, stand-alone skin modifiers and oversized input; full families, skin tones, flags and keycaps remain intact. A text field uses the system keyboard; shortcuts supplement rather than replace free input. Clearing a task override restores inheritance.

Global default and marker appearance live in App Groups `appearance-v1.json`; task overrides are optional fields in existing `todos-v1.json`. Precedence: task override > Widget-specific default (Widget only) > global default. No duplicate task collection. App list, live preview, PNG and all Widget sizes use the same task IDs and marker definitions. Emoji remains colored and completion can preserve, dim or replace it; shape-only checkmarks do not force Emoji into circles.

## Ratio/output and compatibility

Modern portrait 19.5:9 is an approximate common ratio; classic portrait 16:9 and custom width:height are available. Ratio is separate from output pixels. Moderate height 2048; high height 4096: modern 1890×4096, classic 2304×4096. Custom pixels must agree with canvas ratio within one pixel. Output dimensions stay bounded to each axis 480–4096 and 12 MP; square 4096² exceeds that bound, so use moderate/custom. Small rounding differences use uniform scale and centered clipping, never nonuniform stretch.

Legacy wallpaper settings omit the new optional canvasAspect; they continue to derive their exact ratio from original pixels, retaining old composition/output/photo. First upgraded save archives exact old draft as `draft-before-d34.json`. Draft schema remains additive version 1. Selected originals remain local and unchanged.

TodoItem's optional marker decodes missing fields as nil; UUID, order, dates and completion stay unchanged. Core RMW lock, atomic writes, migration receipts and valid previous backup remain. Intents use the same repository completion operation and preserve markers. Shared appearance has its own process lock, atomic primary/backup, refuses corrupt/future writes, and supports explicit valid-backup recovery without touching tasks. Downgrading to an older binary can discard unknown optional fields on edits; forward overlay installation is the supported test route.

## Widget appearance

Separate settings page is reached from About or the wallpaper inspector, with no extra app Tab. Theme/background, text/font/weight, default marker, Emoji size, spacing/density, item limit and completed visibility are independent. Apply-wallpaper-style copies compatible font/color/marker/theme fields only; it never copies photos/crops/positions, and task-specific overrides remain authoritative. Writes request WidgetKit refresh; system scheduling/tint/background policies still apply.

## Evidence and acceptance

CI must run production repository/migration checks, actual weighted-font/colored-Emoji raster comparisons, shape output, modern/classic 4K PNG readback, continuous transform and layout equivalence, legacy task/backup/draft/photo checks and shared Widget-style roundtrip. It then compiles unsigned ARM64 App + embedded Widget and inspects actual IPA/intent metadata. Result JSON, PNGs and logs are build artifacts. Windows signing/install, performance, Emoji appearance on iPhone and interactive Widget regression remain separate, pending device checks. No AI/translation/cloud sync/automatic wallpaper changes are included.

## Actual final delivery · 2026-10-25

- **0.4.0 / 1010**, code commit `a59718b3d8b951782bbab0efccce6838ebc47d01`.
- [Actions run 40180955157](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40180955157), job 121131707564: **success / BUILD SUCCEEDED**. Both ARM64 device bundles are unsigned, IDs/group unchanged, matching version/build; metadata in both targets contains SetTodoCompletionIntent with openAppWhenRun=false. No Swift source warnings in the final build.
- Actual IPA SHA256: `ada475a4d13f38c7a821a68099baf92dda318233799884176525bf6e66ea82c6`. Artifact 12594448166; ZIP SHA256 `f3b5898aef06dea5191cbb130690c39a44e0379306c5196246c136e94875a43a`. Download digest and ZIP CRC independently checked.
- Real production native checks passed: CRUD/backups/migration/three-process writes, actual weighted font raster hashes, composed/skin-tone Emoji PNGs, marker geometry/variable thin-circle width, continuous coordinates, ratio/resolution composition, modern 1890×4096 and classic 2304×4096 PNG readback, legacy item/draft/photo preservation and shared Widget style precedence/roundtrip.
- System mixed-script weights yielded five distinct pixel hashes; ink counts light3679 / regular4333 / medium5044 / semibold5523 / bold5967. Chinese samples yielded four native faces, with bold/semibold mapped to the same supported PingFang face.
- Color pixel checks passed for heart, blossom, books, toned thumb, toned technologist, family, flag and keycap. Native musical note is achromatic and is verified by actual nonzero native glyph/ink rather than requiring invented color. The source Emoji is retained; no fixed picture assets replace user input.
- Inspected actual modern/classic 4K output, wrapping/alignment and separate composed/tone/note/font PNGs. These are synthetic macOS images. iPhone UI/FPS, system ColorPicker, Photos, signing, overlay installation, Widget rendering/taps/tint remain pending real-device feedback.
- Five CI triggers: two failed (overstrict chromatic-note test; SwiftUI multi-variable State declarations) and were fixed from actual logs; three succeeded, including final review fixes for adjustable thin-line style and marker-hidden completion accessibility. No blind reruns. Docs-only result update uses [skip ci].
- R1 installer, original probe and completion Intent source hashes are unchanged. Packaged Python scripts byte-match; CMD/PS1 use the CRLF conversion declared by .gitattributes. This is not a signature/seal mutation inside the unsigned IPA.
- No next phase started.
