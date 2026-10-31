#!/bin/bash
set -euo pipefail
# 独立并行门禁：仍编译同一生产App的Debug与CI夹具，不能代替原有UI/像素检查。
mkdir -p TodoWallpaper/out
MODE_BUILD=$(python3 -c 'import os,json; print(1000+int(os.environ["GITHUB_RUN_NUMBER"]) if "GITHUB_RUN_NUMBER" in os.environ else json.load(open("native-tools/product-version.json"))["fallback_build"])')
TODO_UI_CHECKS=1 python3 native-tools/generate_product_project.py
xcodebuild build -project TodoWallpaper/TodoWallpaper.xcodeproj -scheme TodoWallpaper -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/todo-ui-simulator" CURRENT_PROJECT_VERSION="$MODE_BUILD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee TodoWallpaper/out/mode-compile.log
python3 native-tools/check-mode-performance.py
