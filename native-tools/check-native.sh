#!/bin/bash
set -euo pipefail
# Compile and execute the production persistence code with independent files.
swiftc -parse-as-library TodoWallpaper/Core/*.swift TodoWallpaper/Tests/RepositoryChecks.swift TodoWallpaper/Tests/MigrationChecks.swift -o "$RUNNER_TEMP/todo-repository-checks"
"$RUNNER_TEMP/todo-repository-checks" | tee TodoWallpaper/out/repository-checks.log
mkdir -p TodoWallpaper/out/render-checks
python3 native-tools/make-render-fixture.py TodoWallpaper/out/render-checks/fixture-input.png
# Execute the exact production renderer on macOS, not HTML or a Python imitation.
swiftc -O -parse-as-library TodoWallpaper/Core/*.swift \
    TodoWallpaper/Wallpaper/WallpaperSettings.swift TodoWallpaper/Wallpaper/WallpaperRenderer.swift \
    TodoWallpaper/Wallpaper/WallpaperDraftStore.swift TodoWallpaper/Wallpaper/WallpaperGeometry.swift \
    TodoWallpaper/Tests/WallpaperRenderChecks.swift TodoWallpaper/Tests/D34Checks.swift \
    -o "$RUNNER_TEMP/todo-wallpaper-render-checks" 2>&1 | tee TodoWallpaper/out/render-compile.log
"$RUNNER_TEMP/todo-wallpaper-render-checks" TodoWallpaper/out/render-checks | tee TodoWallpaper/out/render-checks.log
