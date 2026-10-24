"""Inspect an unsigned stage-B device IPA with the preserved R1 Mach-O reader."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'native-validation/tools'))
from verify_ipa import macho_info, require

path = Path(sys.argv[1])
with zipfile.ZipFile(path) as z:
    require(z.testzip() is None, 'ZIP CRC failure')
    for name in z.namelist():
        require(not name.startswith('/') and '..' not in PurePosixPath(name).parts, 'Unsafe ZIP path')
    prefix = 'Payload/TodoWallpaper.app/'
    info = plistlib.loads(z.read(prefix+'Info.plist'))
    require(info['CFBundleIdentifier']=='org.todowallpaper.app', 'Formal Bundle ID changed')
    require(info['CFBundleShortVersionString']=='0.1.0', 'Version mismatch')
    require(not any('.appex/' in name for name in z.namelist()), 'Stage B must not include a Widget yet')
    require(not any(name.endswith('embedded.mobileprovision') or '/_CodeSignature/' in name for name in z.namelist()), 'Unexpected signing material')
    binary = macho_info(z.read(prefix+info['CFBundleExecutable']))
    require(not binary['signature_present'], 'Expected unsigned executable')
    report = {'bundle_id':info['CFBundleIdentifier'],'version':info['CFBundleShortVersionString'],
              'build':info['CFBundleVersion'], 'minimum_os':info['MinimumOSVersion'], **binary,
              'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
              'signing':'not_performed','iphone_installation':'not_verified','device_functionality':'not_verified'}
print(json.dumps(report,ensure_ascii=False,indent=2))
