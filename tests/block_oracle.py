# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent complete extrinsic/block composition over separately tested mathematical child references.

Exposes requests to produce independent native-driver inputs and expected observations, with
reference encoding/decoding helpers.
"""
import copy
import hashlib
import json
import random
from test_support import ROOT
from test_codec import reference_encode as natural,reference_decode
import header_oracle as headers
import tickets_oracle as tickets
import guarantees_oracle as guarantees
import assurances_oracle as assurances
import disputes_oracle as disputes
from report_oracle import from_json as report_json,encode as report_wire

KINDS=('tickets','preimages','guarantees','assurances','disputes')
FULL=(341,1023,600,16,10000,2**24,2**24,2**24)
TINY=(2,6,12,3,10000,2**24,2**24,2**24)


# Empty component input still occupies one trusted batch token.
def token(value):
    return value.hex() or '-'


# All shared structural domains precede even an empty child count or a default source handle.
def valid(config):
    cores,validators,epoch,ticket_limit,*_=config
    return headers.valid_config((cores,validators,epoch,config[-1])) and ticket_limit<=16


# Convert named composite JSON into independent exact child wire bytes, preserving original policy violations.
def child_wires(value,cores):
    records=[bytes([v['attempt']])+bytes.fromhex(v['signature'][2:]) for v in value['tickets']]
    preimages=[(v['requester'],bytes.fromhex(v['blob'][2:])) for v in value['preimages']]
    reports=[dict(report=report_wire(report_json(v['report'])),slot=v['slot'],credentials=[
        (s['validator_index'],bytes.fromhex(s['signature'][2:])) for s in v['signatures']]) for v in value['guarantees']]
    assurance_records=[(bytes.fromhex(v['anchor'][2:]),bytes.fromhex(v['bitfield'][2:])+bytes(43-len(bytes.fromhex(v['bitfield'][2:]))),
        v['validator_index'],bytes.fromhex(v['signature'][2:])) for v in value['assurances']]
    judgment=copy.deepcopy(value['disputes'])
    # Every hash/signature conversion is by explicit field name, without invoking native codecs.
    for kind in ('verdicts','culprits','faults'):
        # Each section carries different named fields; preserve all logical records independently.
        for item in judgment[kind]:
            # Convert only byte-encoded identities present in this section's JSON schema.
            for field in ('target','key','signature'):
                # Missing fields belong to another section rather than an empty default identity.
                if field in item:
                    item[field]=bytes.fromhex(item[field][2:]) # Verdicts do not have top-level key/signature fields.
            # Only verdicts have nested votes; preserve their explicit judgment order.
            for vote in item.get('votes',[]):
                vote['signature']=bytes.fromhex(vote['signature'][2:]) # Only nested verdict judgments carry these signatures.
    return [tickets.wire(records),natural(len(preimages))+b''.join(service.to_bytes(4,'little')+natural(len(blob))+blob for service,blob in preimages),
        guarantees.wire(reports),assurances.wire(assurance_records,cores),disputes.wire(judgment)]


# Internal parser rejection never publishes a partial count, owner or cursor.
class Rejected(Exception):
    pass


# Independent preimage walk adds serialized-frame budget to the established payload policies.
def preimage_inspect(data,config):
    items,per_blob,total,wire_budget=config[4:]
    parsed=reference_decode(data)
    if parsed in ('truncated','noncanonical'):
        return parsed # Canonical count framing precedes every policy/extent decision.
    count,cursor=map(int,parsed.split())
    if count>items:
        return 'limitexceeded' # Count policy applies before minimum-wire extent.
    if count>(len(data)-cursor)//5:
        return 'truncated' # Every E4 service needs at least one blob-length octet.
    if cursor>wire_budget:
        return 'limitexceeded' # Even an empty count consumes serialized bytes.
    # Each tuple is completely checked before its endpoint contributes to the successful prefix.
    for _ in range(count):
        if len(data)-cursor<4:
            return 'truncated'
        if cursor+4>wire_budget:
            return 'limitexceeded'
        cursor+=4;parsed=reference_decode(data[cursor:])
        if parsed in ('truncated','noncanonical'):
            return parsed
        length,prefix=map(int,parsed.split())
        if length>min(per_blob,total):
            return 'limitexceeded' # Payload policies apply before the declared bytes need be present.
        if length>len(data)-cursor-prefix:
            return 'truncated'
        cursor+=prefix+length
        if cursor>wire_budget:
            return 'limitexceeded' # Complete input still must fit this parent's remaining wire budget.
        total-=length
    return cursor,count


# Preserve all three dispute record counts from the independently observed logical token representation.
def dispute_count(parts):
    cursor=1;verdicts=int(parts[0])
    # Each verdict contributes target/epoch/count followed by three tokens per judgment.
    for _ in range(verdicts):
        votes=int(parts[cursor+2]);cursor+=3+3*votes
    culprits=int(parts[cursor]);cursor+=1+3*culprits
    faults=int(parts[cursor])
    return verdicts+culprits+faults


# Delegate child semantics to independent references, retaining exact prefix boundaries and attribution.
def inspect(kind,data,config):
    if not valid(config):
        return 'invalidconfig' # Parent configuration precedes child-specific framing.
    cores,validators,epoch,ticket_limit,_,_,_,budget=config
    # A block's initial component is a sealed header with its own marker profile.
    if kind=='header':
        result=headers.decode('H',data,(cores,validators,epoch,budget))
        # A failure token carries no successful child extent or cardinality.
        if not result.split()[0].isdigit():
            return 'header:'+result # Typed nested header failures are not flattened into parent progress.
        length,count=int(result.split()[0]),1
    elif kind=='tickets':
        # Ticket count and fixed proof extent use the existing independent reference.
        result=tickets.decode(data,ticket_limit,16)
        # A failure token carries no successful child extent or cardinality.
        if not result.split()[0].isdigit():
            return 'tickets:'+result
        parts=result.split();length,count=int(parts[-1]),int(parts[0])
    elif kind=='preimages':
        # Preimages need separate payload and serialized-frame resource budgets.
        result=preimage_inspect(data,config)
        # Preimage failures likewise cannot publish a partial tuple count.
        if isinstance(result,str):
            return 'preimages:'+result
        length,count=result
    elif kind=='guarantees':
        # Every nested report and credential must fit the remaining parent budget.
        result=guarantees.decode(data,cores,validators,budget)
        # A failure token carries no successful child extent or cardinality.
        if not result.split()[0].isdigit():
            return 'guarantees:'+result
        parts=result.split();length,count=int(parts[1]),int(parts[0])
    elif kind=='assurances':
        # Fixed profile bitfield width and canonical validators determine record boundaries.
        result=assurances.decode(cores,validators,validators,data)
        # A failure token carries no successful child extent or cardinality.
        if not result.split()[0].isdigit():
            return 'assurances:'+result
        parts=result.split();length,count=int(parts[-1]),int(parts[0])
    else:
        # The final component includes all three independently framed dispute sections.
        result=disputes.decode(data,validators,budget)
        # A failure token carries no successful child extent or cardinality.
        if not result.split()[0].isdigit():
            return 'disputes:'+result
        parts=result.split();length,count=int(parts[0]),dispute_count(parts[1:])
    if length>budget:
        return 'limitexceeded' # Parent budget applies after every complete authoritative child inspection.
    return length,count


# Scan all children using a remaining whole-frame budget and only then expose independent expected bytes.
def parse(kind,data,config):
    if not valid(config):
        return 'invalidconfig'
    cursor=0;counts=[];parts=[]
    # Blocks prepend one complete sealed header; extrinsics contain exactly the five child families.
    for child in (('header',)+KINDS if kind=='B' else KINDS):
        remaining=config[:-1]+(config[-1]-cursor,);parsed=inspect(child,data[cursor:],remaining)
        if isinstance(parsed,str):
            return parsed # No child prefix, counts or offsets survive a late failure.
        length,count=parsed;parts.append(data[cursor:cursor+length]);counts.append(count);cursor+=length
    return cursor,counts,parts


# Native getters must expose these exact independent child prefixes and cardinalities in normative order.
def decode(kind,data,config):
    parsed=parse(kind,data,config)
    if isinstance(parsed,str):
        return parsed
    consumed,counts,parts=parsed
    return ' '.join([str(consumed)]+[str(v) for v in counts]+[token(v) for v in parts])


# Encoder source components are captured independently, then revalidated under the new parent configuration.
def encode(kind,parts,capture_config,config,capacity):
    # The adapter constructs nominal child owners without using the parent decoder under test.
    for child,data in zip((('header',)+KINDS if kind=='B' else KINDS),parts):
        checked=inspect(child,data,capture_config)
        if isinstance(checked,str):
            return checked # Failed source capture cannot create a typed component for parent encoding.
        assert checked[0]==len(data)
    # Source components must keep their exact schema extent under a changed policy/profile.
    if not valid(config):
        return 'invalidconfig'
    cursor=0
    # New parent policy applies to every retained child, including the final disputes section.
    for child,data in zip((('header',)+KINDS if kind=='B' else KINDS),parts):
        checked=inspect(child,data,config[:-1]+(config[-1]-cursor,))
        if isinstance(checked,str):
            return checked
        if checked[0]!=len(data):
            return 'invalidconfig' # A shorter prefix is not the same already-captured schema value.
        cursor+=checked[0]
    return b''.join(parts).hex() if cursor<=capacity else 'outputtoosmall'


# Reconstruct exact upstream bytes before deriving explicitly labelled policy-valid composition examples.
def published(profile,kind,canonical=False):
    name='block' if kind=='B' else 'extrinsic';folder=ROOT/f'vendor/jamtestvectors/codec/{profile}'
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Immutable JSON and binary provenance is checked separately from any test-only canonicalization.
    for extension in ('json','bin'):
        path=folder/f'{name}.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    value=json.loads((folder/f'{name}.json').read_text());extrinsic=value['extrinsic'] if kind=='B' else value
    cores=2 if profile=='tiny' else 341
    parts=child_wires(extrinsic,cores)
    # Block fixture JSON supplies an independently named complete sealed header.
    if kind=='B':
        parts=[headers.wire('H',headers.from_json(value['header']))]+parts
    assert b''.join(parts)==(folder/f'{name}.bin').read_bytes()
    # Only authored counterparts change policy-invalid sample fields; original hashes were checked above.
    if canonical:
        # Retain original published bytes; authored counterparts fix only the documented structural-policy issues.
        extrinsic['disputes']['verdicts'].sort(key=lambda v:v['target'])
        if profile=='tiny':
            extrinsic['guarantees'][0]['report']['core_index']=0 # Tiny has two cores; sample's core 3 is outside that domain.
        parts=child_wires(extrinsic,cores)
        # Reattach the original opaque header without claiming recomputed commitments/signatures.
        if kind=='B':
            parts=[headers.wire('H',headers.from_json(value['header']))]+parts
    return parts


# Minimal authored children exercise composition without any fixture-specific curve/state eligibility assumptions.
def example(kind):
    empty=[b'\0',b'\0',b'\0',b'\0',b'\0\0\0']
    return [headers.wire('H',headers.example('H'))]+empty if kind=='B' else empty


# Deterministic parent requests keep ownership/source policy and malformed framing checks independently reproducible.
def requests():
    lines,expected=[],[]
    # Each decode receives complete unrelated suffixes only when the caller explicitly leaves trailing input.
    def add_decode(kind,data,config=TINY):
        lines.append(' '.join(['D',kind]+[str(v) for v in config]+[token(data)]));expected.append(decode(kind,data,config))
    # Encode sources are separate child bytes captured into nominal handles, never decoded parent frames.
    def add_encode(kind,parts,capture_config=TINY,config=None,capacity=None):
        config=capture_config if config is None else config;capacity=sum(map(len,parts))+3 if capacity is None else capacity
        lines.append(' '.join(['E',kind]+[str(v) for v in capture_config]+[str(v) for v in config]+[str(capacity)]+[token(v) for v in parts]))
        expected.append(encode(kind,parts,capture_config,config,capacity))
    examples=[(kind,example(kind),TINY) for kind in ('E','B')]
    # All exact published bytes reconstruct; originals retain documented tiny-core/dispute-order rejections.
    for profile,config in (('tiny',TINY),('full',FULL)):
        # Both published parent families must preserve their original documented rejection.
        for kind in ('E','B'):
            raw=published(profile,kind);add_decode(kind,b''.join(raw),config)
            examples.append((kind,published(profile,kind,canonical=True),config))
    # Independent sources cover minimal frames and both policy-valid published counterparts.
    for kind,parts,config in examples:
        data=b''.join(parts);add_decode(kind,data,config);add_encode(kind,parts,config)
        # Every small truncation and representative large-record boundary rejects before parent capture.
        cuts=range(len(data)) if len(data)<10000 else sorted(set(range(0,len(data),128))|{len(data)-1})
        # Each proper prefix must fail before any parent-owned child is captured.
        for cut in cuts:
            add_decode(kind,data[:cut],config)
        # Distinguish absent, short, exact and spare output while retaining atomicity.
        for capacity in (0,len(data)-1,len(data),len(data)+5):
            add_encode(kind,parts,config,capacity=capacity) # Late child preflight precedes whole-output capacity.
        # Whole-frame budget is separate from physical input/output availability.
        for budget in (0,len(data)-1,len(data)):
            limited=config[:-1]+(budget,);add_decode(kind,data,limited);add_encode(kind,parts,config,limited)
        add_decode(kind,data+b'\xaa\xbb',config[:-1]+(len(data),))
        # Every component boundary gets an independently malformed canonical count/tag and missing next section.
        cursor=0
        for index,part in enumerate(parts):
            # Overlong and maximal counts target canonicality and untrusted extent handling.
            for prefix in (b'\x80\0',natural(2**64-1)):
                add_decode(kind,data[:cursor]+prefix+data[cursor+1:],config)
            cursor+=len(part)
            add_decode(kind,data[:cursor],config)
    # Empty/preimage-rich frames cover every byte-budget boundary without opaque crypto fixtures.
    for kind in ('E','B'):
        parts=example(kind);parts[-4]=natural(2)+(2**32-1).to_bytes(4,'little')+b'\0'+bytes(4)+b'\x03abc'
        data=b''.join(parts)
        # Framing overhead matters even when an individual preimage payload is empty.
        for budget in range(len(data)+1):
            add_decode(kind,data,TINY[:-1]+(budget,))
        add_encode(kind,parts)
        # Captured components must still obey stricter count/single/aggregate policies on later parent encoding.
        for field,limit in ((3,0),(4,1),(5,2),(6,2)):
            constrained=list(TINY);constrained[field]=limit
            add_encode(kind,parts,TINY,tuple(constrained),capacity=0)
    # Later stricter limits are checked on already captured nonempty child owners, before even zero output capacity.
    for kind in ('E','B'):
        parts=published('tiny',kind,canonical=True)
        # Enforce every stricter resource dimension on already captured nonempty components.
        for field,limit in ((3,0),(4,0),(5,0),(6,0)):
            strict=list(TINY);strict[field]=limit
            add_encode(kind,parts,TINY,tuple(strict),capacity=0)
    # Invalid configuration precedes any input byte, including domains whose products would overflow if unchecked.
    for cores,validators,epoch,ticket_limit in ((0,6,12,3),(342,6,12,3),(2,7,12,3),(2,6,0,3),(2,6,12,17),(2**64-1,6,12,3)):
        config=(cores,validators,epoch,ticket_limit)+TINY[4:]
        # Invalid domains must fail identically for both parent schemas.
        for kind in ('E','B'):
            add_decode(kind,b'',config);add_encode(kind,example(kind),TINY,config)
    rng=random.Random(0x424c4f434b303038)
    # Structured mutations target boundary lengths and late child policies, not only opaque payload bytes.
    for kind in ('E','B'):
        parts=published('tiny',kind,canonical=True);base=b''.join(parts)
        # Multiple controlled mutations can invalidate later children after earlier ones pass.
        for i in range(1800):
            data=bytearray(base)
            # Mix single and interacting malformed fields under a reproducible random seed.
            for _ in range(rng.randrange(1,5)):
                data[rng.randrange(len(data))]=rng.randrange(256) # Mutations use independently constructed child sources.
            if i%3==0:
                data=data[:rng.randrange(len(data)+1)] # Late truncations must release/no-op every earlier child.
            add_decode(kind,bytes(data))
        # Arbitrary bytes exercise failure-only results without any valid preceding component assumption.
        for _ in range(500):
            add_decode(kind,rng.randbytes(rng.randrange(3000)))
    return lines,expected
