# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent fixed version-zero C(255,service) metadata framing and pinned JSON/trace evidence.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import token,MAX
from state_trie_oracle import tree
from state_outputs_oracle import TRACE_PATHS
from test_support import ROOT

SIZE=105


# Service identity belongs to the interleaved chapter key and is absent from the value except for parent service.
def key(service):
    result=bytearray(31);result[0]=255
    for i,b in enumerate(service.to_bytes(4,'little')):
        result[1+2*i]=b
    return bytes(result)


# Exact source tuple: code hash, balance/minimum gas/storage bytes/deposit offset, item/creation/last/parent fields.
def wire(source):
    code,wide,narrow=source
    return b'\0'+code+b''.join(x.to_bytes(4,'little') for x in narrow[4:])+b''.join(x.to_bytes(8,'little') for x in wide)+b''.join(x.to_bytes(4,'little') for x in narrow[:4])


# Source fields already inhabit fixed unsigned domains; complete parent policy precedes output allocation.
def encode(service,source,budget):
    return 'limitexceeded' if budget<SIZE else key(service).hex()+' '+wire(source).hex()


# Prefix parser models version framing before fixed child access, with caller byte policy first.
def parse(data,budget):
    if budget<SIZE:
        return 'limitexceeded'
    version=reference_decode(data)
    if version in ('truncated','noncanonical'):
        return version
    value,count=map(int,version.split())
    if value:
        return 'unsupportedversion'
    assert count==1
    if len(data)<SIZE:
        return 'truncated'
    return (data[1:33],tuple(int.from_bytes(data[i:i+8],'little') for i in range(41,89,8)),
        tuple(int.from_bytes(data[i:i+4],'little') for i in (*range(89,105,4),33,37)))


# Successful fields are logical numbers/fixed bytes, independently observed rather than native round-trip expectations.
def observe(source):
    code,wide,narrow=source
    return str(SIZE)+' '+code.hex()+' '+' '.join(map(str,[*wide,*narrow]))


# No default fields or consumed extent are observable after any failure.
def decode(data,budget):
    result=parse(data,budget)
    return result if isinstance(result,str) else observe(result)


# Verify exact promised Git blob identities before reading existing upstream data.
def blob(path):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
    return json.loads(raw)


# JSON service fields map directly, without computing or repairing footprint/deposit/chronology relationships.
def published_json():
    result=[]
    fields={'version','code_hash','balance','min_item_gas','min_memo_gas','bytes','deposit_offset','items','creation_slot','last_accumulation_slot','parent_service'}
    for chain in ('tiny','full'):
        for name in ('always_accumulate-1','bless_from_non_manager-2'):
            path=f'stf/accumulate/{chain}/{name}.json';data=blob(path)
            for phase in ('pre_state','post_state'):
                for account in data[phase]['accounts']:
                    service=account['id'];value=account['data']['service']
                    assert set(value)==fields and value['version']==0
                    # Derive the unreleased schema from historical release fields with explicit zero supervisor fields.
                    source=(bytes.fromhex(value['code_hash'][2:]),(value['balance'],0,value['min_item_gas'],value['min_memo_gas'],value['bytes'],value['deposit_offset']),
                        tuple(value[k] for k in ('items','creation_slot','last_accumulation_slot','parent_service'))+(0,0))
                    assert len(source[0])==32
                    result.append((service,source))
    return result


# Historical vectors remain pinned to the release: this explicit test-only transformation supplies new zero fields.
def upgrade_release_metadata(raw):
    assert len(raw)==89 and raw[0]==0
    return raw[:33]+bytes(8)+raw[33:41]+bytes(8)+raw[41:]


