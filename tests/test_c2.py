#!/usr/bin/env python3
"""Verify standalone C.2 records, independent field observations, immutable operand owners and API boundaries."""
import hashlib
import json
import subprocess
from c2_oracle import requests
from dependencies import codec_sources
from test_support import ROOT,nim_command,reject_types


# Compile checked native adapters, compare independent sources/observations and require intended compilation failures.
def main():
    codec_sources()
    folder=ROOT/'build/c2';folder.mkdir(parents=True,exist_ok=True)
    commands=[]
    # Public ownership tests, private-wire aliases and batch source/field adapters retain checked ARC/Clang LTO.
    for source,name in (('test_c2','selftest'),('test_c2_private','private'),('c2_driver','driver')):
        command=nim_command(ROOT/('tests/unit/codec' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache');commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    subprocess.run([str(folder/'private')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Expected fixed fields, blobs, tags, gas encodings, exact owner wire and failure reasons predate native execution.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('units',ROOT/'tests/native/compile_fail/c2_balance_as_gas.nim',('TransferBalance','Gas')),
           ('root',ROOT/'tests/native/compile_fail/c2_swapped_root.nim',('SegmentRoot','ErasureRoot')),
           ('payload',ROOT/'tests/native/compile_fail/c2_swapped_payload_hash.nim',('PackageHash','PayloadHash'))]
    records=reject_types(cases,folder/'types')
    probe=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
        str(ROOT/'tests/native/compile_fail/private_operand_snapshot.nim')],cwd=ROOT,capture_output=True,text=True,timeout=60)
    diagnostic=probe.stdout+probe.stderr;(folder/'types/private.log').write_text(diagnostic)
    assert probe.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=1,
                 request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),build_commands=commands)
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS C.2 records: {len(lines)} independent requests, three nominal and one private-owner rejection')


# Importing references never compiles native code or changes the pinned dependency revision.
if __name__=='__main__':
    main()
