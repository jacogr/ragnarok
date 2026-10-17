#!/usr/bin/env python3
"""Verify the bounded state-key/node foundation, independent byte/hash equations and partial-commitment types."""
import hashlib
import json
import platform
import subprocess
from state_layout_oracle import requests,legacy_singletons
from dependencies import codec_sources
from test_support import ROOT,nim_command,reject_types


# Build checked Nim adapters against an already built primitive library, then compare independent source/field/hash observations.
def main():
    codec_sources()
    folder=ROOT/'build/state-layout';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Build the pinned native primitive bridge with python3 tests/test_crypto.py first'
    commands=[]
    # Native fixed-value lifetime tests and batch adapters retain ARC/Clang LTO and every existing runtime guard.
    for source,name in (('test_state_layout','selftest'),('state_layout_driver','driver')):
        command=nim_command(ROOT/('tests/unit/state' if source.startswith('test_') else 'tests/native')/(source+'.nim'),folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Expected key interleaving, node flags/padding, copied fields and hashes were all derived independently before execution.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,lines[index][:160],got[:160],wanted[:160])
    cases=[('key',ROOT/'tests/native/compile_fail/state_key_as_hash.nim',('StateKey','StateNodeHash')),
           ('partial',ROOT/'tests/native/compile_fail/state_partial_as_hash.nim',('LeftChildCommitment','StateNodeHash')),
           ('value',ROOT/'tests/native/compile_fail/state_value_as_node_hash.nim',('StateValueHash','StateNodeHash'))]
    records=reject_types(cases,folder/'types')
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),
                 legacy_projected_singleton_checks=len(legacy_singletons()),
                 request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),build_commands=commands,
                 scope='key constructors and node layout/hash only; no trie construction or state component serialization')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS state layout: {len(lines)} independent requests, three nominal rejections; {summary["legacy_projected_singleton_checks"]} historical projected singleton checks')


# Importing references never builds native code or executes upstream vector generators.
if __name__=='__main__':
    main()
