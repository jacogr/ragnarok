# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Independent GP 0.8.0 header/marker fields, wire construction, parsing and adversarial corpus."""
import copy
import hashlib
import json
import random
from test_support import ROOT
from test_codec import reference_encode as natural,reference_decode

FULL=(341,1023,600,1024*1024)
TINY=(2,6,12,1024*1024)


# Preserve empty trusted fixture fields without losing a whitespace token.
def token(value):
    return value.hex() or '-'


# Convert named published identities/proofs into exact byte encodings without a production decoder.
def from_json(value):
    value=copy.deepcopy(value)
    # These complete fixed encodings retain their separate logical header roles.
    for key in ('parent','parent_state_root','extrinsic_hash','entropy_source','seal'):
        value[key]=bytes.fromhex(value[key][2:])
    # Present epoch markers preserve indexed validator sequence order, including arbitrary opaque keys.
    if value['epoch_mark'] is not None:
        epoch=value['epoch_mark']
        # The two entropy roles stay independently named despite their identical byte widths.
        for key in ('entropy','tickets_entropy'):
            epoch[key]=bytes.fromhex(epoch[key][2:])
        # Key pairs remain in published validator-index order, including opaque encodings.
        for pair in epoch['validators']:
            # Convert each distinct key algorithm without interpreting curve validity.
            for key in ('bandersnatch','ed25519'):
                pair[key]=bytes.fromhex(pair[key][2:])
    # Present winners have no encoded count, but the JSON list explicitly supplies their slot order.
    if value['tickets_mark'] is not None:
        # Every published winner identifier retains its exact slot position.
        for ticket in value['tickets_mark']:
            ticket['id']=bytes.fromhex(ticket['id'][2:])
    value['offenders_mark']=[bytes.fromhex(key[2:]) for key in value['offenders_mark']]
    return value


# Construct literal C.2 bytes without sorting, deduplicating or enforcing state-dependent eligibility.
def wire(kind,value):
    # Safrole ticket identifiers precede their fixed E1 attempts.
    # Fixed winning tickets own a complete identifier and one E1 attempt octet.
    if kind=='T':
        return value['id']+bytes([value['attempt']])
    # Optional epoch tuples have a natural variable validator count after both entropy hashes.
    # Epoch markers alone have two entropies and a variable validator population.
    if kind=='E':
        # Absence carries no present-marker entropy or validator fields.
        if value is None:
            return b'\0' # Absence contains no default entropy/key bytes.
        return b'\1'+value['entropy']+value['tickets_entropy']+natural(len(value['validators']))+b''.join(
            pair['bandersnatch']+pair['ed25519'] for pair in value['validators'])
    # Optional winners are a fixed-length sequence and carry no natural count discriminator.
    # Winner markers use the configured fixed sequence length without an encoded count.
    if kind=='W':
        return b'\0' if value is None else b'\1'+b''.join(wire('T',v) for v in value)
    # Headers serialize author/proof before offender keys; full headers append exactly one final seal.
    result=(value['parent']+value['parent_state_root']+value['extrinsic_hash']+value['slot'].to_bytes(4,'little')+
        wire('E',value['epoch_mark'])+wire('W',value['tickets_mark'])+value['author_index'].to_bytes(2,'little')+
        value['entropy_source']+natural(len(value['offenders_mark']))+b''.join(value['offenders_mark']))
    return result+value['seal'] if kind=='H' else result


# Describe every named source/getter field independently from encoded byte offsets.
def fields(kind,value):
    # Attempt observation retains the complete E1 source domain, including values above 127.
    # Fixed winning tickets own a complete identifier and one E1 attempt octet.
    if kind=='T':
        return token(value['id'])+' '+str(value['attempt'])
    # Epoch markers alone have two entropies and a variable validator population.
    if kind=='E':
        # A present epoch has explicit entropy/count fields; absent markers contain none of them.
        # Absence carries no present-marker entropy or validator fields.
        if value is None:
            return '0'
        return ' '.join(['1',token(value['entropy']),token(value['tickets_entropy']),str(len(value['validators']))]+
            [token(pair['bandersnatch'])+' '+token(pair['ed25519']) for pair in value['validators']])
    # Winner markers use the configured fixed sequence length without an encoded count.
    if kind=='W':
        # The trusted source protocol includes count, but the production wire deliberately does not.
        return '0' if value is None else ' '.join(['1',str(len(value))]+[fields('T',v) for v in value])
    result=' '.join([token(value['parent']),token(value['parent_state_root']),token(value['extrinsic_hash']),str(value['slot']),
        fields('E',value['epoch_mark']),fields('W',value['tickets_mark']),str(value['author_index']),token(value['entropy_source']),
        str(len(value['offenders_mark']))]+[token(v) for v in value['offenders_mark']])
    return result+' '+token(value['seal']) if kind=='H' else result


