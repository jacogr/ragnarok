from std.collections import Array, Span
from std.sys import size_of
from .types import *
from .scalar import encode_natural
from .bounded import read_frame, overlaps, SequenceInfo


# Fixed identity domains own their bytes; anchor and signature cannot be interchanged.
@fieldwise_init
struct AssuranceBytes[kind: Int, length: Int](Copyable, Movable):
    var bytes: Array[UInt8, Self.length]


comptime AssuranceAnchor = AssuranceBytes[0, 32]
comptime AssuranceBits = AssuranceBytes[1, 43]
comptime AssuranceSignature = AssuranceBytes[2, 64]
comptime CoreCount = Quantity[9]
comptime ValidatorCount = Quantity[10]


# Validator identity retains its two-byte domain independently from configuration counts.
@fieldwise_init
struct ValidatorIndex(Copyable, Movable):
    var value: UInt16


# Explicit resource configuration is validated before touching external input.
@fieldwise_init
struct AssuranceConfig(Copyable, Movable):
    var cores: CoreCount
    var validators: ValidatorCount


# An entirely owned, allocation-free record has no pointer back into the input buffer.
@fieldwise_init
struct Assurance(Copyable, Movable):
    var anchor: AssuranceAnchor
    var bits: AssuranceBits
    var validator: ValidatorIndex
    var signature: AssuranceSignature


# Configuration bounds also prove all following fixed wire arithmetic is small.
def valid_config(config: AssuranceConfig) -> Bool:
    return (
        config.cores.value >= 1
        and config.cores.value <= 341
        and config.validators.value >= 1
        and config.validators.value <= 1023
    )


# Validate padding and validator order without writing output; previous=-1 denotes the first record.
def assurance_error(value: Assurance, config: AssuranceConfig, previous: Int) -> Failure:
    # Validator membership in the configured index domain precedes ordering and padding checks.
    if UInt64(value.validator.value) >= config.validators.value:
        return fail["invalidvalidator"]()
    # Unique ascending indices are the canonical extrinsic ordering.
    if Int(value.validator.value) <= previous:
        return fail["noncanonical"]()
    var width = (Int(config.cores.value) + 7) // 8
    var remainder = Int(config.cores.value) % 8
    # A partial final byte must not introduce availability for nonexistent cores.
    if remainder != 0 and (Int(value.bits.bytes[width - 1]) >> remainder) != 0:
        return fail["noncanonical"]()
    # Encoder-owned storage outside the selected profile must not be silently discarded.
    for i in range(width, 43):
        if value.bits.bytes[i] != 0:
            # This is a canonicality failure even though these bytes are absent from the wire.
            return fail["noncanonical"]()
    return Failure(-1)


# Copy one already extent-proved wire record into independent fixed fields, zero-extending native bits.
def read_assurance(data: Span[mut=False, UInt8, _], start: Int, width: Int) -> Assurance:
    var anchor = Array[UInt8, 32](fill=0)
    var bits = Array[UInt8, 43](fill=0)
    var signature = Array[UInt8, 64](fill=0)
    # Identity bytes do not undergo numeric reinterpretation.
    for i in range(32):
        anchor[i] = data[start + i]
    # Only profile bitfield bytes exist in this wire record.
    for i in range(width):
        bits[i] = data[start + 32 + i]
    var position = start + 32 + width
    var index = UInt16(data[position]) | (UInt16(data[position + 1]) << UInt16(8))
    # Signature bytes remain opaque to this structural codec.
    for i in range(64):
        signature[i] = data[position + 2 + i]
    return Assurance(
        AssuranceAnchor(anchor^),
        AssuranceBits(bits^),
        ValidatorIndex(index),
        AssuranceSignature(signature^),
    )


