# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent chapter-10 composition over the existing mathematical guarantee/report reference.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import json
import random
import subprocess
from guarantees_oracle import record as base_record,wire as frame_wire,fields as guarantee_fields,decode as frame_decode,encode as frame_encode
from assurances_oracle import config_error
from report_oracle import from_json,encode as report_wire
from state_layout_oracle import token,chapter_key,MAX
from state_trie_oracle import tree
from test_support import ROOT

BROAD=(341,1023,2_000_000,341,8_000_000)
ERRORS={'invalidconfig','truncated','noncanonical','limitexceeded','lengthoverflow','invalidtag','invalidreport','invalidcredential','invalidvalidator'}


# Author current-valid tiny-capable reports explicitly; the older general guarantee generator uses full-profile shards.
def record(core,credential_count=2):
    value=base_record(core,credential_count)
    raw=bytearray(value['report']);raw[68:70]=(6).to_bytes(2,'little');value['report']=bytes(raw)
    return value


# Reference-only adaptation strips the independent extrinsic oracle's known one-record count; production uses shared record helpers.
def single_decode(data,cores,validators,budget):
    value=frame_decode(b'\1'+data,cores,validators,budget+1)
    if value in ERRORS:
        return value # No partial progress from a malformed nested guarantee.
    parts=value.split();assert parts[0]=='1' and parts[2]=='1'
    n=int(parts[5]);credentials=[(int(parts[6+2*i]),bytes.fromhex(parts[7+2*i])) for i in range(n)]
    return int(parts[1])-1,dict(report=bytes.fromhex(parts[3]),slot=int(parts[4]),credentials=credentials)


# Source preflight reuses independent mathematical report/credential rules, excluding only the outer extrinsic count.
def single_encode(value,cores,validators,budget):
    result=frame_encode([value],cores,validators,budget+1,MAX)
    return result if result in ERRORS else bytes.fromhex(result)[1:]


# Fixed core sequence, no outer count; guarantee slot precedes its credentials and the extra registered E4 time follows them.
def wire(values):
    return b''.join(b'\0' if value is None else b'\1'+frame_wire([value['guarantee']])[1:]+value['registered'].to_bytes(4,'little') for value in values)


# Keep every optional source field independently visible in trusted transport and decoded observations.
def fields(values):
    return ' '.join('0' if value is None else '1 '+str(value['registered'])+' '+' '.join(guarantee_fields([value['guarantee']]).split()[1:]) for value in values)


# Validate chain/minimum bytes before input/source traversal, matching the fixed-core domain rather than guessing a profile.
def valid(config):
    cores,validators,child,limit,budget=config
    return config_error(cores,validators) or ('limitexceeded' if budget<cores else None)


# Whole-source preflight accounts for each tag and complete child before any expected bytes are produced.
def encode(values,config):
    cores,validators,child,limit,budget=config;error=valid(config)
    if error:
        return error
    if len(values)!=cores:
        return 'invalidcount'
    size=present=0
    # Present-count policy precedes nested owner/credential validation.
    for value in values:
        size+=1
        if size>budget:
            return 'limitexceeded'
        if value is not None:
            if present>=limit:
                return 'limitexceeded'
            encoded=single_encode(value['guarantee'],cores,validators,child)
            if isinstance(encoded,str):
                return encoded
            size+=len(encoded)
            if size>budget:
                return 'limitexceeded'
            size+=4
            if size>budget:
                return 'limitexceeded'
            present+=1
    return chapter_key(10).hex()+' '+wire(values).hex()


# Complete field/progress observations are published only after every fixed core slot validates.
def decode(data,config):
    cores,validators,child,limit,budget=config;error=valid(config)
    if error:
        return error
    cursor=present=0;values=[]
    # Absent core slots remain explicit; no outer sequence count is read.
    for _ in range(cores):
        cursor+=1
        if cursor>budget:
            return 'limitexceeded'
        if cursor>len(data):
            return 'truncated'
        tag=data[cursor-1]
        if tag>1:
            return 'invalidtag'
        if tag==1:
            if present>=limit:
                return 'limitexceeded'
            value=single_decode(data[cursor:],cores,validators,child)
            if isinstance(value,str):
                return value
            consumed,guarantee=value;cursor+=consumed
            if cursor>budget:
                return 'limitexceeded'
            start=cursor;cursor+=4
            if cursor>budget:
                return 'limitexceeded'
            if cursor>len(data):
                return 'truncated'
            values.append(dict(guarantee=guarantee,registered=int.from_bytes(data[start:cursor],'little')));present+=1
        else:
            values.append(None) # Absence is distinct from a present guarantee with registration zero.
    return f'{cursor} {cores} {present} '+fields(values)


# Preserve exact raw published child fields; dummy reports/credentials are not silently repaired.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Both tiny/full assurance families and both state phases expose assignment values, not serialized T binaries.
    for chain in ('tiny','full'):
        for family,name,state_field in (('assurances','no_assurances-1','avail_assignments'),
                                        ('assurances','some_assurances-1','avail_assignments'),
                                        ('disputes','progress_invalidates_avail_assignments-1','rho')):
            path=f'stf/{family}/{chain}/{name}.json';raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
            assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
            d=json.loads(raw)
            for phase in ('pre_state','post_state'):
                values=[]
                for value in d[phase][state_field]:
                    if value is None:
                        values.append(None) # Preserve each absent core position.
                    else:
                        g=value['guarantee'];report=g['report']
                        assert all('ok' in entry['result'] for entry in report['results']) # Preserve the fixture converter's exact supported result schema.
                        assert report['segment_root_lookup']==[] # The reused fixture converter supports exactly this pinned empty lookup schema.
                        credentials=[(x['validator_index'],bytes.fromhex(x['signature'][2:])) for x in g['signatures']]
                        values.append(dict(registered=value['registered_slot'],guarantee=dict(report=report_wire(from_json(report)),slot=g['slot'],credentials=credentials)))
                result.append((values,(len(values),6 if chain=='tiny' else 1023,2_000_000,341,8_000_000)))
    return result


