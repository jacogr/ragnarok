# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent published RawState wire, complete-map and immutable-prefix witnesses.

Authority: pinned vectors traces/schema.asn and traces/convert.py; canonical scalar
widths come from the independent JAM natural reference. Native results are never inputs.
"""
import hashlib
import json
import subprocess
from pathlib import Path
from test_support import ROOT
from test_codec import reference_encode as natural
from current_stf_oracle import Reader, decode_checkpoint, checkpoint, tree
import current_stf_interchange_oracle as current

PIN='23061ae1f9b51171c01387e7dde0f15794c98e24'
FIXTURE=Path(__file__).parent/'fixtures/state-trace-wire.json'
MAX=8388608


def wire(pairs,root=None):
    """Retain record order exactly; SEQUENCE OF does not invent a lexical-order validity restriction."""
    return (tree(pairs)[0] if root is None else root)+natural(len(pairs))+b''.join(key+natural(len(value))+value for key,value in pairs)


def published(path):
    """Read immutable pinned Git objects without modifying the upstream checkout or repairing historical fields."""
    return subprocess.check_output(['git','-C',str(ROOT/'vendor/jamtestvectors'),'show',PIN+':'+path])


def prefix(raw):
    """Decode one independent RawState prefix, preserving empty values and exact wire order."""
    source=Reader(raw);root=source.take(32)
    pairs=[(source.take(31),source.take(source.count())) for _ in range(source.count())]
    assert len(dict(pairs))==len(pairs) and tree(pairs)[0]==root
    assert wire(pairs)==raw[:source.at]
    return pairs,source.at


def expected_observations(check_frozen=True):
    """Calculate all wire/checkpoint answers and source hashes before the native codec is invoked."""
    requests=[];expected=[];proof=[];sources={}
    def accepted(pairs,raw=None,trailer=b'',label='current'):
        """A consumed prefix preserves incoming order while deterministic map export orders complete keys."""
        encoded=wire(pairs) if raw is None else raw
        requests.append(str(MAX)+' '+(encoded+trailer).hex())
        expected.append('S '+str(len(encoded))+' '+encoded.hex()+' '+wire(sorted(pairs)).hex()+' '+checkpoint(pairs).hex())
        proof.append(dict(label=label,root=tree(pairs)[0].hex(),wire_sha256=hashlib.sha256(encoded).hexdigest(),checkpoint_sha256=hashlib.sha256(checkpoint(pairs)).hexdigest()))
    def refused(raw,reason,limit=MAX):
        """Malformed scalar/extent, duplicated keys and wrong roots carry only independently selected typed errors."""
        requests.append(str(limit)+' '+raw.hex());expected.append('E '+reason)
    for path in ('traces/schema.asn','traces/convert.py'):
        raw=published(path);sources[path]=hashlib.sha256(raw).hexdigest() # Bind the exact external schema independently of the current checkout.
    for path in ('traces/fallback/00000001','traces/storage/00000001','traces/preimages/00000001'):
        raw=published(path+'.bin');data=json.loads(published(path+'.json'));pairs,extent=prefix(raw)
        authored=[(bytes.fromhex(item['key'][2:]),bytes.fromhex(item['value'][2:])) for item in data['pre_state']['keyvals']]
        assert pairs==authored and raw[:32].hex()==data['pre_state']['state_root'][2:]
        accepted(pairs,raw[:extent],raw[extent:],path+' pre-state')
        sources[path+'.bin']=hashlib.sha256(raw).hexdigest();sources[path+'.json']=hashlib.sha256(published(path+'.json')).hexdigest()
    _,lines,_=current.expected_observations()
    for line in lines:
        if line.startswith(('P ','O ')):
            accepted(list(decode_checkpoint(bytes.fromhex(line[2:])).items())) # These complete maps are independently calculated current-profile STF inputs and successors.
    key=b'\1'+bytes(30);other=b'\2'+bytes(30)
    for size in (0,1,31,32,33,127,128,129,16383,16384):
        pairs=[(other,bytes(index%256 for index in range(size))),(key,b'')]
        accepted(pairs,trailer=b'\xff\x00',label='unsorted length '+str(size))
    accepted([],trailer=b'\xff',label='empty complete map')
    good=wire([(key,b'abc')]);refused(bytes([good[0]^1])+good[1:],'RootMismatch')
    refused(bytes(32)+natural(2)+key+b'\0'+key+b'\0','DuplicateKey')
    refused(bytes(32)+b'\xff'+bytes(8),'NonCanonical')
    refused(bytes(32)+natural(2**64-1),'LimitExceeded')
    refused(bytes(32)+natural(1)+key+natural(2**64-1),'LimitExceeded')
    for length in (1,31,32,33,40,64,len(good)-1):
        refused(good[:length],'Truncated') # Cut fixed roots, counts, keys, lengths and final payload independently.
    refused(good,'LimitExceeded',len(good)-1)
    evidence=dict(cases=len(requests),accepted=len(proof),refused=len(requests)-len(proof),sources=sources,proof=proof)
    if check_frozen:
        assert json.loads(FIXTURE.read_text())==evidence
    return requests,expected,evidence
