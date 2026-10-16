"""Independent state T chapters 1/2: framed pools and fixed queues, preserving core/row order."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT


# Bound configured descriptor/minimum wire extents independently using Python integers.
def valid(kind,config):
    cores,hashes,budget=config;minimum=1 if kind==0 else 2560
    if cores<2:
        return 'invalidconfig' # A viable JAM population requires at least two cores.
    if cores>(2**63-1)//16 or cores>(2**63-1)//minimum:
        return 'lengthoverflow' # Checked native selftests verify the pinned 64-bit ARC descriptor size (16 bytes).
    if cores*minimum>budget:
        return 'limitexceeded'
    return None


# Direct independent byte construction has no outer count and never sorts or deduplicates rows.
def wire(kind,rows):
    return b''.join((natural(len(row)//32) if kind==0 else b'')+row for row in rows)


# Keep protocol shape and aggregate resource ceilings distinct.
def charge(kind,count,prefix,total,cursor,config):
    cores,hashes,budget=config
    if (kind==0 and count>8) or (kind==1 and count!=80):
        return 'invalidcount'
    if total+count>hashes:
        return 'limitexceeded'
    if cursor+prefix+count*32>2**63-1:
        return 'lengthoverflow'
    if cursor+prefix+count*32>budget:
        return 'limitexceeded'
    return None


# Encoder reference validates late rows before constructing any successful entry bytes.
def encode(kind,rows,config):
    error=valid(kind,config)
    if error:
        return error # Configuration precedes source shape.
    if len(rows)!=config[0]:
        return 'invalidcount'
    total=cursor=0
    # Per-row framing and hash budgets are accumulated without native arithmetic limits.
    for row in rows:
        count=len(row)//32;prefix=len(natural(count)) if kind==0 else 0
        error=charge(kind,count,prefix,total,cursor,config)
        if error:
            return error # No partial earlier payload is exposed.
        total+=count;cursor+=prefix+count*32
    return chapter_key(kind+1).hex()+' '+token(wire(kind,rows))


# Parse canonical counts independently and expose complete ordered field observations only after full validation.
def decode(kind,data,config):
    error=valid(kind,config)
    if error:
        return error # Unsafe/invalid configuration cannot initiate traversal.
    cursor=total=0;rows=[]
    # Fixed outer cardinality is provided by the chain profile, never read from the wire.
    for _ in range(config[0]):
        count=80;prefix=0
        if kind==0:
            parsed=reference_decode(data[cursor:])
            if parsed in ('truncated','noncanonical'):
                return parsed # Reject malformed count framing before row semantics.
            count,prefix=map(int,parsed.split())
        error=charge(kind,count,prefix,total,cursor,config)
        if error:
            return error # Announced work/policy is checked before requiring its bytes.
        cursor+=prefix
        if cursor+count*32>len(data):
            return 'truncated'
        rows.append(data[cursor:cursor+count*32]);cursor+=count*32;total+=count
    return f'{cursor} {config[0]} {kind}'+''.join(f' {len(row)//32}:{token(row)}' for row in rows)


# Read exact frozen Git blobs without changing sparse checkout or executing vector generators.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Tiny/full pre/post JSON values supply named component inputs, not standalone state serialization binaries.
    for chain in ('tiny','full'):
        path=f'stf/authorizations/{chain}/progress_authorizations-1.json'
        data=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
        assert hashlib.sha256(data).hexdigest()==pins['git_blobs'][path]
        parsed=json.loads(data)
        # Preserve published order and duplicates in both core-indexed nested sequences.
        for phase in ('pre_state','post_state'):
            result.append([[b''.join(bytes.fromhex(x[2:]) for x in row) for row in parsed[phase][name]]
                           for name in ('auth_pools','auth_queues')])
    return result


# Construct deterministic success, malformed-wire, shape-policy and integration observations before running native code.
def requests():
    lines=[];expected=[];rng=random.Random(0x4155544853544154)
    # Source rows remain separate tokens so empty pools and wrong outer cardinalities are representable.
    def enc(kind,rows,config=(2,MAX,MAX),op='V'):
        lines.append(f'{op} {kind} '+' '.join(map(str,config))+f' {len(rows)}'+''.join(' '+token(row) for row in rows))
        if op=='V':
            expected.append(encode(kind,rows,config)) # Compare raw keys and bytes independently of native round trips.
        else:
            queues=[b''.join(bytes((i+j+k)%256 for k in range(32)) for j in range(80)) for i in range(len(rows))]
            root,nodes=tree([(chapter_key(1),wire(0,rows)),(chapter_key(2),wire(1,queues))])
            expected.append(root.hex()+f' {nodes}')
    # Hostile wire inputs need no fabricated native sequence descriptors.
    def dec(kind,data,config=(2,MAX,MAX)):
        lines.append(f'D {kind} '+' '.join(map(str,config))+' '+token(data));expected.append(decode(kind,data,config))
    # Exhaust every pool count and every truncation of two nonempty eight-element pools.
    for a in range(10):
        for b in range(10):
            rows=[rng.randbytes(a*32),rng.randbytes(b*32)]
            enc(0,rows);dec(0,wire(0,rows));dec(0,wire(0,rows)+b'extra')
            # Individual late counts and aggregate hash/byte ceilings are exact or one below.
            for config in ((2,a+b,2+(a+b)*32),(2,max(0,a+b-1),MAX),(2,MAX,1+(a+b)*32)):
                enc(0,rows,config);dec(0,wire(0,rows),config)
    data=wire(0,[rng.randbytes(256),rng.randbytes(256)])
    for cut in range(len(data)):
        dec(0,data[:cut]) # No proper truncation may expose an earlier complete core pool.
    queues=[rng.randbytes(2560),rng.randbytes(2560)];data=wire(1,queues)
    enc(1,queues);dec(1,data);dec(1,data+b'suffix')
    # Exhaust fixed-queue truncations, including every hash and core boundary.
    for cut in range(len(data)):
        dec(1,data[:cut])
    # Exact queue shape and source core count must be checked independently from output size.
    for count in (0,1,79,80,81):
        enc(1,[queues[0],rng.randbytes(count*32)])
    for kind in (0,1):
        rows=[b'',b''] if kind==0 else queues
        for count in (0,1,3):
            enc(kind,(rows*2)[:count]) # Wrong implicit outer cardinality cannot be normalized away.
        for config in ((0,MAX,MAX),(1,MAX,MAX),(MAX,MAX,MAX),(2,0,MAX),(2,MAX,0),
                       (2,160,5120),(2,159,5120),(2,160,5119)):
            enc(kind,rows,config);dec(kind,wire(kind,rows),config)
    # Pool count framing rejects overlong encodings and oversized populations before payload access.
    for count in (9,128,2**32,MAX):
        dec(0,natural(count))
    for malformed in (b'',b'\x80',b'\x80\0',b'\xff'+bytes(8),b'\x80\x08'):
        dec(0,malformed)
    # Repeated hashes and empty cores are ordered sequence content, never canonical sets.
    enc(0,[bytes(256),bytes(32)]);dec(0,wire(0,[bytes(256),bytes(32)]))
    # Random source shapes and malformed pool framing supplement the exhaustive boundaries.
    for _ in range(150):
        rows=[rng.randbytes(rng.randrange(9)*32) for _ in range(2)]
        enc(0,rows);dec(0,wire(0,rows));dec(0,rng.randbytes(rng.randrange(600)))
    # Exact pinned JSON supplies derived component cases for both chain profiles and both state phases.
    for pools,queues in published():
        cores=len(pools)
        enc(0,pools,(cores,MAX,MAX));dec(0,wire(0,pools),(cores,MAX,MAX))
        enc(1,queues,(cores,MAX,MAX));dec(1,wire(1,queues),(cores,MAX,MAX))
    # Separate chapter entries compose into a partial mapping commitment, not a full JAM state root.
    for rows in ([b'',b''],[rng.randbytes(256),rng.randbytes(96)]):
        enc(0,rows,op='R')
    return lines,expected
