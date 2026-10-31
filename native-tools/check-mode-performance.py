"""CI Simulator: record the actual production mode action with Apple's Instruments CLI."""
from pathlib import Path
import atexit,collections,json,os,re,signal,statistics,subprocess,sys,time,xml.etree.ElementTree as ET

metrics_only='--metrics-only' in sys.argv
device=next((arg for arg in sys.argv[1:] if not arg.startswith('--')),None)
out=Path('TodoWallpaper/out/mode-performance').resolve();out.mkdir(parents=True,exist_ok=True)
def command(args,timeout=60,check=True):
    try:p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    except subprocess.TimeoutExpired as error:
        if 'simctl' in args and any(step in args for step in ['bootstatus','install','boot']):
            partial=error.stdout or b''
            if isinstance(partial,bytes):partial=partial.decode(errors='replace')
            (out/'simulator-setup-timeout.txt').write_text(' '.join(args)+'\n'+partial)
        if not check:return 'Capability discovery timed out; direct recording will still be attempted.\n'
        raise
    if check and p.returncode:raise RuntimeError('Command failed: '+' '.join(args)+'\n'+p.stdout[-4000:])
    return p.stdout

# 使用已通过完整UI门禁的26.5；26.4在独立CI中无法可靠boot/install，不能当作有效基准。
runtimes=json.loads(command(['xcrun','simctl','list','runtimes','--json']))['runtimes']
stable=[r for r in runtimes if r.get('isAvailable') and r['name'].startswith('iOS') and r['version'].startswith('26.5')]
assert stable,'Profiling needs installed iOS26.5; original UI gates are unchanged'
runtime=stable[-1]
if metrics_only:
    assert device,'Metrics-only path must reuse the fully checked UI device'
    devices=json.loads(command(['xcrun','simctl','list','devices','--json']))['devices']
    assert any(d['udid']==device and d['state']=='Booted' for d in devices.get(runtime['identifier'],[])), 'UI device runtime differs from measurement runtime'
else:
    types=json.loads(command(['xcrun','simctl','list','devicetypes','--json']))['devicetypes']
    phone=next(t for t in types if t['name']=='iPhone 13 Pro')
    if device:command(['xcrun','simctl','shutdown',device],check=False)
    device=command(['xcrun','simctl','create','Todo Wallpaper Mode Profiling',phone['identifier'],runtime['identifier']]).strip()
    def cleanup_device():
        for action in ['shutdown','delete']:
            try:command(['xcrun','simctl',action,device],timeout=20,check=False)
            except subprocess.TimeoutExpired:pass
    atexit.register(cleanup_device)
    command(['xcrun','simctl','boot',device])
    command(['xcrun','simctl','bootstatus',device,'-b'],timeout=420)
    app=Path(os.environ['RUNNER_TEMP'])/'todo-ui-simulator/Build/Products/Debug-iphonesimulator/TodoWallpaper.app'
    assert app.is_dir(),'Simulator Debug app missing'
    command(['xcrun','simctl','install',device,str(app)],timeout=150)
    for name,args in [('help',['xcrun','xctrace','help','record']),('devices',['xcrun','xctrace','list','devices']),('instruments',['xcrun','xctrace','list','instruments']),('templates',['xcrun','xctrace','list','templates'])]:
        (out/('xctrace-'+name+'.txt')).write_text(command(args,timeout=15,check=False))
environment={'hardware':command(['sysctl','-n','machdep.cpu.brand_string'],check=False).strip(),'macOS':command(['sw_vers']).strip(),'xcode':command(['xcodebuild','-version']).strip(),'configuration':'Simulator Debug, identical before/after','device':device,'runtime':runtime['version'],'metrics_only':metrics_only,'git':command(['git','rev-parse','HEAD']).strip()}
(out/'environment.json').write_text(json.dumps(environment,indent=2))
command(['xcrun','simctl','terminate',device,'org.todowallpaper.app'],check=False)
container=Path(command(['xcrun','simctl','get_app_container',device,'org.todowallpaper.app','data']).strip())
local=container/'Documents'/'mode-performance';local.mkdir(parents=True,exist_ok=True)
for name in ['ready','go','metrics.json']:(local/name).unlink(missing_ok=True)
launched=command(['xcrun','simctl','launch',device,'org.todowallpaper.app','--native-mode-performance'])
match=re.search(r'^org\.todowallpaper\.app:\s*(\d+)\s*$',launched,re.MULTILINE);assert match,launched
pid=match.group(1)
deadline=time.monotonic()+150
while not (local/'ready').exists():
    assert time.monotonic()<deadline,'Performance fixture setup timed out'
    if (local/'metrics.json').exists():raise RuntimeError((local/'metrics.json').read_text())
    time.sleep(.25)
# 以App自己写出的PID与主机进程表交叉核对，不凭simctl输出猜主机PID。
reported_pid=(local/'ready').read_text().strip()
processes=[]
for line in command(['ps','-axo','pid=,args=']).splitlines():
    fields=line.strip().split(None,1)
    if len(fields)==2 and 'TodoWallpaper' in fields[1] and '--native-mode-performance' in fields[1]:
        processes.append({'pid':fields[0],'command':fields[1][:600]})
