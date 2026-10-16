"""Independent C.1 collection equations: logical order, pair-count framing and explicit variable-set wrapping."""
import hashlib
import json
import random
from test_codec import reference_encode as natural, reference_decode
from test_support import ROOT

MAX = 2**64-1
SCHEMAS = ('n','0','1','2','3','4','5','6','7','8','b0','b1','b2','b32')
PAIRS = {'nn':('n','n'), '21':('2','1'), 'bn':('b2','n'), 'nb':('n','b2'),
         'zz':('0','0'), 'zn':('b0','n'), 'hh':('b32','b32')}


# Empty frames need a transport token without inventing a wire byte.
def token(data):
    return data.hex() or '-'


# Scalar logical text is independent of native byte order and schema framing.
def scalar_text(schema, value):
    return (value.hex() or 'z') if schema.startswith('b') else str(value)


# Fixed/natural scalar wire equations do not use the production encoder or any owner result.
def scalar_wire(schema, value):
    # Fixed byte strings serialize as themselves, including zero-width values.
    if schema.startswith('b'):
        return value
    # General naturals have their separately verified canonical scalar representation.
    if schema == 'n':
        return natural(value)
    return value.to_bytes(int(schema), 'little')


# Minimum scalar extents bound traversal independently of actual variable-natural representation widths.
def minimum(schema):
    return 1 if schema == 'n' else int(schema.removeprefix('b'))


# Supported value-only schemas have native fixed storage; tests target only unambiguous extreme host-count bounds.
def storage(schema):
    return max(1, int(schema[1:])) if schema.startswith('b') else 8


# Internal oracle errors contain no partial progress or decoded application fields.
class Rejected(Exception):
    pass


# Parse one scalar mathematically, preserving primitive framing errors before parent key ordering.
def scalar_read(schema, data, cursor):
    # Variable naturals must be complete and canonical before yielding a logical value.
    if schema == 'n':
        parsed = reference_decode(data[cursor:])
        # Primitive failures cannot authorize advancing the parent cursor.
        if parsed in ('truncated','noncanonical'):
            raise Rejected(parsed)
        value, size = map(int, parsed.split())
        return value, cursor+size
    size = minimum(schema)
    # Fixed scalars cannot silently consume a short prefix or synthesize missing fields.
    if size > len(data)-cursor:
        raise Rejected('truncated')
    raw = data[cursor:cursor+size]
    return (raw if schema.startswith('b') else int.from_bytes(raw,'little')), cursor+size


# The one dictionary pair count frames key/value tuples; sets add a discriminator only when explicitly variable.
def wire(kind, schema, values):
    # Dictionaries preserve each key/value association and have no extra per-pair count/blob prefix.
    if kind == 'M':
        key, value = PAIRS[schema]
        return natural(len(values))+b''.join(scalar_wire(key,k)+scalar_wire(value,v) for k,v in values)
    return (natural(len(values)) if kind == 'S' else b'')+b''.join(scalar_wire(schema,v) for v in values)


# Observe each logical key/value and exact fixed/variable canonical output independently of native re-emission.
def observed(kind, schema, values, consumed):
    # Dictionary values need not be sorted; tuple text records their original key association.
    if kind == 'M':
        k,v = PAIRS[schema]
        fields = ','.join(scalar_text(k,key)+'/'+scalar_text(v,value) for key,value in values) or '-'
        return f'{consumed} {len(values)} {fields} {token(wire(kind,schema,values))}'
    fields = ','.join(scalar_text(schema,value) for value in values) or '-'
    return f'{consumed} {len(values)} {fields} {token(wire("F",schema,values))} {token(wire("S",schema,values))}'


# Advance exact child bytes against whole-parent resource policy before inspecting another field.
def budget(cursor, maximum):
    # Every count and serialized key/value octet contributes to the same complete-prefix budget.
    if cursor > maximum:
        raise Rejected('limitexceeded')


