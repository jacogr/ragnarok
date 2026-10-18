# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 guarantee construction, nested parsing and deterministic adversarial corpus.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import copy
import hashlib
import json
import random
from test_support import ROOT
from test_codec import reference_encode as natural, reference_decode
from report_oracle import from_json, encode as report_wire, decode as report_decode, corpus
from assurances_oracle import config_error

ERRORS={'truncated','noncanonical','limitexceeded','invalidtag'}


# Render empty wire fields without losing a token in the trusted adapter protocol.
def token(data):
    return data.hex() or '-'


# Serialize all named source fields directly, including values intentionally rejected by protocol preflight.
def wire(records):
    return natural(len(records))+b''.join(value['report']+value['slot'].to_bytes(4,'little')
        +natural(len(value['credentials']))+b''.join(index.to_bytes(2,'little')+signature
        for index,signature in value['credentials']) for value in records)


# Describe source fields independently from the production guarantees decoder.
def fields(records):
    parts=[str(len(records))]
    # Reports are already independently verified child-codec bytes; wrapper fields stay individually visible.
    for value in records:
        parts.extend((token(value['report']),str(value['slot']),str(len(value['credentials']))))
        for index,signature in value['credentials']:
            parts.extend((str(index),token(signature)))
    return ' '.join(parts)


# Convert explicit typed-source policy to its own expected failure without mutating a destination.
def encode(records, cores, validators, budget, capacity):
    error=config_error(cores,validators)
    # Invalid caller domains precede count or owner inspection.
    if error:
        return error
    if len(records)>cores:
        return 'limitexceeded'
    required=len(natural(len(records)));previous=None
    # Check the final source record before judging output capacity, matching whole-source preflight.
    for value in records:
        report=report_decode(value['report'],341)
        if report in ERRORS:
            return 'invalidreport'
        parts=report.split();core=int(parts[2])
        shards=int.from_bytes(value['report'][68:70],'little')
        if core>=cores or shards//3>cores:
            return 'limitexceeded'
        if previous is not None and core<=previous:
            return 'noncanonical'
        previous=core
        credentials=value['credentials']
        if len(credentials) not in (2,3):
            return 'invalidcredential'
        last=None
        for index,_ in credentials:
            if index>=validators:
                return 'invalidvalidator'
            if last is not None and index<=last:
                return 'noncanonical'
            last=index
        required+=len(value['report'])+5+66*len(credentials)
        if required>budget:
            return 'limitexceeded'
    if required>budget:
        return 'limitexceeded'
    return wire(records).hex() if required<=capacity else 'outputtoosmall'


# Internal failure carries only a typed reason while arbitrary-precision cursors stay private.
class Rejected(Exception):
    pass


# Independently parse the wrapper and its child reports, preserving prefix consumption and failure precedence.
def decode(data, cores, validators, budget):
    error=config_error(cores,validators)
    # Configuration determines all subsequent count/index domains.
    if error:
        return error
    cursor=0
    # Canonical counts advance only after complete natural parsing, followed by frame-budget enforcement.
    def number():
        nonlocal cursor
        result=reference_decode(data[cursor:])
        if result in ('truncated','noncanonical'):
            raise Rejected(result)
        value,length=map(int,result.split());cursor+=length
        if cursor>budget:
            raise Rejected('limitexceeded')
        return value
    try:
        count=number()
        if count>cores:
            raise Rejected('limitexceeded')
        records=[];previous=None
        # Every record is fully checked before any result or partial record list can be returned.
        for _ in range(count):
            report=report_decode(data[cursor:],cores)
            if report in ERRORS:
                raise Rejected(report)
            parts=report.split();length=int(parts[-1]);core=int(parts[2])
            if previous is not None and core<=previous:
                raise Rejected('noncanonical')
            previous=core
            report_bytes=data[cursor:cursor+length];cursor+=length
            if cursor>budget:
                raise Rejected('limitexceeded')
            if len(data)-cursor<4:
                raise Rejected('truncated')
            slot=int.from_bytes(data[cursor:cursor+4],'little');cursor+=4
            credentials=number()
            if credentials not in (2,3):
                raise Rejected('invalidcredential')
            if credentials>(len(data)-cursor)//66:
                raise Rejected('truncated')
            if cursor+66*credentials>budget:
                raise Rejected('limitexceeded')
            values=[];last=None
            # E2 identity order is checked before copying an opaque signature into a successful result.
            for _ in range(credentials):
                index=int.from_bytes(data[cursor:cursor+2],'little')
                if index>=validators:
                    raise Rejected('invalidvalidator')
                if last is not None and index<=last:
                    raise Rejected('noncanonical')
                last=index
                values.append((index,data[cursor+2:cursor+66]));cursor+=66
            records.append(dict(report=report_bytes,slot=slot,credentials=values))
        return f'{count} {cursor} '+fields(records)
    except Rejected as failure:
        # Rejection discards the private cursor and every partially collected record.
        return str(failure)


