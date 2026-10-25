#!/bin/bash
set -euo pipefail
# This is an isolated Simulator Debug build, not the IPA delivered to Windows.
TODO_UI_CHECKS=1 python3 native-tools/generate_product_project.py
xcodebuild build -project TodoWallpaper/TodoWallpaper.xcodeproj -scheme TodoWallpaper -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$RUNNER_TEMP/todo-ui-simulator" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee TodoWallpaper/out/ios-ui-compile.log
UI_RUNTIME=$(xcrun simctl list runtimes --json | python3 -c 'import sys,json; r=[x for x in json.load(sys.stdin)["runtimes"] if x.get("isAvailable") and x["name"].startswith("iOS")]; assert r,"No available iOS simulator runtime"; print(sorted(r,key=lambda x:tuple(map(int,x["version"].split("."))))[-1]["identifier"])')
UI_DEVICE_TYPE=$(xcrun simctl list devicetypes --json | python3 -c 'import sys,json; d=json.load(sys.stdin)["devicetypes"]; p=[x for x in d if x["name"]=="iPhone 13 Pro"]; p=p or [x for x in d if x["name"].startswith("iPhone")]; assert p; print(p[0]["identifier"])')
UI_SIMULATOR=$(xcrun simctl create "Todo Wallpaper UI Checks" "$UI_DEVICE_TYPE" "$UI_RUNTIME")
trap 'xcrun simctl shutdown "$UI_SIMULATOR" >/dev/null 2>&1 || true; xcrun simctl delete "$UI_SIMULATOR" >/dev/null 2>&1 || true' EXIT
xcrun simctl boot "$UI_SIMULATOR"
xcrun simctl bootstatus "$UI_SIMULATOR" -b >/dev/null
xcrun simctl install "$UI_SIMULATOR" "$RUNNER_TEMP/todo-ui-simulator/Build/Products/Debug-iphonesimulator/TodoWallpaper.app"
xcrun simctl launch "$UI_SIMULATOR" org.todowallpaper.app --native-ui-probe >/dev/null
UI_CONTAINER=$(xcrun simctl get_app_container "$UI_SIMULATOR" org.todowallpaper.app data)
UI_OUTPUT="$UI_CONTAINER/Documents/native-ui-checks"
for UI_ATTEMPT in $(seq 1 90); do
    if [ -f "$UI_OUTPUT/done.json" ]; then break; fi
    sleep 1
done
mkdir -p TodoWallpaper/out/ios-ui-checks
if [ -d "$UI_OUTPUT" ]; then ditto "$UI_OUTPUT" TodoWallpaper/out/ios-ui-checks; fi
python3 - <<'PY'
import json
from pathlib import Path
p=Path('TodoWallpaper/out/ios-ui-checks/done.json')
assert p.exists(), 'Simulator native probe timed out; see iOS compiler log'
r=json.loads(p.read_text())
print(json.dumps(r,ensure_ascii=False,indent=2))
assert r.get('result')=='passed', r.get('error','Native Simulator render check failed')
PY
sleep 1
xcrun simctl io "$UI_SIMULATOR" screenshot TodoWallpaper/out/ios-ui-checks/actual-editor-dock.png >/dev/null 2>&1
xcrun simctl terminate "$UI_SIMULATOR" org.todowallpaper.app >/dev/null
xcrun simctl launch "$UI_SIMULATOR" org.todowallpaper.app --native-ui-probe --native-widget-screen >/dev/null
sleep 2
xcrun simctl io "$UI_SIMULATOR" screenshot TodoWallpaper/out/ios-ui-checks/actual-widget-page.png >/dev/null 2>&1
if xcrun simctl ui "$UI_SIMULATOR" content_size accessibility-extra-extra-extra-large >/dev/null 2>&1; then
    sleep 2
    xcrun simctl io "$UI_SIMULATOR" screenshot TodoWallpaper/out/ios-ui-checks/actual-widget-max-system-text.png >/dev/null 2>&1
    echo 'Simulator system content-size command accepted; screenshot captured. Real iPhone Display Zoom not verified.' > TodoWallpaper/out/ios-ui-checks/system-size-scope.txt
else
    echo 'Simulator system content-size command unavailable. Five Dynamic Type environments and UIKit metrics were still rendered. Real iPhone Display Zoom not verified.' > TodoWallpaper/out/ios-ui-checks/system-size-scope.txt
fi
echo 'PASS: iOS Simulator native SwiftUI Emoji pixels, completion effects, five Dynamic Type sizes, reduced logical-space matrix and actual app screenshots. Not a physical iPhone acceptance result.'
