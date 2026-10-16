"""Independent T chapter-16 ordered E4-service/commitment sequence equations."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT

DEFAULT=(MAX,MAX)
TRACE_PATHS=('traces/fuzzy/00000010.json','traces/storage/00000001.json','traces/storage/00000002.json','traces/preimages/00000001.json')


# Source sequence order is preserved exactly: this component is not a sorted dictionary or set.
def wire(values):
    return natural(len(values))+b''.join(service.to_bytes(4,'little')+commitment for service,commitment in values)


# Independent unbounded arithmetic checks caller policy then native wire and typed fixed-record capacity.
def extent(count,prefix,config):
    if count>config[0]:
        return 'limitexceeded'
    if count>(2**63-1-prefix)//36 or count>(2**63-1)//36:
        return 'lengthoverflow'
    size=prefix+count*36
    if size>config[1]:
        return 'limitexceeded'
    return size


# Complete extent precedes expected output allocation; fixed typed values already have their exact domains.
def encode(values,config):
    checked=extent(len(values),len(natural(len(values))),config)
    return checked if isinstance(checked,str) else chapter_key(16).hex()+' '+wire(values).hex()


# Parse a full fixed-pair prefix without inferring service ordering, uniqueness or commitment validity.
def parse(data,config):
    parsed=reference_decode(data)
    if parsed in ('truncated','noncanonical'):
        return parsed
    count,prefix=map(int,parsed.split());checked=extent(count,prefix,config)
    if isinstance(checked,str):
        return checked
    if checked>len(data):
        return 'truncated'
    values=[(int.from_bytes(data[i:i+4],'little'),data[i+4:i+36]) for i in range(prefix,checked,36)]
    return values,checked


# Decode expectations are logical copied fields and exact consumed extent, not native round-trip answers.
def decode(data,config):
    result=parse(data,config)
    if isinstance(result,str):
        return result
    values,consumed=result
    return f'{consumed} {len(values)}'+''.join(f' {service}:{commitment.hex()}' for service,commitment in values)


# Exact pinned traces supply raw original C(16) entries; currently selected observations are all empty.
def published():
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors'];result=[]
    for path in TRACE_PATHS:
        raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
        assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
        source=json.loads(raw)
        for phase in ('pre_state','post_state'):
            entries=[bytes.fromhex(x['value'][2:]) for x in source[phase]['keyvals'] if x['key']=='0x'+chapter_key(16).hex()]
            assert len(entries)==1
            data=entries[0];parsed=parse(data,DEFAULT)
            assert not isinstance(parsed,str),parsed
            values,consumed=parsed
            assert consumed==len(data) and wire(values)==data
            result.append(dict(path=path,phase=phase,wire=data,values=values))
    return result


# Deterministic complete/malformed/boundary/source/mutation and partial-trie cases precede native execution.
def requests():
    lines=[];expected=[];rng=random.Random(0x4c4153544f55543136)
    # Decimal service IDs and literal commitments build typed sources independently of wire decoding.
    def enc(values,config=DEFAULT,op='V'):
        fields=' '.join(f'{s}:{h.hex()}' for s,h in values) or '-'
        lines.append(op+' '+' '.join(map(str,config))+' '+fields)
        expected.append(encode(values,config) if op=='V' else tree([(chapter_key(16),wire(values))])[0].hex())
    # Hostile count announcements do not allocate matching native or reference source arrays.
    def dec(data,config=DEFAULT):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    base=[(0x01020304,bytes(range(32))),(2**32-1,bytes([255])*32),(0,bytes(32))]
    raw=wire(base);enc(base);dec(raw);dec(raw+b'suffix');enc(base,op='R')
    # Every proper truncation includes early fixed IDs and the final commitment octet.
    for cut in range(len(raw)):
        dec(raw[:cut])
    # Canonical count widths and exact/one-below element and complete byte policies are independently checked.
    for n in (0,1,2,127,128,129,255,256,1024):
        values=[(i,i.to_bytes(32,'big')) for i in range(n)];data=wire(values)
        for config in ((n,len(data)),(n,len(data)-1),(max(0,n-1),MAX),DEFAULT):
            enc(values,config);dec(data,config)
        dec(data+b'extra')
        enc(values,op='R')
    # Every E4 service octet and every opaque hash octet retains its own position, regardless of value/order.
    for position in range(32):
        commitment=bytes(position)+b'\xff'+bytes(31-position)
        for service in (0,1,127,128,255,256,65535,65536,2**24,2**32-1):
            values=[(service,commitment)];enc(values);dec(wire(values))
    # Duplicate services/pairs, descending service IDs and arbitrary hash order are structural sequences, not set errors.
    for values in ([base[1],base[0],base[2]],[base[0],base[0]],[(1,bytes([255])*32),(1,bytes(32))]):
        enc(values);dec(wire(values));enc(values,op='R')
    # Missing, overlong and unrepresentable announced counts reject without reading or allocating fake pairs.
    for prefix in (b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(MAX),natural(2**60)):
        dec(prefix);dec(prefix,(0,MAX));dec(prefix,(MAX,0))
    # Native capacity boundary is hostile even when caller policy allows the entire uint64 count domain.
    for n in ((2**63-1)//36,(2**63-1)//36+1):
        dec(natural(n));dec(natural(n),(MAX,0))
    # Reproducible nontrivial fixed pairs and single-byte/raw mutations expose all retained field values and errors.
    for _ in range(250):
        values=[(rng.getrandbits(32),rng.randbytes(32)) for _ in range(rng.randrange(20))]
        data=wire(values);enc(values);dec(data)
        changed=bytearray(data);changed[rng.randrange(len(changed))]^=rng.randrange(1,256)
        dec(bytes(changed));dec(rng.randbytes(rng.randrange(300)))
    # Raw published entries consume completely and re-emit identically; nonempty coverage above remains authored.
    for source in published():
        dec(source['wire']);enc(source['values']);enc(source['values'],op='R')
    return lines,expected
