from std.collections import Span, Optional
from std.utils import Variant
from std.ffi import external_call, c_size_t
from std.sys import size_of
from .types import *
from .scalar import decode_natural
from .bounded import *
from .composite import *
from .digest import *


# Native storage is reachable only through an explicit unsafe opaque-pointer cast, as in Odin.
# Copies of the public handle are borrowed aliases; one owner must call release exactly once.
@fieldwise_init
struct Storage(Movable):
    var kind: Int
    var wire: List[UInt8]
    var blobs: List[BlobSpan]
    var services: List[ServiceIndex]
    var tag: UInt64


# Opaque native snapshot handle; no mutable bytes or detached spans are exported by its safe operations.
@fieldwise_init
struct OwnedFrame(Copyable, Movable):
    var _opaque: Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]


# Common scalar information has no source-buffer coordinates.
@fieldwise_init
struct OwnedInfo(Copyable, Movable):
    var kind: Int
    var consumed: Int
    var blob_count: Int


# Internal synchronous storage access requires an explicit unsafe cast; never export this reference.
def unsafe_storage(frame: OwnedFrame) -> Pointer[Storage, MutUntrackedOrigin]:
    return frame._opaque.value().unsafe_bitcast[Storage]()


# Release one original owner after all aliases stop using it; copied handles do not own independent allocations.
def release(mut frame: OwnedFrame):
    # A null/default handle has no allocation to destroy.
    if not frame._opaque:
        return
    var pointer = unsafe_storage(frame)
    pointer.unsafe_deinit_pointee()
    external_call["free", NoneType](frame._opaque.value())
    frame._opaque = None


# Decode an exact schema, validate fully, then retain only its consumed prefix and bound descriptors.
def capture(
    data: Span[mut=False, UInt8, _], kind: Int, limit: ByteLimit, limits: PreimageLimits
) -> CheckedResult[OwnedFrame]:
    comptime Result = CheckedResult[OwnedFrame]
    var consumed: Int
    var blobs = List[BlobSpan]()
    var services = List[ServiceIndex]()
    var tag: UInt64 = 0
    # Bytes own one payload, including the valid empty-payload case.
    if kind == 0:
        var parsed = decode_bytes_borrowed(data, limit)
        # Invalid frames cannot allocate an application snapshot.
        if parsed.isa[Failure]():
            return Result(parsed[Failure].copy())
        var value = parsed[Decoded[BlobSpan]].copy()
        consumed = value.consumed
        blobs.append(value.value.copy())
    elif kind == 1 or kind == 2:
        # Optional/work schemas have different payload tags but share canonical length validation.
        var maximum: UInt64 = 6
        var blob_tag: UInt64 = 0
        if kind == 1:
            # Optional presence has exactly the zero/one discriminator set.
            maximum = 1
            blob_tag = 1
        var parsed = read_tag(data, maximum, blob_tag, limit)
        # Schema errors expose no owner, tag or consumed extent.
        if parsed.isa[Failure]():
            return Result(parsed[Failure].copy())
        var value = parsed[Tagged].copy()
        consumed = value.consumed
        tag = value.tag
        # Payload-free branches retain no span at all.
        if tag == blob_tag:
            blobs.append(value.blob.copy())
    elif kind == 3:
        # Prove count and a minimum frame extent before allocating descriptor storage.
        var prefix = decode_natural(data)
        if prefix.isa[Failure]():
            # Failed counts cannot drive native allocations.
            return Result(prefix[Failure].copy())
        var header = prefix[Decoded[JamNatural]].copy()
        var count = header.value.value
        # Preserve decoder error precedence for count policy and incomplete tuples.
        if count > limits.items.value:
            return Result(fail["limitexceeded"]())
        if count > UInt64((len(data) - header.consumed) // 5):
            # Every record needs at least five wire bytes.
            return Result(fail["truncated"]())
        var records = List[Preimage](
            length=Int(count), fill=Preimage(ServiceIndex(0), BlobSpan(0, 0))
        )
        var parsed = decode_preimages_borrowed(data, limits, Span(records))
        # Late record failures leave no partially validated owned state.
        if parsed.isa[Failure]():
            return Result(parsed[Failure].copy())
        consumed = parsed[SequenceInfo].consumed
        # Retain only descriptors whose entire nested frame was validated.
        for i in range(Int(count)):
            blobs.append(records[i].blob.copy())
            services.append(records[i].service.copy())
    elif kind == 4:
        # Digests validate fixed fields, output, and every refinement metric before snapshot capture.
        var parsed = decode_digest_borrowed(data, limit)
        if parsed.isa[Failure]():
            # A malformed final metric produces no earlier fixed-field owner.
            return Result(parsed[Failure].copy())
        var value = parsed[Decoded[WorkDigest]].copy()
        consumed = value.consumed
        # Successful payloads remain bound to the full original digest coordinates.
        if value.value.output.isa[BlobSpan]():
            blobs.append(value.value.output[BlobSpan].copy())
        else:
            # Valid work errors carry their tag but no payload descriptor.
            tag = value.value.output[WorkFailure].tag
    else:
        # Unknown schema selection is an API misuse, not a guessed codec.
        return Result(fail["wrongschema"]())
    var wire = List[UInt8](length=consumed, fill=0)
    # Retain a deep copy so caller mutation and input lifetime cannot affect validated bytes.
    Span(wire).copy_from(data[:consumed])
    var opaque = external_call["malloc", Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]](
        c_size_t(size_of[Storage]())
    )
    # Allocation failures expose only a reason; the local lists retire normally on return.
    if not opaque:
        return Result(fail["allocationfailure"]())
    opaque.value().unsafe_bitcast[Storage]().unsafe_write(
        Storage(kind, wire^, blobs^, services^, tag)
    )
    return Result(OwnedFrame(opaque))


