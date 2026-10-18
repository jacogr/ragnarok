# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 disputes construction, observation and adversarial corpus."""
import copy
import hashlib
import json
import random
from test_support import ROOT
from test_codec import reference_encode as natural, reference_decode


# Empty fields retain one token in the trusted native adapter protocol.
def token(data):
    return data.hex() or '-'


# Render named fields independently from both the production encoder and decoder.
def fields(value):
    parts=[str(len(value['verdicts']))]
    # Verdicts contain E4 epochs and separately counted variable judgments.
    for item in value['verdicts']:
        parts.extend((token(item['target']),str(item['age']),str(len(item['votes']))))
        # Every judgment gets an independent membership and ordering check.
        for vote in item['votes']:
            parts.extend((str(int(vote['vote'])),str(vote['index']),token(vote['signature'])))
    parts.append(str(len(value['culprits'])))
    # Culprits and faults each carry complete key/signature identities.
    for item in value['culprits']:
        parts.extend(token(item[k]) for k in ('target','key','signature'))
    parts.append(str(len(value['faults'])))
    # Fault observation includes the additional signed validity bit.
    for item in value['faults']:
        parts.extend((token(item['target']),str(int(item['vote'])),token(item['key']),token(item['signature'])))
    return ' '.join(parts)


# Encode literal C.2 fields without applying canonical ordering or state policy to the supplied values.
def wire(value):
    out=natural(len(value['verdicts']))
    # Fixed widths differ deliberately from compact natural count encodings.
    for item in value['verdicts']:
        out+=item['target']+item['age'].to_bytes(4,'little')+natural(len(item['votes']))
        out+=b''.join(bytes([int(v['vote'])])+v['index'].to_bytes(2,'little')+v['signature'] for v in item['votes'])
    out+=natural(len(value['culprits']))+b''.join(v['target']+v['key']+v['signature'] for v in value['culprits'])
    out+=natural(len(value['faults']))+b''.join(v['target']+bytes([int(v['vote'])])+v['key']+v['signature'] for v in value['faults'])
    return out


# The explicit ceiling covers current/previous validator populations without selecting either key set.
def config_error(validators):
    return None if 6<=validators<=1023 and validators%3==0 else 'invalidconfig'


# Predict source preflight errors independently of wire decoding or output writes.
def encode(value, validators, budget, capacity):
    error=config_error(validators)
    # Invalid caller domains take precedence over input access or source traversal.
    if error:
        return error
    # Bound every outer section before inspecting any record.
    if any(len(value[k])>16 for k in ('verdicts','culprits','faults')):
        return 'limitexceeded'
    previous=None
    # Every supplied judgment must satisfy its structural ceiling and strict numeric identity order.
    for item in value['verdicts']:
        # Verdict report identities must be strictly increasing and unique.
        if previous is not None and item['target']<=previous:
            return 'noncanonical'
        previous=item['target']
        # An unselected validator-set ceiling still bounds variable vote storage.
        if len(item['votes'])>validators:
            return 'limitexceeded'
        last=-1
        # Every judgment gets an independent membership and ordering check.
        for vote in item['votes']:
            # Fixed E2 representation does not establish membership in the supplied ceiling.
            if vote['index']>=validators:
                return 'invalidvalidator'
            # Duplicate and descending indices select the same canonicality failure.
            if vote['index']<=last:
                return 'noncanonical'
            last=vote['index']
    # Offender key order is independent in the two evidence sections.
    for kind in ('culprits','faults'):
        keys=[v['key'] for v in value[kind]]
        # Evidence uniqueness is checked by key within this section only.
        if any(a>=b for a,b in zip(keys,keys[1:])):
            return 'noncanonical'
    data=wire(value)
    # Source preflight must reject an over-budget frame before judging output capacity.
    if len(data)>budget:
        return 'limitexceeded'
    return data.hex() if len(data)<=capacity else 'outputtoosmall'


# Rejected inputs expose no partially collected records or progress.
class Rejected(Exception):
    pass


