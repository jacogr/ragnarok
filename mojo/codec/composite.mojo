from std.collections import Span
from std.utils import Variant
from std.sys import size_of
from .types import *
from .scalar import *
from .bounded import *


# Validate coordinates by subtraction so even hostile signed spans cannot overflow endpoints.
def valid_span(blob: BlobSpan, size: Int) -> Bool:
    return (
        blob.offset >= 0
        and blob.length >= 0
        and blob.offset <= size
        and blob.length <= size - blob.offset
    )


# Shared native tag proof for optional blobs and C.2 work outputs, with schema-specific limits.
@fieldwise_init
struct Tagged(Copyable, Movable):
    var tag: UInt64
    var blob: BlobSpan
    var consumed: Int


# Check the discriminator before decoding only the branch that actually carries a blob.
def read_tag(
    data: Span[mut=False, UInt8, _], maximum: UInt64, blob_tag: UInt64, limit: ByteLimit
) -> CheckedResult[Tagged]:
    comptime Result = CheckedResult[Tagged]
    var tag = decode_natural(data)
    # No invalid/incomplete natural may be treated as a schema discriminator.
    if tag.isa[Failure]():
        return Result(tag[Failure].copy())
    var parsed = tag[Decoded[JamNatural]].copy()
    # Unknown tags fail before construction of any public branch.
    if parsed.value.value > maximum:
        return Result(fail["invalidtag"]())
    # Payload-free branches consume only their canonical discriminator.
    if parsed.value.value != blob_tag:
        return Result(Tagged(parsed.value.value, BlobSpan(0, 0), parsed.consumed))
    var blob = decode_bytes_borrowed(data[parsed.consumed :], limit)
    # Preserve nested prefix/policy/payload errors without exposing a partial value.
    if blob.isa[Failure]():
        return Result(blob[Failure].copy())
    var payload = blob[Decoded[BlobSpan]].copy()
    return Result(
        Tagged(
            parsed.value.value,
            BlobSpan(parsed.consumed + payload.value.offset, payload.value.length),
            parsed.consumed + payload.consumed,
        )
    )


# Measure a tag/span before mutation, preserving the caller's pool and resource policy.
def tag_size(
    tag: UInt64, has_blob: Bool, blob: BlobSpan, pool_size: Int, limit: ByteLimit
) -> WriteResult:
    # Tags are validated even for payload-free values supplied by callers.
    if tag > 6:
        return WriteResult(fail["invalidtag"]())
    # No payload span or byte limit belongs to an error/absence branch.
    if not has_blob:
        return WriteResult(Written(1))
    # Prove source coordinates before converting their signed length.
    if not valid_span(blob, pool_size):
        return WriteResult(fail["invalidspan"]())
    # Reject large claims before computing their encoded extent.
    if UInt64(blob.length) > limit.value:
        return WriteResult(fail["limitexceeded"]())
    var prefix = encode_natural(JamNatural(UInt64(blob.length)))
    # Header additions must remain representable on the host.
    if blob.length > Int.MAX - 1 - prefix.length:
        return WriteResult(fail["lengthoverflow"]())
    return WriteResult(Written(1 + prefix.length + blob.length))


