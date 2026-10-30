# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Pinned known JAM session messages exercise structural wire capture; published sessions never become current-profile STF pass claims."""
import hashlib
import json
from pathlib import Path
import subprocess
from test_support import ROOT
from current_stf_oracle import checkpoint, tree
from test_codec import reference_encode as natural
import header_oracle
import block_oracle

FIXTURE = Path(__file__).parent/'fixtures/jam-fuzzer-wire.json'
NAMES = dict(peer_info='PeerInfo',initialize='Initialize',state_root='StateRoot',
             import_block='ImportBlock',get_state='GetState',state='State',error='Error')


def expected_observations(check_frozen=True):
    """Read exact immutable known-message bytes and independently classify framing under explicit current Tiny domains."""
    pins=json.loads((ROOT/'spec/jam-conformance-pins.json').read_text())
    source=ROOT/pins['path']
    assert subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()==pins['commit']
    assert not subprocess.check_output(['git','-C',str(source),'status','--porcelain'],text=True).strip()
    requests,expected,proof=[],[],{}
    variants={}
    refusals={}
    profiles={}
    for metadata in sorted((source/'fuzz-proto/examples').glob('*/*/*.json')):
        profile=metadata.relative_to(source/'fuzz-proto/examples').parts[0]
        counts=profiles.setdefault(profile,dict(cases=0,accepted=0,refused=0))
        counts['cases']+=1
        item=json.loads(metadata.read_text());kind=next(iter(item));value=item[kind]
        binary=metadata.with_suffix('.bin');wire=binary.read_bytes()
        assert 0<len(wire)<=8388608 and wire[0]==dict(peer_info=0,initialize=1,state_root=2,import_block=3,get_state=4,state=5,error=255)[kind]
        for path in (metadata,binary):
            proof[str(path.relative_to(source))]=hashlib.sha256(path.read_bytes()).hexdigest()
        variants[NAMES[kind]]=variants.get(NAMES[kind],0)+1
        detail=''
        if kind=='peer_info':
            versions=[bytes(value[part][field] for field in ('major','minor','patch')) for part in ('jam_version','app_version')]
            name=value['app_name'].encode()
            assert wire==bytes([0,value['fuzz_version']])+value['fuzz_features'].to_bytes(4,'little')+b''.join(versions)+natural(len(name))+name
            detail=f"{value['fuzz_version']} {value['fuzz_features']} {versions[0].hex()} {versions[1].hex()} {name.hex()}"
        elif kind in ('state_root','get_state'):
            raw=bytes.fromhex(value[2:]);assert len(raw)==32 and wire[1:]==raw
            detail=raw.hex()
        elif kind=='error':
            raw=value.encode();assert wire==b'\xff'+natural(len(raw))+raw
            detail=raw.hex()
        elif kind=='import_block':
            parsed=block_oracle.parse('B',wire[1:],block_oracle.TINY)
            if isinstance(parsed,str):
                counts['refused']+=1;requests.append(wire.hex());expected.append('E BlockFailure');refusals['BlockFailure']=refusals.get('BlockFailure',0)+1;continue # Invalid or incompatible child framing is an explicit refusal, never current STF conformance.
            assert parsed[0]==len(wire)-1
            detail=str(parsed[0])
        elif kind in ('state','initialize'):
            header_length=0
            if kind=='initialize':
                parsed=header_oracle.decode('H',wire[1:],header_oracle.TINY)
                if not parsed.split()[0].isdigit():
                    counts['refused']+=1;requests.append(wire.hex());expected.append('E HeaderFailure');refusals['HeaderFailure']=refusals.get('HeaderFailure',0)+1
                    continue # Published sentinel or historical headers remain exact bytes and explicit current-profile refusals.
                header_length=int(parsed.split()[0])
            rows=value if kind=='state' else value['state']
            pairs=[(bytes.fromhex(row['key'][2:]),bytes.fromhex(row['value'][2:])) for row in rows]
            records=natural(len(pairs))+b''.join(key+natural(len(payload))+payload for key,payload in pairs)
            at=1+header_length;assert wire[at:at+len(records)]==records
            detail=str(len(pairs))+' '+tree(pairs)[0].hex()+' '+checkpoint(pairs).hex()
            if kind=='initialize':
                ancestors=value['ancestry']
                ancestry=natural(len(ancestors))+b''.join(
                    row['slot'].to_bytes(4,'little')+bytes.fromhex(row['header_hash'][2:]) for row in ancestors)
                assert wire[at+len(records):]==ancestry
                detail=str(header_length)+' '+detail+' '+str(len(ancestors))
            else:
                assert at+len(records)==len(wire)
        counts['accepted']+=1
        requests.append(wire.hex());expected.append('M '+NAMES[kind]+' '+str(len(wire))+' '+detail)
    evidence=dict(upstream_commit=pins['commit'],cases=len(requests),accepted=len(requests)-sum(refusals.values()),
                  refused=sum(refusals.values()),refusals=refusals,profiles=profiles,variants=variants,sources=proof,
                  expected_sha256=hashlib.sha256(('\n'.join(expected)+'\n').encode()).hexdigest())
    assert set(variants)==set(NAMES.values()) # Every published discriminant has a real known upstream message witness.
    if check_frozen:
        assert json.loads(FIXTURE.read_text())==evidence
    return requests,expected,evidence
