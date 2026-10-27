# Todo Wallpaper 0.5.1 / 1029

[Implementation, evidence and limits](../docs/PHOTO-EDITOR-REPAIRS-051.md) · [Validation](../docs/VALIDATION.json) · [Windows/iPhone checklist](DEVICE-TEST.md).

Actions [40481159418](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40481159418) passed unsigned ARM64 App+Widget compilation, production native Core/PNG tests and iOS Simulator checks. Zero Swift-source warnings. Signing/install, Home Screen photo behavior, iPhone touch FPS and default-icon glass remain pending real-device testing.

- Native four tabs, pinned previews and wallpaper 4K export preserved.
- Widget timeline carries bounded prepared photos; today/tomorrow only, decoded sources released after handoff. Views do not resolve source photos at render time. Daily rotation is system scheduled.
- Global and per-task custom photo markers join existing Emoji/geometry; generated 512px PNG assets stay in the App Group. Emoji/images request full-color accented rendering on supported iOS.
- Native UISlider tracks immediately and coalesces model publications by display frame. Appearance writes/Widget reload requests wait until a continuous edit ends; grouped undo retained.
- Row spacing lives in Text, range 0–40, with tight single-line layout. Count switch lives in Content. Marker-tap effects have a visible heading.
- Header top inset uses a top-aligned frame. Native rendered title ink is identical at 0/12/24 inset with the summary hidden.
- Automatic solid-background text contrast preserves user opacity; subtle shadows protect text on photos/translucent panels. Wallpaper preview/PNG share text drawing.
- First theme control requests public Liquid Glass on iOS26, older systems use material. Default/dark icon mode is experimental; no Batteries equivalence claim. System clear/tinted mode is a distinct system path.

Minimum iOS17. Stable IDs `org.todowallpaper.app` / `org.todowallpaper.app.widget` / `group.org.todowallpaper.app`. Original R1 scripts, Intent, task repository and shared migration stay unchanged. Use the same account and cover-install; do not uninstall. No PWA, AI or cloud sync.
