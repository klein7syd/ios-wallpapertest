#!/bin/bash
set -euo pipefail
mkdir -p TodoWallpaper/out
PRODUCT_BUILD=$((1000 + GITHUB_RUN_NUMBER))
{ sw_vers; xcodebuild -version; xcrun --sdk iphoneos --show-sdk-version; } > TodoWallpaper/out/toolchain.txt
# Compile and execute the production persistence code with independent files.
swiftc -parse-as-library TodoWallpaper/Core/TodoItem.swift TodoWallpaper/Core/TodoRepository.swift TodoWallpaper/Tests/RepositoryChecks.swift -o "$RUNNER_TEMP/todo-repository-checks"
"$RUNNER_TEMP/todo-repository-checks" | tee TodoWallpaper/out/repository-checks.log
plutil -lint TodoWallpaper/TodoWallpaper.xcodeproj/project.pbxproj TodoWallpaper/App/Info.plist
xcodebuild build -project TodoWallpaper/TodoWallpaper.xcodeproj -scheme TodoWallpaper -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/todo-wallpaper-derived" ARCHS=arm64 CURRENT_PROJECT_VERSION="$PRODUCT_BUILD" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee TodoWallpaper/out/build.log
PRODUCT_APP="$RUNNER_TEMP/todo-wallpaper-derived/Build/Products/Release-iphoneos/TodoWallpaper.app"
lipo -archs "$PRODUCT_APP/TodoWallpaper" > TodoWallpaper/out/architectures.txt
xcrun vtool -show-build "$PRODUCT_APP/TodoWallpaper" > TodoWallpaper/out/platform.txt
mkdir -p TodoWallpaper/out/package/Payload
ditto "$PRODUCT_APP" TodoWallpaper/out/package/Payload/TodoWallpaper.app
(cd TodoWallpaper/out/package && ditto -c -k --keepParent Payload ../TodoWallpaper-unsigned.ipa)
python3 native-tools/verify_product_ipa.py TodoWallpaper/out/TodoWallpaper-unsigned.ipa | tee TodoWallpaper/out/package-verification.json
shasum -a 256 TodoWallpaper/out/TodoWallpaper-unsigned.ipa > TodoWallpaper/out/checksum.sha256
cp TodoWallpaper/DEVICE-TEST.md TodoWallpaper/out/
python3 - <<'PY'
import json,os,shutil
from pathlib import Path
out=Path('TodoWallpaper/out')
report=json.loads((out/'package-verification.json').read_text())
(out/'status.json').write_text(json.dumps({'stage':'B','compilation':'succeeded','repository_checks':'passed',
    'version':report['version'],'build':report['build'],'bundle_id':report['bundle_id'],
    'signing':'not_performed','iphone_installation':'not_verified','device_crud':'not_verified',
    'upgrade_data_retention':'not_verified','run_id':os.environ['GITHUB_RUN_ID'],'commit':os.environ['GITHUB_SHA']},indent=2))
shutil.rmtree(out/'package')
PY
echo "Todo Wallpaper 0.1.0 ($PRODUCT_BUILD): unsigned ARM64 IPA; Windows signing and iPhone tests pending." >> "$GITHUB_STEP_SUMMARY"
