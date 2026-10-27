# Todo Wallpaper 0.5.0 / 1025

[Implementation and limits](../docs/MEDIA-MOTION-050.md) · [Validation](../docs/VALIDATION.json) · [Windows/iPhone checklist](DEVICE-TEST.md).

Actions run 40465212518 passed actual unsigned ARM64 App+Widget compilation, production native Core/PNG tests and iOS Simulator rendering. Physical iPhone performance, signing/install, Photos permissions/album selection and Widget system-material appearance remain separate and pending.

- Native four tabs with pinned previews; reducing wallpaper preview now grows the inspector.
- Retained CA photo/panel gestures with one commit at end; small cached blur texture, full target-pixel composition for exact preview/export.
- Widget photo normalized crop, pinch/pan, opacity; explicit theme contrast, footer switch and labeled text-tap effects.
- Native PhotoKit album selection, up to 60 local cached photos, daily Widget timeline. Reselect the album after changes. Actual delivery is system scheduled.
- Optional floating date/time per task; legacy records unchanged until edited; dates survive title/marker/completion operations. Existing Calendar/Reminders import available from create sheet.
- Experimental public material background request; clear/tinted system rendering retained. No assertion of Batteries-style glass in default/dark modes.

Minimum iOS17. Stable IDs org.todowallpaper.app / org.todowallpaper.app.widget / group.org.todowallpaper.app. R1 scripts, Intent and shared migration remain unchanged. Use the same account and cover-install; do not uninstall the existing app. No PWA, AI or cloud-sync implementation is introduced.
