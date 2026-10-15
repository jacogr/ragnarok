from std.collections import Array, Span
from std.utils import Variant
from .types import JamNatural, FixedUnsigned, ByteWidth, Failure, Decoded, CheckedResult, fail


# Fixed local storage keeps primitive encoding allocation-free; only length bytes are wire data.
@fieldwise_init
struct Encoded(Copyable, Movable):
    var bytes: Array[UInt8, 9]
    var length: Int


# GP v0.7.1 C.1.1: emit the shortest natural form, including the full-width ff escape.
def encode_natural(value: JamNatural) -> Encoded:
    var tail = 0
    # Each additional tail byte raises the compact range by seven bits; never shift by 64.
    while tail < 8 and value.value >= (UInt64(1) << UInt64(7 * (tail + 1))):
        tail += 1
    var result = Encoded(Array[UInt8, 9](fill=0), tail + 1)
    # The escape carries all value bits in its eight-byte tail.
    if tail == 8:
        result.bytes[0] = 255
    else:
        # Compact headers retain high value bits below their leading-one size marker.
        result.bytes[0] = UInt8(
            256 - (UInt64(1) << UInt64(8 - tail)) + (value.value >> UInt64(8 * tail))
        )
    # Payload octets are little-endian and every narrowing conversion is masked.
    for i in range(tail):
        result.bytes[i + 1] = UInt8((value.value >> UInt64(8 * i)) & 255)
    return result^


# Decode a borrowed prefix without allocation; failures contain neither value nor consumed extent.
def decode_natural(data: Span[mut=False, UInt8, _]) -> CheckedResult[Decoded[JamNatural]]:
    comptime Result = CheckedResult[Decoded[JamNatural]]
    # Zero requires a header too, so empty input is incomplete.
    if len(data) == 0:
        return Result(fail["truncated"]())
    var tail = 0
    var mask = 128
    # Count announced tail octets before looking at any payload byte.
    while tail < 8 and (Int(data[0]) & mask) != 0:
        tail += 1
        mask >>= 1
    # Prove the complete representation is present before indexing it.
    if len(data) < tail + 1:
        return Result(fail["truncated"]())
    var value: UInt64 = 0
    # The ff form has no residual header bits.
    if tail < 8:
        value = UInt64(Int(data[0]) & (mask - 1)) << UInt64(8 * tail)
    # Merge only bounded octets with shifts at most 56.
    for i in range(tail):
        value |= UInt64(data[i + 1]) << UInt64(8 * i)
    # Reject overlong forms rather than accepting multiple encodings of the same value.
    if tail > 0 and value < (UInt64(1) << UInt64(7 * tail)):
        return Result(fail["noncanonical"]())
    return Result(Decoded(JamNatural(value), tail + 1))


# GP C.1.7: preflight the width/value before producing owned little-endian storage.
def encode_fixed(value: FixedUnsigned, width: ByteWidth) -> CheckedResult[Encoded]:
    comptime Result = CheckedResult[Encoded]
    var n = width.value
    # Signed width validation precedes shifts and loop bounds, even for zero values.
    if n < 0 or n > 8:
        return Result(fail["invalidwidth"]())
    # Width zero permits only zero; eight-byte values bypass the unrepresentable 2^64 bound.
    if n < 8 and value.value >= (UInt64(1) << UInt64(8 * n)):
        return Result(fail["outofrange"]())
    var result = Encoded(Array[UInt8, 9](fill=0), n)
    # An empty loop implements the specified zero-width encoding.
    for i in range(n):
        result.bytes[i] = UInt8((value.value >> UInt64(8 * i)) & 255)
    return Result(result^)


# Decode exactly the requested fixed prefix; trailing bytes stay in the caller's borrowed span.
def decode_fixed(
    data: Span[mut=False, UInt8, _], width: ByteWidth
) -> CheckedResult[Decoded[FixedUnsigned]]:
    comptime Result = CheckedResult[Decoded[FixedUnsigned]]
    var n = width.value
    # Invalid widths take precedence over missing input.
    if n < 0 or n > 8:
        return Result(fail["invalidwidth"]())
    # Do not partially read an incomplete fixed field.
    if len(data) < n:
        return Result(fail["truncated"]())
    var value: UInt64 = 0
    # All full-width bit patterns are valid unsigned values; width zero remains zero.
    for i in range(n):
        value |= UInt64(data[i]) << UInt64(8 * i)
    return Result(Decoded(FixedUnsigned(value), n))
