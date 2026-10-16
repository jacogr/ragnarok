"""Independent E4-length/hash request keys and fixed tagged 0..3 timeslot history equations."""
import hashlib
import random
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import service_key,token,MAX
from state_trie_oracle import tree
from state_service_values_oracle import blob,key as value_key
from state_outputs_oracle import TRACE_PATHS


# Request length is the exact E4 key domain prefix, without a natural or hash-length discriminator.
def key(service,identity,length):
    return service_key(service,length.to_bytes(4,'little')+identity)


# Count 0..3 selects the shape; each corresponding timeslot retains all four little-endian octets.
def wire(slots):
    return natural(len(slots))+b''.join(x.to_bytes(4,'little') for x in slots)


# Protocol shape is checked before stricter caller work/byte policy; native arithmetic is bounded to thirteen bytes.
def extent(count,config):
    items,budget=config
    if count>3:
        return 'invalidcount'
    if count>items or 1+4*count>budget:
        return 'limitexceeded'
    return 1+4*count


# Full history policy precedes logical lookup-hash policy and maintained key hashing.
def encode(service,identity,length,slots,config):
    key_limit,items,budget=config;checked=extent(len(slots),(items,budget))
    if isinstance(checked,str):
        return checked
    if key_limit<32:
        return 'limitexceeded'
    return key(service,identity,length).hex()+' '+wire(slots).hex()


# Prefix parser never reads a timestamp or constructs a history mode before complete payload presence.
def parse(data,config):
    parsed=reference_decode(data)
    if parsed in ('truncated','noncanonical'):
        return parsed
    count,prefix=map(int,parsed.split());checked=extent(count,config)
    if isinstance(checked,str):
        return checked
    assert prefix==1
    if len(data)<checked:
        return 'truncated'
    return tuple(int.from_bytes(data[i:i+4],'little') for i in range(1,checked,4)),checked


# Logical observations preserve all active positions only; no fabricated unused/default timeslots are exposed.
def decode(data,config):
    parsed=parse(data,config)
    if isinstance(parsed,str):
        return parsed
    slots,consumed=parsed
    return f'{consumed} {len(slots)}'+''.join(f' {x}' for x in slots)


# Exact JSON request maps preserve advertised lengths, hashes and sequence order without chronology repair.
def published():
    result=[]
    for chain in ('tiny','full'):
        for name in ('preimage_needed-1','preimage_needed-2','preimage_not_needed-1','preimage_not_needed-2'):
            source=blob(f'stf/preimages/{chain}/{name}.json')
            for phase in ('pre_state','post_state'):
                for account in source[phase]['accounts']:
                    for item in account['data']['preimage_requests']:
                        assert set(item)=={'key','value'} and set(item['key'])=={'hash','length'}
                        identity=bytes.fromhex(item['key']['hash'][2:]);slots=tuple(item['value'])
                        assert len(identity)==32 and len(slots)<=3
                        result.append((account['id'],identity,item['key']['length'],slots))
    return result


# Raw trace request identities are proven through matching preimage content/key, never guessed from digest shape.
def published_traces():
    result=[]
    for path in TRACE_PATHS:
        source=blob(path)
        for phase in ('pre_state','post_state'):
            entries={bytes.fromhex(x['key'][2:]):bytes.fromhex(x['value'][2:]) for x in source[phase]['keyvals']}
            assert len(entries)==len(source[phase]['keyvals']) # Never hide a duplicated serialized key through reference dictionary construction.
            seen=set()
            for state_key,value in entries.items():
                assert len(state_key)==31
                service=int.from_bytes(state_key[:8:2],'little');identity=hashlib.blake2b(value,digest_size=32).digest()
                if value_key('P',service,identity)!=state_key:
                    continue # Only content-consistent explicit preimage-namespace matches identify a lookup hash.
                request_key=key(service,identity,len(value))
                if request_key not in entries or request_key in seen:
                    continue # This evidence requires the matching exact request mapping in the same state.
                raw=entries[request_key];parsed=parse(raw,(3,13))
                assert not isinstance(parsed,str),parsed
                slots,consumed=parsed
                assert consumed==len(raw) and wire(slots)==raw
                result.append(dict(path=path,phase=phase,service=service,hash=identity,length=len(value),slots=slots,key=request_key,wire=raw))
                seen.add(request_key)
    assert result
    return result


