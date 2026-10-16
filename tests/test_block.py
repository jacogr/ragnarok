#!/usr/bin/env python3
"""Verify full extrinsic/block composition, independent boundaries, immutable ownership and nominal schemas."""
import hashlib
import json
import subprocess
from block_oracle import requests,published
from dependencies import codec_sources
from test_support import ROOT,nim_command,reject_types


# Compile with checked ARC/Clang LTO, then compare independent child boundaries, wire and typed failure attribution.
def main():
    codec_sources();folder=ROOT/'build/block';folder.mkdir(parents=True,exist_ok=True)
    fixture=folder/'fixtures';fixture.mkdir(exist_ok=True)
    # The focused native tests consume only independently authored policy-valid counterparts, never edited upstream data.
    for name,data in zip(('tickets','preimages','guarantees','assurances','disputes'),published('tiny','E',canonical=True)):
        (fixture/f'{name}.bin').write_bytes(data)
    (fixture/'header.bin').write_bytes(published('tiny','B',canonical=True)[0])
    # Build public lifetime tests, private-wire alias probes and the independent batch adapter.
    for source,name in (('test_block','selftest'),('test_block_private','private'),('block_driver','driver')):
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache'),
                cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest'),str(fixture)],cwd=ROOT,check=True)
    subprocess.run([str(folder/'private')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=240,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Expected boundaries/bytes/reasons were computed before native execution and are not a same-codec round trip.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('component',ROOT/'tests/native/compile_fail/swapped_extrinsic_component.nim',('TicketComponent','PreimageComponent')),
        ('header',ROOT/'tests/native/compile_fail/swapped_block_header.nim',('HeaderComponent','GuaranteeComponent')),
        ('parent',ROOT/'tests/native/compile_fail/block_as_extrinsic.nim',('OwnedBlock','OwnedExtrinsic'))]
    records=reject_types(cases,folder/'types')
    # External callers must be unable to recover or mutate any private parent/child storage.
    for name in ('component','extrinsic','block'):
        probe=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
            str(ROOT/f'tests/native/compile_fail/private_{name}_snapshot.nim')],capture_output=True,text=True)
        diagnostic=probe.stdout+probe.stderr;(folder/f'types/private-{name}.log').write_text(diagnostic)
        assert probe.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=3,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS full extrinsics/blocks: {len(lines)} independent requests, {len(records)} nominal and three private-owner rejections')


# Importing this runner never compiles native code or advances upstream source revisions.
if __name__=='__main__':
    main()
