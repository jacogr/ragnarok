#!/usr/bin/env python3
"""Verify published guarantees, independent wrapper fields and immutable nested report ownership."""
import hashlib
import os
import json
import subprocess
from guarantees_oracle import requests,record
from test_support import ROOT,nim_command,reject_types
from dependencies import codec_sources


# Build checked native drivers and run semantic, lifetime, alias and nominal-domain tests.
def main():
    codec_sources()
    folder=ROOT/'build/guarantees';folder.mkdir(parents=True,exist_ok=True)
    fixture=folder/'minimal-report.bin';fixture.write_bytes(record(0)['report'])
    # Native ownership tests and the independent field adapter use identical production compilation flags.
    for source,name in (('test_guarantees','selftest'),('guarantees_driver','driver')):
        command=nim_command(ROOT/('tests/unit/codec' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache')
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True,
                   env={**os.environ, 'RAGNAROK_GUARANTEE_FIXTURE': str(fixture)})
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Compare individually observed wrapper fields, child bytes and exact prefix progress.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:200],got[:200],wanted[:200])
    cases=[('slot',ROOT/'tests/native/compile_fail/swapped_guarantee_slot.nim',('GuaranteeSlot','LookupSlot')),
           ('index',ROOT/'tests/native/compile_fail/swapped_guarantor_index.nim',('GuarantorIndex','ValidatorIndex')),
           ('signature',ROOT/'tests/native/compile_fail/swapped_guarantee_signature.nim',('GuaranteeSignature','AssuranceSignature'))]
    records=reject_types(cases,folder/'types')
    private=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
        str(ROOT/'tests/native/compile_fail/private_guarantees_owner.nim')],capture_output=True,text=True)
    diagnostic=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostic)
    assert private.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=1,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS guarantees: {len(lines)} published/independent requests, {len(records)} nominal and one private-owner rejection')


# Importing the runner never compiles code or modifies protocol dependencies.
if __name__=='__main__':
    main()
