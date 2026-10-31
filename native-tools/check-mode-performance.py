"""CI Simulator: record the actual production mode action with Apple's Instruments CLI."""
from pathlib import Path
import collections,json,os,re,signal,statistics,subprocess,sys,time,xml.etree.ElementTree as ET

device=sys.argv[1]
out=Path('TodoWallpaper/out/mode-performance').resolve();out.mkdir(parents=True,exist_ok=True)
def command(args,timeout=60,check=True):
    p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    if check and p.returncode:raise RuntimeError('Command failed: '+' '.join(args)+'\n'+p.stdout[-4000:])
    return p.stdout
for name,args in [('help',['xcrun','xctrace','help','record']),('devices',['xcrun','xctrace','list','devices']),('instruments',['xcrun','xctrace','list','instruments']),('templates',['xcrun','xctrace','list','templates'])]:
    (out/('xctrace-'+name+'.txt')).write_text(command(args,check=False))
environment={'hardware':command(['sysctl','-n','machdep.cpu.brand_string'],check=False).strip(),'macOS':command(['sw_vers']).strip(),'xcode':command(['xcodebuild','-version']).strip(),'configuration':'Simulator Debug, identical before/after','device':device,'git':command(['git','rev-parse','HEAD']).strip()}
(out/'environment.json').write_text(json.dumps(environment,indent=2))
command(['xcrun','simctl','terminate',device,'org.todowallpaper.app'],check=False)
container=Path(command(['xcrun','simctl','get_app_container',device,'org.todowallpaper.app','data']).strip())
local=container/'Documents'/'mode-performance';local.mkdir(parents=True,exist_ok=True)
for name in ['ready','go','metrics.json']:(local/name).unlink(missing_ok=True)
launched=command(['xcrun','simctl','launch',device,'org.todowallpaper.app','--native-mode-performance'])
match=re.search(r':\s*(\d+)',launched);assert match,launched
pid=match.group(1)
deadline=time.monotonic()+150
while not (local/'ready').exists():
    assert time.monotonic()<deadline,'Performance fixture setup timed out'
    if (local/'metrics.json').exists():raise RuntimeError((local/'metrics.json').read_text())
    time.sleep(.25)
instruments=(out/'xctrace-instruments.txt').read_text()
instrument=next((line.strip() for line in instruments.splitlines() if 'signpost' in line.lower() and len(line.strip())<80),None)
if not instrument:instrument=next((line.strip() for line in instruments.splitlines() if line.strip()=='Points of Interest'),None)
instrument_flags=['--instrument',instrument] if instrument else []
proc=None;trace=None
# Simulator UDID first; a host attach is also valid for a Simulator process.
attempts=[(['--device',device],instrument_flags),([],instrument_flags),([],[])]
for index,(device_flags,extra) in enumerate(attempts):
    trace=out/f'mode-switch-{index}.trace';logfile=out/f'xctrace-record-{index}.log'
    args=['xcrun','xctrace','record','--template','Time Profiler','--time-limit','45s','--no-prompt','--output',str(trace),'--attach',pid]+device_flags+extra
    with logfile.open('w') as stream:
        proc=subprocess.Popen(args,stdout=stream,stderr=subprocess.STDOUT)
    time.sleep(5)
    if proc.poll() is None:break
    print(f'Instruments attempt {index} ended before capture: '+logfile.read_text()[-1500:],flush=True)
else:raise RuntimeError('Time Profiler could not attach; see xctrace-record logs. No performance claim is made.')
(local/'go').write_text('recording')
deadline=time.monotonic()+70
while not (local/'metrics.json').exists():
    assert time.monotonic()<deadline,'Production mode action benchmark timed out'
    time.sleep(.25)
metrics=json.loads((local/'metrics.json').read_text())
(out/'metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2))
assert metrics.get('result')=='passed',metrics
try:proc.wait(timeout=55)
except subprocess.TimeoutExpired:
    proc.send_signal(signal.SIGINT);proc.wait(timeout=20)
assert proc.returncode==0,'Time Profiler capture failed after action execution'
assert trace and trace.exists(),'No Instruments trace was produced'
command(['xcrun','xctrace','export','--input',str(trace),'--toc','--output',str(out/'trace-toc.xml')],timeout=60)
toc=ET.parse(out/'trace-toc.xml').getroot()
schemas=sorted({e.get('schema') for e in toc.iter('table') if e.get('schema')})
(out/'trace-schemas.json').write_text(json.dumps(schemas,indent=2))
exported=[]
for schema in schemas:
    if 'signpost' not in schema and schema not in ['time-profile','cpu-profile']:continue
    target=out/(re.sub(r'[^a-zA-Z0-9_-]','_',schema)+'.xml')
    xpath=f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    command(['xcrun','xctrace','export','--input',str(trace),'--xpath',xpath,'--output',str(target)],timeout=90)
    exported.append(target)
assert any('profile' in p.name for p in exported),'Time Profiler table missing from trace'
hot=collections.Counter();sample_count=0
for path in exported:
    if 'profile' not in path.name:continue
    document=ET.parse(path).getroot();ids={e.get('id'):e for e in document.iter() if e.get('id')}
    def resolve(e):return ids.get(e.get('ref'),e)
    for row in document.iter('row'):
        threads=[resolve(e) for e in row if e.tag=='thread']
        if not threads or not any('main' in (e.get('fmt','')+' '+''.join(e.itertext())).lower() for e in threads):continue
        sample_count+=1
        backtrace=next((resolve(e) for e in row if e.tag in ['backtrace','stack']),None)
        if backtrace is None:continue
        names=set()
        for e in backtrace.iter():
            e=resolve(e)
            if e.tag=='frame':
                name=e.get('name') or e.get('fmt') or ''.join(e.itertext()).strip()
                if name:names.add(name[:300])
        hot.update(names)
groups={}
for sample in metrics['samples']:
    assert sample.get('error') is None,sample
    key=sample['page']+'.'+sample['phase'];groups.setdefault(key,[]).append(sample)
def percentile(values,p):return sorted(values)[max(0,min(len(values)-1,int((len(values)-1)*p+.5)))]
summary={}
for key,rows in groups.items():
    times=[r['milliseconds'] for r in rows]
    summary[key]={'count':len(rows),'median_ms':statistics.median(times),'p95_ms':percentile(times,.95),
        'longest_main_busy_ms':max(r['longestMainBusyMilliseconds'] for r in rows),
        'median_total_main_busy_ms':statistics.median(r['totalMainBusyMilliseconds'] for r in rows),
        'wallpaper_photo_imports':sum(r['counters'].get('wallpaper_photo_imports',0) for r in rows),
        'widget_source_decodes':sum(r['counters'].get('widget_source_decodes',0) for r in rows),
        'profile_disk_reads':sum(r['counters'].get('profile_disk_reads',0) for r in rows)}
report={'scope':metrics['scope'],'groups':summary,'time_profiler_main_samples':sample_count,'time_profiler_top_main_inclusive_sample_counts':hot.most_common(20),'signpost_tables':[p.name for p in exported if 'signpost' in p.name],'trace':trace.name}
(out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
print('PASS: production mode actions, CFRunLoop main-busy intervals and Instruments Time Profiler trace; Simulator Debug, not physical iPhone.',flush=True)
