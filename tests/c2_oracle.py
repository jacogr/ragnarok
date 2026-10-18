# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 availability, deferred-transfer and accumulation-operand equations and hostile corpus."""
import hashlib
import json
import random
from test_codec import reference_encode as natural, reference_decode
from test_support import ROOT

MAX=2**64-1
BROAD=(341,MAX,MAX,MAX,MAX)  # cores, result bytes, trace bytes, aggregate payload, complete wire


# Empty blob transport remains a single token without inventing a protocol octet.
def token(data):
    return data.hex() or '-'


# Fixed field fixtures use distinct identities, making role swaps visible independently of round trips.
def example(kind,gas=128,tag=0,payload=b'abc',trace=b'de'):
    # Availability is one fixed tuple, distinct from the following report context.
    if kind=='A':
        return (bytes([1])*32,2**32-1,bytes([2])*32,1023,bytes([3])*32,65535)
    # A memo has exactly 128 bytes and no natural length prefix; transfer gas is E8.
    if kind=='T':
        return (2**32-1,17,MAX,bytes(range(128)),gas)
    return (bytes([1])*32,bytes([2])*32,bytes([3])*32,bytes([4])*32,gas,tag,payload if tag==0 else b'',trace)


# Literal C.2 construction uses independent fixed-width arithmetic and canonical-natural reference equations.
def wire(kind,value):
    # Availability width is 32+4+32+2+32+2 = 104 octets.
    if kind=='A':
        package,length,erasure,shards,segment,count=value
        return package+length.to_bytes(4,'little')+erasure+shards.to_bytes(2,'little')+segment+count.to_bytes(2,'little')
    # The transfer's outer discriminator is part of its standalone encoding, not a separate union prefix.
    if kind=='T':
        source,dest,amount,memo,gas=value
        return b'\1'+source.to_bytes(4,'little')+dest.to_bytes(4,'little')+amount.to_bytes(8,'little')+memo+gas.to_bytes(8,'little')
    package,segment,authorizer,payload_hash,gas,tag,payload,trace=value
    work=natural(tag)+(natural(len(payload))+payload if tag==0 else b'')
    return b'\0'+package+segment+authorizer+payload_hash+natural(gas)+work+natural(len(trace))+trace


# Preserve every fixed field and logical payload separately, without observing through the native codec.
def fields(kind,value):
    return ' '.join(token(v) if isinstance(v,bytes) else str(v) for v in value)


# Expected failures contain no partial metadata, payload or input-progress cursor.
class Rejected(Exception):
    pass


# Independent natural parsing never advances a caller-visible cursor after incomplete or overlong input.
def read_natural(data,cursor):
    parsed=reference_decode(data[cursor:])
    # Primitive framing failures precede field semantics and resource policy.
    if parsed in ('truncated','noncanonical'):
        raise Rejected(parsed)
    value,size=map(int,parsed.split())
    return value,cursor+size


# Complete fixed field extent is proved before any integer conversion or copied-field observation.
def fixed(data,cursor,width):
    # No missing bytes may be silently padded into a complete application record.
    if width>len(data)-cursor:
        raise Rejected('truncated')
    return data[cursor:cursor+width],cursor+width


# Independent variable bytes apply payload policy before requiring the announced payload to exist.
def blob(data,cursor,limit):
    length,cursor=read_natural(data,cursor)
    # Resource limits protect traversal/allocation even when only a hostile length prefix is supplied.
    if length>limit:
        raise Rejected('limitexceeded')
    return fixed(data,cursor,length)


# Serialized budgets count the entire record prefix, separately from any individual/aggregate payload policy.
def budget(cursor,maximum):
    # Complete child extent must fit before another child or parent owner is accepted.
    if cursor>maximum:
        raise Rejected('limitexceeded')


# Validate availability configuration and GP valcount without asserting active-set equality or erasure-root correctness.
def availability_policy(value,config):
    cores,_,_,_,maximum=config
    # Invalid core configuration precedes even missing input or malformed record fields.
    if not 2<=cores<=341:
        raise Rejected('invalidconfig')
    shards=value[3]
    # Cardinality is a multiple of three from six through the configured core ceiling times three.
    if not 6<=shards<=3*cores or shards%3:
        raise Rejected('limitexceeded')
    budget(104,maximum)


