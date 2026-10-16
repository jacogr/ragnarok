#!/usr/bin/env python3
"""Compare chapter-16 source bytes and retained observations to independent equations and pinned traces."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_outputs_oracle import requests,published
from test_support import ROOT,nim_command,reject_types


# Build checked native adapters and verify complete independently expected values/errors and owner contracts.
def main():
    codec_sources();folder=ROOT/'build/state-outputs';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Native supplementary tests protect lifetime/default guards; field transport supplies independent byte observations.
    for source,name in (('test_state_outputs','selftest'),('state_outputs_driver','driver')):
        command=nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Expectations are computed before native execution; no native round-trip answer is reused as a reference.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('commitment',ROOT/'tests/native/compile_fail/output_root_as_commitment.nim',('StateNodeHash','OutputCommitment')),
        ('index',ROOT/'tests/native/compile_fail/output_service_as_index.nim',('ServiceIndex','OutputLogIndex'))],folder/'types')
    command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/'tests/native/compile_fail/output_snapshot_private.nim')]
    private=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
    diagnostics=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostics)
    assert private.returncode!=0 and 'data' in diagnostics and 'undeclared field' in diagnostics,diagnostics
    evidence=[dict(path=x['path'],phase=x['phase'],bytes=len(x['wire']),items=len(x['values']),
        sha256=hashlib.sha256(x['wire']).hexdigest(),complete_match=True) for x in published()]
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),privacy_rejections=1,
        published_trace_components=evidence,build_commands=commands,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='T chapter 16 framing; published trace observations empty, nonempty coverage authored; no log/accumulation transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS output log: {len(lines)} requests, two nominal/one privacy rejections, eight exact empty trace entries')


# Importing test-only references never compiles code or runs upstream programs.
if __name__=='__main__':
    main()
