"""Independent GP v0.7.1 assurances encoding, semantic oracle and frozen matched-task corpus."""
import hashlib
import json
import random
from pathlib import Path
from test_codec import reference_encode as natural, reference_decode

ROOT = Path(__file__).resolve().parents[1]


# Preserve empty native batch fields unambiguously.
def token(data):
    return data.hex() or '-'


# Store every native fixed bitset octet explicitly; unused storage is part of encoder validation.
def logical(records):
    return b''.join(anchor+bits+index.to_bytes(2,'little')+signature for anchor,bits,index,signature in records)


# Evaluate the normative fixed-layout sequence directly with Python integer/byte operations.
def wire(records, cores):
    width = (cores+7)//8
    return natural(len(records))+b''.join(anchor+bits[:width]+index.to_bytes(2,'little')+signature
                                         for anchor,bits,index,signature in records)


# Reject invalid caller configuration before reading attacker-controlled prefixes.
def config_error(cores, validators):
    return 'invalidconfig' if not 1 <= cores <= 341 or not 1 <= validators <= 1023 else None


# Check semantic order/index and all serialized/unused bitset storage without mutating any destination.
def record_error(record, cores, validators, previous):
    _,bits,index,_ = record
    # E2 width alone does not establish membership in the configured validator domain.
    if index >= validators:
        return 'invalidvalidator'
    # Duplicate and descending indices violate the canonical extrinsic ordering.
    if previous is not None and index <= previous:
        return 'noncanonical'
    width = (cores+7)//8
    # Reject both unused final-octet bits and native storage absent from this profile.
    if (cores%8 and bits[width-1] >> (cores%8)) or any(bits[width:]):
        return 'noncanonical'
    return None


# Model the encoder's frozen preflight precedence, including capacity before late-field validation.
def encode(cores, validators, capacity, records):
    error = config_error(cores,validators)
    # No meaningful wire stride exists for an invalid profile.
    if error:
        return error # Invalid configuration has no meaningful record stride.
    # Count policy precedes all output extent and per-record validation.
    if len(records) > validators:
        return 'limitexceeded'
    result = wire(records,cores)
    # An insufficient destination cannot be partially committed.
    if len(result) > capacity:
        return 'outputtoosmall'
    previous = None
    # Validate every record before authorizing a complete result.
    for record in records:
        # A late invalid record cannot allow any earlier header/payload commit.
        error = record_error(record,cores,validators,previous)
        # Preserve the first error in the frozen field-validation precedence.
        if error:
            return error
        previous = record[2]
    return result.hex()


# Parse fixed records with arbitrary-precision arithmetic and independently reconstruct every named value.
def decode(cores, validators, capacity, data):
    error = config_error(cores,validators)
    # Profile errors take precedence even over an absent count header.
    if error:
        return error # Configuration is checked even for an empty/truncated frame.
    header = reference_decode(data)
    # Failed natural decoding provides neither count nor consumed metadata.
    if header in ('truncated','noncanonical'):
        return header
    count,cursor = map(int,header.split())
    # Apply the protocol ceiling before extent, capacity and host conversion.
    if count > validators:
        return 'limitexceeded'
    width = (cores+7)//8
    stride = 98+width
    # Division checks the full fixed payload without a potentially overflowing product.
    if count > (len(data)-cursor)//stride:
        return 'truncated'
    # Complete input still requires enough caller-owned typed storage.
    if count > capacity:
        return 'outputtoosmall'
    records = []
    previous = None
    # Decode named fields independently of all three native representations.
    for _ in range(count):
        # Zero-extension is native metadata storage, not additional wire padding.
        record = (data[cursor:cursor+32],data[cursor+32:cursor+32+width]+bytes(43-width),
                  int.from_bytes(data[cursor+32+width:cursor+34+width],'little'),data[cursor+34+width:cursor+stride])
        error = record_error(record,cores,validators,previous)
        # Preserve the first error in the frozen field-validation precedence.
        if error:
            return error
        records.append(record);previous=record[2];cursor+=stride
    return f'{count} {token(logical(records))} {cursor}'


