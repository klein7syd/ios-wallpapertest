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