# Reproducible independent assignment, every-truncation, discriminator, E4 and inherited child-policy observations.
def requests():
    lines=[];expected=[]
    # Use independently authored current-valid report/credential fields, not a decode/encode-derived guarantee source.
    def item(core=0,registered=0,credentials=2):
        return dict(guarantee=record(core,credentials),registered=registered)
    def enc(values,config=BROAD,op='V'):
        lines.append(op+' '+' '.join(map(str,config))+' '+str(len(values))+' '+fields(values))
        expected.append(encode(values,config) if op=='V' else tree([(chapter_key(10),wire(values))])[0].hex())
    # Raw bytes express invalid tags, truncated children and malformed counts without unsafe source descriptors.
    def dec(data,config=BROAD):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    small=(2,6,2_000_000,2,8_000_000)
    for values in ([None,None],[item(),None],[None,item(1,0x01020304,3)],[item(),item(1,2**32-1)]):
        raw=wire(values);enc(values,small);dec(raw,small);dec(raw+b'suffix',small);enc(values,small,op='R')
        for cut in range(len(raw)):
            dec(raw[:cut],small) # Every proper truncation must reject the whole parent, including the final registered byte.
        for config in ((2,6,2_000_000,0,8_000_000),(2,6,2_000_000,1,8_000_000),(*small[:4],len(raw)-1),(*small[:4],len(raw))):
            enc(values,config);dec(raw,config)
    # E4 guarantee and registration slots are independently observed, including values too large for one-byte naturals.
    for slot in (0,1,127,128,255,256,65535,65536,2**32-1):
        value=item(0,slot);value['guarantee']['slot']=2**32-1-slot
        enc([value,None],small);dec(wire([value,None]),small)
    # Every reserved tag is rejected both first and after a complete earlier present guarantee.
    complete=wire([item()])
    for tag in range(2,256):
        dec(bytes([tag]),small);dec(complete+bytes([tag]),small)
    # Exact fixed shape and full/tiny configuration are explicit, including a 341-slot all-absent value.
    for cores in (2,341):
        config=(cores,3*cores,2_000_000,0,cores);enc([None]*cores,config);dec(bytes(cores),config)
    for n in (0,1,3):
        enc([None]*n,small)
    for config in ((0,6,MAX,2,MAX),(1,6,MAX,2,MAX),(342,1023,MAX,2,MAX),(2,5,MAX,2,MAX),(2,7,MAX,2,MAX),(2,6,MAX,2,1)):
        enc([None,None],config);dec(bytes(2),config)
    # Child limits/credential cardinalities, ordering and membership reuse their exact independent guarantee oracle.
    for n in (0,1,2,3,4):
        value=item(0,0,n);enc([value,None],small);dec(wire([value,None]),small)
    for credentials in ([(1,bytes(64)),(0,bytes(64))],[(0,bytes(64)),(0,bytes(64))],[(0,bytes(64)),(6,bytes(64))]):
        value=item();value['guarantee']['credentials']=credentials;enc([None,value],small);dec(wire([None,value]),small)
    value=item();length=len(frame_wire([value['guarantee']]))-1
    for ceiling in (0,length-1,length,MAX):
        config=(2,6,ceiling,2,8_000_000);enc([value,None],config);dec(wire([value,None]),config)
    # Malformed late reports and overlong credential framing cannot expose an earlier owned report.
    value=item();value['guarantee']['report']=b'';enc([None,value],small);dec(complete+b'\1',small)
    base=item();g=base['guarantee'];report=g['report'];slot=g['slot'].to_bytes(4,'little')
    for prefix in (b'',b'\x80',b'\x80\2',b'\xff'+MAX.to_bytes(8,'little')):
        dec(b'\1'+report+slot+prefix,small)
    # Full-profile late positions and general-natural report core boundaries remain ordinary fixed outer slots.
    values=[None]*341
    for core in (0,127,128,255,256,340):
        values[core]=item(core,core,3)
    enc(values);dec(wire(values))
    rng=random.Random(0x415641494c3130)
    # Random valid assignments and one-byte parent mutations supplement exhaustive local boundaries.
    for _ in range(30):
        cores=rng.choice((2,3,4,8));values=[]
        for core in range(cores):
            if rng.randrange(3)==0:
                values.append(None) # Keep randomly interspersed absent core positions.
            else:
                value=item(core,rng.randrange(2**32),rng.choice((2,3)))
                value['guarantee']['slot']=rng.randrange(2**32)
                value['guarantee']['credentials']=[(index,rng.randbytes(64)) for index in sorted(rng.sample(range(3*cores),len(value['guarantee']['credentials'])))]
                values.append(value)
        config=(cores,3*cores,2_000_000,cores,8_000_000);raw=wire(values);enc(values,config);dec(raw,config)
        changed=bytearray(raw);changed[rng.randrange(len(changed))]^=rng.randrange(1,256)
        dec(bytes(changed),config)
    # Published fields remain unchanged: assurance cases supply success evidence, zeroed dispute children retain inherited failures.
    for values,config in published():
        enc(values,config);dec(wire(values),config)
    return lines,expected


# Report published success/rejection evidence separately rather than conflating expected failures with conformance passes.
def published_verdicts():
    result={}
    for values,config in published():
        verdict=decode(wire(values),config)
        key=verdict if verdict in ERRORS else 'success'
        result[key]=result.get(key,0)+1
    return result
