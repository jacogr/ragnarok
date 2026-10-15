"""Independent GP 0.8.0 work-package codec construction, parsing and policy checks (test only)."""
import copy
import hashlib
import json
import random
from test_support import ROOT
from test_codec import reference_encode as natural,reference_decode

MAX_BUNDLE=13_791_360
FOOTPRINT=4488
DEFAULT=(5_000_000_000,10_000_000,32*1024*1024)


# Empty byte fields retain a whitespace token in the native fixture protocol.
def token(value):
    return value.hex() or '-'


# Convert explicit JSON identity/blob fields without involving a production codec.
def blob(value):
    return bytes.fromhex(value[2:])


# Normalize published context, item and package JSON into independent named byte/scalar fields.
def from_json(kind,item):
    value=copy.deepcopy(item)
    # Context scalar slots remain integers; roots and prerequisite identities become exact bytes.
    # Context fields and prerequisites have their own bounded standalone representation.
    if kind=='C':
        # Each root identity retains its exact published byte order.
        for key in ('anchor','state_root','beefy_root','lookup_anchor','lookup_anchor_state_root'):
            value[key]=blob(value[key])
        value['prerequisites']=[blob(v) for v in value['prerequisites']]
    elif kind=='I':
        # Item manifests preserve their supplied sequence order and duplicate entries.
        value['code_hash']=blob(value['code_hash']);value['payload']=blob(value['payload'])
        value['import_segments']=[dict(kind=int('package_hash' in v),hash=blob(v.get('package_hash',v.get('tree_root'))),index=v['index']) for v in value['import_segments']]
        value['extrinsic']=[dict(hash=blob(v['hash']),len=v['len']) for v in value['extrinsic']]
    else:
        # Packages recursively use the independently normalized context and item fields.
        assert kind=='P'
        # Authorization code and its two blobs are separate named source fields.
        for key in ('auth_code_hash','authorization','authorizer_config'):
            value[key]=blob(value[key])
        value['context']=from_json('C',value['context'])
        value['items']=[from_json('I',v) for v in value['items']]
    return value


# Literal C.2 serialization deliberately does not repair sources rejected by canonical/structural policy.
def wire(kind,value):
    # Context fixed prefix is 168 bytes, followed by a natural set count and ordered hashes.
    # Context fields and prerequisites have their own bounded standalone representation.
    if kind=='C':
        return (value['anchor']+value['anchor_slot'].to_bytes(4,'little')+value['state_root']+value['beefy_root']+
            value['lookup_anchor']+value['lookup_anchor_slot'].to_bytes(4,'little')+value['lookup_anchor_state_root']+
            natural(len(value['prerequisites']))+b''.join(value['prerequisites']))
    # Imports use the selected nominal identity and a packed E2 index/selector.
    if kind=='R':
        # The high E2 bit belongs to identity kind, not to the returned fifteen-bit index.
        return value['hash']+(value['index'] | (value['kind']<<15)).to_bytes(2,'little')
    # Standalone input commitments retain the full advertised E4 preimage length.
    if kind=='X':
        # An input commitment has no blob discriminator: its advertised data length is E4.
        return value['hash']+value['len'].to_bytes(4,'little')
    # Items retain both gas limits and every manifest element in source order.
    if kind=='I':
        # Item gas limits are E8; only payload and manifest counts use general naturals.
        return (value['service'].to_bytes(4,'little')+value['code_hash']+value['refine_gas_limit'].to_bytes(8,'little')+
            value['accumulate_gas_limit'].to_bytes(8,'little')+value['export_count'].to_bytes(2,'little')+
            natural(len(value['payload']))+value['payload']+natural(len(value['import_segments']))+
            b''.join(wire('R',v) for v in value['import_segments'])+natural(len(value['extrinsic']))+
            b''.join(wire('X',v) for v in value['extrinsic']))
    # Package context and items are complete nested tuples, not length-delimited child blobs.
    assert kind=='P'
    return (value['auth_code_host'].to_bytes(4,'little')+value['auth_code_hash']+wire('C',value['context'])+
        natural(len(value['authorization']))+value['authorization']+natural(len(value['authorizer_config']))+
        value['authorizer_config']+natural(len(value['items']))+b''.join(wire('I',v) for v in value['items']))


