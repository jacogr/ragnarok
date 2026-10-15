from std.collections import Array, Span, Optional
from .types import *
from .scalar import *
from .bounded import *
from .composite import *
from .digest import *


# Nominal owned report hashes separate package, root, block, state and authorizer domains.
@fieldwise_init
struct ReportHash[kind: Int](Copyable, Movable):
    var bytes: Array[UInt8, 32]


comptime PackageHash = ReportHash[0]
comptime ErasureRoot = ReportHash[1]
comptime SegmentRoot = ReportHash[2]
comptime BlockHash = ReportHash[3]
comptime StateRoot = ReportHash[4]
comptime AccumulationRoot = ReportHash[5]
comptime AuthorizerHash = ReportHash[6]


# Fixed bundle length has a four-byte unsigned domain.
@fieldwise_init
struct BundleLength(Copyable, Movable):
    var value: UInt32


# Export segment count has a two-byte unsigned domain.
@fieldwise_init
struct SegmentCount(Copyable, Movable):
    var value: UInt16


# Lookup timeslot has a four-byte unsigned domain.
@fieldwise_init
struct LookupSlot(Copyable, Movable):
    var value: UInt32


# Core indices use general naturals with an explicit chain-configuration limit.
@fieldwise_init
struct CoreIndex(Copyable, Movable):
    var value: UInt64


# Complete owned availability/context fixed fields; prerequisites follow separately on the wire.
@fieldwise_init
struct ReportHeader(Copyable, Movable):
    var package_hash: PackageHash
    var bundle_length: BundleLength
    var erasure_root: ErasureRoot
    var segment_root: SegmentRoot
    var segment_count: SegmentCount
    var anchor: BlockHash
    var state_root: StateRoot
    var accumulation_root: AccumulationRoot
    var lookup_anchor: BlockHash
    var lookup_slot: LookupSlot


# A dictionary entry retains its package key and associated segment commitment as distinct domains.
@fieldwise_init
struct SegmentLookup(Copyable, Movable):
    var package_hash: PackageHash
    var segment_root: SegmentRoot


# Protocol-bounded metadata uses fixed storage; spans explicitly borrow the exact matching pool/input.
# Optional child slots avoid inventing default successful digest variants for unused capacity.
@fieldwise_init
struct WorkReport(Copyable, Movable):
    var header: ReportHeader
    var prerequisites: Array[PackageHash, 8]
    var prerequisite_count: Int
    var core: CoreIndex
    var authorizer: AuthorizerHash
    var auth_gas: Gas
    var auth_output: BlobSpan
    var lookup: Array[SegmentLookup, 8]
    var lookup_count: Int
    var digests: Array[Optional[WorkDigest], 16]
    var digest_count: Int


# Initialize private bounded metadata; zero digest count remains an invalid public report until populated.
def empty_report(header: ReportHeader) -> WorkReport:
    var zero = Array[UInt8, 32](fill=0)
    return WorkReport(
        header.copy(),
        Array[PackageHash, 8](fill=PackageHash(zero.copy())),
        0,
        CoreIndex(0),
        AuthorizerHash(zero.copy()),
        Gas(0),
        BlobSpan(0, 0),
        Array[SegmentLookup, 8](
            fill=SegmentLookup(PackageHash(zero.copy()), SegmentRoot(zero.copy()))
        ),
        0,
        Array[Optional[WorkDigest], 16](fill=None),
        0,
    )


