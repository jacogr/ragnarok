"""Independent T chapter-12 fixed roles and numeric-key natural dictionary equations."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT


# Fixed E4 role IDs precede the sole variable dictionary count and natural key/gas pairs.
def wire(source):
    manager,delegator,registrar,assigners,pairs=source
    return b''.join(x.to_bytes(4,'little') for x in [manager,*assigners,delegator,registrar])+natural(len(pairs))+b''.join(natural(k)+natural(g) for k,g in pairs)


# Policy and native storage bounds are explicit; Python integer arithmetic is independently unbounded.
def valid(config):
    cores,limit,budget=config
    if not 2<=cores<=341:
        return 'invalidconfig'
    if 4*(cores+3)>budget:
        return 'limitexceeded'
    return None


# A hostile count is checked before work and before any native typed storage could be allocated.
def count_error(count,config):
    if count>config[1]:
        return 'limitexceeded'
    if count>(2**63-1)//16:
        return 'lengthoverflow'
    return None


# Complete source preflight preserves strict numeric key order rather than sorting caller data.
def encode(source,config):
    error=valid(config)
    if error:
        return error
    manager,delegator,registrar,assigners,pairs=source
    if len(assigners)!=config[0]:
        return 'invalidcount'
    error=count_error(len(pairs),config)
    if error:
        return error
    cursor=4*(len(assigners)+3)+len(natural(len(pairs)))
    if cursor>config[2]:
        return 'limitexceeded'
    previous=None
    # Charge each canonical key and gas separately so late policy failures remain independently modeled.
    for key,gas in pairs:
        if previous is not None and key<=previous:
            return 'noncanonical'
        previous=key
        for x in (key,gas):
            cursor+=len(natural(x))
            if cursor>2**63-1:
                return 'lengthoverflow'
            if cursor>config[2]:
                return 'limitexceeded'
    return chapter_key(12).hex()+' '+wire(source).hex()


# Parse canonical natural fields with a private cursor; malformed values never expose progress.
def decode(data,config):
    error=valid(config)
    if error:
        return error
    cursor=4*(config[0]+3)
    if len(data)<cursor:
        return 'truncated'
    # Each count/key/gas read models primitive framing before whole-parent byte policy.
    def read():
        nonlocal cursor
        parsed=reference_decode(data[cursor:])
        if parsed in ('truncated','noncanonical'):
            return parsed
        value,size=map(int,parsed.split());cursor+=size
        if cursor>config[2]:
            return 'limitexceeded'
        return value
    count=read()
    if isinstance(count,str):
        return count
    error=count_error(count,config)
    if error:
        return error
    pairs=[];previous=None
    # Canonical order applies to decoded numeric IDs, independently of E4 role order and wire octets.
    for _ in range(count):
        key=read()
        if isinstance(key,str):
            return key
        if key>2**32-1:
            return 'invalidservice'
        if previous is not None and key<=previous:
            return 'noncanonical'
        previous=key;gas=read()
        if isinstance(gas,str):
            return gas
        pairs.append((key,gas))
    fields=[int.from_bytes(data[i:i+4],'little') for i in range(0,4*(config[0]+3),4)]
    manager=fields[0];delegator,registrar=fields[-2:];assigners=fields[1:-2]
    return ' '.join(map(str,[cursor,manager,delegator,registrar,len(assigners),*assigners,len(pairs)]))+''.join(f' {k}:{g}' for k,g in pairs)


# Published JSON transports a mathematical dictionary; only its key order is explicitly normalized.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    # Both profiles and phases cover nonempty gas allowances and changed privilege roles.
    for chain in ('tiny','full'):
        for name in ('always_accumulate-1','always_accumulate-2','bless_from_non_manager-2','assign_from_non_assigner-2'):
            path=f'stf/accumulate/{chain}/{name}.json'
            raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
            assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
            source=json.loads(raw)
            # Field-name mapping follows upstream privileges JSON, without executing its STF or generator.
            for phase in ('pre_state','post_state'):
                value=source[phase]['privileges']
                assert set(value)=={'bless','assign','designate','register','always_acc'}
                pairs=sorted((item['id'],item['gas']) for item in value['always_acc'])
                assert len({k for k,_ in pairs})==len(pairs)
                assert all(set(item)=={'id','gas'} for item in value['always_acc'])
                state=(value['bless'],value['designate'],value['register'],value['assign'],pairs)
                assert len(state[3])==(2 if chain=='tiny' else 341)
                result.append(state)
    return result


# Deterministic byte, source, policy, malformed, fuzz and partial-root expectations precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x505249563132)
    # Decimal transport keeps independently constructed source fields separate from raw wire decoding.
    def enc(source,config=None,op='V'):
        manager,delegator,registrar,assigners,pairs=source;config=config or (len(assigners),MAX,MAX)
        lines.append(' '.join(map(str,[op,*config,manager,delegator,registrar]))+' '+(','.join(map(str,assigners)) or '-')+' '+(','.join(f'{k}:{g}' for k,g in pairs) or '-'))
        expected.append(encode(source,config) if op=='V' else tree([(chapter_key(12),wire(source))])[0].hex())
    # Hostile announced counts require no corresponding Python/native source allocation.
    def dec(data,config=(2,MAX,MAX)):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    base=(1,2,3,[4,5],[(0,0),(127,128),(128,255),(256,2**64-1)])
    raw=wire(base);enc(base);dec(raw);dec(raw+b'suffix');enc(base,op='R')
    # Complete fixed tuple and late dictionary fields are tested at every proper truncation.
    for cut in range(len(raw)):
        dec(raw[:cut])
    # All full E4 service octets, including role reuse and max IDs, remain distinct from naturally encoded keys.
    for value in (0,1,127,128,255,256,65535,65536,2**24,2**32-1):
        state=(value,value,value,[value,value],[(value,0)])
        enc(state);dec(wire(state))
    # Natural boundaries exercise key and gas widths separately; gas includes the entire unsigned domain.
    values=sorted({0,1,126,127,128,129,255,256,2**32-1,*[2**i-1 for i in range(7,64,7)],*[2**i for i in range(7,64,7)],MAX})
    for value in values:
        key=min(value,2**32-1);state=(0,0,0,[0,0],[(key,value)])
        enc(state);dec(wire(state));dec(wire(state)+b'x')
    # Count-prefix boundaries and numeric-versus-wire order are tested with exact and one-below ceilings.
    for n in (0,1,2,127,128,129,255,256,1024):
        state=(0,0,0,[0,0],[(i,MAX-i) for i in range(n)]);data=wire(state)
        for config in ((2,n,len(data)),(2,n,len(data)-1),(2,max(0,n-1),MAX)):
            enc(state,config);dec(data,config)
    # Every supported endpoint and selected intermediate core position has exact fixed shape, not an outer count.
    for cores in (2,3,127,128,255,256,341):
        state=(0x01020304,0x04030201,MAX&0xffffffff,list(range(cores)),[]);data=wire(state)
        enc(state);dec(data,(cores,0,len(data)));enc(state,op='R')
        for delta in (-1,1):
            config=(cores+delta,MAX,MAX);enc(state,config);dec(data,config)
    # Invalid profiles precede all source/input work; minimum fixed budget and empty count are independent.
    for config in ((0,MAX,MAX),(1,MAX,MAX),(342,MAX,MAX),(MAX,MAX,MAX),(2,MAX,19),(2,MAX,20),(2,MAX,21)):
        enc((0,0,0,[0,0],[]),config);dec(bytes(21),config)
    # Duplicates, descending IDs and ascending encoded bytes with descending numeric keys all reject unchanged.
    for pairs in ([(1,1),(1,2)],[(256,1),(255,2)],[(128,1),(127,2)],[(1,1),(3,1),(2,1)]):
        state=(0,0,0,[0,0],pairs);enc(state);dec(wire(state))
    fixed=bytes(20)
    # Malformed count/key/gas scalars include overlong forms, huge announcements and all late-field truncations.
    for malformed in (b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(MAX),natural(2**60)):
        dec(fixed+malformed);dec(fixed+b'\1'+malformed);dec(fixed+b'\1\0'+malformed)
        dec(fixed+b'\2\0\0'+malformed);dec(fixed+b'\2\0\0\1'+malformed)
    for key in (2**32,2**56,MAX):
        dec(fixed+b'\1'+natural(key)+b'\0')
    # Reproducible valid fields and raw single-byte/random mutations test independent scalar observations/errors.
    for _ in range(250):
        cores=rng.choice((2,3,8,341));pairs=[(k,rng.getrandbits(64)) for k in sorted(rng.sample(range(2**32),rng.randrange(20)))]
        state=(*(rng.getrandbits(32) for _ in range(3)),[rng.getrandbits(32) for _ in range(cores)],pairs)
        data=wire(state);enc(state);dec(data,(cores,MAX,MAX))
        changed=bytearray(data);changed[rng.randrange(len(changed))]^=rng.randrange(1,256)
        dec(bytes(changed),(cores,MAX,MAX));dec(rng.randbytes(rng.randrange(180)),(2,MAX,MAX))
    # Exact pinned JSON fields give success evidence for both profiles/phases; no standalone T binary is claimed.
    for state in published():
        config=(len(state[3]),MAX,MAX);enc(state);dec(wire(state),config);enc(state,op='R')
    return lines,expected
