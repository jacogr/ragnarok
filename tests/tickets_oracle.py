# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 tickets wire oracle and deterministic boundary/malformed corpus.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import hashlib
import json
import random
from test_codec import reference_encode as natural, reference_decode
from test_support import ROOT


# Render empty trusted-adapter fields without dropping a whitespace token.
def token(data):
    return data.hex() or '-'


# Build one owned opaque proof directly, separate from the production codec.
def record(attempt, salt=0):
    return bytes([attempt])+bytes((i+salt)%251 for i in range(784))


# The attempt is E1; only the outer record count uses general natural encoding.
def wire(records):
    return natural(len(records))+b''.join(records)


# Model framing and policy with arbitrary-precision lengths; never invoke the native codec.
def decode(data, limit, capacity):
    parsed=reference_decode(data)
    # Canonical/truncated prefix failures precede any count or capacity decision.
    if parsed in ('truncated','noncanonical'):
        return parsed
    count,prefix=map(int,parsed.split())
    # Policy precedes a missing payload, which precedes insufficient typed output.
    if count>limit:
        return 'limitexceeded'
    if count>(len(data)-prefix)//785:
        return 'truncated'
    if count>capacity:
        return 'outputtoosmall'
    consumed=prefix+785*count
    return f'{count} {token(data[prefix:consumed])} {consumed}'


# Construct expected bytes or a failure without allowing partial output to masquerade as success.
def encode(records, limit, capacity):
    # Caller count policy is independent of the host's supplied byte capacity.
    if len(records)>limit:
        return 'limitexceeded'
    result=wire(records)
    return result.hex() if len(result)<=capacity else 'outputtoosmall'


# Published fixture fields must independently reproduce their hash-pinned binary representation.
def published(chain):
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    folder=ROOT/f'vendor/jamtestvectors/codec/{chain}'
    # Both representations are immutable upstream evidence, rather than generated peer output.
    for extension in ('json','bin'):
        path=folder/f'tickets_extrinsic.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    values=json.loads((folder/'tickets_extrinsic.json').read_text())
    records=[bytes([value['attempt']])+bytes.fromhex(value['signature'][2:]) for value in values]
    assert wire(records)==(folder/'tickets_extrinsic.bin').read_bytes()
    return records


# Pair each request with independently derived semantics before executing the production codec.
def requests():
    lines,expected=[],[]
    # Keep decoder inputs and explicit typed capacities separate in the request protocol.
    def add_decode(data,limit=16,capacity=16):
        lines.append(f'D {limit} {capacity} {token(data)}')
        expected.append(decode(data,limit,capacity))
    # Encoder construction uses fixed-field records, not a production-decoded structure.
    def add_encode(records,limit,capacity):
        lines.append(f'E {limit} {capacity} {token(b"".join(records))}')
        expected.append(encode(records,limit,capacity))
    cases=[published('tiny'),published('full'),[],[record(128)],[record(255)],
           [record(i%256,i) for i in range(16)], [record(i,i) for i in range(128)]]
    # Every representative fixture covers prefixes, count policy, exact capacities and appended unrelated data.
    for records in cases:
        data=wire(records);limit=max(16,len(records))
        for capacity in sorted(set((0,max(0,len(records)-1),len(records),len(records)+1))):
            add_decode(data,limit,capacity)
        add_decode(data+b'\xaa\xbb',limit,len(records))
        for capacity in sorted(set((0,len(data)-1,len(data),len(data)+1))):
            add_encode(records,limit,capacity)
        # Exhaust all small truncations; large count-boundary frames use fixed and last-byte cuts.
        cuts=range(len(data)) if len(data)<15000 else (0,1,2,784,785,len(data)-1)
        for cut in cuts:
            add_decode(data[:cut],limit,len(records))
        if records:
            # An excessive count must fail before either missing bytes or small destinations.
            add_decode(data,len(records)-1,0)
            add_encode(records,len(records)-1,0)
    # Every possible attempt octet must occupy one unchanged byte, including 128..255.
    for attempt in range(256):
        records=[record(attempt,attempt)];data=wire(records)
        add_decode(data,1,1);add_encode(records,1,len(data))
    # Malformed natural prefixes and huge announced counts cannot trigger input-derived allocation.
    for data in (b'',b'\x80\x00',b'\xff'+bytes(7),natural(2**64-1),natural(17)):
        add_decode(data)
    rng=random.Random(0x5449434b4554)
    # Mutations cover full proofs and complete/truncated count prefixes; opaque proof mutations remain valid.
    for i in range(2500):
        data=bytearray(wire([record(i%256)]))
        for _ in range(rng.randrange(1,5)):
            data[rng.randrange(len(data))]=rng.randrange(256)
        if i%3==0:
            data=data[:rng.randrange(len(data)+1)]
        add_decode(bytes(data),16,rng.randrange(3))
    # Arbitrary bytes check rejection independently of valid-frame mutation.
    for _ in range(1000):
        add_decode(rng.randbytes(rng.randrange(1800)),16,rng.randrange(3))
    return lines,expected