# Flatten named source/getter fields so a native encode request never depends on the decoder under test.
def fields(kind,value):
    # Explicit context slots keep E4 integers separate from the similarly sized identity byte sequences.
    # Context fields and prerequisites have their own bounded standalone representation.
    if kind=='C':
        return ' '.join([token(value['anchor']),str(value['anchor_slot']),token(value['state_root']),token(value['beefy_root']),
            token(value['lookup_anchor']),str(value['lookup_anchor_slot']),token(value['lookup_anchor_state_root']),
            str(len(value['prerequisites']))]+[token(v) for v in value['prerequisites']])
    # Imports use the selected nominal identity and a packed E2 index/selector.
    if kind=='R':
        # Observation includes both selected identity kind and the untagged index.
        return f"{value['kind']} {token(value['hash'])} {value['index']}"
    # Standalone input commitments retain the full advertised E4 preimage length.
    if kind=='X':
        # Observe advertised length independently from exact hash identity.
        return f"{token(value['hash'])} {value['len']}"
    # Items retain both gas limits and every manifest element in source order.
    if kind=='I':
        # Every manifest element is visible individually, alongside payload and both gas fields.
        return ' '.join([str(value['service']),token(value['code_hash']),str(value['refine_gas_limit']),
            str(value['accumulate_gas_limit']),str(value['export_count']),token(value['payload']),str(len(value['import_segments']))]+
            [fields('R',v) for v in value['import_segments']]+[str(len(value['extrinsic']))]+[fields('X',v) for v in value['extrinsic']])
    # A package's retained context and child items must reproduce independently expected fields.
    return ' '.join([str(value['auth_code_host']),token(value['auth_code_hash']),fields('C',value['context']),
        token(value['authorization']),token(value['authorizer_config']),str(len(value['items']))]+[fields('I',v) for v in value['items']])


# Internal rejection discards all partially parsed source fields and cursor state.
class Rejected(Exception):
    pass


# Independently enforce context set policy before allowing a source or decoded context to succeed.
def context_policy(value):
    keys=value['prerequisites']
    # The eight-entry fixed domain precedes identity-order checks.
    if len(keys)>8:
        raise Rejected('limitexceeded')
    # Lexicographic strict ordering also rejects duplicates.
    if any(a>=b for a,b in zip(keys,keys[1:])):
        raise Rejected('noncanonical')


# Stateful package-wide policy uses Python arbitrary precision as an independent overflow reference.
class Policy:
    # Every package begins with separate explicit-prerequisite and distinct tagged-import dependency counts.
    def __init__(self,config,context=None):
        self.config=config;self.deps=set();self.allowed=8-(len(context['prerequisites']) if context else 0)
        self.imports=self.exports=self.xts=self.bytes=self.refine=self.accumulate=0

    # Counts/gas/footprint are nonnegative and retain their full mathematical value before comparisons.
    def charge(self,imports=0,exports=0,xts=0,size=0,refine=0,accumulate=0):
        self.imports+=imports;self.exports+=exports;self.xts+=xts;self.bytes+=size
        self.refine+=refine;self.accumulate+=accumulate
        # Gas ceilings are strict; all other aggregate boundaries here are inclusive.
        if (self.imports>3072 or self.exports>3072 or self.xts>128 or self.bytes>MAX_BUNDLE or
                self.refine>=self.config[0] or self.accumulate>=self.config[1]):
            raise Rejected('limitexceeded')

    # Repeated package references share one lookup; direct roots never add a dependency.
    def dependency(self,value):
        # Only tagged package identities consume dependency lookup slots.
        if value['kind']==1:
            self.deps.add(value['hash'])
            # Explicit prerequisites are added separately, even when an imported hash is also a prerequisite.
            if len(self.deps)>self.allowed:
                raise Rejected('limitexceeded')


