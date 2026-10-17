#!/usr/bin/env python3
"""Compare ready/accumulated rings to independent expectations, immutable observations and pinned fixtures."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_workqueues_oracle import requests,published,published_traces,parse,wire,record
from test_support import ROOT,nim_command,reject_types


# Build checked native adapters and validate every independently computed source/wire observation.
def main():
    codec_sources();folder=ROOT/'build/state-workqueues';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    fixture=folder/'report.bin';fixture.write_bytes(record(0)['report'])
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Native selftests cover lifecycle/guard contracts; the driver supplies independent byte and retained-value comparisons.
    for source,name in (('test_state_workqueues','selftest'),('state_workqueues_driver','driver')):
        command=nim_command(ROOT/('tests/unit/state' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest'),str(fixture)],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Test-only reference values precede native execution; no native round-trip output becomes an expectation.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('hash',ROOT/'tests/native/compile_fail/workqueue_hash_as_item.nim',('WorkQueueHashIndex','ReadyItemIndex')),
        ('slot',ROOT/'tests/native/compile_fail/workqueue_item_as_slot.nim',('ReadyItemIndex','WorkQueueSlot')),
        ('owner',ROOT/'tests/native/compile_fail/workqueue_wrong_owner.nim',('AccumulatedSnapshot','ReadySnapshot'))],folder/'types')
    # Both schema-specific retained owners must reject direct storage access for the intended privacy reason.
    for kind in ('ready','accumulated'):
        command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/f'tests/native/compile_fail/workqueue_{kind}_private.nim')]
        private=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
        diagnostics=private.stdout+private.stderr;(folder/f'types/{kind}-private.log').write_text(diagnostics)
        assert private.returncode!=0 and 'data' in diagnostics and 'undeclared field' in diagnostics,diagnostics
    traces=[]
    # Full trace consumption and independent re-emission are required, not merely successful prefix parsing.
    for kind,data,config in published_traces():
        parsed=parse(kind,data,config);assert not isinstance(parsed,str),parsed
        rows,consumed,items,deps=parsed
        assert consumed==len(data) and wire(kind,rows)==data
        traces.append(dict(kind=kind,bytes=len(data),consumed=consumed,items=items,dependencies=deps,
            sha256=hashlib.sha256(data).hexdigest(),complete_match=True))
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),privacy_rejections=2,
        published_json_components=len(published()),published_trace_components=traces,build_commands=commands,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='T chapters 14/15 framing; no dependency resolution or queue/accumulation transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS work queues: {len(lines)} requests, three nominal/two privacy rejections, 24 derived JSON and 12 exact trace components')


# Importing references never compiles native code or runs upstream generators.
if __name__=='__main__':
    main()
