from std.sys import size_of
from std.collections import Span
from std.utils import Variant
from .types import *
from .scalar import encode_natural, decode_natural, encode_fixed, decode_fixed, Encoded


# Internal validated length-prefix proof; unsigned count is narrowed only after a storage proof.
@fieldwise_init
struct Frame(Copyable, Movable):
    var count: UInt64
    var offset: Int
    var consumed: Int


# Completed typed sequence selects only the initialized output prefix.
@fieldwise_init
struct SequenceInfo(Copyable, Movable):
    var count: Int
    var consumed: Int


# Compare address distances instead of overflowing pointer-end sums; empty buffers never alias.
def overlaps(a: UInt, alen: Int, b: UInt, blen: Int) -> Bool:
    # Empty spans borrow no bytes and may have null pointers.
    if alen == 0 or blen == 0:
        return False
    # Measure from whichever address comes first, avoiding endpoint addition.
    if a <= b:
        return b - a < UInt(alen)
    else:
        return a - b < UInt(blen)


# Validate canonical count, caller ceiling and complete fixed-stride payload in that order.
def read_frame(data: Span[mut=False, UInt8, _], stride: Int, limit: UInt64) -> CheckedResult[Frame]:
    var prefix = decode_natural(data)
    # Failed naturals have no count or cursor that can be used by the enclosing decoder.
    if prefix.isa[Failure]():
        return CheckedResult[Frame](prefix[Failure].copy())
    var parsed = prefix[Decoded[JamNatural]].copy()
    var count = parsed.value.value
    # Apply the policy in UInt64 before a host-size conversion or product.
    if count > limit:
        return CheckedResult[Frame](fail["limitexceeded"]())
    var remaining = len(data) - parsed.consumed
    # Division proves the product fits both input and host indexing; zero-width elements need no bytes.
    if stride > 0 and count > UInt64(remaining // stride):
        return CheckedResult[Frame](fail["truncated"]())
    var payload = 0
    # Only a positive-stride proof permits narrowing here.
    if stride > 0:
        payload = Int(count) * stride
    return CheckedResult[Frame](Frame(count, parsed.consumed, parsed.consumed + payload))


# Return borrowed coordinates for a bounded blob, retaining no owner or writable pointer.
def decode_bytes_borrowed(
    data: Span[mut=False, UInt8, _], limit: ByteLimit
) -> CheckedResult[Decoded[BlobSpan]]:
    var frame = read_frame(data, 1, limit.value)
    # Failure carries only its validated reason, never detached coordinates.
    if frame.isa[Failure]():
        return CheckedResult[Decoded[BlobSpan]](frame[Failure].copy())
    var value = frame[Frame].copy()
    return CheckedResult[Decoded[BlobSpan]](
        Decoded(BlobSpan(value.offset, Int(value.count)), value.consumed)
    )


# Emit a bounded blob atomically into separate caller storage after preflighting extent and aliasing.
def encode_bytes(
    value: Span[mut=False, UInt8, _], limit: ByteLimit, output: Span[mut=True, UInt8, _]
) -> WriteResult:
    # Reject policy failures before touching even the length header.
    if UInt64(len(value)) > limit.value:
        return WriteResult(fail["limitexceeded"]())
    var prefix = encode_natural(JamNatural(UInt64(len(value))))
    # Subtraction proves the sum fits without overflowing it.
    if len(output) < prefix.length or len(value) > len(output) - prefix.length:
        return WriteResult(fail["outputtoosmall"]())
    var total = prefix.length + len(value)
    # Reject overlapping borrowed payload and destination before committing any bytes.
    if overlaps(UInt(value.unsafe_ptr()), len(value), UInt(output.unsafe_ptr()), total):
        return WriteResult(fail["aliasedbuffers"]())
    # Commit the canonical length only after all checks pass.
    for i in range(prefix.length):
        output[i] = prefix.bytes[i]
    # Copy only the caller's borrowed payload, never its trailing storage.
    for i in range(len(value)):
        output[prefix.length + i] = value[i]
    return WriteResult(Written(total))


# Encode homogeneous fixed unsigned values; every element is preflighted before the first output write.
def encode_sequence(
    values: Span[mut=False, FixedUnsigned, _],
    width: ByteWidth,
    limit: ElementLimit,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    var stride = width.value
    # Unsupported widths fail even for an empty sequence.
    if stride < 0 or stride > 8:
        return WriteResult(fail["invalidwidth"]())
    # Element ceilings apply independently of a possibly zero-width wire payload.
    if UInt64(len(values)) > limit.value:
        return WriteResult(fail["limitexceeded"]())
    var prefix = encode_natural(JamNatural(UInt64(len(values))))
    # Bound the product through destination capacity before multiplication.
    if len(output) < prefix.length or (
        stride > 0 and len(values) > (len(output) - prefix.length) // stride
    ):
        return WriteResult(fail["outputtoosmall"]())
    var total = prefix.length + len(values) * stride
    # Guard the typed byte extent before constructing the overlap check.
    if len(values) > Int.MAX // size_of[FixedUnsigned]():
        return WriteResult(fail["lengthoverflow"]())
    # Protect descriptor storage from aliasing too, including width-zero inputs.
    if overlaps(
        UInt(values.unsafe_ptr()),
        len(values) * size_of[FixedUnsigned](),
        UInt(output.unsafe_ptr()),
        total,
    ):
        return WriteResult(fail["aliasedbuffers"]())
    # A late out-of-range value must leave earlier destination bytes unchanged.
    for i in range(len(values)):
        var item = encode_fixed(values[i], width)
        # Width is proved valid, so preserve only the value-range failure name for containers.
        if item.isa[Failure]():
            return WriteResult(fail["valueoutofrange"]())
    # Commit the outer count once all values have passed preflight.
    for i in range(prefix.length):
        output[i] = prefix.bytes[i]
    # Each encoding has already been proved valid and every target byte lies in total.
    for index in range(len(values)):
        var item = encode_fixed(values[index], width)
        # Checked extraction follows the successful preflight of these stable borrowed values.
        var encoded = item[Encoded].copy()
        for i in range(stride):
            output[prefix.length + index * stride + i] = encoded.bytes[i]
    return WriteResult(Written(total))


# Decode into caller-owned typed storage only after the full frame, capacity and alias checks succeed.
def decode_sequence(
    data: Span[mut=False, UInt8, _],
    width: ByteWidth,
    limit: ElementLimit,
    output: Span[mut=True, FixedUnsigned, _],
) -> CheckedResult[SequenceInfo]:
    comptime Result = CheckedResult[SequenceInfo]
    var stride = width.value
    # Validate signed widths before any input access.
    if stride < 0 or stride > 8:
        return Result(fail["invalidwidth"]())
    var checked = read_frame(data, stride, limit.value)
    # Invalid prefix/limit/payload must preserve the entire output sentinel.
    if checked.isa[Failure]():
        return Result(checked[Failure].copy())
    var frame = checked[Frame].copy()
    # Capacity also proves a width-zero count is representable on the host.
    if frame.count > UInt64(len(output)):
        return Result(fail["outputtoosmall"]())
    # Typed storage byte extent must fit before the overlap product.
    if frame.count > UInt64(Int.MAX // size_of[FixedUnsigned]()):
        return Result(fail["lengthoverflow"]())
    var count = Int(frame.count)
    # Protect all borrowed input, including its unused trailing fields.
    if overlaps(
        UInt(data.unsafe_ptr()),
        len(data),
        UInt(output.unsafe_ptr()),
        count * size_of[FixedUnsigned](),
    ):
        return Result(fail["aliasedbuffers"]())
    # Full frame proof means fixed-field reads cannot fail during this commit pass.
    for i in range(count):
        var start = frame.offset + i * stride
        var item = decode_fixed(data[start : start + stride], width)
        output[i] = item[Decoded[FixedUnsigned]].value.copy()
    return Result(SequenceInfo(count, frame.consumed))
