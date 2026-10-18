# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent T chapter-13 equations with separate partial JSON and complete published-wire evidence."""
import hashlib
import json
import random
import subprocess
from test_codec import reference_encode as natural,reference_decode
from state_layout_oracle import chapter_key,token,MAX
from state_trie_oracle import tree
from test_support import ROOT

DEFAULT=(2,6,6,MAX,MAX)


# Counters in the two epoch arrays are E4; service keys use E4 while core/service values retain canonical naturals.
def wire(source):
    current,previous,cores,services=source
    return b''.join(natural(len(rows))+b''.join(x.to_bytes(4,'little') for row in rows for x in row) for rows in (current,previous))+b''.join(natural(x) for row in cores for x in row)+natural(len(services))+b''.join(row[0].to_bytes(4,'little')+b''.join(natural(x) for x in row[1:]) for row in services)


# Both roster profiles are explicit and independent; a previous roster may survive a current-set resize.
def valid(config):
    cores,current,previous,limit,budget=config
    if not 2<=cores<=341 or any(n<6 or n>3*cores or n%3 for n in (current,previous)):
        return 'invalidconfig'
    return None


# Native fixed typed service storage, not merely minimal wire size, must fit an announced count.
def count_error(n,config):
    if n>config[3]:
        return 'limitexceeded'
    if n>(2**63-1)//96:
        return 'lengthoverflow'
    return None


# Source preflight checks array shape, strict key order and each natural byte charge before producing output.
def encode(source,config):
    error=valid(config)
    if error:
        return error
    current,previous,cores,services=source;size=0
    # Roster count/extent policy is checked in the same current/previous schema order.
    for rows,count in zip((current,previous),config[1:3]):
        if len(rows)!=count:
            return 'invalidcount'
        size+=len(natural(count))+24*count
        if size>config[4]:
            return 'limitexceeded'
    if len(cores)!=config[0]:
        return 'invalidcount'
    error=count_error(len(services),config)
    if error:
        return error
    # Unbounded Python arithmetic models checked extent for all variable-width scalar fields.
    def charge(x):
        nonlocal size
        size+=len(natural(x))
        if size>2**63-1:
            return 'lengthoverflow'
        if size>config[4]:
            return 'limitexceeded'
        return None
    for row in cores:
        for x in row:
            error=charge(x)
            if error:
                return error
    error=charge(len(services))
    if error:
        return error
    previous=None
    # Dictionary order is numeric by service ID; tuple counters and gas need no monotonicity.
    for row in services:
        if previous is not None and row[0]<=previous:
            return 'noncanonical'
        previous=row[0]
        size+=4
        if size>config[4]:
            return 'limitexceeded'
        for x in row[1:]:
            error=charge(x)
            if error:
                return error
    return chapter_key(13).hex()+' '+wire(source).hex()


# Independently parse complete prefixes into Python field tuples before making any native observation.
def parse(data,config):
    error=valid(config)
    if error:
        return error
    cursor=0;epochs=[]
    # Private cursor advances only for canonical complete scalars, with parent policy charged afterward.
    def read():
        nonlocal cursor
        parsed=reference_decode(data[cursor:])
        if parsed in ('truncated','noncanonical'):
            return parsed
        value,size=map(int,parsed.split());cursor+=size
        if cursor>config[4]:
            return 'limitexceeded'
        return value
    # Each tuple array has its own canonical count followed by exact E4 fields.
    for count in config[1:3]:
        n=read()
        if isinstance(n,str):
            return n
        if n!=count:
            return 'invalidcount'
        end=cursor+n*24
        if end>config[4]:
            return 'limitexceeded'
        if end>len(data):
            return 'truncated'
        epochs.append([tuple(int.from_bytes(data[i+j:i+j+4],'little') for j in range(0,24,4)) for i in range(cursor,end,24)])
        cursor=end
    cores=[]
    # Fixed core sequence has no count; every tuple is exactly eight natural fields.
    for _ in range(config[0]):
        row=[]
        for _ in range(8):
            x=read()
            if isinstance(x,str):
                return x
            row.append(x)
        cores.append(tuple(row))
    n=read()
    if isinstance(n,str):
        return n
    error=count_error(n,config)
    if error:
        return error
    services=[];previous=None
    # E4 service keys inherently fit uint32 and remain strictly ascending numerically.
    for _ in range(n):
        end=cursor+4
        if end>config[4]:
            return 'limitexceeded'
        if end>len(data):
            return 'truncated'
        key=int.from_bytes(data[cursor:end],'little');cursor=end
        if previous is not None and key<=previous:
            return 'noncanonical'
        previous=key;row=[key]
        for _ in range(11):
            x=read()
            if isinstance(x,str):
                return x
            row.append(x)
        services.append(tuple(row))
    return (epochs[0],epochs[1],cores,services),cursor


