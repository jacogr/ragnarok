#!/usr/bin/env python3
"""Compare tagged service request histories to independent keys/fields, JSON maps and exact raw traces."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_requests_oracle import requests,published,published_traces
from test_support import ROOT,nim_command,reject_types


# Checked builds protect fixed copies/variants and compare every independently computed value/error observation.
def main():
    codec_sources();folder=ROOT/'build/state-requests';folder.mkdir(parents=True,exist_ok=True)
    library=ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system()=='Darwin' else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(),'Run python3 tests/test_crypto.py first'
    lines,expected=requests();path=folder/'requests.txt';path.write_text('\n'.join(lines)+'\n');commands=[]
    # Native source fields do not use production decoding; tagged lifetime/invalid-field behavior is supplementary.
    for source,name in (('test_state_requests','selftest'),('state_requests_driver','driver')):
        command=nim_command(ROOT/f'tests/native/{source}.nim',folder/name,folder/f'{name}-cache',[library]);commands.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    subprocess.run([str(folder/'selftest')],cwd=ROOT,check=True)
    result=subprocess.run([str(folder/'driver'),str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180,check=True)
    (folder/'stderr.log').write_text(result.stderr);actual=result.stdout.splitlines()
    assert len(actual)==len(expected),(len(actual),len(expected))
    # Complete logical fields/consumed extents and failure-only reasons must match without native round-trip expected answers.
    for i,(got,wanted) in enumerate(zip(actual,expected)):
        assert got==wanted,(i,got[:180],wanted[:180],lines[i][:160])
    records=reject_types([
        ('slot',ROOT/'tests/native/compile_fail/request_length_as_slot.nim',('RequestLength','RequestSlot')),
        ('length',ROOT/'tests/native/compile_fail/request_slot_as_length.nim',('RequestSlot','RequestLength'))],folder/'types')
    sources=published();traces=[dict(path=x['path'],phase=x['phase'],service=x['service'],length=x['length'],key=x['key'].hex(),
        bytes=len(x['wire']),count=len(x['slots']),sha256=hashlib.sha256(x['wire']).hexdigest(),complete_match=True) for x in published_traces()]
    summary=dict(status='passed',requests=len(lines),nominal_rejections=len(records),published_json_histories=len(sources),
        published_json_shapes={str(n):sum(len(x[3])==n for x in sources) for n in range(4)},
        published_trace_histories=traces,build_commands=commands,request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        namespace_overlap=dict(status='pending_normative_clarification',lengths=[2**32-2,2**32-1],
            observation='request key domains overlap preimage/storage markers; no restriction inferred; trie rejects duplicate keys'),
        scope='service request key/history framing only; no chronology, availability or request lifecycle transitions')
    (folder/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS requests: {len(lines)} cases, two nominal rejections, {len(sources)} JSON and {len(traces)} exact identified trace histories')


# Importing references never builds native code or executes upstream generators.
if __name__=='__main__':
    main()
