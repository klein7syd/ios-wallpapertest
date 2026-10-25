# Todo Wallpaper 0.4.0 · D3+D4

Minimum iOS17. Stable IDs and native navigation preserved. CI build number = 1000 + product workflow run number.

- Core: backward-compatible optional task marker, original repository lock/backup/migration; shared appearance lock+backup and weighted native typography.
- Shared: unchanged completion App Intent and common native marker view used by App and Widget.
- Widget: interactive small/medium/large widgets with task Emoji and independent App Groups appearance.
- App: existing CRUD/navigation; task marker override editor and Widget/global style page under About.
- Wallpaper: large live canvas, cached photo textures, GPU transformations/backdrop, small shared Core Text vector layer; stable native bitmap preview and full target-pixel PNG export. Ratio is independent of resolution; 19.5:9 modern, 16:9 classic and custom. Old draft/photo stays compatible.
- Tests: production repository, migration, marker/appearance compatibility and actual font/colored-Emoji/4K/geometry image output. Synthetic content stays in tests only.
- native-tools: deterministic Xcode generator, one product workflow, unsigned packaging/IPA checks and unchanged R1 Windows installer.

[Implementation/limits](../docs/STAGE-D3-D4.md) · [Validation evidence](../docs/VALIDATION.json) · [Windows and iPhone checklist](DEVICE-TEST.md). No iPhone success is inferred from CI.

Final build **1010**: [actual Actions success](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40180955157). Both unsigned ARM64 bundles independently inspected. Native PNG/compatibility checks passed; actual iPhone live interaction and Widget regression await feedback. See full evidence and limitations above.