# Logical scalar observations preserve every field and count without reusing native encoder answers.
def observe(source,consumed):
    return str(consumed)+''.join(' '+str(len(rows))+':'+(','.join(str(x) for row in rows for x in row) or '-') for rows in source)


# Failures have reasons alone; complete prefix success has field values and exact consumed extent.
def decode(data,config):
    result=parse(data,config)
    return result if isinstance(result,str) else observe(*result)


# Verify exact promised Git objects at the existing vector pin before consuming any upstream data.
def blob(path):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']
    raw=subprocess.check_output(['git','-C',str(ROOT/pins['path']),'show',pins['commit']+':'+path])
    assert hashlib.sha256(raw).hexdigest()==pins['git_blobs'][path]
    return json.loads(raw)


# STF statistics JSON has only validator arrays; zero cores/empty services are explicit authored completion.
def published_validators():
    result=[];fields=('blocks','tickets','pre_images','pre_images_size','guarantees','assurances')
    # Both profiles/phases include a full-profile current population resized from 1023 to six validators.
    for chain in ('tiny','full'):
        for name in ('stats_with_some_extrinsic-1','stats_epoch_change_with_set_resize-1'):
            d=blob(f'stf/statistics/{chain}/{name}.json')
            for phase in ('pre_state','post_state'):
                arrays=[]
                for key in ('vals_curr_stats','vals_last_stats'):
                    assert all(set(row)==set(fields) for row in d[phase][key])
                    arrays.append([tuple(row[x] for x in fields) for row in d[phase][key]])
                cores=2 if chain=='tiny' else 341
                result.append(((*arrays,[(0,)*8]*cores,[]),(cores,len(arrays[0]),len(arrays[1]),MAX,MAX)))
    return result


# Exact raw trace keyvals retain the migrated E4 service-key schema.
def published_wires():
    result=[]
    # Raw bytes remain unchanged; complete consumption and trailing bytes are recorded separately.
    for n in (1,2,3):
        d=blob(f'traces/fuzzy/{n:08}.json')
        for phase in ('pre_state','post_state'):
            values=[bytes.fromhex(x['value'][2:]) for x in d[phase]['keyvals'] if x['key']=='0x'+chapter_key(13).hex()]
            assert len(values)==1
            data=values[0];parsed=parse(data,DEFAULT)
            assert not isinstance(parsed,str),parsed
            source,consumed=parsed
            assert wire(source)==data[:consumed]
            result.append((source,data,consumed))
    return result


# Retain exact trace extent and independent E4-key reconstruction evidence after the migration.
def trace_evidence():
    result=[]
    # Independent E4-key reconstruction must reproduce the entire raw component, not a shorter prefix.
    for source,data,consumed in published_wires():
        current,previous,cores,_=source
        cursor=len(wire((current,previous,cores,[])))-1
        count,size=map(int,reference_decode(data[cursor:]).split());cursor+=size
        pairs=[]
        for _ in range(count):
            key=int.from_bytes(data[cursor:cursor+4],'little');cursor+=4;row=[key]
            for _ in range(11):
                value,size=map(int,reference_decode(data[cursor:]).split());cursor+=size;row.append(value)
            pairs.append(tuple(row))
        assert cursor==len(data)
        fixed_wire=wire((current,previous,cores,[]))[:-1]+natural(count)+b''.join(row[0].to_bytes(4,'little')+b''.join(natural(x) for x in row[1:]) for row in pairs)
        assert fixed_wire==data
        result.append(dict(bytes=len(data),consumed=consumed,trailing_bytes=len(data)-consumed,
            complete_component_match=consumed==len(data),diagnostic_e4_key_match=True,
            sha256=hashlib.sha256(data).hexdigest()))
    return result