# Produce a fully owned fixed record, with independent identity/signature bytes and selected availability bits.
def record(index, cores, seed=0):
    bits = bytearray(43)
    for bit in range(cores):
        # Patterned bits expose both bit order and byte-boundary handling in every configured layout.
        if (bit+seed)%3 == 0:
            bits[bit//8] |= 1 << (bit%8)
    return bytes((i+seed)%256 for i in range(32)),bytes(bits),index,bytes((255-i+seed)%256 for i in range(64))


# Verify immutable official JSON/bin pairs and convert their named fields to independent source records.
def official(chain, cores):
    folder = ROOT/f'vendor/jamtestvectors/codec/{chain}'
    pins = json.loads((ROOT/'spec/pins.json').read_text())['vectors']['files']
    # Both published formats must remain byte-for-byte at their pinned hashes.
    for extension in ('json','bin'):
        path=folder/f'assurances_extrinsic.{extension}'
        assert hashlib.sha256(path.read_bytes()).hexdigest()==pins[str(path.relative_to(ROOT))]
    result=[]
    # Reconstruct fields by JSON names rather than decoding the binary with a candidate.
    for value in json.loads((folder/'assurances_extrinsic.json').read_text()):
        bits=bytes.fromhex(value['bitfield'][2:])
        assert len(bits)==(cores+7)//8
        result.append((bytes.fromhex(value['anchor'][2:]),bits+bytes(43-len(bits)),value['validator_index'],
                       bytes.fromhex(value['signature'][2:])))
    assert wire(result,cores)==(folder/'assurances_extrinsic.bin').read_bytes()
    return result


# Freeze equivalent valid/negative/boundary/fuzz requests before the first native candidate begins.
def requests():
    lines,expected=[],[]
    # Decoding must never depend on another candidate's encoder or result representation.
    def add_decode(cores,validators,capacity,data):
        lines.append(f'D {cores} {validators} {capacity} {token(data)}')
        expected.append(decode(cores,validators,capacity,data))
    # Encoding receives all fixed metadata, not a new-codec decode/re-encode input.
    def add_encode(cores,validators,capacity,records):
        lines.append(f'E {cores} {validators} {capacity} {token(logical(records))}')
        expected.append(encode(cores,validators,capacity,records))
    profiles=((2,6),(341,1023))
    # Official tiny and full fixtures use their actual chain profile parameters.
    for chain,(cores,validators) in zip(('tiny','full'),profiles):
        records=official(chain,cores);data=wire(records,cores)
        add_decode(cores,validators,len(records),data)
        add_encode(cores,validators,len(data),records)
    # All meaningful width boundaries include one-byte, aligned and partial final-octet shapes.
    for cores in (1,2,7,8,9,15,16,17,255,256,257,340,341):
        validators=1023 if cores>2 else 6
        # Include empty, singleton and later-record failure opportunities for every width.
        for count in (0,1,2,5):
            records=[record(i,cores,i) for i in range(count)]
            data=wire(records,cores)
            # Capacity on each side of the typed boundary proves decoder precedence.
            for capacity in sorted(set((0,max(0,count-1),count,count+1))):
                add_decode(cores,validators,capacity,data)
            add_decode(cores,validators,count,data+b'\xab\xcd')
            # Byte destinations straddle the complete output extent boundary.
            for capacity in (0,len(data)-1,len(data),len(data)+3):
                add_encode(cores,validators,capacity,records)
            # Nonempty records permit truncation and real alias probes.
            if count:
                # Test every cut through the final record, plus prefix and prior-record boundaries.
                for cut in range(len(data)):
                    add_decode(cores,validators,count,data[:cut])
                lines.extend([f'XE {cores} {validators} {token(logical(records))}',
                              f'XD {cores} {validators} {token(data)}'])
                expected.extend(['aliasedbuffers','aliasedbuffers'])
        # Single-bit cases establish least-significant-first ordering for every configured core.
        for bit in range(cores):
            anchor,_,index,signature=record(0,cores)
            bits=bytearray(43);bits[bit//8]=1 << (bit%8)
            records=[(anchor,bytes(bits),index,signature)]
            add_decode(cores,validators,1,wire(records,cores))
            add_encode(cores,validators,150000,records)
        # Padding failures are explicit both on the wire and in unused native storage octets.
        for position,mask in [((cores+7)//8,1)] + ([(cores//8,1 << (cores%8))] if cores%8 else []):
            # Full-width storage has no omitted octet at index 43 to corrupt.
            if position < 43:
                item=list(record(0,cores));bits=bytearray(item[1]);bits[position]|=mask;item[1]=bytes(bits)
                add_encode(cores,validators,150000,[tuple(item)])
                add_decode(cores,validators,1,wire([tuple(item)],cores))
        # Late invalid indices and duplicate/descending validators must preserve earlier destination records.
        for last in (0,validators,65535):
            records=[record(1,cores),record(last,cores,7)]
            add_decode(cores,validators,2,wire(records,cores))
            add_encode(cores,validators,150000,records)
        records=[record(1,cores),record(1,cores,9)]
        add_decode(cores,validators,2,wire(records,cores));add_encode(cores,validators,150000,records)
    # Exercise every validator index and protocol count boundary without a guessed smaller utility limit.
    for cores,validators in profiles:
        records=[record(i,cores,i) for i in range(validators)]
        data=wire(records,cores)
        add_encode(cores,validators,len(data),records);add_decode(cores,validators,validators,data)
        add_decode(cores,validators,validators-1,data)
        add_encode(cores,validators,150000,records+[record(0,cores)])
        # Oversized announced counts fail before any fixed payload is required.
        for count in (validators+1,2**64-1):
            add_decode(cores,validators,0,natural(count))
        # Missing and overlong natural headers must preserve their distinct failures.
        for prefix in (b'',b'\x80\x00',b'\xff'+bytes(7),b'\xff'+bytes(8)):
            add_decode(cores,validators,0,prefix)
    # Configuration is deliberately tested before malformed counts, for both empty and nonempty source arrays.
    for cores,validators in ((0,6),(342,6),(2,0),(2,1024),(2**64-1,6),(2,2**64-1)):
        add_decode(cores,validators,0,b'\x80\x00');add_encode(cores,validators,0,[])
    rng=random.Random(0x415353555245)
    # Deterministic mutations exercise structured inputs without candidate-generated expectations.
    for i in range(5000):
        cores,validators=profiles[i%2]
        records=[record(index,cores,index) for index in range(rng.randrange(6))]
        data=bytearray(wire(records,cores))
        # Multiple altered positions include both framing and late semantic fields.
        for _ in range(rng.randrange(1,5)):
            data[rng.randrange(len(data))]=rng.randrange(256)
        # Some mutations additionally remove a suffix to mix semantic and extent failures.
        if i%3==0:
            data=data[:rng.randrange(len(data)+1)]
        add_decode(cores,validators,rng.randrange(8),bytes(data))
    # Unstructured bytes ensure fuzz coverage does not depend on a valid initial frame.
    for _ in range(1000):
        add_decode(341,1023,rng.randrange(8),rng.randbytes(rng.randrange(800)))
    return lines,expected
