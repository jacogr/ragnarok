#!/usr/bin/env python3
"""Run independent disputes vectors, malformed inputs, ownership and compile-time boundary checks."""
import hashlib
import json
import subprocess
from disputes_oracle import requests
from test_support import ROOT,nim_command,reject_types
from dependencies import codec_sources


# All native checks retain ARC, Clang LTO and assertions/bounds/range/field/overflow guards.
def main():
    codec_sources()
    folder=ROOT/'build/disputes';folder.mkdir(parents=True,exist_ok=True)
    # Build a focused native selftest and a separate field-observation driver.
    for source,name in (('test_disputes','selftest'),('disputes_driver','driver')):
        command=nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache')
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Compare independently observed fields and written bytes against precomputed expectations.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('epoch',ROOT/'tests/native/compile_fail/swapped_dispute_epoch.nim',('DisputeEpoch','GuaranteeSlot')),
        ('judge',ROOT/'tests/native/compile_fail/swapped_judge_index.nim',('JudgeIndex','ValidatorIndex')),
        ('key',ROOT/'tests/native/compile_fail/swapped_offender_key.nim',('OffenderKey','DisputeHash')),
        ('signature',ROOT/'tests/native/compile_fail/swapped_dispute_signature.nim',('DisputeSignature','GuaranteeSignature'))]
    records=reject_types(cases,folder/'types')
    private=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
        str(ROOT/'tests/native/compile_fail/private_disputes_owner.nim')],capture_output=True,text=True)
    diagnostic=private.stdout+private.stderr;(folder/'types/private.log').write_text(diagnostic)
    assert private.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=1,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS disputes: {len(lines)} independent requests, {len(records)} nominal and one private-owner rejection')


# Importing this runner never builds code or mutates dependencies.
if __name__=='__main__':
    main()