# Independent complete-record parser exposes named fields only after the final byte/count/policy succeeds.
def parse(kind,data,config):
    cores,out_limit,auth_limit,total,maximum=config
    # Availability has no accumulation tag and starts directly with its fixed package identity.
    if kind=='A':
        # Config failure is intentionally earlier than missing input for this standalone caller domain.
        if not 2<=cores<=341:
            raise Rejected('invalidconfig')
        raw,_=fixed(data,0,104)
        value=(raw[:32],int.from_bytes(raw[32:36],'little'),raw[36:68],int.from_bytes(raw[68:70],'little'),
               raw[70:102],int.from_bytes(raw[102:104],'little'))
        availability_policy(value,config)
        return kind,104,value
    tag,cursor=read_natural(data,0)
    # The accumulation union selects the standalone schema, adding no new wrapper discriminator.
    if kind=='I':
        # Unknown tags cannot choose either valid alternative or expose any fields.
        if tag not in (0,1):
            raise Rejected('invalidtag')
        selected='O' if tag==0 else 'T'
        actual,consumed,value=parse(selected,data,config)
        return actual,consumed,value
    # Standalone transfer/operand decoders reject the other valid union tag too.
    if tag != (1 if kind=='T' else 0):
        raise Rejected('invalidtag')
    # Transfers require their entire fixed body before whole-wire policy and field observation.
    if kind=='T':
        raw,cursor=fixed(data,cursor,152)
        budget(cursor,maximum)
        return kind,cursor,(int.from_bytes(raw[:4],'little'),int.from_bytes(raw[4:8],'little'),
            int.from_bytes(raw[8:16],'little'),raw[16:144],int.from_bytes(raw[144:152],'little'))
    hashes,cursor=fixed(data,cursor,128);budget(cursor,maximum)
    gas,cursor=read_natural(data,cursor);budget(cursor,maximum)
    work,cursor=read_natural(data,cursor)
    # Work tags 0..6 are exact protocol alternatives, not arbitrary truthy/error values.
    if work>6:
        raise Rejected('invalidtag')
    payload=b''
    # Only a successful work result has a variable-length payload and consumes aggregate payload budget.
    if work==0:
        payload,cursor=blob(data,cursor,min(out_limit,total))
        total-=len(payload)
    budget(cursor,maximum)
    trace,cursor=blob(data,cursor,min(auth_limit,total));budget(cursor,maximum)
    return kind,cursor,(hashes[:32],hashes[32:64],hashes[64:96],hashes[96:128],gas,work,payload,trace)


# Native observations compare logical field identities and cursor extent, not a same-codec round trip.
def decode(kind,data,config=BROAD):
    try:
        actual,consumed,value=parse(kind,data,config)
        prefix=(str(0 if actual=='O' else 1)+' ') if kind=='I' else ''
        return prefix+str(consumed)+' '+fields(actual,value)+((' '+token(wire('O',value))) if actual=='O' else '')
    except Rejected as error:
        # A failed final field discards every earlier value and cursor.
        return str(error)


# Encoder preflight derives sizes from independent logical sources before destination capacity or mutation.
def encode(kind,value,config,capacity):
    try:
        _,out_limit,auth_limit,total,maximum=config
        # Union encoder alternatives share the exact standalone source fields and wire bytes.
        actual=kind.removeprefix('U')
        if actual=='A':
            availability_policy(value,config)
        elif actual=='T':
            # Transfer payloads do not consume any operand-only blob ceilings.
            budget(153,maximum)
        else:
            # Operand gas is natural; each complete framing piece contributes to the same serialized budget.
            cursor=129;budget(cursor,maximum)
            cursor+=len(natural(value[4]));budget(cursor,maximum)
            tag,payload,trace=value[5:]
            # Individual and aggregate result limits precede work byte-size/capacity decisions.
            if tag==0:
                if len(payload)>min(out_limit,total):
                    raise Rejected('limitexceeded')
                total-=len(payload)
                cursor+=1+len(natural(len(payload)));budget(cursor,maximum)
                cursor+=len(payload);budget(cursor,maximum)
            else:
                # Work errors contain their tag alone, with no default payload length/pool.
                cursor+=1;budget(cursor,maximum)
            # The final trace policy must pass before an earlier hash is ever committed.
            if len(trace)>min(auth_limit,total):
                raise Rejected('limitexceeded')
            cursor+=len(natural(len(trace)));budget(cursor,maximum)
            cursor+=len(trace);budget(cursor,maximum)
        raw=wire(actual,value)
        # Only valid complete sources proceed to output capacity.
        if len(raw)>capacity:
            raise Rejected('outputtoosmall')
        return token(raw)
    except Rejected as error:
        # Source/policy/capacity failures contain no partial write count.
        return str(error)


