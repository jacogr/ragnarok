from std.collections import Array, Span
from std.utils import Variant
from .types import *
from .scalar import *
from .bounded import overlaps
from .composite import *


# Nominal fixed hashes own their bytes; code and payload specializations cannot be interchanged.
@fieldwise_init
struct DigestHash[kind: Int](Copyable, Movable):
    var bytes: Array[UInt8, 32]


comptime CodeHash = DigestHash[0]
comptime PayloadHash = DigestHash[1]


# Five refinement metrics retain distinct domains in their normative C.2 order.
@fieldwise_init
struct RefineLoad(Copyable, Movable):
    var gas_used: Gas
    var imports: ImportCount
    var extrinsic_count: ExtrinsicCount
    var extrinsic_size: ExtrinsicBytes
    var exports: ExportCount


# Complete C.2 digest owns its fixed fields; a successful output span explicitly borrows its input/pool.
@fieldwise_init
struct WorkDigest(Copyable, Movable):
    var service: ServiceIndex
    var code_hash: CodeHash
    var payload_hash: PayloadHash
    var accumulate_gas: Gas
    var output: WorkOutput
    var refine: RefineLoad


# Gather metrics locally without allowing their public nominal types to be swapped by callers.
def metrics(value: RefineLoad) -> Array[UInt64, 5]:
    var result: Array[UInt64, 5] = [
        value.gas_used.value,
        value.imports.value,
        value.extrinsic_count.value,
        value.extrinsic_size.value,
        value.exports.value,
    ]
    return result^


# Encode the full fixed/work/metrics tuple after proving the entire output extent and borrowed pool.
def encode_digest_borrowed(
    var value: WorkDigest,
    pool: Span[mut=False, UInt8, _],
    limit: ByteLimit,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    var work = measure_work(value.output.copy(), len(pool), limit)
    # Invalid work spans or discriminators must not commit any earlier fixed field.
    if work.isa[Failure]():
        return work^
    var required = 76
    var work_size = work[Written].written
    # Prove the work addition before constructing a host extent.
    if work_size > Int.MAX - required:
        return WriteResult(fail["lengthoverflow"]())
    required += work_size
    var numbers = metrics(value.refine)
    # Each bounded natural adds at most nine bytes, but check every host addition explicitly.
    for i in range(5):
        var encoded = encode_natural(JamNatural(numbers[i]))
        # A representability failure produces no partially encoded digest.
        if required > Int.MAX - encoded.length:
            return WriteResult(fail["lengthoverflow"]())
        required += encoded.length
    # Capacity includes the final metric before the first write.
    if len(output) < required:
        return WriteResult(fail["outputtoosmall"]())
    # Error outputs borrow no pool; successful outputs protect the entire retained pool.
    if value.output.isa[BlobSpan]() and overlaps(
        UInt(pool.unsafe_ptr()), len(pool), UInt(output.unsafe_ptr()), required
    ):
        return WriteResult(fail["aliasedbuffers"]())
    var service = encode_fixed(FixedUnsigned(UInt64(value.service.value)), ByteWidth(4))
    var gas = encode_fixed(FixedUnsigned(value.accumulate_gas.value), ByteWidth(8))
    # Commit the service in fixed little-endian wire order.
    for i in range(4):
        output[i] = service[Encoded].bytes[i]
    # Hashes retain identity byte encoding, without reversal or implicit hashing.
    for i in range(32):
        output[4 + i] = value.code_hash.bytes[i]
        output[36 + i] = value.payload_hash.bytes[i]
    # Accumulation gas uses E8, unlike refinement gas below.
    for i in range(8):
        output[68 + i] = gas[Encoded].bytes[i]
    _ = encode_work_borrowed(value.output.copy(), pool, limit, output[76 : 76 + work_size])
    var cursor = 76 + work_size
    # Commit all five preflighted canonical naturals in their normative order.
    for index in range(5):
        var encoded = encode_natural(JamNatural(numbers[index]))
        # Every target byte belongs to the checked total extent.
        for i in range(encoded.length):
            output[cursor + i] = encoded.bytes[i]
        cursor += encoded.length
    return WriteResult(Written(required))


# Decode one complete digest prefix; all fixed values are owned and successful spans refer to original input.
def decode_digest_borrowed(
    data: Span[mut=False, UInt8, _], limit: ByteLimit
) -> CheckedResult[Decoded[WorkDigest]]:
    comptime Result = CheckedResult[Decoded[WorkDigest]]
    # Require the fixed prefix before accessing any hash or integer field.
    if len(data) < 76:
        return Result(fail["truncated"]())
    var work = decode_work_borrowed(data[76:], limit)
    # An invalid output leaves no digest or consumed metadata.
    if work.isa[Failure]():
        return Result(work[Failure].copy())
    var parsed_work = work[Decoded[WorkOutput]].copy()
    var cursor = 76 + parsed_work.consumed
    var numbers = Array[UInt64, 5](fill=0)
    # Every suffix natural, including the last, must be present and canonical.
    for i in range(5):
        var number = decode_natural(data[cursor:])
        # Preserve the exact nested failure rather than constructing a partial digest.
        if number.isa[Failure]():
            return Result(number[Failure].copy())
        var parsed = number[Decoded[JamNatural]].copy()
        numbers[i] = parsed.value.value
        cursor += parsed.consumed
    var service = decode_fixed(data[:4], ByteWidth(4))
    var gas = decode_fixed(data[68:76], ByteWidth(8))
    var code = Array[UInt8, 32](fill=0)
    var payload = Array[UInt8, 32](fill=0)
    # Copy only complete fixed hashes into owned value storage.
    for i in range(32):
        code[i] = data[4 + i]
        payload[i] = data[36 + i]
    # Rebase the successful work span to the enclosing original wire buffer.
    if parsed_work.value.isa[BlobSpan]():
        parsed_work.value[BlobSpan].offset += 76
    var value = WorkDigest(
        ServiceIndex(UInt32(service[Decoded[FixedUnsigned]].value.value)),
        CodeHash(code^),
        PayloadHash(payload^),
        Gas(gas[Decoded[FixedUnsigned]].value.value),
        parsed_work.value.copy(),
        RefineLoad(
            Gas(numbers[0]),
            ImportCount(numbers[1]),
            ExtrinsicCount(numbers[2]),
            ExtrinsicBytes(numbers[3]),
            ExportCount(numbers[4]),
        ),
    )
    return Result(Decoded(value^, cursor))
