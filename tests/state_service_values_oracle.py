"""Independent storage/preimage domains, raw values and opaque keyed capture equations for T service maps."""
import hashlib
import json
import random
import subprocess
from state_layout_oracle import service_key,chapter_key,chapter_service,token,MAX
from state_trie_oracle import tree
from state_outputs_oracle import TRACE_PATHS
from test_support import ROOT


# Exact namespace prefixes are E4 uint32-max and uint32-max-1; raw keys and hashes have no length prefixes.
def key(kind,service,identity):
    return service_key(service,(2**32-(1 if kind=='S' else 2)).to_bytes(4,'little')+identity)


# Value policy precedes key scratch/hash work, matching complete single-entry resource preflight.
def encode(kind,service,identity,value,limits):
    key_limit,value_limit=limits
    if len(value)>value_limit or len(identity)>key_limit:
        return 'limitexceeded'
    if kind=='S' and len(identity)>2**63-5:
        return 'lengthoverflow'
    return key(kind,service,identity).hex()+' '+token(value)


# Externally delimited input is the complete raw value, so no internal suffix or natural count is inferred.
def capture(service,state_key,value,limit):
    if len(value)>limit:
        return 'limitexceeded'
    if state_key[:8:2]!=service.to_bytes(4,'little'):
        return 'invalidservicekey'
    return state_key.hex()+' '+str(service)+' '+str(len(value))+' '+token(value)


# Exact promised data is hash-checked before use; upstream generators are never executed.
def blob(path):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
    return json.loads(raw)


# Published account maps retain every raw key/hash/value; no hashes are substituted or fields repaired.
def published():
    result=[]
    for chain in ('tiny','full'):
        for name in ('same_round_storage_isolation-1','same_round_storage_isolation-2'):
            source=blob(f'stf/accumulate/{chain}/{name}.json')
            for phase in ('pre_state','post_state'):
                for account in source[phase]['accounts']:
                    service=account['id'];data=account['data']
                    for item in data['storage']:
                        assert set(item)=={'key','value'}
                        result.append(('S',service,bytes.fromhex(item['key'][2:]),bytes.fromhex(item['value'][2:])))
                    for item in data['preimage_blobs']:
                        assert set(item)=={'hash','blob'}
                        identity=bytes.fromhex(item['hash'][2:]);assert len(identity)==32
                        result.append(('P',service,identity,bytes.fromhex(item['blob'][2:])))
    return result


# Existing raw hashed service keys cannot reveal their original namespace/key; evidence is explicitly unclassified.
def published_traces():
    result=[]
    for path in TRACE_PATHS:
        source=blob(path)
        for phase in ('pre_state','post_state'):
            candidates=[]
            for entry in source[phase]['keyvals']:
                state_key=bytes.fromhex(entry['key'][2:]);assert len(state_key)==31
                if state_key==chapter_key(state_key[0]):
                    continue # Exclude fixed global chapter mappings, without claiming a reversible hashed namespace.
                metadata_service=int.from_bytes(state_key[1:8:2],'little')
                if state_key==chapter_service(255,metadata_service):
                    continue # Metadata is a separate fixed mapping, not a raw hashed-service key.
                service=int.from_bytes(state_key[:8:2],'little')
                candidates.append((state_key,service,bytes.fromhex(entry['value'][2:])))
            assert candidates
            for state_key,service,value in sorted(candidates)[:2]:
                result.append(dict(path=path,phase=phase,key=state_key,service=service,value=value))
    return result