# Every authored and derived case has explicit independent expected bytes/fields/failures before native execution.
def requests():
    lines,expected=[],[]

    # Decoding treats raw bytes as untrusted while chain/resource domains remain explicit trusted caller input.
    def dec(kind,data,config=BROAD):
        lines.append(' '.join(['D',kind]+[str(v) for v in config]+[token(data)]));expected.append(decode(kind,data,config))

    # Encoder source fields are independently named logical values, never supplied by a production decoder.
    def enc(kind,value,config=BROAD,capacity=None):
        capacity=len(wire(kind.removeprefix('U'),value))+3 if capacity is None else capacity
        lines.append(' '.join(['E',kind]+[str(v) for v in config]+[str(capacity),fields(kind,value)]))
        expected.append(encode(kind,value,config,capacity))

    examples=[('A',example('A')),('T',example('T'))]
    # Every work-result alternative is a valid operand value, including empty success and error traces.
    for tag in range(7):
        examples.append(('O',example('O',tag=tag)))
        examples.append(('O',example('O',tag=tag,payload=b'',trace=b'')))
    # General-natural gas transitions differ from the transfer's always-eight-byte gas field.
    for gas in [0,1,127,128,255,256]+[2**k+d for k in (14,21,28,35,42,49,56,63) for d in (-1,0,1)]+[MAX]:
        examples.append(('O',example('O',gas=gas)))
        examples.append(('T',example('T',gas=gas)))
    # Both independent variable blob counts exercise length-prefix transitions and distinct byte patterns.
    for length in (0,1,7,127,128,129,16383,16384):
        payload=bytes(i%251 for i in range(length))
        examples.append(('O',example('O',payload=payload,trace=b'xyz')))
        examples.append(('O',example('O',payload=b'xyz',trace=payload)))
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Availability fixtures are actual complete report prefixes; operand counterparts are explicitly derived, not upstream wire vectors.
    for profile,cores in (('tiny',2),('full',341)):
        folder=ROOT/f'vendor/jamtestvectors/codec/{profile}'
        # Freeze each published JSON/binary identity before extracting any field or fixed prefix.
        for extension in ('json','bin'):
            path=folder/f'work_report.{extension}'
            assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
        report=json.loads((folder/'work_report.json').read_text());spec=report['package_spec']
        av=(bytes.fromhex(spec['hash'][2:]),spec['length'],bytes.fromhex(spec['erasure_root'][2:]),spec['erasure_shards'],
            bytes.fromhex(spec['exports_root'][2:]),spec['exports_count'])
        assert wire('A',av)==(folder/'work_report.bin').read_bytes()[:104]
        cfg=(cores,)+BROAD[1:]
        dec('A',(folder/'work_report.bin').read_bytes(),cfg);enc('A',av,cfg)
        # Derive accumulator operand fields by the pinned accumulation mapping, retaining opaque identities unchanged.
        for digest in report['results']:
            result=digest['result'];tag=0 if 'ok' in result else 2
            assert 'ok' in result or result=={'panic':None}
            payload=bytes.fromhex(result['ok'][2:]) if tag==0 else b''
            value=(av[0],av[4],bytes.fromhex(report['authorizer_hash'][2:]),bytes.fromhex(digest['payload_hash'][2:]),
                   digest['accumulate_gas'],tag,payload,bytes.fromhex(report['auth_output'][2:]))
            dec('O',wire('O',value));dec('I',wire('O',value));enc('O',value);enc('UO',value)
    # Complete source cases cover all boundaries, final-field policies and distinct standalone/union APIs.
    for kind,value in examples:
        data=wire(kind,value)
        dec(kind,data+b'\xAA');enc(kind,value)
        # Union wire is identical to the standalone operand or transfer representation.
        if kind!='A':
            dec('I',data);enc('U'+kind,value)
        # Every short representative prefix and sampled large blob boundary fails before successful parent capture.
        cuts=range(len(data)) if len(data)<400 else sorted(set(range(0,len(data),257))|{len(data)-1})
        for cut in cuts:
            dec(kind,data[:cut])
        # Whole capacity is distinct from resource policy and success preserves spare destination bytes.
        for capacity in (0,len(data)-1,len(data),len(data)+3):
            enc(kind,value,capacity=capacity)
            # The public union entry point must preserve standalone capacity/atomicity semantics too.
            if kind!='A':
                enc('U'+kind,value,capacity=capacity)
        # Every parent byte budget boundary has an independent consumed-prefix observation and source failure case.
        for maximum in (0,len(data)-1,len(data)):
            cfg=BROAD[:-1]+(maximum,);dec(kind,data,cfg);enc(kind,value,cfg,capacity=0)
            # Dispatch must retain the caller's complete-prefix budget for either selected alternative.
            if kind!='A':
                dec('I',data,cfg);enc('U'+kind,value,cfg,capacity=0)
        # Single/aggregate policies apply to operands only; transfers deliberately ignore these blob ceilings.
        for field in (1,2,3):
            cfg=list(BROAD);cfg[field]=0;cfg=tuple(cfg)
            dec(kind,data,cfg);enc(kind,value,cfg,capacity=0)
            # Union operand policies must not be bypassed, and transfer alternatives must ignore blob-only ceilings.
            if kind!='A':
                dec('I',data,cfg);enc('U'+kind,value,cfg,capacity=0)
    # Every GP shard-domain value and adjacent invalid counts, plus the E2 maximum, exercise the valcount predicate.
    for shards in [*range(0,1027),65535]:
        av=list(example('A'));av[3]=shards;av=tuple(av)
        for cores in (2,341):
            cfg=(cores,)+BROAD[1:]
            dec('A',wire('A',av),cfg);enc('A',av,cfg,capacity=0)
    # Invalid caller core domains precede even an absent availability frame or zero output.
    for cores in (0,1,342,MAX):
        cfg=(cores,)+BROAD[1:];dec('A',b'',cfg);enc('A',example('A'),cfg,capacity=0)
    # All unknown single-byte outer tags and overlong natural forms preserve schema/framing errors.
    for tag in range(2,256):
        for kind in ('O','T','I'):
            dec(kind,bytes([tag]))
    for tag in (b'\x80\0',b'\x80\1',b'\xff'+bytes(8),b'\xff'+bytes(7)):
        for kind in ('O','T','I'):
            dec(kind,tag)
    hashes=wire('O',example('O'))[:129]
    # Nested work tags are canonical naturals too, independently of the valid outer operand tag.
    for tag in range(7,256):
        dec('O',hashes+b'\0'+natural(tag));dec('I',hashes+b'\0'+natural(tag))
    # Natural framing failures at gas, work, result length and final trace length exercise late rejection paths.
    for bad in (b'\x80\0',b'\xff'+bytes(8),b'\xff'+bytes(7)):
        dec('O',hashes+bad)
        dec('O',hashes+b'\0'+bad)
        dec('O',hashes+b'\0\0'+bad)
        dec('O',hashes+b'\0\1'+bad)
    # Hostile announced blob lengths are bounded before any input-derived allocation or narrowing.
    for length in (2**32,2**56,MAX):
        for policy in (0,MAX):
            cfg=(341,policy,policy,policy,MAX)
            dec('O',hashes+b'\0\0'+natural(length),cfg)
            dec('O',hashes+b'\0\1'+natural(length),cfg)
    rng=random.Random(0x43325245433038)
    # Structured source mutations reach late operand/availability fields rather than only random invalid outer tags.
    for kind in ('A','T','O'):
        base=wire(kind,example(kind))
        for i in range(700):
            data=bytearray(base)
            # Multiple altered bytes combine plausible fixed fields with malformed scalar framing.
            for _ in range(rng.randrange(1,5)):
                data[rng.randrange(len(data))]=rng.randrange(256)
            if i%3==0:
                data=data[:rng.randrange(len(data)+1)] # Late truncations cannot expose earlier partial records.
            dec(kind,bytes(data))
    # Arbitrary streams must fail normally or produce a complete independently observed value under explicit limits.
    for _ in range(1200):
        data=rng.randbytes(rng.randrange(300))
        dec(rng.choice(('A','T','O','I')),data,(rng.choice((2,341)),8,8,12,rng.choice((0,128,300,MAX))))
    return lines,expected
