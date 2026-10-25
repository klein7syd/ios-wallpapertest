#!/bin/bash
set -euo pipefail
mkdir -p TodoWallpaper/out
PRODUCT_BUILD=$((1000 + GITHUB_RUN_NUMBER))
{ sw_vers; xcodebuild -version; xcrun --sdk iphoneos --show-sdk-version; } > TodoWallpaper/out/toolchain.txt
# Collect both test and iOS compiler diagnostics in the same run, but never package
# a deliverable if native checks fail. This avoids a second run just to discover UI errors.
NATIVE_CHECKS_PASSED=true
if bash native-tools/check-native.sh; then :; else NATIVE_CHECKS_PASSED=false; fi
python3 native-tools/generate_product_project.py
plutil -lint TodoWallpaper/TodoWallpaper.xcodeproj/project.pbxproj TodoWallpaper/App/Info.plist TodoWallpaper/Widget/Info.plist TodoWallpaper/App/TodoWallpaper.entitlements TodoWallpaper/Widget/TodoWallpaper.entitlements
xcodebuild build -project TodoWallpaper/TodoWallpaper.xcodeproj -scheme TodoWallpaper -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/todo-wallpaper-derived" ARCHS=arm64 CURRENT_PROJECT_VERSION="$PRODUCT_BUILD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee TodoWallpaper/out/build.log
PRODUCT_APP="$RUNNER_TEMP/todo-wallpaper-derived/Build/Products/Release-iphoneos/TodoWallpaper.app"
for PRODUCT_BINARY in "$PRODUCT_APP/TodoWallpaper" "$PRODUCT_APP/PlugIns/TodoWallpaperWidget.appex/TodoWallpaperWidget"; do
    lipo -archs "$PRODUCT_BINARY" >> TodoWallpaper/out/architectures.txt
    xcrun vtool -show-build "$PRODUCT_BINARY" >> TodoWallpaper/out/platform.txt
done
if [ "$NATIVE_CHECKS_PASSED" != true ]; then
    echo "Native checks failed; iOS compiler diagnostics collected, no deliverable IPA packaged." >&2
    exit 1
fi
mkdir -p TodoWallpaper/out/package/Payload
ditto "$PRODUCT_APP" TodoWallpaper/out/package/Payload/TodoWallpaper.app
(cd TodoWallpaper/out/package && ditto -c -k --keepParent Payload ../TodoWallpaper-unsigned.ipa)
python3 native-tools/verify_product_ipa.py TodoWallpaper/out/TodoWallpaper-unsigned.ipa | tee TodoWallpaper/out/package-verification.json
shasum -a 256 TodoWallpaper/out/TodoWallpaper-unsigned.ipa > TodoWallpaper/out/checksum.sha256
cp TodoWallpaper/DEVICE-TEST.md TodoWallpaper/out/
cp native-tools/windows/*.py native-tools/windows/*.ps1 native-tools/windows/*.cmd TodoWallpaper/out/
python3 - <<'PY'
import json,os,shutil
from pathlib import Path
out=Path('TodoWallpaper/out')
report=json.loads((out/'package-verification.json').read_text())
(out/'status.json').write_text(json.dumps({'stage':'native_UI_feedback_revision','compilation':'succeeded','repository_and_migration_checks':'passed',
    'wallpaper_render_checks':'passed_on_macos_production_renderer','ui_state_checks':'passed_compiled_production_state','ui_structure_checks':'passed','iphone_scroll_visual_bug':'pending_device_retest','wallpaper_photos_and_touch_on_iphone':'not_verified',
    'version':report['bundles'][0]['version'],'build':report['bundles'][0]['build'],'bundle_id':report['bundles'][0]['bundle_id'],
    'signing':'not_performed','iphone_installation':'not_verified','device_crud':'not_verified',
    'widget_interaction':'not_verified','app_group_migration_on_iphone':'not_verified',
    'upgrade_data_retention':'not_verified','stage_acceptance':'pending_user_device_feedback',
    'run_id':os.environ['GITHUB_RUN_ID'],'commit':os.environ['GITHUB_SHA']},indent=2))
shutil.rmtree(out/'package')
PY
echo "Todo Wallpaper 0.4.1 ($PRODUCT_BUILD): native PNG checks passed, unsigned ARM64 app + Widget IPA; Windows signing and iPhone wallpaper tests pending." >> "$GITHUB_STEP_SUMMARY"