# Return scalar extent/count metadata while keeping all snapshot bytes and span coordinates opaque.
def owned_info(frame: OwnedFrame) -> CheckedResult[OwnedInfo]:
    # Null/default owners cannot manufacture a validated empty frame.
    if not frame._opaque:
        return CheckedResult[OwnedInfo](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    return CheckedResult[OwnedInfo](OwnedInfo(value.kind, len(value.wire), len(value.blobs)))


# Copy only one owner-bound payload into separate caller storage; no unrelated source pool is accepted.
def copy_owned_blob(frame: OwnedFrame, index: Int, output: Span[mut=True, UInt8, _]) -> WriteResult:
    # Require a live original owner before dereferencing its foreign allocation.
    if not frame._opaque:
        return WriteResult(fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Validate signed indices before descriptor access.
    if index < 0 or index >= len(value.blobs):
        return WriteResult(fail["invalidindex"]())
    var blob = value.blobs[index].copy()
    # Full output capacity is proved before mutation.
    if len(output) < blob.length:
        return WriteResult(fail["outputtoosmall"]())
    # Unsafe callers must not arrange output over the otherwise opaque retained snapshot.
    if overlaps(
        UInt(value.wire.unsafe_ptr()), len(value.wire), UInt(output.unsafe_ptr()), blob.length
    ):
        return WriteResult(fail["aliasedbuffers"]())
    # Coordinates were validated against the exact retained consumed-prefix owner during capture.
    output[: blob.length].copy_from(Span(value.wire)[blob.offset : blob.offset + blob.length])
    return WriteResult(Written(blob.length))


# Re-emit the complete canonical retained frame atomically, without exposing its backing bytes.
def encode_owned(frame: OwnedFrame, output: Span[mut=True, UInt8, _]) -> WriteResult:
    # Default handles contain no validated schema or bytes.
    if not frame._opaque:
        return WriteResult(fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Require the whole consumed prefix before copying a single byte.
    if len(output) < len(value.wire):
        return WriteResult(fail["outputtoosmall"]())
    # Keep retained bytes immutable even when an explicit unsafe caller manufactures aliasing storage.
    if overlaps(
        UInt(value.wire.unsafe_ptr()), len(value.wire), UInt(output.unsafe_ptr()), len(value.wire)
    ):
        return WriteResult(fail["aliasedbuffers"]())
    # Every saved byte belongs to the validated canonical frame, excluding original trailing bytes.
    output[: len(value.wire)].copy_from(Span(value.wire))
    return WriteResult(Written(len(value.wire)))


# Retrieve a nominal service value only for the preimage schema and a validated tuple index.
def owned_service(frame: OwnedFrame, index: Int) -> CheckedResult[ServiceIndex]:
    # Missing owner is distinct from a valid empty preimage extrinsic.
    if not frame._opaque:
        return CheckedResult[ServiceIndex](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Other schemas have no service-list interpretation.
    if value.kind != 3:
        return CheckedResult[ServiceIndex](fail["wrongschema"]())
    # Signed indices must lie in the actual retained list.
    if index < 0 or index >= len(value.services):
        return CheckedResult[ServiceIndex](fail["invalidindex"]())
    return CheckedResult[ServiceIndex](value.services[index].copy())


# Retrieve an owner-bound payload length without returning coordinates into its snapshot.
def owned_blob_length(frame: OwnedFrame, index: Int) -> CheckedResult[Int]:
    # Require live ownership before accessing retained descriptors.
    if not frame._opaque:
        return CheckedResult[Int](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Signed indices cannot wrap into a valid descriptor.
    if index < 0 or index >= len(value.blobs):
        return CheckedResult[Int](fail["invalidindex"]())
    return CheckedResult[Int](value.blobs[index].length)


# Presence metadata has a length only in its present alternative, never a detached span.
@fieldwise_init
struct OwnedPresent(Copyable, Movable):
    var length: Int


# Work success metadata carries only length; errors retain their payload-free protocol tag.
comptime OwnedOptionalInfo = Variant[Absent, OwnedPresent]
comptime OwnedWorkInfo = Variant[OwnedPresent, WorkFailure]


# All fixed digest fields are owned copies; the output exposes only tag/length metadata.
@fieldwise_init
struct OwnedDigestInfo(Copyable, Movable):
    var service: ServiceIndex
    var code_hash: CodeHash
    var payload_hash: PayloadHash
    var accumulate_gas: Gas
    var output: OwnedWorkInfo
    var refine: RefineLoad


# Return optional metadata only for its validated schema and live owner.
def owned_optional_info(frame: OwnedFrame) -> CheckedResult[OwnedOptionalInfo]:
    # Null owners cannot manufacture a valid absence value.
    if not frame._opaque:
        return CheckedResult[OwnedOptionalInfo](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Schema identity is checked before interpreting the retained tag.
    if value.kind != 1:
        return CheckedResult[OwnedOptionalInfo](fail["wrongschema"]())
    # Presence includes the valid zero-length payload case.
    if value.tag == 1:
        return CheckedResult[OwnedOptionalInfo](
            OwnedOptionalInfo(OwnedPresent(value.blobs[0].length))
        )
    return CheckedResult[OwnedOptionalInfo](OwnedOptionalInfo(Absent()))


# Return work metadata for either a work-only owner or the output inside an owned digest.
def owned_work_info(frame: OwnedFrame) -> CheckedResult[OwnedWorkInfo]:
    # Missing owners carry no meaningful discriminator.
    if not frame._opaque:
        return CheckedResult[OwnedWorkInfo](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Other schema tags must never be interpreted as work errors.
    if value.kind != 2 and value.kind != 4:
        return CheckedResult[OwnedWorkInfo](fail["wrongschema"]())
    # Success exposes length only; all coordinates remain in the opaque allocation.
    if value.tag == 0:
        return CheckedResult[OwnedWorkInfo](OwnedWorkInfo(OwnedPresent(value.blobs[0].length)))
    return CheckedResult[OwnedWorkInfo](OwnedWorkInfo(WorkFailure(value.tag)))


# Return copied fixed digest metadata while keeping payload storage owner-bound and immutable.
def owned_digest_info(frame: OwnedFrame) -> CheckedResult[OwnedDigestInfo]:
    # Require a live owner before parsing the retained canonical snapshot.
    if not frame._opaque:
        return CheckedResult[OwnedDigestInfo](fail["invalidowner"]())
    ref value = unsafe_storage(frame)[]
    # Only the digest schema contains these fixed fields and refinement metrics.
    if value.kind != 4:
        return CheckedResult[OwnedDigestInfo](fail["wrongschema"]())
    var decoded = decode_digest_borrowed(Span(value.wire), ByteLimit(UInt64.MAX))
    # Unsafe corruption is rejected rather than silently exposing default metadata.
    if decoded.isa[Failure]():
        return CheckedResult[OwnedDigestInfo](decoded[Failure].copy())
    var digest = decoded[Decoded[WorkDigest]].value.copy()
    var info = owned_work_info(frame)
    return CheckedResult[OwnedDigestInfo](
        OwnedDigestInfo(
            digest.service.copy(),
            digest.code_hash.copy(),
            digest.payload_hash.copy(),
            digest.accumulate_gas.copy(),
            info[OwnedWorkInfo].copy(),
            digest.refine.copy(),
        )
    )