# Validate an explicit encoding source without decoding wire bytes or judging capacity prematurely.
def source_policy(kind,value,config):
    # Standalone fixed records/context have no chain gas or serialized-byte configuration policy.
    # Context fields and prerequisites have their own bounded standalone representation.
    if kind=='C':
        context_policy(value);return
    # Imports use the selected nominal identity and a packed E2 index/selector.
    if kind=='R':
        # A typed E2 source index still must fit the lower fifteen bits.
        if value['index']>32767:
            raise Rejected('limitexceeded')
        return
    # Standalone input commitments retain the full advertised E4 preimage length.
    if kind=='X':
        return # All E4 advertised lengths have valid standalone fixed encodings.
    # A zero strict gas ceiling cannot admit a well-formed item or package.
    if not config[0] or not config[1]:
        raise Rejected('invalidconfig') # Empty/default gas domains cannot admit strict sums.
    context=value['context'] if kind=='P' else None
    # Packages need canonical context and at least one bounded item before source traversal.
    if context is not None:
        context_policy(context)
        # A bounded nonempty item sequence and bounded auth blobs precede source traversal.
        if not 1<=len(value['items'])<=16 or max(len(value['authorization']),len(value['authorizer_config']))>MAX_BUNDLE:
            raise Rejected('limitexceeded')
    policy=Policy(config,context)
    # Auth token and configuration are part of the same footprint as payload/import/preimage costs.
    if kind=='P':
        policy.charge(size=len(value['authorization'])+len(value['authorizer_config']))
    # Standalone items use one item's package-compatible budget without authorization/context costs.
    for item in (value['items'] if kind=='P' else [value]):
        # Bound all nested sources before walking any manifest or multiplying its stride.
        if len(item['payload'])>MAX_BUNDLE or len(item['import_segments'])>3072 or len(item['extrinsic'])>128 or item['export_count']>3072:
            raise Rejected('limitexceeded') # Bound source iteration and wire products before traversing manifests.
        # Each reference needs its own index-domain and shared dependency check.
        for reference in item['import_segments']:
            # A source index cannot consume the identity-selector bit.
            if reference['index']>32767:
                raise Rejected('limitexceeded') # Invalid typed source indices cannot borrow the selector bit.
            policy.dependency(reference)
        policy.charge(imports=len(item['import_segments']),exports=item['export_count'],xts=len(item['extrinsic']),
            size=len(item['payload']),refine=item['refine_gas_limit'],accumulate=item['accumulate_gas_limit'])
        policy.charge(size=len(item['import_segments'])*FOOTPRINT)
        # Repeated extrinsic commitments still advertise distinct input occurrences/costs.
        for commitment in item['extrinsic']:
            policy.charge(size=commitment['len'])
    # Retained serialized bytes have a separate caller budget after full source policy.
    if len(wire(kind,value))>config[2]:
        raise Rejected('limitexceeded') # Serialized storage policy is independent of normative bundle footprint.


# Predict complete source validation before capacity while carrying failures without progress.
def encode(kind,value,config,capacity):
    # Only complete validation/parsing can produce a successful value or byte representation.
    try:
        source_policy(kind,value,config)
        data=wire(kind,value)
        return data.hex() if len(data)<=capacity else 'outputtoosmall'
    # Preserve the typed rejection reason and discard all intermediate application data.
    except Rejected as failure:
        return str(failure) # No source failure exposes partial bytes or a default record.