# Independent prefix decoder uses numeric/byte-string logical ordering, never serialized-byte sorting.
def decode(kind, schema, count, items, maximum, data):
    try:
        cursor = 0
        # Both dictionaries and explicitly variable sets carry one canonical natural cardinality.
        if kind != 'F':
            count,cursor = scalar_read('n',data,0)
        # Count policy precedes any host conversion, minimum-wire multiplication or traversal.
        if count > items:
            raise Rejected('limitexceeded')
        types = PAIRS[schema] if kind == 'M' else (schema,)
        # C ABI tuple layout aligns numeric scalars to eight octets and byte arrays to one on both tested 64-bit hosts.
        stride = 0
        alignment = 1
        # Compute independent typed allocation bounds without assuming wire size equals native scalar storage.
        for schema_type in types:
            align = 1 if schema_type.startswith('b') else 8
            alignment = max(alignment, align)
            stride = (stride+align-1)//align*align+storage(schema_type)
        stride = (stride+alignment-1)//alignment*alignment
        # Counts at uint64 maximum must not narrow to signed host indices or authorize allocation.
        if count > (2**63-1)//stride:
            raise Rejected('lengthoverflow')
        budget(cursor,maximum)
        minimum_size = sum(minimum(t) for t in types)
        # Prove whole minimum payload by division before inspecting any child.
        if minimum_size and count > (len(data)-cursor)//minimum_size:
            raise Rejected('truncated')
        values=[];previous=None
        # All keys are strictly increasing; equality is an error even if dictionary values differ.
        for _ in range(count):
            value,cursor = scalar_read(types[0],data,cursor);budget(cursor,maximum)
            # Compare values in their logical domains: Python integers numerically, bytes lexicographically.
            if previous is not None and not previous < value:
                raise Rejected('noncanonical')
            previous=value
            # Dictionary order never depends on its associated values.
            if kind == 'M':
                child,cursor=scalar_read(types[1],data,cursor);budget(cursor,maximum)
                value=(value,child)
            values.append(value)
        return observed(kind,schema,values,cursor)
    except Rejected as error:
        # Rejected frames expose no initialized fields or successful progress.
        return str(error)


# Reject out-of-range fixed scalar sources before capacity, without narrowing any caller field.
def source_scalar(schema, value):
    # Byte values have an exact trusted schema extent; natural sources span the complete uint64 domain.
    if not schema.startswith('b') and schema != 'n' and value >= 2**(8*int(schema)):
        raise Rejected('valueoutofrange')
    return len(scalar_wire(schema,value))


# Encoder expectation validates complete logical sources before whole output capacity.
def encode(kind, schema, values, count, items, maximum, capacity):
    try:
        # Fixed cardinality is a schema assertion, not permission to truncate the supplied logical source.
        if kind == 'F' and count != len(values):
            raise Rejected('invalidcount')
        # Variable count derives from independently supplied logical source length.
        if len(values)>items:
            raise Rejected('limitexceeded')
        cursor=0 if kind == 'F' else len(natural(len(values)));budget(cursor,maximum)
        types=PAIRS[schema] if kind == 'M' else (schema,)
        previous=None
        # A late value failure must not leave an earlier valid key/prefix committed.
        for value in values:
            key=value[0] if kind == 'M' else value
            cursor+=source_scalar(types[0],key);budget(cursor,maximum)
            # Unsorted/duplicate sources are rejected rather than sorted or overwritten.
            if previous is not None and not previous<key:
                raise Rejected('noncanonical')
            previous=key
            # Associated values retain independent domains and need no ordering constraint.
            if kind == 'M':
                cursor+=source_scalar(types[1],value[1]);budget(cursor,maximum)
        # Only completely valid sources can proceed to destination capacity.
        if cursor>capacity:
            raise Rejected('outputtoosmall')
        return token(wire(kind,schema,values))
    except Rejected as error:
        # Error expectations contain no partial write extent or source values.
        return str(error)


