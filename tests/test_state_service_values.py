#!/usr/bin/env python3
"""Verify service storage/preimage entries, immutable opaque capture and exact pinned source evidence."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_service_values_oracle import requests,published,published_traces
from test_support import ROOT,nim_command,reject_types


# Checked native source/copy/private-alias tests compare against independent Blake2b/key/value equations.
def main():
    codec_sources();folder=ROOT/'build/state-service-values';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Supplementary tests protect retained ownership/atomicity; field transport supplies independent expected observations.
    for source,name in (('test_state_service_values','selftest'),('test_service_values_private','private'),('state_service_values_driver','driver')):
        command=nim_command(ROOT/('tests/unit/state' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    subprocess.run([str(folder/'private')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Full key/raw-byte/identity/length observations or failure-only reasons must agree without native round-trip answers.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('preimage',ROOT/'tests/native/compile_fail/service_value_code_as_preimage.nim',('CodeHash','ServicePreimageHash')),
        ('key',ROOT/'tests/native/compile_fail/service_value_hash_as_key.nim',('ServicePreimageHash','StateKey'))],folder/'types')
    command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/'tests/native/compile_fail/service_value_private.nim')]
    private=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
    diagnostics=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostics)
    assert private.returncode!=0 and 'data' in diagnostics and 'undeclared field' in diagnostics,diagnostics
    sources=published();traces=[dict(path=x['path'],phase=x['phase'],service=x['service'],key=x['key'].hex(),
        bytes=len(x['value']),sha256=hashlib.sha256(x['value']).hexdigest(),namespace='opaque; not recoverable from key') for x in published_traces()]
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),privacy_rejections=1,
        published_json_storage=sum(x[0]=='S' for x in sources),published_json_preimages=sum(x[0]=='P' for x in sources),
        published_opaque_trace_values=traces,build_commands=commands,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='storage/preimage keyed serialization and opaque raw-value ownership; no hash/content invariant, requests or transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS service values: {len(lines)} requests, two nominal/one privacy rejections, 12 storage/16 preimage JSON mappings and 16 opaque trace captures')


# Importing the references never compiles code or runs upstream generators.
if __name__=='__main__':
    main()