# Parse independent exact fields using mathematical cursors and no native/prod helper.
def decode(kind,data,config):
    # Fixed C/R/X records do not consume configurable gas or wire-storage policies.
    if kind in ('I','P') and (not config[0] or not config[1]):
        return 'invalidconfig'
    cursor=0
    # Prove a fixed extent before inspecting any of its bytes; budget follows input presence.
    def extent(count,stride,limit):
        # Division proves all backing input before any count-times-stride operation.
        if count>(len(data)-cursor)//stride:
            raise Rejected('truncated')
        # Present input may still exceed the explicitly retained prefix budget.
        if cursor+count*stride>limit:
            raise Rejected('limitexceeded')
    # Every caller proves the exact extent before using this private cursor movement.
    def take(size):
        nonlocal cursor
        value=data[cursor:cursor+size];cursor+=size;return value
    # Read a proved little-endian scalar at its explicit E2/E4/E8 width.
    def scalar(width):
        return int.from_bytes(take(width),'little')
    # Counts are canonical naturals and are bounded before iteration or input-derived storage.
    def number(ceiling,limit):
        nonlocal cursor
        parsed=reference_decode(data[cursor:])
        # An incomplete or overlong natural cannot select a trustworthy count.
        if parsed in ('truncated','noncanonical'):
            raise Rejected(parsed) # A partial natural cannot select its logical count.
        value,length=map(int,parsed.split());cursor+=length
        # Bound both prefix cost and unsigned value before loops or narrowing.
        if cursor>limit or value>ceiling:
            raise Rejected('limitexceeded') # Prefix bytes and count ceiling are independent resources.
        return value
    # Context decoding has a fixed bounded maximum and no chain gas configuration.
    def context():
        extent(1,168,2**64-1)
        value=dict(anchor=take(32),anchor_slot=scalar(4),state_root=take(32),beefy_root=take(32),
            lookup_anchor=take(32),lookup_anchor_slot=scalar(4),lookup_anchor_state_root=take(32))
        count=number(8,2**64-1);extent(count,32,2**64-1)
        value['prerequisites']=[take(32) for _ in range(count)];context_policy(value);return value
    # Decode selector and lower index independently; every packed E2 value has one valid alternative.
    def reference():
        hash_value=take(32);packed=scalar(2)
        return dict(kind=packed>>15,hash=hash_value,index=packed&32767)
    # The fixed advertised preimage length is not a compact count or inline blob length.
    def commitment():
        return dict(hash=take(32),len=scalar(4))
    # Scan one complete item with the enclosing package's live aggregate policy.
    def item(policy):
        extent(1,54,config[2])
        value=dict(service=scalar(4),code_hash=take(32),refine_gas_limit=scalar(8),accumulate_gas_limit=scalar(8),export_count=scalar(2))
        length=number(MAX_BUNDLE,config[2]);extent(length,1,config[2]);value['payload']=take(length)
        count=number(3072,config[2]);extent(count,34,config[2]);value['import_segments']=[]
        # Every reference participates in shared dependency accounting, preserving manifest order.
        for _ in range(count):
            imported=reference();policy.dependency(imported);value['import_segments'].append(imported)
        count=number(128,config[2]);extent(count,36,config[2]);value['extrinsic']=[]
        policy.charge(imports=len(value['import_segments']),exports=value['export_count'],xts=count,size=length,
            refine=value['refine_gas_limit'],accumulate=value['accumulate_gas_limit'])
        policy.charge(size=len(value['import_segments'])*FOOTPRINT)
        # Advertised preimage lengths count in full before accepting the final manifest.
        for _ in range(count):
            value['extrinsic'].append(commitment());policy.charge(size=value['extrinsic'][-1]['len'])
        return value
    # Only complete validation/parsing can produce a successful value or byte representation.
    try:
        # Standalone components have exact fixed/bounded representations and ignore unrelated suffixes.
        if kind=='C':
            value=context()
        elif kind=='R':
            extent(1,34,2**64-1);value=reference()
        elif kind=='X':
            extent(1,36,2**64-1);value=commitment()
        elif kind=='I':
            value=item(Policy(config))
        else:
            # Package host/code/context precede auth blobs and the nonempty item sequence.
            extent(1,36,config[2]);value=dict(auth_code_host=scalar(4),auth_code_hash=take(32),context=context())
            # A complete context consumes serialized budget before later auth counts are parsed.
            if cursor>config[2]:
                raise Rejected('limitexceeded') # A complete context already consumes the package's serialized budget.
            policy=Policy(config,value['context'])
            # The two inline authorization blobs share one footprint budget.
            for field in ('authorization','authorizer_config'):
                length=number(MAX_BUNDLE,config[2]);extent(length,1,config[2]);value[field]=take(length);policy.charge(size=length)
            count=number(16,config[2])
            # Every encoded work package must contain at least one item.
            if count==0:
                raise Rejected('limitexceeded') # An empty item sequence is not a work package.
            value['items']=[item(policy) for _ in range(count)]
        return f'{cursor} '+fields(kind,value)
    # Preserve the typed rejection reason and discard all intermediate application data.
    except Rejected as failure:
        return str(failure) # Discard every partial field and progress value on rejection.


# Preserve both JSON and binary identities for every consumed upstream release sample.
def published(kind,profile='tiny'):
    name={'C':'refine_context','I':'work_item','P':'work_package'}[kind]
    folder=ROOT/f'vendor/jamtestvectors/codec/{profile}';pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Reconstruct exact bytes from named JSON only after confirming both immutable source hashes.
    for extension in ('json','bin'):
        path=folder/f'{name}.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    value=from_json(kind,json.loads((folder/f'{name}.json').read_text()))
    assert wire(kind,value)==(folder/f'{name}.bin').read_bytes()
    return value