# Independent arbitrary-precision cursor parser with explicit error precedence.
def decode(data, validators, budget):
    error=config_error(validators)
    # Invalid caller domains take precedence over input access or source traversal.
    if error:
        return error
    cursor=0
    # Decode canonical counts and bound them before iteration or narrowing.
    def number(ceiling):
        nonlocal cursor
        parsed=reference_decode(data[cursor:])
        # Preserve canonical natural failures before inspecting a partial count.
        if parsed in ('truncated','noncanonical'):
            raise Rejected(parsed)
        count,length=map(int,parsed.split());cursor+=length
        # Prefix bytes and selected counts both need explicit resource bounds.
        if cursor>budget or count>ceiling:
            raise Rejected('limitexceeded')
        return count
    # Extents precede record interpretation, including section-wide culprit/fault tag checks.
    def extent(count,stride):
        # Division proves remaining input without an overflowing untrusted product.
        if count>(len(data)-cursor)//stride:
            raise Rejected('truncated')
        # An input-backed extent can still exceed the retained prefix budget.
        if cursor+count*stride>budget:
            raise Rejected('limitexceeded')
    # Take only previously extent-checked bytes into private oracle fields.
    def take(size):
        nonlocal cursor
        value=data[cursor:cursor+size];cursor+=size
        return value
    # Keep parser progress private until all three sections pass.
    try:
        value=dict(verdicts=[],culprits=[],faults=[]);previous=None
        # Verdict order precedes its count and judgment checks, as prescribed by the public contract.
        for _ in range(number(16)):
            extent(1,36);target=take(32);age=int.from_bytes(take(4),'little')
            # Ordering failure precedes parsing this verdict's judgment sequence.
            if previous is not None and target<=previous:
                raise Rejected('noncanonical')
            previous=target;count=number(validators);extent(count,67);votes=[];last=-1
            # Read only complete records whose enclosing section extent has already been proved.
            for _ in range(count):
                tag=take(1)[0];index=int.from_bytes(take(2),'little');signature=take(64)
                # Only canonical Boolean octets have a semantic validity value.
                if tag>1:
                    raise Rejected('invalidtag')
                # A decoded E2 judge needs the supplied structural validator domain.
                if index>=validators:
                    raise Rejected('invalidvalidator')
                # Strict identity order rejects both duplication and reversal.
                if index<=last:
                    raise Rejected('noncanonical')
                last=index;votes.append(dict(vote=bool(tag),index=index,signature=signature))
            value['verdicts'].append(dict(target=target,age=age,votes=votes))
        # Culprit/fault order is per-section and never compares keys across the section boundary.
        for kind,stride in (('culprits',128),('faults',129)):
            count=number(16);extent(count,stride);previous=None
            # Read only complete records whose enclosing section extent has already been proved.
            for _ in range(count):
                item=dict(target=take(32))
                # Only fault evidence includes a Boolean between report hash and key.
                if kind=='faults':
                    tag=take(1)[0]
                    # Reject an illegal fault tag before judging offender key order.
                    if tag>1:
                        raise Rejected('invalidtag')
                    item['vote']=bool(tag)
                key=take(32);signature=take(64)
                # This section must independently order offender identities.
                if previous is not None and key<=previous:
                    raise Rejected('noncanonical')
                previous=key;item.update(key=key,signature=signature);value[kind].append(item)
        return str(cursor)+' '+fields(value)
    except Rejected as failure:
        # A rejection discards every private partial record and cursor.
        return str(failure)


# Published JSON/binary sources are preserved, even where their logical ordering violates the GP.
def published(profile):
    folder=ROOT/f'vendor/jamtestvectors/codec/{profile}'
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Verify both representations at the pinned release before deriving a canonical authored counterpart.
    for suffix in ('json','bin'):
        path=folder/f'disputes_extrinsic.{suffix}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    value=json.loads((folder/'disputes_extrinsic.json').read_text())
    # Convert explicit named identity encodings without relying on any production decoder.
    for kind in ('verdicts','culprits','faults'):
        # Walk named JSON records without interpreting their state eligibility.
        for item in value[kind]:
            # Each exact identity/signature field becomes raw bytes independently.
            for field in ('target','key','signature'):
                # Verdicts lack offender keys and top-level signatures.
                if field in item:
                    item[field]=bytes.fromhex(item[field][2:])
            # Only verdicts contain nested judgment signatures.
            for vote in item.get('votes',[]):
                vote['signature']=bytes.fromhex(vote['signature'][2:])
    assert wire(value)==(folder/'disputes_extrinsic.bin').read_bytes()
    return value


# Deterministic identities deliberately separate report order from offender key order.
def example(verdicts=2,votes=3,culprits=2,faults=2):
    return dict(verdicts=[dict(target=bytes([i+1])*32,age=2**32-1-i,votes=[
        dict(vote=bool(j%2),index=j,signature=bytes([(j+11)%256])*64) for j in range(votes)]) for i in range(verdicts)],
        culprits=[dict(target=bytes([31-i])*32,key=bytes([i+1])*32,signature=bytes([71+i])*64) for i in range(culprits)],
        faults=[dict(target=bytes([61-i])*32,vote=bool(i%2),key=bytes([i+1])*32,signature=bytes([91+i])*64) for i in range(faults)])


