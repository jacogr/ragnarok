#!/usr/bin/env python3
"""Verify canonical typed collections against independent logical-order, framing and adversarial references."""
import hashlib
import json
import subprocess
from collections_oracle import requests
from dependencies import codec_sources
from test_support import ROOT, nim_command, reject_types


# Build checked native tests, compare independent semantic observations and protect type/ownership boundaries.
def main():
    codec_sources()
    folder=ROOT/'build/collections';folder.mkdir(parents=True,exist_ok=True)
    commands=[]
    # Public lifetime tests, private typed-storage aliases and independent field adapters share checked ARC/Clang LTO.
    for source,name in (('test_collections','selftest'),('test_collections_private','private'),('collections_driver','driver')):
        command=nim_command(ROOT/('tests/unit/codec' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache');commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    subprocess.run([str(folder/'private')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Each expected field, canonical wire interval and typed reason was derived before native execution.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('count',ROOT/'tests/native/compile_fail/raw_collection_count.nim',('CollectionCount','uint64')),
           ('schema',ROOT/'tests/native/compile_fail/swapped_collection_schema.nim',('CollectionUInt[1]','CollectionUInt[2]')),
           ('owner',ROOT/'tests/native/compile_fail/dictionary_as_set.nim',('OwnedDictionary','OwnedSet'))]
    records=reject_types(cases,folder/'types')
    # Unsupported mutable schemas and private field accesses must fail for the intended public API boundary.
    for name,needles in (('unsupported_collection_scalar',('Unsupported collection scalar','string')),
                         ('negative_collection_width',('CollectionUInt width must be 0..8',)),
                         ('wide_collection_width',('CollectionUInt width must be 0..8',)),
                         ('private_set_snapshot',('undeclared field','data')),
                         ('private_dictionary_snapshot',('undeclared field','data'))):
        command=['nim','check','--mm:arc','--skipParentCfg','--skipUserCfg',str(ROOT/f'tests/native/compile_fail/{name}.nim')]
        probe=subprocess.run(command,cwd=ROOT,capture_output=True,text=True,timeout=60)
        diagnostic=probe.stdout+probe.stderr;(folder/f'types/{name}.log').write_text(diagnostic)
        assert probe.returncode!=0 and all(needle in diagnostic for needle in needles),(name,diagnostic)
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),unsupported_schema_rejections=1,
                 private_owner_rejections=2,invalid_width_rejections=2,request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),build_commands=commands)
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS canonical collections: {len(lines)} independent requests, three nominal, one unsupported-schema, two invalid-width and two privacy rejections')


# Importing the runner never builds binaries or advances a source pin.
if __name__=='__main__':
    main()