# Preflight all records before committing any byte; borrowed sources must stay stable through the call.
def encode_assurances(
    values: Span[mut=False, Assurance, _], config: AssuranceConfig, output: Span[mut=True, UInt8, _]
) -> WriteResult:
    # Configuration failures have precedence even for an empty sequence.
    if not valid_config(config):
        return WriteResult(fail["invalidconfig"]())
    # The protocol count ceiling applies before destination capacity.
    if UInt64(len(values)) > config.validators.value:
        return WriteResult(fail["limitexceeded"]())
    var width = (Int(config.cores.value) + 7) // 8
    var stride = 98 + width
    var prefix = encode_natural(JamNatural(UInt64(len(values))))
    # Division proves the complete output product without overflowing host arithmetic.
    if len(output) < prefix.length or len(values) > (len(output) - prefix.length) // stride:
        return WriteResult(fail["outputtoosmall"]())
    var total = prefix.length + len(values) * stride
    # Check typed byte extent before computing source/output overlap.
    if len(values) > Int.MAX // size_of[Assurance]():
        return WriteResult(fail["lengthoverflow"]())
    # Protect source metadata, even when it would otherwise be overwritten by its own output.
    if overlaps(
        UInt(values.unsafe_ptr()),
        len(values) * size_of[Assurance](),
        UInt(output.unsafe_ptr()),
        total,
    ):
        return WriteResult(fail["aliasedbuffers"]())
    var previous = -1
    # A failure in the final record leaves the whole caller destination untouched.
    for i in range(len(values)):
        var error = assurance_error(values[i], config, previous)
        if error._code != -1:
            # Failure returns only its reason, never partial written metadata.
            return WriteResult(error^)
        previous = Int(values[i].validator.value)
    # Only fully validated input reaches the commit phase.
    for i in range(prefix.length):
        output[i] = prefix.bytes[i]
    # Field copies are bounded by the complete extent proof and preserve wire identity.
    for i in range(len(values)):
        var start = prefix.length + i * stride
        for j in range(32):
            # Emit the anchor in its declared byte order.
            output[start + j] = values[i].anchor.bytes[j]
        for j in range(width):
            # Fixed bitfields carry neither a count nor native storage padding.
            output[start + 32 + j] = values[i].bits.bytes[j]
        var position = start + 32 + width
        output[position] = UInt8(values[i].validator.value & 255)
        output[position + 1] = UInt8(values[i].validator.value >> UInt16(8))
        for j in range(64):
            # Cryptographic verification belongs to a separate context-aware layer.
            output[position + 2 + j] = values[i].signature.bytes[j]
    return WriteResult(Written(total))


# Decode a prefix into caller-owned records with an atomic two-pass validation/commit contract.
def decode_assurances(
    data: Span[mut=False, UInt8, _], config: AssuranceConfig, output: Span[mut=True, Assurance, _]
) -> CheckedResult[SequenceInfo]:
    comptime Result = CheckedResult[SequenceInfo]
    # Invalid configuration cannot be masked by malformed input.
    if not valid_config(config):
        return Result(fail["invalidconfig"]())
    var width = (Int(config.cores.value) + 7) // 8
    var checked = read_frame(data, 98 + width, config.validators.value)
    # Frame proof validates count, ceiling and complete wire extent in that order.
    if checked.isa[Failure]():
        return Result(checked[Failure])
    from .bounded import Frame

    var frame = checked[Frame]
    # Typed capacity failures precede semantic record validation.
    if frame.count > UInt64(len(output)):
        return Result(fail["outputtoosmall"]())
    # Storage multiplication must be checked even though the protocol limit is small.
    if frame.count > UInt64(Int.MAX // size_of[Assurance]()):
        return Result(fail["lengthoverflow"]())
    var count = Int(frame.count)
    # Protect the whole input including trailing fields against typed output overlap.
    if overlaps(
        UInt(data.unsafe_ptr()), len(data), UInt(output.unsafe_ptr()), count * size_of[Assurance]()
    ):
        return Result(fail["aliasedbuffers"]())
    var previous = -1
    # Validate every field before changing even the first destination record.
    for i in range(count):
        var value = read_assurance(data, frame.offset + i * (98 + width), width)
        var error = assurance_error(value, config, previous)
        if error._code != -1:
            # No value or progress can escape a failed result alternative.
            return Result(error^)
        previous = Int(value.validator.value)
    # Stable disjoint input makes the second pass a bounded infallible copy.
    for i in range(count):
        output[i] = read_assurance(data, frame.offset + i * (98 + width), width)
    return Result(SequenceInfo(count, frame.consumed))
