#!/bin/bash
set -euo pipefail
# Target Membership：原生检查脚本；执行与 App 相同的 ImageIO/CoreGraphics 分析服务。
PHOTO_ANALYSIS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PHOTO_ANALYSIS_ROOT"
PHOTO_ANALYSIS_TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
mkdir -p TodoWallpaper/out
swiftc -parse-as-library TodoWallpaper/Core/*.swift \
    TodoWallpaper/Shared/AppearanceStore.swift TodoWallpaper/App/PhotoAnalysisService.swift \
    TodoWallpaper/Tests/PhotoAnalysisChecks.swift \
    -o "$PHOTO_ANALYSIS_TEMP/todo-photo-analysis-checks" 2>&1 | tee TodoWallpaper/out/photo-analysis-compile.log
"$PHOTO_ANALYSIS_TEMP/todo-photo-analysis-checks" | tee TodoWallpaper/out/photo-analysis-checks.log