# Decode the complete fixed availability/context prefix without retaining input references.
def decode_report_header(data: Span[mut=False, UInt8, _]) -> CheckedResult[ReportHeader]:
    comptime Result = CheckedResult[ReportHeader]
    # Prove every fixed field extent before any indexing or narrowing conversion.
    if len(data) < 234:
        return Result(fail["truncated"]())
    var package_hash = Array[UInt8, 32](fill=0)
    # Identity-copy the complete package_hash into nominal owned storage.
    for i in range(32):
        package_hash[i] = data[0 + i]
    var bundle_length = decode_fixed(data[32:36], ByteWidth(4))
    var erasure_root = Array[UInt8, 32](fill=0)
    # Identity-copy the complete erasure_root into nominal owned storage.
    for i in range(32):
        erasure_root[i] = data[36 + i]
    var segment_root = Array[UInt8, 32](fill=0)
    # Identity-copy the complete segment_root into nominal owned storage.
    for i in range(32):
        segment_root[i] = data[68 + i]
    var segment_count = decode_fixed(data[100:102], ByteWidth(2))
    var anchor = Array[UInt8, 32](fill=0)
    # Identity-copy the complete anchor into nominal owned storage.
    for i in range(32):
        anchor[i] = data[102 + i]
    var state_root = Array[UInt8, 32](fill=0)
    # Identity-copy the complete state_root into nominal owned storage.
    for i in range(32):
        state_root[i] = data[134 + i]
    var accumulation_root = Array[UInt8, 32](fill=0)
    # Identity-copy the complete accumulation_root into nominal owned storage.
    for i in range(32):
        accumulation_root[i] = data[166 + i]
    var lookup_anchor = Array[UInt8, 32](fill=0)
    # Identity-copy the complete lookup_anchor into nominal owned storage.
    for i in range(32):
        lookup_anchor[i] = data[198 + i]
    var lookup_slot = decode_fixed(data[230:234], ByteWidth(4))
    return Result(
        ReportHeader(
            PackageHash(package_hash^),
            BundleLength(UInt32(bundle_length[Decoded[FixedUnsigned]].value.value)),
            ErasureRoot(erasure_root^),
            SegmentRoot(segment_root^),
            SegmentCount(UInt16(segment_count[Decoded[FixedUnsigned]].value.value)),
            BlockHash(anchor^),
            StateRoot(state_root^),
            AccumulationRoot(accumulation_root^),
            BlockHash(lookup_anchor^),
            LookupSlot(UInt32(lookup_slot[Decoded[FixedUnsigned]].value.value)),
        )
    )


# Emit a fixed-header value snapshot atomically into checked caller storage.
def encode_report_header(var value: ReportHeader, output: Span[mut=True, UInt8, _]) -> WriteResult:
    # No fixed field may be committed until the whole header fits.
    if len(output) < 234:
        return WriteResult(fail["outputtoosmall"]())
    # Preserve the declared package_hash domain and identity byte order.
    for i in range(32):
        output[0 + i] = value.package_hash.bytes[i]
    var bundle_length = encode_fixed(FixedUnsigned(UInt64(value.bundle_length.value)), ByteWidth(4))
    # The nominal bundle_length width proves the narrowing and complete fixed output extent.
    for i in range(4):
        output[32 + i] = bundle_length[Encoded].bytes[i]
    # Preserve the declared erasure_root domain and identity byte order.
    for i in range(32):
        output[36 + i] = value.erasure_root.bytes[i]
    # Preserve the declared segment_root domain and identity byte order.
    for i in range(32):
        output[68 + i] = value.segment_root.bytes[i]
    var segment_count = encode_fixed(FixedUnsigned(UInt64(value.segment_count.value)), ByteWidth(2))
    # The nominal segment_count width proves the narrowing and complete fixed output extent.
    for i in range(2):
        output[100 + i] = segment_count[Encoded].bytes[i]
    # Preserve the declared anchor domain and identity byte order.
    for i in range(32):
        output[102 + i] = value.anchor.bytes[i]
    # Preserve the declared state_root domain and identity byte order.
    for i in range(32):
        output[134 + i] = value.state_root.bytes[i]
    # Preserve the declared accumulation_root domain and identity byte order.
    for i in range(32):
        output[166 + i] = value.accumulation_root.bytes[i]
    # Preserve the declared lookup_anchor domain and identity byte order.
    for i in range(32):
        output[198 + i] = value.lookup_anchor.bytes[i]
    var lookup_slot = encode_fixed(FixedUnsigned(UInt64(value.lookup_slot.value)), ByteWidth(4))
    # The nominal lookup_slot width proves the narrowing and complete fixed output extent.
    for i in range(4):
        output[230 + i] = lookup_slot[Encoded].bytes[i]
    return WriteResult(Written(234))


