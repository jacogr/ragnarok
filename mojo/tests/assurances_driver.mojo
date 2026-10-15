from std.collections import Array, Span
from std.sys import argv, size_of
from codec.types import *
from codec.bounded import SequenceInfo
from codec.assurances import *
from tests.support import unsigned, capacity, hex_text, unchanged


# Trusted adapter failures must abort rather than masquerade as protocol rejections.
def require(good: Bool) raises:
    if not good:
        # An assertion failure is a test defect or a violated production invariant.
        raise Error("assurances adapter invariant")


# Parse large but bounded test tokens independently from any production codec.
def unhex(text: String) raises -> List[UInt8]:
    var result = List[UInt8]()
    # Dash preserves an empty token in the line protocol.
    if text == "-":
        return result^
    var chars = text.as_bytes()
    require(len(chars) % 2 == 0 and len(chars) <= 300000)
    # Validate every nibble before extending trusted test storage.
    for i in range(len(chars) // 2):
        var value = 0
        for j in range(2):
            # Only lowercase hexadecimal is admitted by this test protocol.
            var c = Int(chars[2 * i + j])
            var digit = c - 48
            if c >= 97 and c <= 102:
                # Map lowercase letters after decimal digits.
                digit = c - 87
            else:
                # Other alphabets must not reach the native decoder.
                require(c >= 48 and c <= 57)
            value = value * 16 + digit
        result.append(UInt8(value))
    return result^


# Every member is initialized explicitly, including the unused native bitset storage.
def sentinel() -> Assurance:
    return Assurance(
        AssuranceAnchor(Array[UInt8, 32](fill=77)),
        AssuranceBits(Array[UInt8, 43](fill=77)),
        ValidatorIndex(77),
        AssuranceSignature(Array[UInt8, 64](fill=77)),
    )


# Construct source records by named fields, independently of the new wire decoder.
def records(data: Span[mut=False, UInt8, _]) raises -> List[Assurance]:
    require(len(data) % 141 == 0)
    var result = List[Assurance]()
    # Logical test storage always contains the entire fixed bitset, regardless of wire profile.
    for i in range(len(data) // 141):
        var value = sentinel()
        var start = i * 141
        for j in range(32):
            # Anchors and signatures are distinct domains even in trusted construction.
            value.anchor.bytes[j] = data[start + j]
        for j in range(43):
            # Explicit unused octets exercise encoder rejection rather than silent dropping.
            value.bits.bytes[j] = data[start + 32 + j]
        value.validator = ValidatorIndex(
            UInt16(data[start + 75]) | (UInt16(data[start + 76]) << UInt16(8))
        )
        for j in range(64):
            # Signatures remain opaque fixed identity bytes.
            value.signature.bytes[j] = data[start + 77 + j]
        result.append(value^)
    return result^


# Render actual named fields, never the production encoder's reconstruction of them.
def logical(values: Span[mut=False, Assurance, _]) -> List[UInt8]:
    var result = List[UInt8]()
    # Canonical logical test order is independent of native padding and wire width.
    for i in range(len(values)):
        for j in range(32):
            # Read the declared anchor field.
            result.append(values[i].anchor.bytes[j])
        for j in range(43):
            # Preserve all native storage octets for padding and ownership assertions.
            result.append(values[i].bits.bytes[j])
        result.append(UInt8(values[i].validator.value & 255))
        result.append(UInt8(values[i].validator.value >> UInt16(8)))
        for j in range(64):
            # Read the declared signature field.
            result.append(values[i].signature.bytes[j])
    return result^


# Compare all bytes in a test snapshot, including raw native padding for overlap failures.
def equal(a: Span[mut=False, UInt8, _], b: Span[mut=False, UInt8, _]) raises:
    require(len(a) == len(b))
    # Compare every byte rather than a checksum or a successful prefix only.
    for i in range(len(a)):
        require(a[i] == b[i])


# Process one equivalent request and assert failure atomicity plus successful field ownership.
def request(p: List[String]) raises:
    var config = AssuranceConfig(CoreCount(unsigned(p[1])), ValidatorCount(unsigned(p[2])))
    # Encoder inputs are independently constructed typed fields.
    if p[0] == "E":
        var bytes = unhex(p[4])
        var values = records(Span(bytes))
        var cap = capacity(p[3], 150000)
        var output = List[UInt8](length=cap + 3, fill=77)
        var encoded = encode_assurances(Span(values), config, Span(output)[:cap])
        if encoded.isa[Failure]():
            # Late errors must preserve both active output and its trailing sentinel.
            unchanged(Span(output))
            print(encoded[Failure].reason())
        else:
            # Verify the encoder never writes beyond its declared success extent.
            var written = encoded[Written].written
            unchanged(Span(output)[written:])
            print(hex_text(Span(output)[:written]))
    elif p[0] == "D":
        # Decode into initialized typed capacity with two untouched trailing records.
        var data = unhex(p[4])
        var saved = data.copy()
        var cap = capacity(p[3], 1024)
        var output = List[Assurance]()
        for i in range(cap + 2):
            # Explicit initialization makes full failure atomicity observable.
            output.append(sentinel())
        var before = logical(Span(output))
        var decoded = decode_assurances(Span(data), config, Span(output)[:cap])
        if decoded.isa[Failure]():
            # Check the entire destination after every malformed request.
            var after = logical(Span(output))
            equal(Span(before), Span(after))
            print(decoded[Failure].reason())
        else:
            # Erase the backing input before examining owned decoded values.
            var info = decoded[SequenceInfo]
            for i in range(len(data)):
                data[i] = 0
            var tail = logical(Span(output)[info.count :])
            equal(Span(tail), Span(before)[141 * info.count :])
            var bytes = logical(Span(output)[: info.count])
            var encoded = List[UInt8](length=info.consumed, fill=77)
            var check = encode_assurances(Span(output)[: info.count], config, Span(encoded))
            require(check.isa[Written]() and check[Written].written == info.consumed)
            equal(Span(encoded), Span(saved)[: info.consumed])
            print(String(info.count) + " " + hex_text(Span(bytes)) + " " + String(info.consumed))
    else:
        # Deliberately bypass borrow provenance only in trusted overlap tests.
        var data = unhex(p[3])
        var values = List[Assurance]()
        if p[0] == "XE":
            # Reserve one extra typed record for the encoded count prefix.
            values = records(Span(data))
        else:
            # Typed allocation gives the aliased decode destination proper alignment.
            require(p[0] == "XD")
            for i in range(len(data) // 99 + 2):
                values.append(sentinel())
        var count = len(values)
        values.append(sentinel())
        var raw = Span(
            unsafe_ptr=values.unsafe_ptr().unsafe_bitcast[UInt8]().as_unsafe_any_origin(),
            length=len(values) * size_of[Assurance](),
        )
        if p[0] == "XD":
            # Place an external wire image over the aligned output allocation.
            raw[: len(data)].copy_from(Span(data))
        var saved = List[UInt8]()
        for i in range(len(raw)):
            # Raw snapshots detect writes to padding as well as declared fields.
            saved.append(raw[i])
        if p[0] == "XE":
            var encoded = encode_assurances(Span(values)[:count], config, raw)
            require(encoded.isa[Failure]())
            print(encoded[Failure].reason())
        else:
            # The source view aliases exactly the typed output allocation.
            var decoded = decode_assurances(raw[: len(data)], config, Span(values))
            require(decoded.isa[Failure]())
            print(decoded[Failure].reason())
        equal(raw, Span(saved))


# Read frozen requests in one native process; no Python runtime participates in codec execution.
def main() raises:
    var args = argv()
    require(len(args) == 2)
    var text = String()
    with open(args[1], "r") as file:
        # The harness writes a bounded, trusted batch file.
        text = file.read()
    var lines = text.split("\n")
    for i in range(len(lines)):
        # A final newline must not introduce a spurious empty request.
        var line = String(lines[i])
        if line.byte_length() == 0:
            continue
        var parts = line.split(" ")
        var p = List[String]()
        for j in range(len(parts)):
            # Tokens own their text through each synchronous call.
            p.append(String(parts[j]))
        require(len(p) == 4 or len(p) == 5)
        request(p^)
