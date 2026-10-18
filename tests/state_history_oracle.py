# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent T chapter-3 byte equations: header/super-peak/state/E4-slot, dictionaries and optional belt peaks.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT

BROAD=(341,8,341,2728,1024,2_000_000)


# Direct byte equations preserve tuple/dictionary/peak order and every optional hole.
def wire(source):
    blocks,peaks=source
    return natural(len(blocks))+b''.join(fixed+natural(len(pairs)//64)+pairs for fixed,pairs in blocks)+natural(len(peaks))+b''.join(b'\0' if p is None else b'\1'+p for p in peaks)


# Canonical dictionaries sort only by package key, with values retained beside their keys.
def canonical(pairs):
    keys=[pairs[i:i+32] for i in range(0,len(pairs),64)]
    return all(a<b for a,b in zip(keys,keys[1:]))


# Python unbounded arithmetic models checked native extent and complete-byte policy independently.
def grow(cursor,n,width,budget):
    end=cursor+n*width
    if end>2**63-1:
        return 'lengthoverflow'
    if end>budget:
        return 'limitexceeded'
    return end


# Check typed source counts and all late dictionaries/peaks before producing expected entry bytes.
def encode(source,config):
    cores,limit,per,total,peak_limit,budget=config;blocks,peaks=source
    if cores<2:
        return 'invalidconfig'
    if len(blocks)>8:
        return 'invalidcount'
    if len(blocks)>limit:
        return 'limitexceeded'
    cursor=grow(0,len(natural(len(blocks))),1,budget);used=0
    if isinstance(cursor,str):
        return cursor
    # The fixed tuple deliberately follows T, which orders super-peak before state root.
    for fixed,pairs in blocks:
        cursor=grow(cursor,100,1,budget)
        if isinstance(cursor,str):
            return cursor
        n=len(pairs)//64
        if n>cores:
            return 'invalidcount'
        if n>per or used+n>total:
            return 'limitexceeded'
        if n>(2**63-1)//64:
            return 'lengthoverflow'
        used+=n
        for amount,width in ((len(natural(n)),1),(n,64)):
            cursor=grow(cursor,amount,width,budget)
            if isinstance(cursor,str):
                return cursor
        if not canonical(pairs):
            return 'noncanonical'
    if len(peaks)>peak_limit:
        return 'limitexceeded'
    if len(peaks)>(2**63-1)//33:
        return 'lengthoverflow'
    cursor=grow(cursor,len(natural(len(peaks))),1,budget)
    if isinstance(cursor,str):
        return cursor
    # Present zero hashes retain all 33 bytes, while absent peaks use one tag byte.
    for peak in peaks:
        cursor=grow(cursor,1,1 if peak is None else 33,budget)
        if isinstance(cursor,str):
            return cursor
    return chapter_key(3).hex()+' '+wire(source).hex()


# Prefix parsing uses independently calculated extents and field observations, not production round trips.
def decode(data,config):
    cores,limit,per,total,peak_limit,budget=config
    if cores<2:
        return 'invalidconfig'
    cursor=used=0;blocks=[];peaks=[]
    # Return a framing failure without publishing an advanced cursor.
    def count(at):
        result=reference_decode(data[at:])
        return result if result in ('truncated','noncanonical') else tuple(map(int,result.split()))
    parsed=count(cursor)
    if isinstance(parsed,str):
        return parsed
    n,prefix=parsed
    if n>8:
        return 'invalidcount'
    if n>limit:
        return 'limitexceeded'
    cursor=grow(cursor,prefix,1,budget)
    if isinstance(cursor,str):
        return cursor
    # Complete fixed fields precede each dictionary's canonical count and fixed pair payload.
    for _ in range(n):
        start=cursor;cursor=grow(cursor,100,1,budget)
        if isinstance(cursor,str):
            return cursor
        if cursor>len(data):
            return 'truncated'
        fixed=data[start:cursor];parsed=count(cursor)
        if isinstance(parsed,str):
            return parsed
        pairs,prefix=parsed
        if pairs>cores:
            return 'invalidcount'
        if pairs>per or pairs>total-used:
            return 'limitexceeded'
        if pairs>(2**63-1)//64:
            return 'lengthoverflow'
        used+=pairs;cursor=grow(cursor,prefix,1,budget)
        if isinstance(cursor,str):
            return cursor
        start=cursor;cursor=grow(cursor,pairs,64,budget)
        if isinstance(cursor,str):
            return cursor
        if cursor>len(data):
            return 'truncated'
        row=data[start:cursor]
        if not canonical(row):
            return 'noncanonical'
        blocks.append((fixed,row))
    parsed=count(cursor)
    if isinstance(parsed,str):
        return parsed
    peak_count,prefix=parsed
    if peak_count>peak_limit:
        return 'limitexceeded'
    if peak_count>(2**63-1)//33:
        return 'lengthoverflow'
    cursor=grow(cursor,prefix,1,budget)
    if isinstance(cursor,str):
        return cursor
    # Every discriminator and selected hash payload is validated before publishing the parent.
    for _ in range(peak_count):
        cursor=grow(cursor,1,1,budget)
        if isinstance(cursor,str):
            return cursor
        if cursor>len(data):
            return 'truncated'
        tag=data[cursor-1]
        if tag>1:
            return 'invalidtag'
        if tag==1:
            start=cursor;cursor=grow(cursor,32,1,budget)
            if isinstance(cursor,str):
                return cursor
            if cursor>len(data):
                return 'truncated'
            peaks.append(data[start:cursor])
        else:
            peaks.append(None) # Absence retains its index without fabricating a zero hash.
    return str(cursor)+fields((blocks,peaks))


# Structured observations expose field roles, E4 numeric value and dictionary association independently.
def fields(source):
    blocks,peaks=source;output=f' {len(blocks)} {len(peaks)}'
    # Report slots are observed numerically to distinguish byte order from fixed hash fields.
    for fixed,pairs in blocks:
        output+=' '+fixed[:32].hex()+' '+fixed[32:64].hex()+' '+fixed[64:96].hex()+' '+str(int.from_bytes(fixed[96:100],'little'))+f' {len(pairs)//64}:{token(pairs)}'
    return output+''.join(' -' if peak is None else ' '+peak.hex() for peak in peaks)


# Exact pinned published fields become explicitly derived T encodings, with dictionary sorting preserving values.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Empty/full/shifted histories and MMR holes are covered by both profiles and both state phases.
    for chain in ('tiny','full'):
        for name in ('progress_blocks_history-1','progress_blocks_history-4'):
            path=f'stf/history/{chain}/{name}.json'
            raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
            assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
            data=json.loads(raw)
            # Source tuples use named fields; T's explicit order is independent of JSON property order.
            for phase in ('pre_state','post_state'):
                beta=data[phase]['beta'];blocks=[]
                for record in beta['history']:
                    fixed=b''.join(bytes.fromhex(record[f][2:]) for f in ('header_hash','beefy_root','state_root'))+record['slot'].to_bytes(4,'little')
                    pairs=[(bytes.fromhex(p['hash'][2:]),bytes.fromhex(p['exports_root'][2:])) for p in record['reported']]
                    assert len({k for k,v in pairs})==len(pairs)
                    blocks.append((fixed,b''.join(k+v for k,v in sorted(pairs))))
                peaks=[None if p is None else bytes.fromhex(p[2:]) for p in beta['mmr']['peaks']]
                result.append(((blocks,peaks),(2 if chain=='tiny' else 341,8,341,2728,1024,2_000_000)))
    return result


# Reproducible independent field, malformed/tag/order, policy, truncation and trie integration expectations.
def requests():
    lines=[];expected=[];rng=random.Random(0x484953544f525933)
    # Trusted sources separate fixed block fields, dictionary pairs and optional peaks, without production decoding.
    def enc(source,config=BROAD,op='V'):
        blocks,peaks=source
        parts=[op,*map(str,config),str(len(blocks))]
        for fixed,pairs in blocks:
            parts.extend((fixed.hex(),token(pairs))) # Preserve source dictionary order/association, including malformed cases.
        parts.append(str(len(peaks)));parts.extend('-' if p is None else p.hex() for p in peaks)
        lines.append(' '.join(parts));expected.append(encode(source,config) if op=='V' else tree([(chapter_key(3),wire(source))])[0].hex())
    # Raw wire represents missing values and impossible counts without unsafe fabricated native arrays.
    def dec(data,config=BROAD):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    enc(([],[]),(2,0,0,0,0,2));dec(b'\0\0',(2,0,0,0,0,2))
    fixed=bytes([1])*32+bytes([2])*32+bytes([3])*32+(0x01020304).to_bytes(4,'little')
    pairs=b''.join(i.to_bytes(32,'big')+bytes([17-i])*32 for i in range(3))
    source=([(fixed,pairs),(fixed,bytes(64))],[None,bytes(32),bytes([7])*32,None]);raw=wire(source)
    enc(source);dec(raw);dec(raw+b'suffix');enc(source,op='R')
    # Every proper truncation rejects the entire parent, including a late optional hash payload or tag.
    for cut in range(len(raw)):
        dec(raw[:cut])
    for config in ((1,*BROAD[1:]),(341,1,*BROAD[2:]),(2,*BROAD[1:]),(341,8,2,*BROAD[3:]),
                   (341,8,341,3,*BROAD[4:]),(341,8,341,2728,3,BROAD[5]),(*BROAD[:5],len(raw)-1),(*BROAD[:5],len(raw))):
        enc(source,config);dec(raw,config)
    # Header/state/super-peak roles and E4 boundaries are observed independently in both directions.
    for slot in (0,1,127,128,255,256,65535,65536,2**32-1):
        source=([(fixed[:96]+slot.to_bytes(4,'little'),b'')],[]);enc(source);dec(wire(source))
    # Fixed history protocol maximum is independent from caller block policy.
    for n in (0,1,7,8,9):
        source=([(fixed,b'')]*n,[]);enc(source);dec(wire(source))
    # Canonical package keys retain their values, including duplicates of values across distinct keys.
    for position in range(32):
        a=bytes(32);b=bytearray(32);b[position]=1;b=bytes(b)
        for row in (a+bytes([8])*32+b+bytes([7])*32,b+bytes(32)+a+bytes(32),a+bytes(32)+a+bytes([9])*32):
            source=([(fixed,b''),(fixed,row)],[]);enc(source);dec(wire(source))
    # Dictionary and belt count boundaries cross canonical-natural prefix widths separately.
    for n in (0,1,127,128,129,255,256,341,342):
        row=b''.join(i.to_bytes(32,'big')+bytes([5])*32 for i in range(n));source=([(fixed,row)],[])
        enc(source);dec(wire(source));enc(source,(341,8,341,2728,1024,len(wire(source))))
    for n in (0,1,127,128,129,255,256,1024):
        source=([],[None]*n);enc(source);dec(wire(source))
    # Every reserved optional tag is rejected, including late positions after complete history and earlier peaks.
    for tag in range(2,256):
        dec(b'\0\1'+bytes([tag]));dec(b'\0\2\0'+bytes([tag]))
        dec(b'\1'+fixed+b'\0\2\0'+bytes([tag])) # A late invalid tag rejects complete earlier history and peak data.
    # Present zero and trailing absent entries remain distinct; no belt shape normalization occurs in this codec.
    for peaks in ([None],[bytes(32)],[bytes(32),None],[None,None],[bytes([255])*32,bytes(32)]):
        source=([],peaks);enc(source);dec(wire(source))
    # Incomplete/overlong/huge counts at each nested position fail before allocation or narrowing.
    for prefix in (b'',b'\x80',b'\xff',b'\x80\0',natural(MAX)):
        dec(prefix);dec(b'\1'+fixed+prefix);dec(b'\0'+prefix,(*BROAD[:4],MAX,MAX))
    dec(b'\1'+fixed+natural(MAX),(MAX,8,MAX,MAX,1024,MAX)) # Native typed-pair overflow is tested without fake source arrays.
    # Random complete dictionary rows and arbitrary malformed wire supplement exact boundary coverage.
    for _ in range(120):
        blocks=[]
        for _ in range(rng.randrange(9)):
            pairs=sorted((rng.randbytes(32),rng.randbytes(32)) for _ in range(rng.randrange(6)))
            blocks.append((rng.randbytes(100),b''.join(k+v for k,v in pairs)))
        peaks=[None if rng.randrange(3)==0 else rng.randbytes(32) for _ in range(rng.randrange(12))]
        source=(blocks,peaks);enc(source);dec(wire(source));dec(rng.randbytes(rng.randrange(500)))
    # Published tuples/dictionaries/peaks are derived component inputs, not claims of executing history STF logic.
    for source,config in published():
        enc(source,config);dec(wire(source),config);enc(source,config,op='R')
    return lines,expected
