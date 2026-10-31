#!/bin/bash
set -euo pipefail
# 独立采样工作流；正式分组交付仍必须运行完整build-product.sh，绝不代替原门禁。
mkdir -p TodoWallpaper/out
TODO_UI_CHECKS=1 python3 native-tools/generate_product_project.py
xcodebuild build -project TodoWallpaper/TodoWallpaper.xcodeproj -scheme TodoWallpaper -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/todo-ui-simulator" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee TodoWallpaper/out/mode-compile.log
MODE_RUNTIME=$(xcrun simctl list runtimes --json | python3 -c 'import sys,json; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("iOS")]; assert r; print(sorted(r,key=lambda x:tuple(map(int,x["version"].split("."))))[-1]["identifier"])')
MODE_TYPE=$(xcrun simctl list devicetypes --json | python3 -c 'import sys,json; r=json.load(sys.stdin)["devicetypes"]; p=[x for x in r if x["name"]=="iPhone 13 Pro"]; p=p or [x for x in r if x["name"].startswith("iPhone")]; assert p; print(p[0]["identifier"])')
MODE_DEVICE=$(xcrun simctl create "Todo Wallpaper Mode Measurement" "$MODE_TYPE" "$MODE_RUNTIME")
trap 'xcrun simctl shutdown "$MODE_DEVICE" >/dev/null 2>&1 || true; xcrun simctl delete "$MODE_DEVICE" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$MODE_DEVICE"
xcrun simctl bootstatus "$MODE_DEVICE" -b >/dev/null
xcrun simctl install "$MODE_DEVICE" "$RUNNER_TEMP/todo-ui-simulator/Build/Products/Debug-iphonesimulator/TodoWallpaper.app"
python3 native-tools/check-mode-performance.py "$MODE_DEVICE"