# Normalize explicit numeric samples or fixed-byte identities, including the zero-width singleton domain.
def value(schema, number):
    # Numeric scalar samples remain numeric so their logical order can differ from serialized order.
    if not schema.startswith('b'):
        return number
    return number.to_bytes(minimum(schema),'big')


# Build deterministic independent sources, malformed bytes and resource boundaries across every supported schema family.
def requests():
    lines,expected=[],[]

    # Native decoder inputs come from independent equations or arbitrary bytes, never a native encoder result.
    def dec(kind,schema,data,count=0,items=MAX,maximum=MAX):
        lines.append(f'D {kind} {schema} {count} {items} {maximum} {token(data)}')
        expected.append(decode(kind,schema,count,items,maximum,data))

    # Logical named fields construct native source records independently of any collection decoder.
    def enc(kind,schema,values,count=None,items=MAX,maximum=MAX,capacity=None):
        count=len(values) if count is None else count
        # Range-invalid sources cannot be serialized even by the oracle before source preflight runs.
        if capacity is None:
            capacity=8192
        types=PAIRS[schema] if kind == 'M' else (schema,)
        fields=(','.join(scalar_text(types[0],k)+'/'+scalar_text(types[1],v) for k,v in values) if kind=='M'
                else ','.join(scalar_text(schema,v) for v in values)) or '-'
        lines.append(f'E {kind} {schema} {count} {items} {maximum} {capacity} {fields}')
        expected.append(encode(kind,schema,values,count,items,maximum,capacity))

    examples=[]
    # Every scalar schema exercises both count-free sets and explicitly variable set framing.
    for schema in SCHEMAS:
        numbers=([0] if schema in ('0','b0') else [0,1,2,127,128,254,255])
        # Wider/natural domains include little-endian order inversions and representation-size transitions.
        if schema not in ('0','1','b0','b1'):
            numbers += [256,257,16383,16384,65535]
        # Complete uint64 widths also test the largest logical keys.
        if schema in ('n','8'):
            numbers += [2**32,2**56,MAX]
        values=[value(schema,n) for n in numbers]
        # Empty/singleton/full examples distinguish default owners from validated zero-entry collections.
        for elements in ([],values[:1],values):
            # Fixed and variable set payloads must agree exactly apart from the chosen discriminator.
            for kind in ('F','S'):
                examples.append((kind,schema,elements))
    # Dictionary values deliberately descend or repeat while keys are strictly increasing.
    for schema,(key,val) in PAIRS.items():
        keys=[0] if key in ('0','b0') else [0,1,2,255,256]
        # E1 values stay in range even when a larger numeric key domain is used.
        values=[(value(key,k),value(val,0 if val in ('0','b0') else 7-i)) for i,k in enumerate(keys)]
        examples += [('M',schema,[]),('M',schema,values[:1]),('M',schema,values)]
    # Successful count-prefix transitions use independent distinct keys rather than only hostile missing-payload claims.
    for count in (127,128,129):
        examples.append(('S','n',list(range(count))))
        examples.append(('M','nn',[(i,count-i) for i in range(count)]))
    # Each independent complete sample gets extent, resource, canonical-order and capacity adversaries.
    for kind,schema,values in examples:
        data=wire(kind,schema,values);dec(kind,schema,data+b'\xAA',len(values));enc(kind,schema,values)
        # Empty/exact/one-short/spare destinations establish failure atomicity and preserved suffixes.
        for capacity in sorted({0,max(0,len(data)-1),len(data),len(data)+3}):
            enc(kind,schema,values,capacity=capacity)
        # Every small proper input prefix must fail before ownership, unless fixed zero-width schema makes it complete.
        for cut in range(len(data)):
            dec(kind,schema,data[:cut],len(values))
        # Complete byte budgets include discriminators while caller suffix bytes do not consume them.
        for maximum in sorted({0,max(0,len(data)-1),len(data)}):
            dec(kind,schema,data,len(values),maximum=maximum)
            enc(kind,schema,values,maximum=maximum,capacity=0)
        # Logical item limits are independent of encoded width, including zero-width keys/values.
        for items in sorted({0,max(0,len(values)-1),len(values)}):
            dec(kind,schema,data,len(values),items=items);enc(kind,schema,values,items=items,capacity=0)
        # Source schema mismatch takes precedence over policy and output capacity for fixed sets.
        if kind=='F':
            enc(kind,schema,values,count=len(values)+1,items=0,capacity=0)
        # Duplicate keys reject even when every child is individually canonical.
        if values:
            duplicate=values[:1]+values[:1]
            dec(kind,schema,wire(kind,schema,duplicate),2);enc(kind,schema,duplicate,capacity=0)
        # Descending inputs must not be silently sorted and dictionary associations must not be rebuilt.
        if len(values)>1:
            reverse=list(reversed(values))
            dec(kind,schema,wire(kind,schema,reverse),len(reverse));enc(kind,schema,reverse,capacity=0)
    # Exhaustive byte-key pairs separate strict order from nondecreasing/serialized integer comparison.
    for first in range(256):
        # Neighbors, equality and distant values cover every possible byte as an ordering boundary.
        for second in sorted({0,255,first,max(0,first-1),min(255,first+1)}):
            values=[first,second];raw=wire('S','1',values)
            dec('S','1',raw);enc('S','1',values,capacity=0)
    # Natural collection-count transitions and large zero-width claims must never authorize unbounded iteration/allocation.
    for count in (0,1,2,127,128,16383,16384,2**32,2**56,MAX):
        # Broad versus restrictive item limits distinguish host extent, missing input and policy failures.
        for items in (MAX,0):
            dec('S','n',natural(count),items=items)
            dec('S','0',natural(count),items=items)
            dec('M','zz',natural(count),items=items)
            dec('F','b0',b'',count,items=items)
    # Overlong/incomplete parent and nested natural forms preserve their own canonicality and framing errors.
    for bad in (b'\x80\0',b'\xc0\0\0',b'\xff'+bytes(8),b'\xff'+bytes(7),b'\x80'):
        dec('S','n',bad,items=0);dec('M','nn',bad,items=0)
        dec('S','n',b'\1'+bad);dec('M','nn',b'\1\0'+bad)
    # Fixed-width overflow in a late key/value is checked before any destination capacity or writes.
    for schema in ('0','1','2','3','4','5','6','7'):
        bad=1 if schema=='0' else 2**(8*int(schema))
        enc('S',schema,[0,bad],capacity=0)
    enc('M','zz',[(0,1)],capacity=0)
    enc('M','21',[(0,1),(1,256)],capacity=0)
    enc('M','21',[(0,1),(65536,1)],capacity=0)
    pins=json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Published report prerequisite sets and hash/root lookup dictionaries instantiate the reusable fixed-byte schemas.
    for profile in ('tiny','full'):
        path=ROOT/f'vendor/jamtestvectors/codec/{profile}/work_report.json'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
        report=json.loads(path.read_text())
        keys=[bytes.fromhex(k[2:]) for k in report['context']['prerequisites']]
        # Both pinned report lookup samples are empty; do not infer an unpublished nonempty JSON schema.
        assert report['segment_root_lookup'] == []
        lookup=[]
        dec('S','b32',wire('S','b32',keys));enc('S','b32',keys)
        dec('M','hh',wire('M','hh',lookup));enc('M','hh',lookup)
    rng=random.Random(0x434f4c4c303038)
    # Random malformed inputs mix schemas with different logical ordering and scalar wire extents.
    for _ in range(2500):
        data=rng.randbytes(rng.randrange(128))
        schema=rng.choice(SCHEMAS);kind=rng.choice(('F','S'));count=rng.randrange(20)
        dec(kind,schema,data,count,rng.choice((0,2,32,MAX)),rng.choice((0,16,128,MAX)))
        dec('M',rng.choice(tuple(PAIRS)),data,items=rng.choice((0,2,32,MAX)),maximum=rng.choice((0,16,128,MAX)))
    return lines,expected
