#!/usr/bin/env python3
"""Build checked Nim state trie roots and compare independent list-partition equations."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_trie_oracle import requests,legacy_maps
from test_support import ROOT,nim_command,reject_types


# Native construction runs only after independent roots and explicit historical projections are derived.
def main():
    codec_sources()
    folder=ROOT/'build/state-trie';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n')
    selftest=nim_command(ROOT/'tests/unit/state/test_state_trie.nim',folder/'selftest',folder/'selftest-cache',[library])
    with (folder/'selftest-build.log').open('w') as log:
        subprocess.run(selftest,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    command=nim_command(ROOT/'tests/native/state_trie_driver.nim',folder/'driver',folder/'cache',[library])
    with (folder/'build.log').open('w') as log:
        subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual=result.stdout.splitlines();assert len(actual)==len(expected),(len(actual),len(expected))
    # Every success compares exact roots and node counts, every failure compares a reason without progress.
    for index,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(index,got,wanted,lines[index][:160])
    cases=[('root',ROOT/'tests/native/compile_fail/state_root_as_node.nim',('StateRoot','StateNodeHash')),
           ('nodes',ROOT/'tests/native/compile_fail/state_bytes_as_nodes.nim',('ByteLimit','TrieNodeLimit'))]
    records=reject_types(cases,folder/'types')
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),
                 historical_projected_maps=len(legacy_maps()),build_commands=[selftest,command],
                 request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                 scope='serialized 31-byte-key mappings only; no state-component serialization, proofs or persistence')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS state trie: {len(lines)} independent requests, {len(records)} nominal rejections, {len(legacy_maps())} historical projected maps')


# Importing the runner never builds code or executes an upstream generator.
if __name__=='__main__':
    main()
