#!/usr/bin/env python3
"""Run pinned header vectors, independent field comparisons, malformed input and nominal ownership tests."""
import hashlib
import json
import subprocess
from header_oracle import requests
from dependencies import codec_sources
from test_support import ROOT,nim_command,reject_types


# Every native build retains ARC/Clang LTO and assertion/bounds/range/field/overflow guards.
def main():
    codec_sources();folder=ROOT/'build/header';folder.mkdir(parents=True,exist_ok=True)
    # Keep focused native aliases/lifetimes separate from independently driven field/wire comparison.
    for source,name in (('test_header','selftest'),('header_driver','driver')):
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(nim_command(ROOT/('tests/unit/codec' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache'),
                cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Expectations were computed before the native implementation observes any request input.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('root',ROOT/'tests/native/compile_fail/swapped_header_root.nim',('PriorStateRoot','ExtrinsicRoot')),
        ('author',ROOT/'tests/native/compile_fail/swapped_header_author.nim',('AuthorIndex','ValidatorIndex')),
        ('proof',ROOT/'tests/native/compile_fail/swapped_header_proof.nim',('HeaderEntropyProof','HeaderSeal')),
        ('ticket',ROOT/'tests/native/compile_fail/swapped_winning_ticket_id.nim',('WinningTicketId','EpochEntropy')),
        ('unsigned',ROOT/'tests/native/compile_fail/unsigned_as_full_header.nim',('OwnedUnsignedHeader','OwnedHeader'))]
    records=reject_types(cases,folder/'types')
    # Every distinct public owner handle must keep retained bytes and private coordinates inaccessible.
    for name in ('header','unsigned_header','epoch_marker','winners_marker'):
        probe=subprocess.run(['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',
            str(ROOT/f'tests/native/compile_fail/private_{name}_owner.nim')],capture_output=True,text=True)
        diagnostic=probe.stdout+probe.stderr;(folder/f'types/private-{name}.log').write_text(diagnostic)
        assert probe.returncode!=0 and 'undeclared field' in diagnostic and 'data' in diagnostic,diagnostic
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),private_owner_rejections=4,
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS headers/markers: {len(lines)} independent requests, {len(records)} nominal and four private-owner rejections')


# Importing the runner never compiles code or changes dependency revisions.
if __name__=='__main__':
    main()