# Deterministic source, policy, namespace, capture and partial-trie comparisons precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x53455256414c554553)
    # Storage keys and preimage hash identities remain distinct source schemas in trusted transport.
    def enc(kind,service,identity,value,limits=(MAX,MAX),op='V'):
        lines.append(' '.join(map(str,[op,kind,*limits,service,token(identity),token(value)])))
        expected.append(encode(kind,service,identity,value,limits) if op=='V' else tree([(key(kind,service,identity),value)])[0].hex())
    # Raw keyed capture needs no original storage key; service/key association and value policy remain explicit.
    def cap(service,state_key,value,limit=MAX):
        lines.append(f'C {limit} {service} {state_key.hex()} {token(value)}');expected.append(capture(service,state_key,value,limit))
    # Hash padding boundaries distinguish prefixed raw keys from a natural-length or prehashed-key workaround.
    for n in (0,1,2,3,4,27,28,31,32,33,63,64,123,124,125,127,128,129,255,256,1024):
        identity=bytes(i%256 for i in range(n))
        for m in (0,1,31,32,33,127,128,129,256):
            value=bytes((255-i)%256 for i in range(m));enc('S',0x01020304,identity,value)
            cap(0x01020304,key('S',0x01020304,identity),value)
        for limits in ((n,0),(max(0,n-1),MAX),(n,3)):
            enc('S',1729,identity,b'abc',limits)
        enc('S',1729,identity,b'abc',op='R')
    # Every preimage-hash octet is part of a fixed 36-byte hashing preimage and remains separate from storage.
    for position in range(32):
        identity=bytes(position)+b'\xff'+bytes(31-position)
        for service in (0,1,127,128,255,256,65535,65536,2**24,2**32-1):
            enc('P',service,identity,b'payload');cap(service,key('P',service,identity),b'payload')
        enc('P',0,identity,b'payload',(31,MAX));enc('P',0,identity,b'payload',(32,6));enc('P',0,identity,b'payload',(32,7))
        enc('P',0,identity,b'payload',op='R')
    # Identical identity bytes in both namespaces must produce different keys; values are raw even when count-like.
    identity=bytes(range(32))
    for kind in ('S','P'):
        for value in (b'',b'\0',b'\x80\0',b'\xff'+bytes(8),b'\1payloadsuffix'):
            enc(kind,1729,identity,value);cap(1729,key(kind,1729,identity),value)
    # Preimage hash/value consistency is contextual: malformed relationships are preserved by the structural serializer.
    enc('P',1,bytes(32),b'not a zero-hash preimage')
    # Every service-position octet is checked on capture, while copied digest bytes remain intentionally opaque.
    state_key=key('S',0x01020304,b'key')
    for position in range(31):
        changed=bytearray(state_key);changed[position]^=255
        cap(0x01020304,bytes(changed),b'value');cap(0x01020304,bytes(changed),b'value',4)
    # Exact and one-below value budget bounds externally delimited input; appending bytes changes the raw value itself.
    for n in (0,1,31,32,33,127,128,1024):
        value=bytes(n)
        for limit in (max(0,n-1),n,n+1):
            cap(1,key('P',1,bytes(32)),value,limit)
        cap(1,key('P',1,bytes(32)),value+b'suffix')
    # Reproducible opaque binary keys and values exercise independent hashes, service binding and immutable observations.
    for _ in range(150):
        service=rng.getrandbits(32);identity=rng.randbytes(rng.randrange(200));value=rng.randbytes(rng.randrange(400))
        enc('S',service,identity,value);cap(service,key('S',service,identity),value)
        identity=rng.randbytes(32);enc('P',service,identity,value);cap(service,key('P',service,identity),value)
    # Empty raw values remain present leaves, distinct from an absent mapping, in both key namespaces.
    enc('S',0,b'',b'',op='R');enc('P',0,bytes(32),b'',op='R')
    # Pinned JSON supplies source-derivation evidence for both namespaces, including nonempty storage and code blobs.
    for kind,service,identity,value in published():
        enc(kind,service,identity,value);cap(service,key(kind,service,identity),value);enc(kind,service,identity,value,op='R')
    # Raw trace capture only proves opaque key/value retention; it cannot identify a hashed key's original namespace.
    for entry in published_traces():
        cap(entry['service'],entry['key'],entry['value'])
    return lines,expected