# Configuration uses GP valcount for the author's set and a separate positive configured epoch length.
def valid_config(config):
    cores,authors,epoch,_=config
    return 2<=cores<=341 and 6<=authors<=3*cores and authors%3==0 and epoch>0


# Rejections discard every partial field and consumed-prefix cursor.
class Rejected(Exception):
    pass


# Independent source preflight enforces structural counts without guessing future/past state rules.
def source_policy(kind,value,config):
    # Fixed tickets have no chain configuration or byte-budget parameter in their standalone API.
    # Fixed winning tickets own a complete identifier and one E1 attempt octet.
    if kind=='T':
        return
    # Invalid chain domains cannot authorize any nested source traversal.
    if not valid_config(config):
        raise Rejected('invalidconfig') # Invalid profiles precede nested source traversal.
    # Present epoch counts follow the core ceiling, independently of the author's current population.
    def epoch(marker):
        # Only a present epoch marker has a validator cardinality to validate.
        if marker is not None:
            count=len(marker['validators'])
            # The pending population follows GP valcount rather than the author population.
            if count<6 or count>3*config[0] or count%3:
                raise Rejected('limitexceeded') # Zero, unsupported cardinality and excessive key sets reject.
    # Exact configured epoch length is required only for a present winner marker.
    def winners(marker):
        # Present winner sources must contain precisely one ticket for each configured epoch slot.
        if marker is not None and len(marker)!=config[2]:
            raise Rejected('limitexceeded')
    # Epoch markers alone have two entropies and a variable validator population.
    if kind=='E':
        epoch(value)
    # Standalone winner validation applies exact configured cardinality only when present.
    elif kind=='W':
        winners(value)
    # Composite header policy validates both complete marker sources before later fields.
    else:
        # Every nested marker is checked before author/offender/output policy.
        epoch(value['epoch_mark']);winners(value['tickets_mark'])
        # A fixed E2 representation must still select an author below the caller ceiling.
        if value['author_index']>=config[1]:
            raise Rejected('invalidauthor') # Representable E2 values still require the supplied author ceiling.
        # The concatenated evidence sequences can contain at most sixteen plus sixteen keys.
        if len(value['offenders_mark'])>32:
            raise Rejected('limitexceeded') # At most sixteen culprit plus sixteen fault entries exist.
    # The caller byte budget bounds the selected prefix independently from destination capacity.
    if len(wire(kind,value))>config[3]:
        raise Rejected('limitexceeded') # Serialized prefix budget is independent from actual output capacity.


# All source errors precede capacity so late failures cannot authorize any output prefix.
def encode(kind,value,config,capacity):
    # Only a complete successful operation can publish wire, fields or consumed progress.
    try:
        source_policy(kind,value,config);data=wire(kind,value)
        return data.hex() if len(data)<=capacity else 'outputtoosmall'
    # Discard every partial logical value and preserve only the typed failure reason.
    except Rejected as failure:
        return str(failure) # No partial bytes/progress are returned for malformed sources.


