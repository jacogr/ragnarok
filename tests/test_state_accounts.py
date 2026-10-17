#!/usr/bin/env python3
"""Compare fixed service metadata to independent field equations, JSON fields and raw trace entries."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_accounts_oracle import requests,published_json,published_traces,key
from test_support import ROOT,nim_command,reject_types


# Checked native adapters validate exact fields/bytes, guarded failures and nominal domain separation.
def main():
    codec_sources();folder=ROOT/'build/state-accounts';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Fixed-copy tests require no private owner; driver sources/observations remain independent of production decoding.
    for source,name in (('test_state_accounts','selftest'),('state_accounts_driver','driver')):
        command=nim_command(ROOT/('tests/unit/state' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Full copied values/consumed extents or failure-only reasons must match without native round-trip expectations.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('balance',ROOT/'tests/native/compile_fail/account_gas_as_balance.nim',('Gas','AccountBalance')),
        ('storage',ROOT/'tests/native/compile_fail/account_bytes_as_items.nim',('AccountStorageBytes','AccountStorageItems')),
        ('parent',ROOT/'tests/native/compile_fail/account_slot_as_parent.nim',('AccountSlot','ServiceIndex'))],folder/'types')
    traces=[dict(path=x['path'],phase=x['phase'],service=x['service'],key=key(x['service']).hex(),bytes=len(x['wire']),
        sha256=hashlib.sha256(x['wire']).hexdigest(),complete_match=True) for x in published_traces()]
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),
        published_json_metadata=len(published_json()),published_trace_metadata=traces,build_commands=commands,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='C(255,service) version-zero fixed metadata only; no nested maps, account validation or transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS service metadata: {len(lines)} requests, three nominal rejections, 20 JSON and 20 exact trace metadata entries')


# Importing references never compiles code or runs upstream programs.
if __name__=='__main__':
    main()