# Exact C(255,s) trace keys identify nonempty fixed metadata entries; general hashed service keys are not metadata.
def published_traces():
    result=[]
    for path in TRACE_PATHS:
        data=blob(path)
        for phase in ('pre_state','post_state'):
            found=0
            for entry in data[phase]['keyvals']:
                rawkey=bytes.fromhex(entry['key'][2:])
                if len(rawkey)!=31 or rawkey[0]!=255:
                    continue
                service=int.from_bytes(rawkey[1:8:2],'little')
                if key(service)!=rawkey:
                    continue
                raw=upgrade_release_metadata(bytes.fromhex(entry['value'][2:]));source=parse(raw,MAX)
                assert not isinstance(source,str),source
                assert len(raw)==SIZE and wire(source)==raw
                result.append(dict(path=path,phase=phase,service=service,wire=raw,source=source));found+=1
            assert found>0
    return result


# Boundary/source/malformed/fuzz cases compare full independent values and partial trie roots before native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x53455256494345323535)
    # Trusted field transport builds fixed typed source values without production byte decoding.
    def enc(service,source,budget=MAX,op='V'):
        code,wide,narrow=source
        lines.append(' '.join(map(str,[op,budget,service,code.hex(),*wide,*narrow])))
        expected.append(encode(service,source,budget) if op=='V' else tree([(key(service),wire(source))])[0].hex())
    # Invalid tags/versions, truncations and suffixes remain expressible independently of valid source construction.
    def dec(data,budget=MAX):
        lines.append(f'D {budget} {token(data)}');expected.append(decode(data,budget))
    base=(bytes(range(32)),tuple(range(1,7)),tuple(range(7,13)))
    enc(0x01020304,base);dec(wire(base));dec(wire(base)+b'suffix');enc(0x01020304,base,op='R')
    for cut in range(SIZE):
        dec(wire(base)[:cut])
    # Fixed payload and full uint64/E4 boundary values are independently exercised in each scalar field.
    for group,width,values in ((1,6,(0,1,127,128,255,256,2**32-1,2**32,2**56,2**63,MAX)),
                               (2,6,(0,1,127,128,255,256,65535,65536,2**24,2**32-1))):
        for position in range(width):
            for value in values:
                parts=list(base);row=list(parts[group]);row[position]=value;parts[group]=tuple(row);source=tuple(parts)
                enc(1729,source);dec(wire(source))
    # Every code-hash octet and each interleaved service key byte are preserved, without namespace mixing.
    for position in range(32):
        source=(bytes(position)+b'\xff'+bytes(31-position),base[1],base[2])
        enc(0,source);dec(wire(source))
    for service in (0,1,127,128,255,256,65535,65536,2**24,2**32-1):
        enc(service,base);enc(service,base,op='R')
    # Complete fixed-schema byte policy is checked before input access, independent of suffix length.
    for budget in (0,1,32,33,72,73,88,89,90,MAX):
        enc(0,base,budget);dec(wire(base),budget);dec(b'',budget);dec(wire(base)+bytes(100),budget)
    # Every nonzero first discriminator and canonical larger version rejects without guessing future field layout.
    for first in range(1,256):
        dec(bytes([first])+bytes(SIZE-1))
    for prefix in (b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(128),natural(MAX)):
        dec(prefix);dec(prefix+wire(base)[1:])
    # Reproducible arbitrary fixed fields and version-preserving/raw mutations test value copies and failure reasons.
    for _ in range(250):
        source=(rng.randbytes(32),tuple(rng.getrandbits(64) for _ in range(6)),tuple(rng.getrandbits(32) for _ in range(6)))
        service=rng.getrandbits(32);data=wire(source);enc(service,source);dec(data)
        changed=bytearray(data);changed[rng.randrange(SIZE)]^=rng.randrange(1,256)
        dec(bytes(changed));dec(rng.randbytes(rng.randrange(140)))
    for service,source in published_json():
        enc(service,source);dec(wire(source));enc(service,source,op='R')
    for entry in published_traces():
        dec(entry['wire']);enc(entry['service'],entry['source']);enc(entry['service'],entry['source'],op='R')
    return lines,expected