# Published JSON and binary evidence is accepted only at the exact pinned release hashes.
def published(chain):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    folder=ROOT/f'vendor/jamtestvectors/codec/{chain}'
    # Both byte and field representations retain immutable source identities.
    for extension in ('json','bin'):
        path=folder/f'guarantees_extrinsic.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    items=json.loads((folder/'guarantees_extrinsic.json').read_text())
    result=[dict(report=report_wire(from_json(item['report'])),slot=item['slot'],
        credentials=[(entry['validator_index'],bytes.fromhex(entry['signature'][2:])) for entry in item['signatures']]) for item in items]
    assert wire(result)==(folder/'guarantees_extrinsic.bin').read_bytes()
    return result


# Construct a report with an independently encoded core and distinctive fixed credentials.
def record(core, credential_count=2):
    report=copy.deepcopy(corpus()[1][1]);report['core']=core
    return dict(report=report_wire(report),slot=2**32-1,
        credentials=[(i,bytes([17+i])*64) for i in range(credential_count)])


# Pair valid, malformed and boundary requests with expectations before the native implementation runs.
def requests():
    lines,expected=[],[]
    # Decode budgets bound retained bytes rather than unrelated trailing input.
    def add_decode(data,cores=341,validators=1023,budget=4*1024*1024):
        lines.append(f'D {cores} {validators} {budget} {token(data)}')
        expected.append(decode(data,cores,validators,budget))
    # All source fields are explicit, so construction never depends on the guarantees decoder.
    def add_encode(values,cores=341,validators=1023,budget=4*1024*1024,capacity=4*1024*1024):
        lines.append(f'E {cores} {validators} {budget} {capacity} '+fields(values))
        expected.append(encode(values,cores,validators,budget,capacity))
    examples=[published('tiny'),published('full'),[],[record(0)],
        [record(0,3),record(1)], [record(340,3)]]
    # Published and authored small frames exhaust all truncations and output extent boundaries.
    for values in examples:
        data=wire(values)
        for suffix in (b'',b'\xaa\xbb'):
            add_decode(data+suffix,budget=len(data))
        for capacity in sorted(set((0,len(data)-1,len(data),len(data)+5))):
            add_encode(values,capacity=capacity)
        for cut in range(len(data)):
            add_decode(data[:cut])
        for budget in (0,len(data)-1,len(data)):
            add_decode(data,budget=budget);add_encode(values,budget=budget)
    # The full configured core population and the next count exercise bounded scan/allocation behavior.
    values=[record(i) for i in range(341)];data=wire(values)
    add_decode(data);add_encode(values,capacity=len(data));add_decode(natural(342))
    # High validator identities are fixed E2, including values that need longer general-natural encodings.
    for validators in (6,9,1023):
        values=[record(0,3)];values[0]['credentials']=[(0,bytes(64)),(1,bytes([1])*64),(validators-1,bytes([2])*64)]
        add_decode(wire(values),validators=validators);add_encode(values,validators=validators)
    # Late invalid source fields must leave all output unchanged, despite earlier complete records.
    for kind in ('credential-zero','credential-one','credential-four','duplicate-index','descending-index','invalid-index','duplicate-core','descending-core'):
        values=[record(0),record(1)]
        if kind.startswith('credential'):
            count={'credential-zero':0,'credential-one':1,'credential-four':4}[kind]
            values[-1]['credentials']=[(i,bytes([i])*64) for i in range(count)]
        elif kind=='duplicate-index':
            values[-1]['credentials']=[(1,bytes(64)),(1,bytes(64))]
        elif kind=='descending-index':
            values[-1]['credentials']=[(2,bytes(64)),(1,bytes(64))]
        elif kind=='invalid-index':
            values[-1]['credentials']=[(0,bytes(64)),(1023,bytes(64))]
        elif kind=='duplicate-core':
            values[-1]['report']=values[0]['report']
        else:
            values.reverse() # Descending core order remains explicitly supplied by the caller.
        add_decode(wire(values));add_encode(values)
    small=[record(0)];data=wire(small);report_length=len(small[0]['report'])
    # Corrupt outer/credential natural prefixes separately from nested report parsing.
    for prefix in (b'\x80\x00',natural(2**64-1)):
        add_decode(prefix+data[1:])
        at=1+report_length+4;add_decode(data[:at]+prefix+data[at+1:])
    for core,validators in ((0,6),(1,6),(342,6),(2,0),(2,5),(2,7),(2,9),(341,1022),(2**64-1,6)):
        add_decode(b'',core,validators);add_encode([],core,validators)
    rng=random.Random(0x47554152414e5445)
    # Structured changes reach late reports, core order, timeslots, credential counts and opaque signatures.
    base=wire([record(0,3),record(1)])
    for i in range(3000):
        data=bytearray(base)
        for _ in range(rng.randrange(1,5)):
            data[rng.randrange(len(data))]=rng.randrange(256)
        if i%3==0:
            data=data[:rng.randrange(len(data)+1)]
        add_decode(bytes(data))
    # Random buffers check rejection without relying on native-generated seed frames.
    for _ in range(1000):
        add_decode(rng.randbytes(rng.randrange(2000)))
    return lines,expected
