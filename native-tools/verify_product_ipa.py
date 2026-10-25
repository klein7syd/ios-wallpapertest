"""Inspect both production bundles with the adapted, preserved R1 verifier."""
from pathlib import Path
import json,sys,zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent/'windows'))
from verify_ipa import verify,require,ROOT,EXT
path=Path(sys.argv[1])
report=verify(path,unsigned=True)
with zipfile.ZipFile(path) as z:
    for prefix,bundle in zip([ROOT,EXT],report['bundles']):
        require(bundle['version']=='0.4.2','Version mismatch')
        if prefix==ROOT:
            require(b'--native-ui-probe' not in z.read(prefix+'TodoWallpaper'), 'CI probe must not be in device IPA')
            import plistlib
            require(plistlib.loads(z.read(prefix+'Info.plist')).get('NSPhotoLibraryAddUsageDescription'), 'Missing add-only Photos permission explanation')
        metadata=json.loads(z.read(prefix+'Metadata.appintents/extract.actionsdata'))
        intent=metadata['actions']['SetTodoCompletionIntent']
        require(intent['openAppWhenRun'] is False,'Intent must not open the app')
        bundle['intent_metadata_present']=True
        bundle['intent_open_app_when_run']=False
print(json.dumps(report,ensure_ascii=False,indent=2))