# Minimal authored inputs keep every protocol family independently testable without published fixture assumptions.
def example(kind):
    # Context fields and prerequisites have their own bounded standalone representation.
    if kind=='C':
        return dict(anchor=bytes([1])*32,anchor_slot=2**32-1,state_root=bytes([2])*32,beefy_root=bytes([3])*32,
            lookup_anchor=bytes([4])*32,lookup_anchor_slot=128,lookup_anchor_state_root=bytes([5])*32,prerequisites=[])
    # Imports use the selected nominal identity and a packed E2 index/selector.
    if kind=='R':
        return dict(kind=0,hash=bytes([9])*32,index=32767)
    # Standalone input commitments retain the full advertised E4 preimage length.
    if kind=='X':
        return dict(hash=bytes([7])*32,len=3)
    # Items retain both gas limits and every manifest element in source order.
    if kind=='I':
        return dict(service=2**32-1,code_hash=bytes([6])*32,refine_gas_limit=1,accumulate_gas_limit=1,export_count=2,
            payload=bytes([1,2,3]),import_segments=[example('R')],extrinsic=[example('X')])
    return dict(auth_code_host=2**32-1,auth_code_hash=bytes([8])*32,context=example('C'),authorization=b'auth',
        authorizer_config=b'config',items=[example('I')])