# Deterministic complete, malformed, policy, namespace and mutation comparisons precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x5245515545535453)
    # Source modes are valid tagged alternatives; impossible source arities are not manufactured with unsafe casts.
    def enc(service,identity,length,slots,config=(MAX,MAX,MAX),op='V'):
        lines.append(' '.join(map(str,[op,*config,service,identity.hex(),length,len(slots),*slots])))
        expected.append(encode(service,identity,length,slots,config) if op=='V' else tree([(key(service,identity,length),wire(slots))])[0].hex())
    # Hostile wire counts remain independently expressible without constructing an invalid source variant.
    def dec(data,config=(MAX,MAX)):
        lines.append(f'D {config[0]} {config[1]} {token(data)}');expected.append(decode(data,config))
    identity=bytes(range(32))
    for slots in ((),(0,),(1,2),(1,2,3),(MAX&0xffffffff,0,0),(7,7,7)):
        data=wire(slots);enc(1729,identity,42,slots);dec(data);dec(data+b'suffix');enc(1729,identity,42,slots,op='R')
        for cut in range(len(data)):
            dec(data[:cut])
        for config in ((32,len(slots),len(data)),(32,len(slots),len(data)-1),(31,MAX,MAX),(32,max(0,len(slots)-1),MAX)):
            enc(1729,identity,42,slots,config);dec(data,config[1:])
    # All E4 timeslot/length/service domains are distinct and independently cross high/low octet boundaries.
    values=(0,1,127,128,255,256,65535,65536,2**24,2**32-3,2**32-2,2**32-1)
    for count in (1,2,3):
        for position in range(count):
            for value in values:
                slots=[0]*count;slots[position]=value;enc(0,identity,0,slots);dec(wire(slots))
    for length in values:
        for service in values:
            enc(service,identity,length,(0,1,2))
        enc(0,identity,length,(),op='R')
    # Every lookup hash octet participates in the exact fixed hashing preimage.
    for position in range(32):
        changed=bytes(position)+b'\xff'+bytes(31-position)
        enc(1,changed,128,(1,));enc(1,changed,128,(1,),op='R')
    # Malformed and overlong count framing is distinct from the protocol's four-slot rejection.
    for prefix in (b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(4),natural(127),natural(128),natural(MAX)):
        dec(prefix);dec(prefix,(0,0));dec(prefix+bytes(16))
    for first in range(4,256):
        dec(bytes([first])+bytes(20))
    # Caller maxima apply independently to every shape, including the empty requested count byte.
    for count in range(4):
        slots=tuple(range(count))
        for items in range(5):
            for budget in (0,1,4,5,8,9,12,13,14):
                enc(1,identity,1,slots,(32,items,budget));dec(wire(slots),(items,budget))
    # Reproducible tagged sources and raw mutations exercise fixed values and precise malformed-wire reasons.
    for _ in range(250):
        slots=tuple(rng.getrandbits(32) for _ in range(rng.randrange(4)));identity=rng.randbytes(32)
        enc(rng.getrandbits(32),identity,rng.getrandbits(32),slots);dec(wire(slots))
        raw=bytearray(wire(slots));raw[rng.randrange(len(raw))]^=rng.randrange(1,256)
        dec(bytes(raw));dec(rng.randbytes(rng.randrange(20)))
    for service,identity,length,slots in published():
        enc(service,identity,length,slots);dec(wire(slots));enc(service,identity,length,slots,op='R')
    for entry in published_traces():
        enc(entry['service'],entry['hash'],entry['length'],entry['slots']);dec(entry['wire']);enc(entry['service'],entry['hash'],entry['length'],entry['slots'],op='R')
    return lines,expected
