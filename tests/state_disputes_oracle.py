# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent T chapter-5 canonical set framing; JSON set fields are explicitly sorted when deriving fixtures."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT


# Direct byte equations retain four independently framed sets with no outer count.
def wire(rows):
    return b''.join(natural(len(row)//32)+row for row in rows)


# Python lexicographic byte ordering supplies an independent canonical-set check.
def canonical(row):
    values=[row[i:i+32] for i in range(0,len(row),32)]
    return all(a<b for a,b in zip(values,values[1:]))


# Account for complete canonical prefixes and fixed identities before native narrowing or allocation.
def charge(count,prefix,total,cursor,config):
    per,aggregate,budget=config
    if count>per or count>aggregate-total:
        return 'limitexceeded'
    if cursor+prefix+count*32>2**63-1:
        return 'lengthoverflow'
    if cursor+prefix+count*32>budget:
        return 'limitexceeded'
    return None


# A source's late disorder or duplicate rejects the whole entry without silently repairing it.
def encode(rows,config):
    cursor=total=0
    # Resource/extent checks precede per-set ordering, consistently for every section.
    for row in rows:
        count=len(row)//32;prefix=len(natural(count))
        error=charge(count,prefix,total,cursor,config)
        if error:
            return error
        if not canonical(row):
            return 'noncanonical'
        cursor+=prefix+count*32;total+=count
    return chapter_key(5).hex()+' '+wire(rows).hex()


# Independently parse every set before publishing any complete field/progress observation.
def decode(data,config):
    cursor=total=0;rows=[]
    # The exact good/bad/wonky/offender order has no outer tuple length or tags.
    for _ in range(4):
        parsed=reference_decode(data[cursor:])
        if parsed in ('truncated','noncanonical'):
            return parsed
        count,prefix=map(int,parsed.split());error=charge(count,prefix,total,cursor,config)
        if error:
            return error
        cursor+=prefix
        if cursor+count*32>len(data):
            return 'truncated'
        row=data[cursor:cursor+count*32]
        if not canonical(row):
            return 'noncanonical'
        rows.append(row);cursor+=count*32;total+=count
    return str(cursor)+''.join(f' {len(row)//32}:{token(row)}' for row in rows)


# Exact upstream JSON fields represent sets; normative sorting is explicit derivation, not native source repair.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Successful good, wonky and bad/offender examples cover both chain profiles and state phases.
    for chain in ('tiny','full'):
        for name in ('progress_with_verdicts-4','progress_with_verdicts-6','progress_with_culprits-2'):
            path=f'stf/disputes/{chain}/{name}.json'
            raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
            assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
            source=json.loads(raw)
            # Source JSON arrays are a transport for mathematical sets, not published T(state) wire encodings.
            for phase in ('pre_state','post_state'):
                rows=[]
                for field in ('good','bad','wonky','offenders'):
                    values=[bytes.fromhex(x[2:]) for x in source[phase]['psi'][field]]
                    assert all(len(x)==32 for x in values) and len(set(values))==len(values)
                    rows.append(b''.join(sorted(values)))
                result.append(rows)
    return result


# Deterministic source, malformed-wire, boundary and partial-trie integration expectations precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x4453505554455335)
    # Row transport preserves duplicates and input order rather than converting hostile source lists into sets.
    def enc(rows,config=(MAX,MAX,MAX),op='V'):
        lines.append(op+' '+' '.join(map(str,config))+' '+' '.join(token(row) for row in rows))
        expected.append(encode(rows,config) if op=='V' else tree([(chapter_key(5),wire(rows))])[0].hex())
    # Announced hostile counts need no fake native sequence allocation.
    def dec(data,config=(MAX,MAX,MAX)):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    enc([b'']*4,(0,0,4));dec(bytes(4),(0,0,4))
    # Literal ascending fixed identities expose byte-order mistakes at every identity octet.
    for position in range(32):
        a=bytearray(32);b=bytearray(32);b[position]=1
        pair=bytes(a+b)
        for section in range(4):
            rows=[b'']*4;rows[section]=pair
            enc(rows);dec(wire(rows));dec(wire(rows)+b'suffix')
            # Descending and equal identities are independently malformed within each of the four sets.
            for changed in (bytes(b+a),bytes(a+a),bytes(b+b)):
                rows[section]=changed;enc(rows);dec(wire(rows))
    rows=[b''.join(i.to_bytes(32,'big') for i in range(3))]*4;raw=wire(rows)
    # Every proper truncation must reject even when the first three sets are complete.
    for cut in range(len(raw)):
        dec(raw[:cut])
    # Per-set and aggregate budgets are exact/one-below and include every set prefix byte.
    for config in ((3,12,len(raw)),(2,12,MAX),(3,11,MAX),(3,12,len(raw)-1),(0,0,0)):
        enc(rows,config);dec(raw,config)
    # Canonical natural count boundaries occur independently in every set, not as an outer total count.
    for section in range(4):
        for count in (0,1,2,127,128,129,255,256,1024):
            rows=[b'']*4;rows[section]=b''.join(i.to_bytes(32,'big') for i in range(count))
            raw=wire(rows);enc(rows);dec(raw);enc(rows,(count,count,len(raw)));dec(raw,(count,count,len(raw)))
            if count:
                enc(rows,(count-1,MAX,MAX));dec(raw,(count-1,MAX,MAX)) # Per-set ceiling precedes payload/order reads.
    # A malformed count in any late set invalidates the whole parent, even after complete earlier sets.
    for section in range(4):
        for prefix in (b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(MAX),natural(2**59)):
            dec(bytes(section)+prefix)
    # The same report may appear in multiple independent sets structurally; transition consistency is not inferred here.
    enc([bytes(32)]*4);dec(wire([bytes(32)]*4))
    # Reproducible arbitrary sorted and deliberately disordered values provide independently observed nontrivial fields.
    for _ in range(200):
        rows=[b''.join(sorted(rng.randbytes(32) for _ in range(rng.randrange(20)))) for _ in range(4)]
        enc(rows);dec(wire(rows));dec(rng.randbytes(rng.randrange(450)))
        if len(rows[3])>=64:
            rows[3]=rows[3][32:64]+rows[3][:32]+rows[3][64:];enc(rows);dec(wire(rows)) # Late noncanonical offender order.
    # Published set fields are explicitly sorted before deriving each state component wire value.
    for rows in published():
        enc(rows);dec(wire(rows));enc(rows,op='R')
    return lines,expected