# Independent parser keeps mathematical cursor arithmetic and complete logical fields separate from native code.
def decode(kind,data,config):
    # Standalone fixed tickets ignore irrelevant chain/budget fields carried by the trusted adapter protocol.
    if kind!='T' and not valid_config(config):
        return 'invalidconfig'
    cursor=0
    # Input existence precedes byte budget; division avoids any attacker-selected extent product.
    def extent(count,stride,budget=None):
        # Division proves available input without an untrusted count-times-stride overflow.
        if count>(len(data)-cursor)//stride:
            raise Rejected('truncated')
        # Backed input can still exceed the caller retained-prefix budget.
        if cursor+count*stride>(config[3] if budget is None else budget):
            raise Rejected('limitexceeded')
    # Only previously proved fixed intervals move the private cursor.
    def take(size):
        nonlocal cursor
        value=data[cursor:cursor+size];cursor+=size;return value
    # Read an exact previously checked E2/E4 scalar rather than a compact natural.
    def scalar(width):
        return int.from_bytes(take(width),'little')
    # Optional tags are one Boolean octet; arbitrary high discriminator values have no alternative.
    def tag():
        extent(1,1);value=take(1)[0]
        # An optional discriminator has exactly the absent/present alternatives.
        if value>1:
            raise Rejected('invalidtag')
        return bool(value)
    # Canonical natural counts are bounded before loops, narrowing or input-derived collections.
    def number(ceiling):
        nonlocal cursor
        parsed=reference_decode(data[cursor:])
        # Incomplete or overlong naturals cannot choose trusted count/progress values.
        if parsed in ('truncated','noncanonical'):
            raise Rejected(parsed)
        count,length=map(int,parsed.split());cursor+=length
        # Bound canonical prefix bytes and count before iteration or storage selection.
        if cursor>config[3] or count>ceiling:
            raise Rejected('limitexceeded')
        return count
    # The fixed ticket tuple owns every byte; no eligibility limit is inferred for its E1 attempt.
    def ticket():
        return dict(id=take(32),attempt=scalar(1))
    # Epoch validator pairs preserve indexed sequence order and may differ from the author's set size.
    def epoch():
        # Canonical absence returns without inspecting any present tuple fields.
        if not tag():
            return None # An absent marker has no entropy/count fields to parse.
        extent(1,64);value=dict(entropy=take(32),tickets_entropy=take(32));count=number(3*config[0])
        # Only a supported multiple-of-three pending population can select key metadata.
        if count<6 or count%3:
            raise Rejected('limitexceeded')
        extent(count,64);value['validators']=[dict(bandersnatch=take(32),ed25519=take(32)) for _ in range(count)]
        return value
    # Configured count is not read from the wire and is extent-proved before iteration.
    def winners():
        # Canonical absence returns without inspecting any present tuple fields.
        if not tag():
            return None # Absence requires no configured number of ticket bytes.
        extent(config[2],33);return [ticket() for _ in range(config[2])]
    # Only a complete successful operation can publish wire, fields or consumed progress.
    try:
        # All standalone components consume one exact prefix and leave unrelated trailing input untouched.
        if kind=='T':
            extent(1,33,budget=2**64-1);value=ticket()
        # Decode a complete standalone epoch prefix with its own optional alternative.
        elif kind=='E':
            value=epoch()
        # Decode exactly the configured winner tuple, leaving unrelated suffixes to the caller.
        elif kind=='W':
            value=winners()
        # Full and unsigned headers share every field before the optional final seal.
        else:
            # Hashes/slot precede both optional markers and the complete author/VRF tuple.
            extent(1,100);value=dict(parent=take(32),parent_state_root=take(32),extrinsic_hash=take(32),slot=scalar(4))
            value['epoch_mark']=epoch();value['tickets_mark']=winners();extent(1,98)
            value['author_index']=scalar(2)
            # Author membership in the supplied structural ceiling precedes offender framing.
            if value['author_index']>=config[1]:
                raise Rejected('invalidauthor')
            value['entropy_source']=take(96);count=number(32);extent(count,32)
            value['offenders_mark']=[take(32) for _ in range(count)]
            # Only a complete full header requires and consumes the final 96-byte seal.
            if kind=='H':
                extent(1,96);value['seal']=take(96) # Seal comes after every offender identity.
        return f'{cursor} '+fields(kind,value)
    # Discard every partial logical value and preserve only the typed failure reason.
    except Rejected as failure:
        return str(failure) # Failure exposes neither a logical record nor a default/partial cursor.


# Verify both immutable published representations before reconstructing their bytes from named fields.
def published(profile,name):
    folder=ROOT/f'vendor/jamtestvectors/codec/{profile}';pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Frozen hashes protect the raw published fixtures, not merely normalized derived examples.
    for extension in ('json','bin'):
        path=folder/f'{name}.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    value=from_json(json.loads((folder/f'{name}.json').read_text()))
    assert wire('H',value)==(folder/f'{name}.bin').read_bytes()
    assert wire('U',value)==wire('H',value)[:-96]
    return value


