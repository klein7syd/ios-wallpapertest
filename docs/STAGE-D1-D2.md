# D1 + D2 · Native wallpaper editor

Version 0.3.0. Stage C 0.2.0 / 1002 accepted by the user in the D1+D2 instruction on 2026-10-25. D1+D2 device acceptance remains pending.

## Scope and identities

Native SwiftUI wallpaper tab added to the existing system TabView. Existing todo screens are unchanged. Product IDs remain `org.todowallpaper.app`, `org.todowallpaper.app.widget`, `group.org.todowallpaper.app`. No new entitlements. Todo core, migration/backup, Widget, intents, R1 installer and native-validation baseline are unchanged. Wallpaper data is stored separately in private Application Support/WallpaperEditor and never writes todo data.

## Rendering contract

`WallpaperSettings` stores a 390-unit logical canvas, normalized panel centers and aspect-fill photo pan. Shared Core Text layout shapes real TodoStore items in existing order. It measures fallback glyphs, wraps long titles, limits per-item lines with ellipsis, fits complete rows and reports omitted count. Default panel is centered with automatic height. Extreme parameters are bounded to the canvas.

`WallpaperRenderer` renders background crop, a clipped Core Image Gaussian backdrop blur, neutral black/white translucent fill, white border/highlight, vector status marks and Core Text glyphs into an sRGB Core Graphics bitmap. Both preview and export invoke this renderer and layout at different raster scales. Export allocates target pixel dimensions, draws again from the locally retained original and writes PNG using ImageIO, then independently reads its pixel metadata. It does not enlarge the preview, snapshot the screen or attempt to capture SwiftUI system materials. Differences in rasterization/downsampling at preview vs final resolution remain possible; no pixel-perfect claim.

Actor-isolated rendering runs outside the UI actor, debounces/cancels obsolete previews, serializes expensive work and signals export progress. Selected source data remains local; EXIF/GPS is not copied to output. Original source encoding is retained; decoded working image long edge is bounded to 6144 to limit memory. Export max 12 MP, each axis 480–4096. Source-resolution warnings consider full target and zoom. Output is SDR sRGB, not HDR or Live Photo.

## Persistence and permissions

One versioned local JSON draft with atomic writes. Selected photo is validated before draft reference commit. Unreadable or newer draft is preserved and prevents autosave until explicit reset; reset archives the file. Default reset retains valid photo and target size. Selected original is kept across app restarts. Old unreferenced photos/exports expire after 24h on editor entry; explicit cache clear touches only generated export PNGs. Preview is memory-only and never writes Photos.

PhotosPicker grants access to the selected asset; no broad photo-read permission requested. Only explicit Save requests add-only authorization with NSPhotoLibraryAddUsageDescription. PHPhotoLibrary errors are surfaced; system sharing works without adding to Photos. User manually sets wallpaper using supported system UI; no silent background wallpaper API.

## Automated evidence

The product workflow runs unchanged production repository/migration checks, compiles and executes the actual wallpaper renderer on macOS using synthetic fixture files, then builds real ARM64 iOS App + embedded Widget unsigned. Rendering checks cover output PNG dimensions/readback, shared logical wrap/geometry, zero-material no-tint/orientation, crop bounds, presets/custom sizes, overflow and protected draft reset. Generated PNGs are artifacts for visual inspection, never app sample content.

Compilation, signing, installation and iPhone behavior are recorded separately in docs/VALIDATION.json. See TodoWallpaper/DEVICE-TEST.md for the Windows/iPhone checklist. D3+D4 await actual iPhone feedback.

## Actual delivery · 2026-10-25

- Version **0.3.0 / 1005**, code commit `a6850546717a17dae3bcb438a0b1636d7e06e5c0`.
- [Actions run 40115769912](https://github.com/klein7syd/ios-wallpapertest/actions/runs/40115769912), job 120936609323: success, **BUILD SUCCEEDED**. Both ARM64 device targets, no Swift source warning in the final build.
- Production repository/migration checks passed, including concurrent writes and recovery.
- Production renderer executed and wrote verified PNGs at 1170×2532, 390×844 preview, 1200×1200 and 1600×900. Layout and wrapping match; zero-material RGBA channel difference = 0. Five device presets checked.
- Inspected the generated 1170×2532 and 1200×1200 images: center/bounds, Chinese wrapping, emoji, truncation, completed styling and omission footer visible. These are synthetic macOS outputs, not phone screenshots or device acceptance.
- Downloaded artifact digest and ZIP CRC checked, then independently inspected the actual IPA: main+one Widget extension, stable IDs/group, version/build match, true ARM64 iOS device platform, App Intents metadata in both with openAppWhenRun=false, no embedded profile/signature.
- IPA SHA256: `a8b3b59bff7568395d46b6eecd07df32769222acbd0b13b09143ac87cde6d777`.
- Artifact 12568511768, ZIP SHA256 `cb7dd79a1abc4aac2dbd735f49ed2b67fbab84b2818a37709e91f4f25ebab215`. Contains unsigned IPA, original Windows R1 scripts, device checklist, actual logs and synthetic rendering outputs.
- Three macOS runs this delivery: first failed at Swift mixed-number type inference; second passed renderer checks but failed at two SwiftUI Section initializers; third passed after log-based fixes. No blind reruns. Result documentation uses [skip ci].
- **Windows signing, 0.2.0→0.3.0 overlay installation, Photos permissions, touch gestures, Widget regression and actual iPhone export remain pending. D3+D4 not started.**