# Pair native requests with independently computed expectations before invoking the implementation.
def requests():
    lines,expected=[],[]
    # Each call records a standalone borrowed input and explicit profile/budget.
    def add_decode(data,validators=1023,budget=2*1024*1024):
        lines.append(f'D {validators} {budget} {token(data)}');expected.append(decode(data,validators,budget))
    # Typed source fields are passed directly, never created using the new production decoder.
    def add_encode(value,validators=1023,budget=2*1024*1024,capacity=None):
        capacity=len(wire(value))+3 if capacity is None else capacity
        lines.append(f'E {validators} {budget} {capacity} '+fields(value))
        expected.append(encode(value,validators,budget,capacity))
    examples=[example(0,0,0,0),example(),example(1,0,0,0),example(0,0,2,2)]
    # Original upstream descending verdicts must reject; sorted copies are explicitly derived fixtures.
    for profile in ('tiny','full'):
        value=published(profile);add_decode(wire(value));add_encode(value)
        assert expected[-1]=='noncanonical' and expected[-2]=='noncanonical'
        canonical=copy.deepcopy(value);canonical['verdicts'].sort(key=lambda v:v['target'])
        add_decode(wire(canonical));add_encode(canonical)
        # Full-profile truncations sample every vote boundary rather than duplicating quadratic wire storage.
        data=wire(canonical)
        # Sample every full-profile vote-stride boundary without quadratic exhaustive storage.
        for cut in range(0,len(data),67):
            add_decode(data[:cut])
        # The small published counterpart is cheap enough for exhaustive truncation coverage.
        if profile=='tiny':
            examples.append(canonical)
    # Representative frames exhaust every truncation and every consumed-byte budget boundary.
    for value in examples:
        data=wire(value)
        # Every missing suffix of representative complete frames must reject safely.
        for cut in range(len(data)):
            add_decode(data[:cut])
        # Every retained-byte boundary is tested independently of input capacity.
        for budget in range(len(data)+1):
            add_decode(data, budget=budget)
        # Compare empty, one-short, exact and spare output destinations.
        for capacity in (0,len(data)-1,len(data),len(data)+5):
            add_encode(value,capacity=capacity)
        # Encoder budget checks are independent from destination sizing.
        for budget in (0,len(data)-1,len(data)):
            add_encode(value,budget=budget)
        add_decode(data+b'\xaa\xbb',budget=len(data));add_encode(value)
    # GP maxima, count-width transitions and variable vote cardinality remain structural, not quorum claims.
    for count in (0,1,5,6,127,128,682,683,1023,1024):
        value=example(1,count,0,0);add_decode(wire(value));add_encode(value)
    value=example(16,1023,16,16);add_decode(wire(value));add_encode(value)
    # Each section's seventeenth record and an enormous count fail before allocation or record traversal.
    for kind in ('verdicts','culprits','faults'):
        value=example(1,2,1,1);value[kind]*=17
        add_decode(wire(value));add_encode(value)
    # Overlong and enormous counts must reject in every variable sequence position.
    for prefix in (b'\x80\x00',natural(2**64-1)):
        # Zero-length preceding sections isolate each outer count parser.
        for start in (b'',b'\x00',b'\x00\x00'):
            add_decode(start+prefix)
        base=wire(example(1,1,0,0));add_decode(base[:37]+prefix+base[38:])
    # Late duplicate/descending identities and out-of-domain E2 indices exercise full-source atomicity.
    for kind in ('verdicts','culprits','faults','votes'):
        # Duplicate identities and reversed identities are separate canonicality cases.
        for descending in (False,True):
            value=example()
            items=value['verdicts'][-1]['votes'] if kind=='votes' else value[kind]
            key='index' if kind=='votes' else 'target' if kind=='verdicts' else 'key'
            # Preserve distinct identities while reversing their supplied order.
            if descending:
                items.reverse()
            # Keep the sequence order but deliberately duplicate the final identity.
            else:
                items[-1][key]=items[-2][key]
            add_decode(wire(value));add_encode(value)
    # Exercise tiny, intermediate and full structural populations.
    for validators in (6,9,1023):
        # Compare the last eligible judge, first ineligible judge and maximal E2 value.
        for index in (validators-1,validators,65535):
            value=example(1,1,0,0);value['verdicts'][0]['votes'][0]['index']=index
            add_decode(wire(value),validators);add_encode(value,validators)
    # Invalid domains cannot authorize even a canonical empty extrinsic.
    for validators in (0,5,7,1022,1026,2**64-1):
        add_decode(b'',validators);add_encode(example(0,0,0,0),validators)
    # Every illegal Boolean octet is checked in both judgment and fault locations.
    base=wire(example(1,1,0,1));fault_tag=len(base)-97
    # Exhaust all unsupported Boolean octets rather than testing just one example.
    for tag in range(2,256):
        # Judgments and faults have distinct validity positions and parsers.
        for at in (38,fault_tag):
            data=bytearray(base);data[at]=tag;add_decode(bytes(data))
    rng=random.Random(0x4449535055544553);base=wire(example())
    # Structured mutation reaches late order, tag, epoch and signature fields as well as count prefixes.
    for i in range(2500):
        data=bytearray(base)
        # Mutate multiple deterministic positions to reach both early and late failures.
        for _ in range(rng.randrange(1,5)):
            data[rng.randrange(len(data))]=rng.randrange(256)
        # Some structured mutations also lose their suffix, testing failure precedence.
        if i%3==0:
            data=data[:rng.randrange(len(data)+1)]
        add_decode(bytes(data))
    # Arbitrary bytes ensure no valid framing assumption is needed for safe rejection.
    for _ in range(1000):
        add_decode(rng.randbytes(rng.randrange(1800)))
    return lines,expected