# Deterministic equivalent native requests carry precomputed independent field/wire/error expectations.
def requests():
    lines,expected=[],[]
    # Retained byte budget applies only to consumed input prefixes, never unrelated suffix data.
    def add_decode(kind,data,config=DEFAULT):
        lines.append(f'D {kind} {config[0]} {config[1]} {config[2]} {token(data)}');expected.append(decode(kind,data,config))
    # Native sources are all explicit named fields; the production decoder cannot create encoder input.
    def add_encode(kind,value,config=DEFAULT,capacity=None):
        capacity=len(wire(kind,value))+5 if capacity is None else capacity
        lines.append(f'E {kind} {config[0]} {config[1]} {config[2]} {capacity} '+fields(kind,value))
        expected.append(encode(kind,value,config,capacity))
    # Published tiny/full JSON must agree byte-for-byte, then every component runs all representative truncations.
    examples=[(kind,example(kind)) for kind in ('C','R','X','I','P')]
    # Both pinned published parameter profiles must reconstruct their complete binary fixtures.
    for profile in ('tiny','full'):
        # Exercise each published standalone and composite family independently.
        for kind in ('C','I','P'):
            examples.append((kind,published(kind,profile)))
    # Published and authored representative inputs get matching encode/decode boundary coverage.
    for kind,value in examples:
        data=wire(kind,value);add_decode(kind,data);add_encode(kind,value)
        # Every missing suffix must reject without a partial successful record or owner.
        for cut in range(len(data)):
            add_decode(kind,data[:cut]) # Every required suffix must be present before successful capture.
        # Compare empty, one-short, exact and spare complete-output capacity.
        for capacity in (0,len(data)-1,len(data),len(data)+7):
            add_encode(kind,value,capacity=capacity) # Whole-source preflight and exact capacity are separate.
        # Serialized byte limits are independent of actual input/output capacity.
        for budget in (0,len(data)-1,len(data)):
            add_decode(kind,data,config=DEFAULT[:2]+(budget,));add_encode(kind,value,config=DEFAULT[:2]+(budget,))
        add_decode(kind,data+b'\xaa\xbb',config=DEFAULT[:2]+(len(data),))
    # Every E2 selector/index value is legal on decode; sample both identities at all width boundaries.
    for identity in (0,1):
        # Separate wire-width transitions from source indices that would steal the selector bit.
        for index in (0,1,127,128,255,256,3071,3072,32767,32768,65535):
            value=example('R');value.update(kind=identity,index=index);add_encode('R',value);add_decode('R',wire('R',value))
    # Advertised input lengths keep all E4 bits even when compact naturals would be shorter.
    for length in (0,127,128,2**24,2**32-1):
        value=example('X');value['len']=length;add_encode('X',value);add_decode('X',wire('X',value))
    # Prerequisites are canonical sets with an eight-entry bound, unlike manifests which preserve duplicates/order.
    for count in (0,1,8,9):
        value=example('C');value['prerequisites']=[bytes([i])*32 for i in range(count)]
        add_encode('C',value);add_decode('C',wire('C',value))
    # Duplicate and reversed prerequisites are distinct canonical set failures.
    for hashes in ([bytes(32)]*2,[bytes([2])*32,bytes([1])*32]):
        value=example('C');value['prerequisites']=hashes;add_encode('C',value);add_decode('C',wire('C',value))
    # Natural-width transitions and all count maxima include their first invalid successor.
    for kind,key,counts in (('I','import_segments',(0,127,128,3072,3073)),('I','extrinsic',(0,127,128,129)),('P','items',(0,1,16,17))):
        # Test each natural-width transition, inclusive maximum and first excessive count.
        for count in counts:
            value=example(kind)
            value[key]=[example('R' if key=='import_segments' else 'X' if key=='extrinsic' else 'I') for _ in range(count)]
            add_encode(kind,value);add_decode(kind,wire(kind,value))
    # Zero/maximum E8 fields cannot overflow aggregate gas; equality with the supplied ceiling must reject.
    for field,ceiling in (('refine_gas_limit',DEFAULT[0]),('accumulate_gas_limit',DEFAULT[1])):
        # Zero and just-below gas values differ from equality/maximal-E8 failures.
        for gas in (0,ceiling-1,ceiling,2**64-1):
            value=example('I');value[field]=gas;add_encode('I',value);add_decode('I',wire('I',value))
        value=example('P');value['items']=[example('I'),example('I')]
        value['items'][0][field]=ceiling-2;value['items'][1][field]=2
        add_encode('P',value);add_decode('P',wire('P',value))
    # Fixed E2 export counts still need the narrower package-wide resource domain.
    for exports in (0,3072,3073,65535):
        value=example('I');value['export_count']=exports;add_encode('I',value);add_decode('I',wire('I',value))
    # Package-wide count maxima reject even when each individual item's counters would pass.
    for key,total in (('import_segments',3073),('extrinsic',129)):
        value=example('P');value['items']=[example('I'),example('I')]
        # Direct roots avoid adding unrelated dependency failures to count tests.
        # Each child remains below the individual export bound while its package total varies.
        for i in range(2):
            count=total//2+(total%2 if i==1 else 0)
            value['items'][i][key]=[example('R' if key=='import_segments' else 'X') for _ in range(count)]
        add_encode('P',value);add_decode('P',wire('P',value))
    value=example('P');value['items']=[example('I'),example('I')]
    # Build independently admissible children whose combined resource cost is tested afterward.
    for item in value['items']:
        item['export_count']=1537 # Two valid individual export counts exceed the total package bound.
    add_encode('P',value);add_decode('P',wire('P',value))
    # Footprint sums count declared preimages and imported-segment proofs, not just inline wire bytes.
    for delta in (-1,0,1):
        value=example('I');value['import_segments']=[];value['payload']=b'';value['extrinsic'][0]['len']=MAX_BUNDLE+delta
        add_encode('I',value);add_decode('I',wire('I',value))
    value=example('P');value['items']=[example('I'),example('I')]
    # Build independently admissible children whose combined resource cost is tested afterward.
    for item in value['items']:
        item['import_segments']=[];item['payload']=b'';item['extrinsic'][0]['len']=MAX_BUNDLE//2
    add_encode('P',value);add_decode('P',wire('P',value))
    # Repeated tagged package hashes share a dependency; direct roots never do, and prerequisites count separately.
    for prerequisites in (0,1,8):
        # Repeated references count once while the ninth distinct package dependency must fail.
        for distinct in (0,1,7,8,9):
            value=example('P');value['context']['prerequisites']=[bytes([i])*32 for i in range(prerequisites)]
            value['items']=[example('I'),example('I')]
            # Shared dependencies are counted across items, not restarted for each child.
            for item in value['items']:
                item['import_segments']=[dict(kind=1,hash=bytes([i])*32,index=i) for i in range(distinct)]*2
            add_encode('P',value);add_decode('P',wire('P',value))
    # Manifest duplicates and reversal remain legal sequence operations, not accidental set normalization.
    value=example('I');value['import_segments']=[dict(kind=1,hash=bytes(32),index=5),dict(kind=0,hash=bytes(32),index=2)]*2
    value['extrinsic']=[example('X')]*2;add_encode('I',value);add_decode('I',wire('I',value))
    # Corrupt every variable count position with overlong and maximal canonical naturals.
    for kind,value,positions in (('C',example('C'),[168]),('I',example('I'),[54,58,93]),('P',example('P'),[204,205,210,217])):
        data=wire(kind,value)
        # Corrupt each known variable count location independently from its enclosing fields.
        for at in positions:
            # Overlong and huge canonical naturals exercise different safe rejection paths.
            for prefix in (b'\x80\x00',natural(2**64-1)):
                add_decode(kind,data[:at]+prefix+data[at+1:])
    # Every serialized budget boundary of a representative complete package is independently exercised.
    value=example('P');data=wire('P',value)
    # Every consumed-byte boundary of the representative package is checked explicitly.
    for budget in range(len(data)+1):
        add_decode('P',data,config=DEFAULT[:2]+(budget,))
    # Maximal E8 configurable ceilings require mathematical aggregate comparisons before any machine addition.
    for key,position in (('refine_gas_limit',0),('accumulate_gas_limit',1)):
        value=example('P');value['items']=[example('I'),example('I')]
        config=list(DEFAULT);config[position]=2**64-1
        # Use two legal individual E8 values whose mathematical sum exceeds the configured ceiling.
        for item in value['items']:
            item[key]=2**63 # Two admissible individual values overflow uint64 when summed naively.
        add_encode('P',value,config=tuple(config));add_decode('P',wire('P',value),config=tuple(config))
    # Import proof footprint plus payload/preimage bytes reaches the exact auditable-bundle boundary.
    for excess in (0,1):
        value=example('I');value['import_segments']=[example('R') for _ in range(3072)]
        value['payload']=bytes(4221+excess)
        add_encode('I',value);add_decode('I',wire('I',value))
    # Equivalent multisource counts must accept the maximum and reject its immediate successor.
    for key,maximum,child in (('import_segments',3072,'R'),('extrinsic',128,'X')):
        # Accept the inclusive cross-item maximum and reject its immediate successor.
        for total in (maximum,maximum+1):
            value=example('P');value['items']=[example('I'),example('I')]
            # Split the requested total into two separately legal child manifests.
            for i in range(2):
                value['items'][i][key]=[example(child) for _ in range(total//2+(total%2 if i else 0))]
            add_encode('P',value);add_decode('P',wire('P',value))
    # Cross-item exports need the same exact-boundary treatment as manifest occurrence counts.
    for total in (3072,3073):
        value=example('P');value['items']=[example('I'),example('I')]
        # Each child remains below the individual export bound while its package total varies.
        for i in range(2):
            value['items'][i]['export_count']=total//2+(total%2 if i else 0)
        add_encode('P',value);add_decode('P',wire('P',value))
    # Invalid chain configurations cannot authorize even a byte read or an encoding capacity check.
    for refine,accumulate in ((0,0),(0,1),(1,0)):
        # Invalid configuration must precede both standalone and composite input/source access.
        for kind in ('I','P'):
            add_decode(kind,b'',config=(refine,accumulate,1000));add_encode(kind,example(kind),config=(refine,accumulate,1000))
    rng=random.Random(0x574f524b5041434b)
    # Structured mutations reach scalar widths, packed selectors, late manifests and context ordering.
    for kind in ('C','R','X','I','P'):
        base=wire(kind,example(kind))
        # Run a deterministic structured mutation workload for each separate codec family.
        for i in range(700):
            data=bytearray(base)
            # Multiple modified fields can reach late framing and aggregate checks together.
            for _ in range(rng.randrange(1,5)):
                data[rng.randrange(len(data))]=rng.randrange(256) # Mutate deterministic independent fixture positions.
            # Some mutated records also lose their suffix to check truncation precedence.
            if i%3==0:
                data=data[:rng.randrange(len(data)+1)] # Missing suffixes combine with structured malformed prefixes.
            add_decode(kind,bytes(data))
        # Arbitrary bytes require safe typed rejection without any valid framing assumption.
        for _ in range(200):
            add_decode(kind,rng.randbytes(rng.randrange(600)))
    return lines,expected
