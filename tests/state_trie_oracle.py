# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent list-partition reference for GP 0.8.0 serialized state mappings.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import json
import random
import subprocess
from state_layout_oracle import branch, digest, leaf, MAX, token
from test_support import ROOT


# Partition unsorted lists directly, independently of the production sorted range/binary search implementation.
def tree(entries, depth=0):
    # Empty children have a zero identity and contribute no nonempty node.
    if not entries:
        return bytes(32), 0
    # Singletons stop immediately, even when the key has a long zero prefix.
    if len(entries)==1:
        key,value=entries[0]
        return digest(leaf(key,value)),1
    assert depth<248
    left=[];right=[]
    # Bits are consumed most significant first over the full 31-byte domain.
    for entry in entries:
        (right if entry[0][depth//8] & (128>>(depth%8)) else left).append(entry)
    a,n=tree(left,depth+1);b,m=tree(right,depth+1)
    return digest(branch(a,b)),1+n+m


# Reject ambiguous repeated identities and payload limits before forming an expected successful root.
def reference(entries, limits):
    count,per,total,nodes=limits
    # Independent aggregate arithmetic uses Python's unbounded integers.
    if len(entries)>count or any(len(v)>per for _,v in entries) or sum(len(v) for _,v in entries)>total:
        return 'limitexceeded'
    if len({k for k,_ in entries})!=len(entries):
        return 'duplicatekey'
    root,used=tree(entries)
    if used>nodes:
        return 'limitexceeded'
    return f'{root.hex()} {len(entries)} {used}'


# Frozen 32-byte historical inputs are explicitly projected, never represented as current unmodified conformance inputs.
def legacy_maps():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    data=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':trie/trie.json'])
    assert hashlib.sha256(data).hexdigest()==pins['git_blobs']['trie/trie.json']
    result=[]
    # Unique projected identities preserve these historical roots; any collision would invalidate the compatibility check.
    for item in json.loads(data):
        entries=[]
        # The final historical octet is not part of the current 31-byte key domain.
        for key,value in item['input'].items():
            raw=bytes.fromhex(key);assert len(raw)==32
            entries.append((raw[:31],bytes.fromhex(value)))
        assert len({k for k,_ in entries})==len(entries)
        assert tree(entries)[0].hex()==item['output']
        result.append(entries)
    return result


# Build deterministic current-schema, resource-policy, permutation and historical compatibility observations.
def requests():
    lines=[];expected=[]
    # One line carries complete trusted limits and key/value pairs; no implicit dictionary deduplication occurs.
    def add(entries,limits=(MAX,MAX,MAX,MAX)):
        lines.append(' '.join(map(str,limits))+' '+str(len(entries))+''.join(' '+k.hex()+' '+token(v) for k,v in entries))
        expected.append(reference(entries,limits))
    add([], (0,0,0,0))
    # Every possible divergence depth tests MSB-first partitioning, unary branches and the final key bit.
    for depth in range(248):
        for prefix in (0,255):
            a=bytearray([prefix]*31);b=bytearray(a)
            a[depth//8]&=255^(128>>(depth%8));b[depth//8]|=128>>(depth%8)
            entries=[(bytes(a),b''),(bytes(b),bytes(range(33)))]
            _,used=tree(entries)
            add(entries);add(entries[::-1]);add(entries,(2,33,33,used));add(entries,(2,33,33,used-1))
    # Inline/hash transitions and primitive block boundaries retain exact payload limits.
    for length in (0,1,31,32,33,63,64,127,128,129,1024,16384):
        entries=[(bytes(31),bytes(i%251 for i in range(length)))]
        add(entries,(1,length,length,1));add(entries,(0,MAX,MAX,MAX));add(entries,(1,MAX,MAX,0))
        if length:
            add(entries,(1,length-1,MAX,MAX));add(entries,(1,MAX,length-1,MAX)) # Tight individual and aggregate ceilings reject independently.
    # Repeated keys are invalid even if their values agree; distinct keys may have identical values.
    for value in (b'',b'a',bytes(33)):
        add([(bytes(31),value)]*2)
        add([(bytes(31),value),(bytes(31),b'different')])
    rng=random.Random(0x5354415445545249)
    # Reproducible arbitrary maps and permutations expose sorting, unequal subtrees and repeated payloads.
    for size in (2,3,5,10,31,128,256,1024):
        entries=[(rng.randbytes(31),rng.randbytes(rng.choice((0,1,32,33,128)))) for _ in range(size)]
        root,used=tree(entries);total=sum(len(v) for _,v in entries);per=max(len(v) for _,v in entries)
        add(entries,(size,per,total,used));add(entries,(size,per,total,used-1))
        add(entries,(size,per,total-1,used))
        # Three independent insertion orders must commit the identical mapping.
        for _ in range(3):
            rng.shuffle(entries);add(entries)
    # Random small source maps include intentional duplicate keys, not merely valid hash/encode round trips.
    for _ in range(200):
        entries=[(rng.randbytes(31),rng.randbytes(rng.randrange(65))) for _ in range(rng.randrange(12))]
        if entries and rng.randrange(4)==0:
            entries.append(entries[0]) # Duplicate identities remain visible in the list transport.
        add(entries)
    # All frozen roots are cross-checked only after explicit legacy key projection.
    for entries in legacy_maps():
        add(entries)
    return lines,expected
