#!/usr/bin/env python3
"""Check chapter-12 entries/owners against independent fixed-role and natural-dictionary equations."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_privileges_oracle import requests,published
from test_support import ROOT,nim_command,reject_types


# Build checked native tests and compare complete independently expected values, consumed extents and reasons.
def main():
    codec_sources();folder=ROOT/'build/state-privileges';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Native supplementary tests cover lifetime/default guards; the driver observes independent byte/field cases.
    for source,name in (('test_state_privileges','selftest'),('state_privileges_driver','driver')):
        command=nim_command(ROOT/('tests/unit/state' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Test-only expectations are computed before native execution, without round-trip-derived answers.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('gas',ROOT/'tests/native/compile_fail/privilege_gas_as_service.nim',('PrivilegeGas','ServiceIndex')),
        ('index',ROOT/'tests/native/compile_fail/privilege_entry_as_core.nim',('PrivilegeEntryIndex','PrivilegeCoreIndex'))],folder/'types')
    command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/'tests/native/compile_fail/privilege_snapshot_private.nim')]
    private=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
    diagnostics=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostics)
    assert private.returncode!=0 and 'data' in diagnostics and 'undeclared field' in diagnostics,diagnostics
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),privacy_rejections=1,
        published_state_sources=len(published()),build_commands=commands,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='T chapter 12 only; no full state serialization or privilege transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS privilege state: {len(lines)} requests, two nominal/one privacy rejections, sixteen published state sources')


# Importing references does not compile code or run upstream programs.
if __name__=='__main__':
    main()