# Commit one checked variant only after size, destination and whole-pool alias preflight.
def write_tag(
    tag: UInt64,
    has_blob: Bool,
    blob: BlobSpan,
    pool: Span[mut=False, UInt8, _],
    limit: ByteLimit,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    var checked = tag_size(tag, has_blob, blob, len(pool), limit)
    # Rejected variants cannot commit their discriminator either.
    if checked.isa[Failure]():
        return checked^
    var size = checked[Written].written
    # Require the complete frame rather than a partial prefix.
    if len(output) < size:
        return WriteResult(fail["outputtoosmall"]())
    # Protect the whole source pool while copying its selected blob.
    if has_blob and overlaps(UInt(pool.unsafe_ptr()), len(pool), UInt(output.unsafe_ptr()), size):
        return WriteResult(fail["aliasedbuffers"]())
    output[0] = UInt8(tag)
    # Only the payload branch emits a canonical length followed by bytes.
    if has_blob:
        var prefix = encode_natural(JamNatural(UInt64(blob.length)))
        # All target extents and source coordinates have been proved above.
        for i in range(prefix.length):
            output[1 + i] = prefix.bytes[i]
        # Raw blobs use identity encoding in their original order.
        output[1 + prefix.length : size].copy_from(pool[blob.offset : blob.offset + blob.length])
    return WriteResult(Written(size))


# C.1.3 optional blob: absent zero or present one plus a bounded variable blob.
def decode_optional_borrowed(
    data: Span[mut=False, UInt8, _], limit: ByteLimit
) -> CheckedResult[Decoded[OptionalBlob]]:
    comptime Result = CheckedResult[Decoded[OptionalBlob]]
    var tag = read_tag(data, 1, 1, limit)
    # Invalid frames have no optional payload or progress fields.
    if tag.isa[Failure]():
        return Result(tag[Failure].copy())
    var value = tag[Tagged].copy()
    # Absence contains no span at all.
    if value.tag == 0:
        return Result(Decoded(OptionalBlob(Absent()), value.consumed))
    return Result(Decoded(OptionalBlob(value.blob.copy()), value.consumed))


# Encode the same optional schema with checked access to its active alternative.
def encode_optional_borrowed(
    var value: OptionalBlob,
    pool: Span[mut=False, UInt8, _],
    limit: ByteLimit,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    # Presence borrows its original pool through the synchronous commit only.
    if value.isa[BlobSpan]():
        return write_tag(1, True, value[BlobSpan], pool, limit, output)
    return write_tag(0, False, BlobSpan(0, 0), pool, limit, output)


# C.2 work output: success zero carries a blob; the six errors are payload-free.
def decode_work_borrowed(
    data: Span[mut=False, UInt8, _], limit: ByteLimit
) -> CheckedResult[Decoded[WorkOutput]]:
    comptime Result = CheckedResult[Decoded[WorkOutput]]
    var tag = read_tag(data, 6, 0, limit)
    # Do not manufacture a default output after malformed wire input.
    if tag.isa[Failure]():
        return Result(tag[Failure].copy())
    var value = tag[Tagged].copy()
    # Only success retains borrowed payload coordinates.
    if value.tag == 0:
        return Result(Decoded(WorkOutput(value.blob.copy()), value.consumed))
    return Result(Decoded(WorkOutput(WorkFailure(value.tag)), value.consumed))


# Measure work output for enclosing digest preflight, without writing any bytes.
def measure_work(var value: WorkOutput, pool_size: Int, limit: ByteLimit) -> WriteResult:
    # The successful branch validates its span and byte ceiling.
    if value.isa[BlobSpan]():
        return tag_size(0, True, value[BlobSpan], pool_size, limit)
    var tag = value[WorkFailure].tag
    # A payload-free work failure must be one of the six nonzero tags.
    if tag == 0:
        return WriteResult(fail["invalidtag"]())
    return tag_size(tag, False, BlobSpan(0, 0), pool_size, limit)


# Encode a work variant; invalid caller-supplied error tags are ordinary failures.
def encode_work_borrowed(
    var value: WorkOutput,
    pool: Span[mut=False, UInt8, _],
    limit: ByteLimit,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    # Successful payload coordinates remain attached to the explicit borrowed pool argument.
    if value.isa[BlobSpan]():
        return write_tag(0, True, value[BlobSpan], pool, limit, output)
    var tag = value[WorkFailure].tag
    # An error branch cannot smuggle in the successful discriminator without its payload.
    if tag == 0:
        return WriteResult(fail["invalidtag"]())
    return write_tag(tag, False, BlobSpan(0, 0), pool, limit, output)


# Traverse nested records twice: validation writes nothing, commit runs only over stable checked input.
def walk_preimages(
    data: Span[mut=False, UInt8, _],
    offset: Int,
    count: Int,
    limits: PreimageLimits,
    output: Span[mut=True, Preimage, _],
    commit: Bool,
) -> CheckedResult[SequenceInfo]:
    comptime Result = CheckedResult[SequenceInfo]
    var cursor = offset
    var budget = limits.total_bytes.value
    # Each record consumes a four-byte service and one bounded variable blob.
    for i in range(count):
        # Missing fixed fields fail before any read or record assignment.
        if len(data) - cursor < 4:
            return Result(fail["truncated"]())
        var service = decode_fixed(data[cursor : cursor + 4], ByteWidth(4))
        cursor += 4
        var blob = decode_bytes_borrowed(
            data[cursor:], ByteLimit(min(limits.per_blob.value, budget))
        )
        # Both the per-item and remaining aggregate policies apply before payload access.
        if blob.isa[Failure]():
            return Result(blob[Failure].copy())
        var value = blob[Decoded[BlobSpan]].copy()
        # A failing final record must never leave an earlier partial output prefix.
        if commit:
            output[i] = Preimage(
                ServiceIndex(UInt32(service[Decoded[FixedUnsigned]].value.value)),
                BlobSpan(cursor + value.value.offset, value.value.length),
            )
        budget -= UInt64(value.value.length)
        cursor += value.consumed
    return Result(SequenceInfo(count, cursor))


# Decode a complete preimage extrinsic atomically into separate caller descriptor storage.
def decode_preimages_borrowed(
    data: Span[mut=False, UInt8, _], limits: PreimageLimits, output: Span[mut=True, Preimage, _]
) -> CheckedResult[SequenceInfo]:
    comptime Result = CheckedResult[SequenceInfo]
    var prefix = decode_natural(data)
    # Failed outer prefixes have no count to allocate or cursor to advance.
    if prefix.isa[Failure]():
        return Result(prefix[Failure].copy())
    var header = prefix[Decoded[JamNatural]].copy()
    var claimed = header.value.value
    # Count ceilings precede even the minimum-frame proof.
    if claimed > limits.items.value:
        return Result(fail["limitexceeded"]())
    # Every tuple requires at least four fixed bytes and one length octet.
    if claimed > UInt64((len(data) - header.consumed) // 5):
        return Result(fail["truncated"]())
    # Output capacity proves host count conversion before traversal.
    if claimed > UInt64(len(output)):
        return Result(fail["outputtoosmall"]())
    # Protect descriptor extent calculations from multiplication overflow.
    if claimed > UInt64(Int.MAX // size_of[Preimage]()):
        return Result(fail["lengthoverflow"]())
    var count = Int(claimed)
    # Trailing input remains protected from descriptor writes too.
    if overlaps(
        UInt(data.unsafe_ptr()), len(data), UInt(output.unsafe_ptr()), count * size_of[Preimage]()
    ):
        return Result(fail["aliasedbuffers"]())
    var checked = walk_preimages(data, header.consumed, count, limits, output, False)
    # Commit is permitted only when every nested record passed the first traversal.
    if checked.isa[Failure]():
        return checked^
    return walk_preimages(data, header.consumed, count, limits, output, True)


# Encode nested tuples with whole-frame preflight of spans, byte budgets, capacity and aliasing.
def encode_preimages_borrowed(
    values: Span[mut=False, Preimage, _],
    pool: Span[mut=False, UInt8, _],
    limits: PreimageLimits,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    # Count ceilings apply even to an empty tuple's length header.
    if UInt64(len(values)) > limits.items.value:
        return WriteResult(fail["limitexceeded"]())
    var prefix = encode_natural(JamNatural(UInt64(len(values))))
    # The outer header itself must fit before subtracting remaining capacity.
    if len(output) < prefix.length:
        return WriteResult(fail["outputtoosmall"]())
    var required = prefix.length
    var budget = limits.total_bytes.value
    # Prove every late record before any mutation of the destination.
    for i in range(len(values)):
        var blob = values[i].blob.copy()
        # Validate signed endpoints before converting lengths to UInt64.
        if not valid_span(blob, len(pool)):
            return WriteResult(fail["invalidspan"]())
        # Subtract from the remaining budget rather than summing possibly huge claims.
        if UInt64(blob.length) > min(limits.per_blob.value, budget):
            return WriteResult(fail["limitexceeded"]())
        var length = encode_natural(JamNatural(UInt64(blob.length)))
        # Capacity subtraction proves both the header and payload fit without overflowing their sum.
        if (
            len(output) - required < 4 + length.length
            or blob.length > len(output) - required - 4 - length.length
        ):
            return WriteResult(fail["outputtoosmall"]())
        required += 4 + length.length + blob.length
        budget -= UInt64(blob.length)
    # Descriptor byte extent must remain host-representable for alias detection.
    if len(values) > Int.MAX // size_of[Preimage]():
        return WriteResult(fail["lengthoverflow"]())
    # Protect the complete borrowed pool, including unused bytes.
    if overlaps(UInt(pool.unsafe_ptr()), len(pool), UInt(output.unsafe_ptr()), required):
        return WriteResult(fail["aliasedbuffers"]())
    # Output also cannot overwrite descriptors needed by later tuple commits.
    if overlaps(
        UInt(values.unsafe_ptr()),
        len(values) * size_of[Preimage](),
        UInt(output.unsafe_ptr()),
        required,
    ):
        return WriteResult(fail["aliasedbuffers"]())
    # Commit the canonical outer count after the entire input has passed validation.
    for i in range(prefix.length):
        output[i] = prefix.bytes[i]
    var cursor = prefix.length
    # Every descriptor and corresponding pool span is stable and fully checked.
    for index in range(len(values)):
        var blob = values[index].blob.copy()
        var service = encode_fixed(FixedUnsigned(UInt64(values[index].service.value)), ByteWidth(4))
        # Write the nominal service in its four-byte little-endian format.
        for i in range(4):
            output[cursor + i] = service[Encoded].bytes[i]
        cursor += 4
        var length = encode_natural(JamNatural(UInt64(blob.length)))
        # Prefix the nested payload with its canonical natural length.
        for i in range(length.length):
            output[cursor + i] = length.bytes[i]
        cursor += length.length
        # Identity-copy precisely the selected borrowed pool bytes.
        output[cursor : cursor + blob.length].copy_from(
            pool[blob.offset : blob.offset + blob.length]
        )
        cursor += blob.length
    return WriteResult(Written(required))
