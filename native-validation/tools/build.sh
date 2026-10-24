#!/bin/bash
set -euo pipefail
mkdir -p out
{ sw_vers; xcodebuild -version; xcrun --sdk iphoneos --show-sdk-version; } > out/toolchain.txt
plutil -lint NativeInstallProbe.xcodeproj/project.pbxproj
plutil -lint NativeInstallProbe/Probe.entitlements NativeInstallProbe/Info.plist NativeProbeWidget/Probe.entitlements NativeProbeWidget/Info.plist
xcodebuild -list -json -project NativeInstallProbe.xcodeproj > out/project.json
xcodebuild build -project NativeInstallProbe.xcodeproj -scheme NativeInstallProbe -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/native-probe-derived" ARCHS=arm64 CURRENT_PROJECT_VERSION="$GITHUB_RUN_NUMBER" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' DEVELOPMENT_TEAM='' 2>&1 | tee out/build.log
APP="$RUNNER_TEMP/native-probe-derived/Build/Products/Release-iphoneos/NativeInstallProbe.app"
EXT="$APP/PlugIns/NativeProbeWidget.appex"
for BUNDLE in "$APP" "$EXT"; do
    EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleExecutable' "$BUNDLE/Info.plist")
    test -f "$BUNDLE/$EXECUTABLE"
    test ! -f "$BUNDLE/embedded.mobileprovision"
    test ! -d "$BUNDLE/_CodeSignature"
    lipo -archs "$BUNDLE/$EXECUTABLE" | tee "out/$EXECUTABLE-architectures.txt"
    xcrun vtool -show-build "$BUNDLE/$EXECUTABLE" | tee "out/$EXECUTABLE-platform.txt"
    grep -q arm64 "out/$EXECUTABLE-architectures.txt"
    grep -Eq 'platform[[:space:]]+IOS([[:space:]]|$)' "out/$EXECUTABLE-platform.txt"
done
mkdir -p out/package/Payload
ditto "$APP" out/package/Payload/NativeInstallProbe.app
(cd out/package && ditto -c -k --keepParent Payload ../NativeInstallProbe-unsigned.ipa)
python3 tools/verify_ipa.py out/NativeInstallProbe-unsigned.ipa --unsigned --report out/package-verification.json
shasum -a 256 out/NativeInstallProbe-unsigned.ipa > out/checksum.sha256
python3 - <<'CHECK'
import json, os
from pathlib import Path
Path('out/status.json').write_text(json.dumps({
    'version':'0.0.2', 'build':os.environ['GITHUB_RUN_NUMBER'],
    'compilation':'succeeded', 'extension_packaging':'verified',
    'apple_signing':'not_performed', 'iphone_installation':'not_verified',
    'app_groups_on_device':'not_verified', 'widget_intent_on_device':'not_verified',
    'commit':os.environ['GITHUB_SHA'], 'run':os.environ['GITHUB_RUN_ID']
},indent=2))
CHECK
cp tools/sign_widget_probe.py tools/verify_ipa.py tools/Install-WidgetProbe.ps1 tools/Install-WidgetProbe.cmd out/
cp DEVICE-TEST.md out/
# Upload only IPA/logs, not the redundant expanded app.
python3 - <<'CLEAN'
from pathlib import Path
import shutil
p=Path('out/package').resolve()
assert p.parent==Path('out').resolve() and p.name=='package'
shutil.rmtree(p)
CLEAN
echo 'Device ARM64 app and Widget extension compiled and packaged; Apple signing and device capability tests remain pending.' >> "$GITHUB_STEP_SUMMARY"
