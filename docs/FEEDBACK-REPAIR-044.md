# 0.4.4 — iPhone feedback repairs

Final candidate **0.4.4 / 1022**, code `a4e3e423b92f593ee79dbd796e9a1754d85f3d69`. [Actions run 40456422144](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40456422144) succeeded. Windows signing, installation and physical iPhone acceptance remain pending.

- Static wallpaper has no completed-text strike/dim controls or rendering. Legacy draft fields remain decodable.
- Wallpaper marker source is explicit. Old drafts retain per-task markers. Choosing a uniform marker changes the wallpaper immediately while retaining original task Emoji. Individual markers can also be edited; automatic selection and its menu include only rows visible on the current canvas, excluding hidden completed/overflow tasks. Widget styles stay independent.
- Marker and text align as a group, fixing gap cancellation for center/trailing alignment. Both gap controls use 标记与文字间距.
- Menu/arrow/tool expansion share a Reduce Motion-aware animation. Gestures suppress only their own animations.
- Advanced export controls include an editor-only preview-size preference, 0.55–1.0, with undo. It never changes canvas/export coordinates.
- Every slider has standard-point capture, hysteresis and selection haptics. Numeric input bypasses snapping.
- Widget title has independent text, visibility, color, font/weight, horizontal alignment; advanced size and precise horizontal/top position. Top-right unfinished count has a switch. Header space is bounded and follows system text scaling.
- Widget photos: native PhotosPicker, orientation-normalized JPEG up to 1536 px long edge, local App Group storage, bounded decode cache. Preview and extension use the same background view. No album/network writes; system tint can change colors.
- Explicit EventKit import for Calendar events (at most 90 days per query) and Reminders, separately authorized and selected. Local snapshots, no automatic/bidirectional sync. Event date/time is included in task text. Source-derived UUIDs make repeat imports idempotent while Apple identifiers stay stable; account resync can change them.
- Ordinary undo immediately applies live state with deferred persistence, no photo loading overlay. Poster bitmap rendering is on demand for exact preview/export. Widget-only changes no longer invalidate wallpaper. Multi-task marker undo uses one compare-and-write repository transaction. Changing the photo still needs asynchronous image loading.

## Protected data and signing

Installation identifiers, task schema/IDs/order/completion, migration and R1 scripts/Intent remain unchanged. New appearance/draft fields are optional. Old backups/drafts remain decodable; downgrade after using the new photo backdrop is not supported.

Four protected-source hashes intentionally change after review: App Info.plist adds two EventKit purpose strings; TodoStore adds import/batch marker wrappers and ignores equal appearance changes; TodoRepository adds operations through its existing process lock/backup/atomic-write path; WallpaperGeometry excludes the retired completion effect from its glyph cache key. No signing or migration capability is replaced.

Older Widget photos are retained for undo/appearance backup references. Orphan-photo cleanup is outside this release.

## Verification scope

Local checks: Python/shell syntax, deterministic Xcode generation, architecture/protected-source guards and public-upload inspection.

macOS CI: existing CRUD/migration/backup/Intent regressions, detents, bounded header geometry, local import idempotence and marker conflicts; static wallpaper effects, actual PNG gap deltas in three alignments, five marker outputs, old draft compatibility and existing 4K/Emoji/font-weight tests.

iOS Simulator CI: production live-model marker ownership, ordinary undo fast-path timing (state application, not physical button latency), Widget photo encode/decode/background pixels, custom header/count images, color Emoji and five Dynamic Type environments, actual editor screenshots.

Physical iPhone permissions, touch animation, haptics, undo responsiveness, signing, installation and system Widget functionality remain pending real feedback. CI does not establish them.

EventKit references: [Apple access-level sample](https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui), [Reminders permission](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders(completion:)), [fetchReminders](https://developer.apple.com/documentation/eventkit/ekeventstore/fetchreminders(matching:completion:)). Design references, not device evidence.

## Actual result

Device App+Widget and Simulator compiled successfully; 104 architecture/reviewed-source guards and all native regression checks passed. Custom title glyph completeness, right-count on/off pixels and shared photo readback passed; actual screenshots reviewed. Full evidence and prior attempts are recorded in VALIDATION.json. No real iPhone success is inferred.
