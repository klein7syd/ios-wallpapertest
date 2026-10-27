# Todo Wallpaper 0.4.4 / 1022

[Changes, data scope and limits](../docs/FEEDBACK-REPAIR-044.md) · [Actual validation](../docs/VALIDATION.json) · [Windows/iPhone checklist](DEVICE-TEST.md).

Actual Actions run **40456422144** passed: unsigned ARM64 App+Widget, production storage/migration/backup/PNG checks, and native iOS Simulator rendering/screenshots. Zero Swift-source warnings. Windows signing, installation and real iPhone acceptance remain pending.

Minimum iOS 17. IDs remain org.todowallpaper.app, org.todowallpaper.app.widget, group.org.todowallpaper.app. Use the existing iPASide/R1 installer to cover-install with the same account; keep the current app installed.

- Four native tabs; fixed previews and independently scrolling controls; advanced controls in About.
- Wallpaper uniform/task marker selection targets visible rows; real gap adjustments under all alignments; static completion text; preview scale; common expansion animation; snap-to-standard sliders.
- Widget custom title/count, local photo background, independent marker/text styles and direct App Intent completion/restore.
- Explicit local Calendar/Reminders selection/import through EventKit. Imported tasks are independent snapshots.
- Ordinary undo applies live settings without photo decoding or poster bitmap rendering. Exact preview/export runs on demand.
- Real target-pixel SDR PNG export: 19.5:9 approx 1890×4096, 16:9 2304×4096, custom ratios/pixels. Original drafts/photos/tasks and R1 signing sources preserved.

CI is evidence of compilation and its stated native checks. Touch feel, scrolling, haptics, system Widget appearance/interaction, permissions, signing and installation require real iPhone feedback.