# Author compact independent sources whose individual field values are visibly different.
def example(current=6,previous=6,cores=2,services=2):
    return ([tuple(i*6+j for j in range(6)) for i in range(current)],
        [tuple(100+i*6+j for j in range(6)) for i in range(previous)],
        [tuple(200+i*8+j for j in range(8)) for i in range(cores)],
        [tuple([255+i,*range(300+i*11,311+i*11)]) for i in range(services)])


# Build deterministic success, hostile framing, policy, shape, mutation and partial-root comparisons.
def requests():
    lines=[];expected=[];rng=random.Random(0x53544154533133)
    # Decimal arrays construct source fields independently of the production wire decoder.
    def enc(source,config=DEFAULT,op='V'):
        tokens=[','.join(str(x) for row in rows for x in row) or '-' for rows in source]
        lines.append(op+' '+' '.join(map(str,config))+' '+' '.join(tokens))
        expected.append(encode(source,config) if op=='V' else tree([(chapter_key(13),wire(source))])[0].hex())
    # Raw decoder requests include impossible announcements without allocating corresponding sources.
    def dec(data,config=DEFAULT):
        lines.append('D '+' '.join(map(str,config))+' '+token(data));expected.append(decode(data,config))
    base=example();raw=wire(base);enc(base);dec(raw);dec(raw+b'suffix');enc(base,op='R')
    # Every proper truncation crosses both epoch arrays, all cores and the complete last service tuple.
    for cut in range(len(raw)):
        dec(raw[:cut])
    # Every validator field is exercised at E4 boundaries independently of naturally encoded core/service fields.
    for slot in range(6):
        for value in (0,127,128,255,256,65535,65536,2**24,2**32-1):
            source=example();source[0][0]=tuple(value if j==slot else 0 for j in range(6));source[1][-1]=source[0][0]
            enc(source);dec(wire(source))
    # All core/service tuple positions separately cross canonical natural width boundaries and full uint64 gas.
    for group,width in ((2,8),(3,12)):
        for slot in range(0 if group==2 else 1,width):
            for value in sorted({0,1,127,128,255,256,2**32,MAX,*[2**i-1 for i in range(7,57,7)],*[2**i for i in range(7,57,7)],*[2**i+1 for i in range(7,57,7)]}):
                source=example();row=list(source[group][-1]);row[slot]=value;source[group][-1]=tuple(row)
                enc(source);dec(wire(source))
    # Fixed core shapes and separate allowed roster populations include natural count-prefix boundaries.
    for cores,current,previous in ((2,6,6),(3,6,9),(43,126,129),(86,255,258),(341,1023,6),(341,6,1023)):
        source=example(current,previous,cores,0);config=(cores,current,previous,0,MAX);data=wire(source)
        enc(source,config);dec(data,config);enc(source,config,op='R')
        for c in ((cores,current,previous,0,len(data)),(cores,current,previous,0,len(data)-1)):
            enc(source,c);dec(data,c)
    # Wrong source array shapes and wrong announced populations do not infer/change the supplied roster domain.
    for group in range(3):
        for delta in (-1,1):
            source=example();source[group][:]=source[group][:len(source[group])+delta] if delta<0 else source[group]+[source[group][0]]
            enc(source);dec(wire(source))
    # Invalid profiles reject before source or input access, including either malformed roster population.
    for config in ((0,6,6,MAX,MAX),(1,6,6,MAX,MAX),(342,6,6,MAX,MAX),(MAX,6,6,MAX,MAX),
                   (2,0,6,MAX,MAX),(2,5,6,MAX,MAX),(2,7,6,MAX,MAX),(2,6,9,MAX,MAX),(2,6,MAX,MAX,MAX)):
        enc(base,config);dec(b'',config)
    # Parent-byte and service-count ceilings include late fields and even the empty dictionary count.
    for budget in (0,1,144,145,146,289,290,len(raw)-1,len(raw),len(raw)+1):
        config=(2,6,6,MAX,budget);enc(base,config);dec(raw,config)
    for n in (0,1,2,127,128,129,255,256):
        source=example(services=n);data=wire(source)
        for limit in (max(0,n-1),n):
            config=(2,6,6,limit,len(data));enc(source,config);dec(data,config)
    # Numeric key ordering can disagree with encoded-byte ordering; duplicates/descending late IDs reject unchanged.
    for keys in ((255,256),(256,255),(1,1),(128,127),(0,2,1),(0,2**32-1)):
        source=example(services=len(keys));source[3][:]=[tuple([key,*row[1:]]) for key,row in zip(keys,source[3])]
        enc(source);dec(wire(source))
    epochs=wire(example(services=0))[:290];prefix=epochs+bytes(16)
    # Missing/overlong/huge count encodings at both epochs and the service dictionary reject safely.
    malformed=(b'',b'\x80',b'\xff',b'\x80\0',b'\xff'+bytes(8),natural(MAX),natural(2**60))
    for bad in malformed:
        dec(bad);dec(epochs[:145]+bad);dec(prefix+bad)
    # Natural core scalars and mixed fixed-key/service payloads receive malformed byte probes, including late gas.
    for slot in range(16):
        for bad in malformed[:5]:
            dec(epochs+bytes(slot)+bad)
    for slot in range(12):
        for bad in malformed[:5]:
            dec(prefix+b'\1'+bytes(slot)+bad)
    for key in (2**32,2**56,MAX):
        dec(prefix+b'\1'+natural(key)+bytes(11))
    # Deterministic valid fields, single-byte mutations and arbitrary raw inputs exercise value and error observations.
    for _ in range(150):
        source=example(services=rng.randrange(8))
        for group in (0,1):
            source[group][:]=[tuple(rng.getrandbits(32) for _ in range(6)) for _ in source[group]]
        source[2][:]=[tuple(rng.getrandbits(64) for _ in range(8)) for _ in source[2]]
        keys=sorted(rng.sample(range(2**32),len(source[3])))
        source[3][:]=[tuple([key,*(rng.getrandbits(64) for _ in range(11))]) for key in keys]
        data=wire(source);enc(source);dec(data)
        changed=bytearray(data);changed[rng.randrange(len(changed))]^=rng.randrange(1,256)
        dec(bytes(changed));dec(rng.randbytes(rng.randrange(500)))
    # Published validator fields are unchanged; only absent component families receive explicit authored completion.
    for source,config in published_validators():
        enc(source,config);dec(wire(source),config)
    # Exact raw traces now decode and reconstruct completely with migrated E4 keys; gas policy stays gated.
    for source,data,consumed in published_wires():
        dec(data)
        if consumed==len(data):
            enc(source);enc(source,op='R') # Every complete entry is retained without fixture repair; gas policy remains explicitly gated.
    # Wide service IDs cover every fixed-key octet boundary without changing natural gas/measure fields.
    for key in (0,1,127,128,255,256,65535,65536,2**24-1,2**24,2**32-1):
        source=example(services=1);source[3][:]=[(key,*source[3][0][1:])]
        enc(source);dec(wire(source))
    # Additional unchanged raw statistics values include nonzero wide IDs independently bound to metadata keys.
    from state_widths_oracle import trace_values
    for _,data,_ in trace_values():
        source,consumed=parse(data,DEFAULT)
        assert consumed==len(data) and wire(source)==data
        dec(data);enc(source)
    return lines,expected
