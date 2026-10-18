# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent chapter-4 byte equations; all values are structural, with transition checks explicitly separate."""
import hashlib
import json
import random
from state_safrole_oracle import extent
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import token,chapter_key,MAX
from state_trie_oracle import tree
from test_support import ROOT

BROAD=(341,1023,400_000,12,12,1_000_000)


# Fixed-width tickets retain identifier order and every E1 attempt value, without score sorting.
def wire(source):
    pending,root,kind,schedule,accumulator=source
    return natural(len(pending)//336)+pending+root+bytes([kind])+schedule+natural(len(accumulator)//33)+accumulator


# Positive epoch length and typed/native extent must be proved before any variable work.
def valid(config):
    if config[3]==0:
        return 'invalidconfig'
    if config[3]>(2**63-1)//33:
        return 'lengthoverflow'
    return None


# Parent byte arithmetic is independent and unbounded in Python, with explicit native/policy comparisons.
def grow(cursor,count,width,budget):
    end=cursor+count*width
    if end>2**63-1:
        return 'lengthoverflow'
    if end>budget:
        return 'limitexceeded'
    return end


# Independently validate typed source populations and size the complete entry before producing expected bytes.
def encode(source,config):
    error=valid(config)
    if error:
        return error # Invalid epoch configuration precedes all source validation.
    pending,root,kind,schedule,accumulator=source
    cursor=extent(len(pending)//336,len(natural(len(pending)//336)),config[:3])
    if isinstance(cursor,str):
        return cursor
    slots=len(schedule)//(33 if kind==0 else 32);count=len(accumulator)//33
    if slots!=config[3] or count>config[3]:
        return 'invalidcount'
    if count>config[4]:
        return 'limitexceeded'
    # Full parent accounting includes every fixed field, schedule byte and accumulator prefix.
    for n,width in ((145,1),(slots,33 if kind==0 else 32),(len(natural(count)),1),(count,33)):
        cursor=grow(cursor,n,width,config[5])
        if isinstance(cursor,str):
            return cursor # No earlier source is exposed after a late resource failure.
    return f'{cursor} '+wire(source).hex()


# Prefix parser handles hostile counts/tags independently of production offsets or copied metadata.
def decode(data,config):
    error=valid(config)
    if error:
        return error
    parsed=reference_decode(data)
    if parsed in ('truncated','noncanonical'):
        # The pending roster's invalid core configuration takes precedence over framing.
        return 'invalidconfig' if config[0]<2 else parsed
    count,prefix=map(int,parsed.split());cursor=extent(count,prefix,config[:3])
    if isinstance(cursor,str):
        return cursor
    if len(data)<cursor:
        return 'truncated'
    pending=data[prefix:cursor];root=data[cursor:cursor+144]
    cursor=grow(cursor,145,1,config[5])
    if isinstance(cursor,str):
        return cursor
    if len(data)<cursor:
        return 'truncated'
    kind=data[cursor-1]
    if kind>1:
        return 'invalidtag'
    start=cursor;cursor=grow(cursor,config[3],33 if kind==0 else 32,config[5])
    if isinstance(cursor,str):
        return cursor
    if len(data)<cursor:
        return 'truncated'
    schedule=data[start:cursor];parsed=reference_decode(data[cursor:])
    if parsed in ('truncated','noncanonical'):
        return parsed
    count,prefix=map(int,parsed.split())
    if count>config[3]:
        return 'invalidcount'
    if count>config[4]:
        return 'limitexceeded'
    cursor=grow(cursor,prefix,1,config[5])
    if isinstance(cursor,str):
        return cursor
    start=cursor;cursor=grow(cursor,count,33,config[5])
    if isinstance(cursor,str):
        return cursor
    if len(data)<cursor:
        return 'truncated'
    return f'{cursor} {token(pending)} {root.hex()} {kind} {token(schedule)} {token(data[start:cursor])}'


# Frozen published before/after states cover fallback keys and tickets; their chapter encodings are explicitly derived.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Two fixture families, two chain profiles and two phases provide eight independent named state sources.
    for chain,slots,cores in (('tiny',12,2),('full',600,341)):
        for name in ('enact-epoch-change-with-no-tickets-1','publish-tickets-with-mark-5'):
            path=f'vendor/jamtestvectors/stf/safrole/{chain}/{name}.json';raw=(ROOT/path).read_bytes()
            assert hashlib.sha256(raw).hexdigest()==pins['files'][path]
            parsed=json.loads(raw)
            # Pending keys and schedules retain published order and exact opaque bytes.
            for phase in ('pre_state','post_state'):
                s=parsed[phase];pending=b''.join(bytes.fromhex(v[f][2:]) for v in s['gamma_k']
                                               for f in ('bandersnatch','ed25519','bls','metadata'))
                schedule=s['gamma_s'];kind=0 if 'tickets' in schedule else 1
                # Ticket identifiers and E1 attempts use C.2's fixed 33-byte record layout.
                def tickets(values):
                    return b''.join(bytes.fromhex(v['id'][2:])+bytes([v['attempt']]) for v in values)
                data=tickets(schedule['tickets']) if kind==0 else b''.join(bytes.fromhex(k[2:]) for k in schedule['keys'])
                source=(pending,bytes.fromhex(s['gamma_z'][2:]),kind,data,tickets(s['gamma_a']))
                result.append((source,(cores,1023,400_000,slots,slots,1_000_000)))
    return result


# Build reproducible independent success, every-truncation, malformed-discriminator/count and policy observations.
def requests():
    lines=[];expected=[];rng=random.Random(0x534146524f4c4534)
    # Typed source transport keeps all fields independently authored, including invalid fixed schedule lengths.
    def enc(source,config=BROAD,op='V'):
        p,r,k,s,a=source
        lines.append(op+' '+' '.join(map(str,config))+f' {token(p)} {r.hex()} {k} {token(s)} {token(a)}')
        expected.append(encode(source,config) if op=='V' else tree([(chapter_key(4),wire(source))])[0].hex())
    # Raw wire can represent every malformed count/tag without unsafe fake source objects.
    def dec(data,config=BROAD):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    # Fixed schemas preserve 0/127/128/255 E1 attempts and arbitrary accumulator/schedule order.
    for kind in (0,1):
        width=33 if kind==0 else 32
        source=(rng.randbytes(2016),rng.randbytes(144),kind,rng.randbytes(12*width),rng.randbytes(12*33))
        raw=wire(source);enc(source);dec(raw);dec(raw+b'suffix');enc(source,op='R')
        # Every missing byte, including the final accumulator attempt, must reject the whole parent.
        for cut in range(len(raw)):
            dec(raw[:cut])
        for budget in (0,len(raw)-1,len(raw),MAX):
            config=(*BROAD[:5],budget);enc(source,config);dec(raw,config)
        for limit in (0,11,12,MAX):
            config=(*BROAD[:4],limit,BROAD[5]);enc(source,config);dec(raw,config)
        for slots in (0,11,12,13,MAX):
            config=(*BROAD[:3],slots,MAX,MAX);enc(source,config);dec(raw,config)
        # Empty accumulators and wrong fixed schedule counts are source cases, not only round trips.
        enc((*source[:4],b''));dec(wire((*source[:4],b'')))
        for n in (0,11,13):
            enc((*source[:3],rng.randbytes(n*width),source[4]))
        enc((*source[:4],rng.randbytes(13*33)))
        tagOffset=len(natural(6))+2016+144
        # Exhaust every reserved schedule tag byte.
        for tag in range(2,256):
            changed=bytearray(raw);changed[tagOffset]=tag;dec(bytes(changed))
        accOffset=tagOffset+1+12*width
        for prefix in (b'\x80',b'\x80\0',natural(13),natural(MAX)):
            dec(raw[:accOffset]+prefix)
        # Late truncated/policy errors are independent of pending roster population and budgets.
        for config in ((1,1023,400_000,12,12,MAX),(2,5,400_000,12,12,MAX),(2,6,2016,12,12,MAX)):
            enc(source,config);dec(raw,config)
    # Exhaust every E1 attempt value in both a schedule ticket and accumulator ticket.
    for attempt in range(256):
        value=bytes([17])*32+bytes([attempt])
        source=(bytes(2016),bytes(144),0,value*2,value)
        config=(2,6,2017,2,2,10_000);enc(source,config);dec(wire(source),config)
    # Canonical accumulator count framing crosses 127/128 while fixed schedules still omit their own count.
    for kind in (0,1):
        for n in (0,1,127,128,129):
            source=(bytes(2016),bytes(144),kind,bytes(128*(33 if kind==0 else 32)),bytes(n*33))
            config=(2,6,2017,128,128,30_000);enc(source,config);dec(wire(source),config)
        source=(*source[:4],b'')
        config=(2,6,2017,128,0,30_000);enc(source,config);dec(wire(source),config)
    # Random complete source values span both modes, arbitrary E1 values and varying allowed populations/epochs.
    for _ in range(120):
        slots=rng.choice((1,2,12,128));kind=rng.randrange(2);n=rng.choice((6,9,129))
        source=(rng.randbytes(n*336),rng.randbytes(144),kind,rng.randbytes(slots*(33 if kind==0 else 32)),rng.randbytes(rng.randrange(slots+1)*33))
        config=(341,1023,400_000,slots,slots,1_000_000);enc(source,config);dec(wire(source),config)
    # Published field inputs are derived chapter cases, not claims of executing their STF transitions.
    for source,config in published():
        enc(source,config);dec(wire(source),config);enc(source,config,op='R')
    return lines,expected