# Small authored values exercise all optional combinations without relying on the same upstream fixture fields.
def example(kind,slots=12):
    # Fixed winning tickets own a complete identifier and one E1 attempt octet.
    if kind=='T':
        return dict(id=bytes([7])*32,attempt=255)
    # Epoch markers alone have two entropies and a variable validator population.
    if kind=='E':
        return dict(entropy=bytes([8])*32,tickets_entropy=bytes([9])*32,validators=[
            dict(bandersnatch=bytes([i])*32,ed25519=bytes([10+i])*32) for i in range(6)])
    # Winner markers use the configured fixed sequence length without an encoded count.
    if kind=='W':
        return [dict(id=bytes([i%256])*32,attempt=(i*17)%256) for i in range(slots)]
    return dict(parent=bytes([1])*32,parent_state_root=bytes([2])*32,extrinsic_hash=bytes([3])*32,slot=2**32-1,
        epoch_mark=None,tickets_mark=None,author_index=5,entropy_source=bytes([4])*96,
        offenders_mark=[bytes([6])*32,bytes([5])*32,bytes([6])*32],seal=bytes([11])*96)


# Pair each independent native request with its wire, field or typed-rejection expectation before execution.
def requests():
    lines,expected=[],[]
    # Decode budgets cover consumed prefix only; suffixes never become part of the retained owner.
    def add_decode(kind,data,config=TINY):
        lines.append(f'D {kind} {config[0]} {config[1]} {config[2]} {config[3]} {token(data)}')
        expected.append(decode(kind,data,config))
    # Native encoding sources are explicit named fields, never decoded by the production codec under test.
    def add_encode(kind,value,config=TINY,capacity=None):
        capacity=len(wire(kind,value))+3 if capacity is None else capacity
        lines.append(f'E {kind} {config[0]} {config[1]} {config[2]} {config[3]} {capacity} '+fields(kind,value))
        expected.append(encode(kind,value,config,capacity))
    examples=[(kind,example(kind),TINY) for kind in ('T','E','W','U','H')]+[('E',None,TINY),('W',None,TINY)]
    # Both published profiles exercise standalone components, exact unsigned signing payload and full headers.
    for profile,config in (('tiny',TINY),('full',FULL)):
        # The two published fixtures exercise both marker choices within each profile.
        for name in ('header_0','header_1'):
            value=published(profile,name)
            examples.extend([('H',value,config),('U',value,config),('E',value['epoch_mark'],config),('W',value['tickets_mark'],config)])
    # The complete Cartesian product of optional markers has unambiguous structural framing.
    for has_epoch in (False,True):
        # Every optional combination has distinct unambiguous structural framing.
        for has_winners in (False,True):
            value=example('H');value['epoch_mark']=example('E') if has_epoch else None
            value['tickets_mark']=example('W') if has_winners else None
            examples.append(('H',value,TINY))
    # Published and authored sources share equivalent encode/decode and ownership checks.
    for kind,value,config in examples:
        data=wire(kind,value);add_decode(kind,data,config);add_encode(kind,value,config)
        # Exhaust all small-frame truncations, sampling large published key/ticket records by their fixed strides.
        cuts=range(len(data)) if len(data)<2048 else sorted(set(range(0,len(data),33 if kind=='W' else 64))|{len(data)-1})
        # Missing tails must reject safely before any owner or progress can escape.
        for cut in cuts:
            add_decode(kind,data[:cut],config)
        # Empty, short, exact and spare destinations check complete-output atomicity and suffix preservation.
        for capacity in (0,len(data)-1,len(data),len(data)+5):
            add_encode(kind,value,config,capacity)
        # Zero, one-short and exact prefix budgets are independent from actual input/output capacity.
        for budget in (0,len(data)-1,len(data)):
            add_decode(kind,data,config[:3]+(budget,));add_encode(kind,value,config[:3]+(budget,))
        add_decode(kind,data+b'\xaa\xbb',config[:3]+(len(data),))
    # Epoch key cardinalities are variable, in multiples of three, and independent from author set cardinality.
    for cores,authors in ((2,6),(3,6),(3,9),(341,6),(341,1023)):
        # Sample unsupported cardinalities, natural-width transitions and the full valcount ceiling.
        for count in (0,5,6,7,9,126,129,1023,1024):
            value=example('E');value['validators']=[dict(bandersnatch=bytes([i%256])*32,ed25519=bytes([(i+1)%256])*32) for i in range(count)]
            config=(cores,authors,12,FULL[3]);add_encode('E',value,config);add_decode('E',wire('E',value),config)
    # Repeated/reversed/null validator pairs remain opaque indexed sequence entries, never sorted sets.
    for pairs in ([dict(bandersnatch=bytes(32),ed25519=bytes(32))]*6,list(reversed(example('E')['validators']))):
        value=example('E');value['validators']=pairs;add_encode('E',value);add_decode('E',wire('E',value))
    # Configured winner cardinality has no discriminator; source mismatches reject and decoding consumes one tuple.
    for slots in (1,2,12,600,2**64-1):
        config=TINY[:2]+(slots,TINY[3])
        # Source cardinality mismatches reject; decoding still selects only its configured tuple prefix.
        for count in (0,1,2,12,13,600):
            value=example('W',count);add_encode('W',value,config);add_decode('W',wire('W',value),config)
        add_decode('W',b'\0',config)
    # All E1 attempt values are structurally valid and must not become compact naturals above 127.
    for attempt in range(256):
        value=example('T');value['attempt']=attempt;add_encode('T',value);add_decode('T',wire('T',value))
    # Offenders are culprit/fault concatenation; duplicates and descending keys are preserved through the 32-entry maximum.
    for count in (0,1,16,32,33):
        value=example('H');value['offenders_mark']=[bytes([31-i%32])*32 for i in range(count)]
        # Unsigned and full header paths must preserve identical offender sequence semantics.
        for kind in ('U','H'):
            add_encode(kind,value);add_decode(kind,wire(kind,value))
    # Compare last eligible, first ineligible and maximal E2 author representations.
    for author in (0,5,6,1022,1023,65535):
        value=example('H');value['author_index']=author
        # The same E2 author can have different eligibility under the two explicit structural ceilings.
        for config in (TINY,FULL):
            add_encode('H',value,config);add_decode('H',wire('H',value),config)
    # Each unsupported optional tag must reject in standalone and header-relative locations.
    for tag in range(2,256):
        # Both standalone optional discriminators reject every unsupported tag octet.
        for kind in ('E','W'):
            add_decode(kind,bytes([tag]))
        value=example('H');data=wire('H',value)
        # The two optional header positions must use the same canonical tag rules.
        for offset in (100,101):
            add_decode('H',data[:offset]+bytes([tag])+data[offset+1:])
    # Overlong/huge count prefixes cannot choose a validator/offender extent or allocate partial owners.
    for prefix in (b'\x80\0',natural(2**64-1)):
        epoch=wire('E',example('E'));add_decode('E',epoch[:65]+prefix+epoch[66:])
        data=wire('H',example('H'));add_decode('H',data[:200]+prefix+data[201:])
    # Every consumed-byte budget boundary in a representative header/marker is checked independently.
    for kind in ('E','W','H'):
        value=example(kind);data=wire(kind,value)
        # Every byte of a representative consumed prefix has an independent budget-boundary case.
        for budget in range(len(data)+1):
            add_decode(kind,data,TINY[:3]+(budget,))
    # Invalid chain domains must precede input access or an encoding output-capacity check.
    for cores,authors,slots in ((0,6,12),(1,6,12),(342,6,12),(2,5,12),(2,7,12),(2,9,12),(2,6,0),(2**64-1,6,12)):
        config=(cores,authors,slots,FULL[3])
        # Every configured component must reject invalid domains before input/source access.
        for kind in ('E','W','U','H'):
            add_decode(kind,b'',config);add_encode(kind,example(kind),config)
    rng=random.Random(0x4845414445523038)
    # Deterministic structured mutations reach tags, counts, authors and late opaque identity/proof fields.
    for kind in ('T','E','W','U','H'):
        value=example(kind)
        # Structured header mutations include complete nested epoch and winner fields.
        if kind in ('U','H'):
            value['epoch_mark']=example('E');value['tickets_mark']=example('W') # Reach every nested marker position.
        base=wire(kind,value)
        # Deterministic structured changes exercise both early tags and late header fields.
        for i in range(650):
            data=bytearray(base)
            # Multiple changed positions can combine canonicality, membership and tail errors.
            for _ in range(rng.randrange(1,5)):
                data[rng.randrange(len(data))]=rng.randrange(256) # Each seed is independently constructed oracle wire.
            # Some mutations also lose a suffix to exercise framing-error precedence.
            if i%3==0:
                data=data[:rng.randrange(len(data)+1)] # Structured mutation also exercises missing tails.
            add_decode(kind,bytes(data))
        # Arbitrary buffers require typed rejection with no valid-marker framing assumption.
        for _ in range(150):
            add_decode(kind,rng.randbytes(rng.randrange(1000)))
    return lines,expected