# Hash order is lexicographic on bytes, never host-endian integer order; equality is deliberately false.
def report_hash_less(a: PackageHash, b: PackageHash) -> Bool:
    # The first unequal byte decides strict ordering for both sets and dictionary keys.
    for i in range(32):
        if a.bytes[i] != b.bytes[i]:
            # Duplicate keys must not acquire an arbitrary ordering.
            return a.bytes[i] < b.bytes[i]
    return False


# Consume one canonical natural, preserving the caller's cursor on failure.
def report_natural(
    data: Span[mut=False, UInt8, _], mut cursor: Int
) -> CheckedResult[Decoded[JamNatural]]:
    var parsed = decode_natural(data[cursor:])
    # Failed counts cannot advance the cursor or expose default scalar values.
    if parsed.isa[Decoded[JamNatural]]():
        cursor += parsed[Decoded[JamNatural]].consumed
    return parsed^


# Decode one bounded report prefix without heap allocation or partial successful metadata.
def decode_report_borrowed(
    data: Span[mut=False, UInt8, _], core_count: UInt64
) -> CheckedResult[Decoded[WorkReport]]:
    comptime Result = CheckedResult[Decoded[WorkReport]]
    var header = decode_report_header(data)
    # A missing fixed header cannot create a report with invented default fields.
    if header.isa[Failure]():
        return Result(header[Failure].copy())
    var value = empty_report(header[ReportHeader].copy())
    var cursor = 234
    var prerequisites = report_natural(data, cursor)
    # Canonicality precedes narrowing and count-driven indexing.
    if prerequisites.isa[Failure]():
        return Result(prerequisites[Failure].copy())
    var count = prerequisites[Decoded[JamNatural]].value.value
    # Apply protocol count limits before proving the whole fixed-stride wire extent.
    if count > 8:
        return Result(fail["limitexceeded"]())
    if count > UInt64((len(data) - cursor) // 32):
        return Result(fail["truncated"]())
    value.prerequisite_count = Int(count)
    # Retain ordered, unique set members in bounded owned metadata.
    for i in range(value.prerequisite_count):
        var bytes = Array[UInt8, 32](fill=0)
        # The count/stride proof covers all bytes of this complete hash.
        for j in range(32):
            bytes[j] = data[cursor + j]
        value.prerequisites[i] = PackageHash(bytes^)
        cursor += 32
        # Duplicate and descending prerequisites are noncanonical.
        if i > 0 and not report_hash_less(value.prerequisites[i - 1], value.prerequisites[i]):
            return Result(fail["noncanonical"]())
    var core = report_natural(data, cursor)
    # Core indices use a general natural, followed by the configured chain bound.
    if core.isa[Failure]():
        return Result(core[Failure].copy())
    value.core = CoreIndex(core[Decoded[JamNatural]].value.value)
    if value.core.value >= core_count:
        return Result(fail["limitexceeded"]())
    # Authorizer identity must exist in full before any hash-byte access.
    if len(data) - cursor < 32:
        return Result(fail["truncated"]())
    for i in range(32):
        # This owned nominal hash retains no reference to caller storage.
        value.authorizer.bytes[i] = data[cursor + i]
    cursor += 32
    var gas = report_natural(data, cursor)
    # A failed gas natural cannot masquerade as zero authorization cost.
    if gas.isa[Failure]():
        return Result(gas[Failure].copy())
    value.auth_gas = Gas(gas[Decoded[JamNatural]].value.value)
    var auth = decode_bytes_borrowed(data[cursor:], ByteLimit(49152))
    # Per-blob policy and payload extent validate before selecting a span.
    if auth.isa[Failure]():
        return Result(auth[Failure].copy())
    var parsed_auth = auth[Decoded[BlobSpan]].copy()
    value.auth_output = BlobSpan(cursor + parsed_auth.value.offset, parsed_auth.value.length)
    cursor += parsed_auth.consumed
    var total = value.auth_output.length
    var lookups = report_natural(data, cursor)
    # Lookups share the eight-entry dependency budget with prerequisite hashes.
    if lookups.isa[Failure]():
        return Result(lookups[Failure].copy())
    count = lookups[Decoded[JamNatural]].value.value
    if count > UInt64(8 - value.prerequisite_count):
        return Result(fail["limitexceeded"]())
    if count > UInt64((len(data) - cursor) // 64):
        return Result(fail["truncated"]())
    value.lookup_count = Int(count)
    # Each complete dictionary entry owns a distinct key and segment root.
    for i in range(value.lookup_count):
        var key = Array[UInt8, 32](fill=0)
        var root = Array[UInt8, 32](fill=0)
        # The bounded fixed-stride proof covers both identity-encoded hashes.
        for j in range(32):
            key[j] = data[cursor + j]
            root[j] = data[cursor + 32 + j]
        value.lookup[i] = SegmentLookup(PackageHash(key^), SegmentRoot(root^))
        cursor += 64
        # Dictionary uniqueness depends only on package keys, never the associated roots.
        if i > 0 and not report_hash_less(
            value.lookup[i - 1].package_hash, value.lookup[i].package_hash
        ):
            return Result(fail["noncanonical"]())
    var digests = report_natural(data, cursor)
    # No attacker-supplied count is narrowed before checking fixed metadata capacity.
    if digests.isa[Failure]():
        return Result(digests[Failure].copy())
    count = digests[Decoded[JamNatural]].value.value
    if count < 1 or count > 16:
        return Result(fail["limitexceeded"]())
    value.digest_count = Int(count)
    # Every final digest metric must validate before the complete report becomes usable.
    for i in range(value.digest_count):
        var parsed = decode_digest_borrowed(data[cursor:], ByteLimit(UInt64(49152 - total)))
        # Preserve precise child decoding and aggregate payload-policy failures.
        if parsed.isa[Failure]():
            return Result(parsed[Failure].copy())
        var child = parsed[Decoded[WorkDigest]].copy()
        var digest = child.value.copy()
        # Successful payloads alone consume blob budget and need whole-input coordinates.
        if digest.output.isa[BlobSpan]():
            var blob = digest.output[BlobSpan].copy()
            total += blob.length
            digest.output = WorkOutput(BlobSpan(cursor + blob.offset, blob.length))
        value.digests[i] = Optional[WorkDigest](digest^)
        cursor += child.consumed
    return Result(Decoded(value^, cursor))


# Preflight canonical order, every nested span and the full aggregate budget before any output mutation.
def measure_report_borrowed(value: WorkReport, pool_size: Int, core_count: UInt64) -> WriteResult:
    # Signed public counts must fit fixed metadata arrays before indexing them.
    if (
        value.prerequisite_count < 0
        or value.prerequisite_count > 8
        or value.lookup_count < 0
        or value.lookup_count > 8
        or value.lookup_count > 8 - value.prerequisite_count
        or value.digest_count < 1
        or value.digest_count > 16
        or value.core.value >= core_count
    ):
        return WriteResult(fail["limitexceeded"]())
    # Subtraction-based span validation admits empty spans at the exact end of a stable pool.
    if not valid_span(value.auth_output, pool_size):
        return WriteResult(fail["invalidspan"]())
    var total = value.auth_output.length
    if total > 49152:
        return WriteResult(fail["limitexceeded"]())
    # Caller metadata must already use canonical set order; encoding does not silently sort it.
    for i in range(1, value.prerequisite_count):
        if not report_hash_less(value.prerequisites[i - 1], value.prerequisites[i]):
            return WriteResult(fail["noncanonical"]())
    # Only keys decide dictionary order and uniqueness.
    for i in range(1, value.lookup_count):
        if not report_hash_less(value.lookup[i - 1].package_hash, value.lookup[i].package_hash):
            return WriteResult(fail["noncanonical"]())
    var required = (
        234
        + encode_natural(JamNatural(UInt64(value.prerequisite_count))).length
        + 32 * value.prerequisite_count
        + encode_natural(JamNatural(value.core.value)).length
        + 32
        + encode_natural(JamNatural(value.auth_gas.value)).length
        + encode_natural(JamNatural(UInt64(total))).length
        + total
        + encode_natural(JamNatural(UInt64(value.lookup_count))).length
        + 64 * value.lookup_count
        + encode_natural(JamNatural(UInt64(value.digest_count))).length
    )
    # No inactive child slot or malformed late output may allow an earlier header write.
    for i in range(value.digest_count):
        if not value.digests[i]:
            return WriteResult(fail["invalidtag"]())
        var child = value.digests[i].value().copy()
        var measured = measure_work(
            child.output.copy(), pool_size, ByteLimit(UInt64(49152 - total))
        )
        if measured.isa[Failure]():
            # Child spans and tags retain their exact failure reason.
            return measured^
        if child.output.isa[BlobSpan]():
            # Error variants contribute no bytes to the shared payload budget.
            total += child.output[BlobSpan].length
        var size = 76 + measured[Written].written
        var numbers = metrics(child.refine)
        # Five bounded naturals follow the fixed fields and work output in normative order.
        for j in range(5):
            size += encode_natural(JamNatural(numbers[j])).length
        if size > Int.MAX - required:
            # No unchecked host addition is allowed even on a narrower target.
            return WriteResult(fail["lengthoverflow"]())
        required += size
    return WriteResult(Written(required))


# Commit one canonical natural into the enclosing encoder's already proved destination extent.
def report_put_natural(number: UInt64, output: Span[mut=True, UInt8, _], mut cursor: Int):
    var encoded = encode_natural(JamNatural(number))
    # Each byte belongs to the preflighted complete report extent.
    for i in range(encoded.length):
        output[cursor + i] = encoded.bytes[i]
    cursor += encoded.length


# Encode a local value snapshot atomically while protecting the entire stable borrowed pool against overlap.
def encode_report_borrowed(
    var value: WorkReport,
    pool: Span[mut=False, UInt8, _],
    core_count: UInt64,
    output: Span[mut=True, UInt8, _],
) -> WriteResult:
    var measured = measure_report_borrowed(value, pool.__len__(), core_count)
    # No earlier field may be written when any later nested field is invalid.
    if measured.isa[Failure]():
        return measured^
    var required = measured[Written].written
    if len(output) < required:
        return WriteResult(fail["outputtoosmall"]())
    if overlaps(UInt(pool.unsafe_ptr()), len(pool), UInt(output.unsafe_ptr()), required):
        # Pool protection includes bytes outside the selected payload spans.
        return WriteResult(fail["aliasedbuffers"]())
    _ = encode_report_header(value.header.copy(), output[:234])
    var cursor = 234
    report_put_natural(UInt64(value.prerequisite_count), output, cursor)
    # Retain exact ordered set-member identity bytes.
    for i in range(value.prerequisite_count):
        for j in range(32):
            # The complete hash target belongs to the preflighted extent.
            output[cursor + j] = value.prerequisites[i].bytes[j]
        cursor += 32
    report_put_natural(value.core.value, output, cursor)
    # Authorizer identity has no implicit hashing or byte reversal.
    for i in range(32):
        output[cursor + i] = value.authorizer.bytes[i]
    cursor += 32
    report_put_natural(value.auth_gas.value, output, cursor)
    report_put_natural(UInt64(value.auth_output.length), output, cursor)
    output[cursor : cursor + value.auth_output.length].copy_from(
        pool[value.auth_output.offset : value.auth_output.offset + value.auth_output.length]
    )
    cursor += value.auth_output.length
    report_put_natural(UInt64(value.lookup_count), output, cursor)
    # Commit complete dictionary pairs only after validating every key and descriptor.
    for i in range(value.lookup_count):
        for j in range(32):
            # Both fixed hashes fit within the complete validated dictionary extent.
            output[cursor + j] = value.lookup[i].package_hash.bytes[j]
            output[cursor + 32 + j] = value.lookup[i].segment_root.bytes[j]
        cursor += 64
    report_put_natural(UInt64(value.digest_count), output, cursor)
    # Child encoders retain checked result selection even after enclosing preflight.
    for i in range(value.digest_count):
        var encoded = encode_digest_borrowed(
            value.digests[i].value().copy(), pool, ByteLimit(49152), output[cursor:required]
        )
        # Enclosing preflight proves success; still preserve a typed failure if the invariant is violated.
        if encoded.isa[Failure]():
            return encoded^
        cursor += encoded[Written].written
    return WriteResult(Written(cursor))