host_pid=next((p['pid'] for p in processes if p['pid']==reported_pid),processes[0]['pid'] if len(processes)==1 else None)
environment.update({'simctl_pid':pid,'app_reported_pid':reported_pid,'host_app_processes':processes})
(out/'environment.json').write_text(json.dumps(environment,indent=2))
if not metrics_only:assert host_pid,'No unambiguous production App host process; refusing unrelated process profiling'
instruments='' if metrics_only else (out/'xctrace-instruments.txt').read_text()
instrument=next((line.strip() for line in instruments.splitlines() if 'signpost' in line.lower() and len(line.strip())<80),None)
if not instrument:instrument=next((line.strip() for line in instruments.splitlines() if line.strip()=='Points of Interest'),None)
instrument_flags=['--instrument',instrument] if instrument else []
proc=None;trace=None
# 等待真正开始录制，不能把仍在查找目标的进程当作已attach。
attempts=[] if metrics_only else [([],['--attach',host_pid],instrument_flags),(['--device',device],['--attach',pid],instrument_flags),([],['--all-processes'],instrument_flags)]
whole_host=False
for index,(device_flags,target_flags,extra) in enumerate(attempts):
    trace=out/f'mode-switch-{index}.trace';logfile=out/f'xctrace-record-{index}.log'
    args=['xcrun','xctrace','record','--template','Time Profiler','--time-limit','60s','--no-prompt','--output',str(trace)]+target_flags+device_flags+extra
    with logfile.open('w') as stream:
        proc=subprocess.Popen(args,stdout=stream,stderr=subprocess.STDOUT)
    recording=False;attach_deadline=time.monotonic()+25
    while proc.poll() is None and time.monotonic()<attach_deadline:
        output=logfile.read_text()
        if 'Recording started' in output or 'Started recording' in output or 'Starting recording with the Time Profiler template' in output:
            recording=True;break
        time.sleep(.25)
    if recording:
        whole_host='--all-processes' in target_flags
        break
    if proc.poll() is None:
        proc.send_signal(signal.SIGINT)
        try:proc.wait(timeout=10)
        except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=5)
    print(f'Instruments attempt {index} ended before capture: '+logfile.read_text()[-1500:],flush=True)
else:
    if not metrics_only:raise RuntimeError('Time Profiler could not attach; see xctrace-record logs. No performance claim is made.')
(local/'go').write_text('recording')
deadline=time.monotonic()+70
while not (local/'metrics.json').exists():
    assert time.monotonic()<deadline,'Production mode action benchmark timed out'
    time.sleep(.25)
metrics=json.loads((local/'metrics.json').read_text())
(out/'metrics.json').write_text(json.dumps(metrics,ensure_ascii=False,indent=2))
assert metrics.get('result')=='passed',metrics
def measurements():
    groups={}
    for sample in metrics['samples']:
        assert sample.get('error') is None,sample
        key=sample['page']+'.'+sample['phase'];groups.setdefault(key,[]).append(sample)
    assert {key:len(rows) for key,rows in groups.items()}=={'widget.cold':1,'widget.warm':21,'wallpaper.cold':1,'wallpaper.warm':21},'Expected all 44 actions'
    summary={}
    for key,rows in groups.items():
        times=[r['milliseconds'] for r in rows]
        summary[key]={'count':len(rows),'median_ms':statistics.median(times),'p95_ms':sorted(times)[int((len(times)-1)*.95+.5)],
            'longest_main_busy_ms':max(r['longestMainBusyMilliseconds'] for r in rows),
            'median_total_main_busy_ms':statistics.median(r['totalMainBusyMilliseconds'] for r in rows),
            'wallpaper_photo_imports':sum(r['counters'].get('wallpaper_photo_imports',0) for r in rows),
            'widget_source_decodes':sum(r['counters'].get('widget_source_decodes',0) for r in rows),
            'profile_disk_reads':sum(r['counters'].get('profile_disk_reads',0) for r in rows)}
    return summary
summary=measurements()
measured_report={'scope':metrics['scope'],'groups':summary,'instruments':'not_run_metrics_only' if metrics_only else 'pending_separate_strict_trace_validation'}
(out/'measurements.json').write_text(json.dumps(measured_report,ensure_ascii=False,indent=2))
if metrics_only:
    print(json.dumps(measured_report,ensure_ascii=False,indent=2),flush=True)
    print('PASS: 44 production mode actions and CFRunLoop intervals. Not Instruments validation and not physical touch.',flush=True)
    sys.exit(0)
try:proc.wait(timeout=105)
except subprocess.TimeoutExpired:
    proc.send_signal(signal.SIGINT)
    try:proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill();proc.wait(timeout=10)
        raise RuntimeError('Time Profiler failed to stop; raw logs/trace preserved, no valid profile is claimed')
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
        if whole_host:
            processes=[resolve(e) for e in row if e.tag=='process']
            for thread in threads:processes.extend(resolve(e) for e in thread.iter('process'))
            labels=[' '.join([e.get('fmt',''),''.join(e.itertext())]) for e in processes]
            if not any('TodoWallpaper' in value or 'Todo Wallpaper' in value or re.search(r'\b'+pid+r'\b',value) for value in labels):continue
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
assert sample_count>0,'No target-app main-thread Time Profiler samples were exported; no call-stack claim is made'
report={'scope':metrics['scope'],'groups':summary,'time_profiler_main_samples':sample_count,'time_profiler_top_main_inclusive_sample_counts':hot.most_common(20),'signpost_tables':[p.name for p in exported if 'signpost' in p.name],'trace':trace.name}
(out/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
print('PASS: production mode actions, CFRunLoop main-busy intervals and Instruments Time Profiler trace; Simulator Debug, not physical iPhone.',flush=True)
