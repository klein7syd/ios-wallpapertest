"""Inspect both production bundles with the adapted, preserved R1 verifier."""
from pathlib import Path
import json,sys,zipfile
sys.path.insert(0,str(Path(__file__).resolve().parent/'windows'))
from verify_ipa import verify,require,ROOT,EXT
path=Path(sys.argv[1])
report=verify(path,unsigned=True)
with zipfile.ZipFile(path) as z:
    for prefix,bundle in zip([ROOT,EXT],report['bundles']):
        require(bundle['version']=='0.2.0','Version mismatch')
        metadata=json.loads(z.read(prefix+'Metadata.appintents/extract.actionsdata'))
        intent=metadata['actions']['SetTodoCompletionIntent']
        require(intent['openAppWhenRun'] is False,'Intent must not open the app')
        bundle['intent_metadata_present']=True
        bundle['intent_open_app_when_run']=False
print(json.dumps(report,ensure_ascii=False,indent=2))
