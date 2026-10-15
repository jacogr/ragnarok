from std.collections import Span, Optional
from std.ffi import external_call, c_size_t
from std.sys import size_of
from .types import *
from .bounded import overlaps
from .report import *
from .owned import OwnedDigestInfo, OwnedWorkInfo, OwnedPresent


# Private native storage binds bounded typed metadata to one exact immutable wire copy.
@fieldwise_init
struct ReportStorage(Movable):
    var value: WorkReport
    var wire: List[UInt8]


# One explicit release owner, with borrowed handle aliases; no compiler-enforced unique ownership claim.
@fieldwise_init
struct OwnedReport(Copyable, Movable):
    var _opaque: Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]


# Copied scalar metadata contains no mutable snapshot bytes or detached source coordinates.
@fieldwise_init
struct OwnedReportInfo(Copyable, Movable):
    var header: ReportHeader
    var core: CoreIndex
    var authorizer: AuthorizerHash
    var auth_gas: Gas
    var prerequisite_count: Int
    var lookup_count: Int
    var digest_count: Int
    var consumed: Int


# Dereferencing storage requires an explicit unsafe cast, outside the ordinary snapshot API.
def unsafe_report_storage(owner: OwnedReport) -> Pointer[ReportStorage, MutUntrackedOrigin]:
    return owner._opaque.value().unsafe_bitcast[ReportStorage]()


# Release exactly one original owner after all borrowed aliases have stopped using its allocation.
def release_report(mut owner: OwnedReport):
    # Null/default owners retain no allocation to retire.
    if not owner._opaque:
        return
    unsafe_report_storage(owner).unsafe_deinit_pointee()
    external_call["free", NoneType](owner._opaque.value())
    owner._opaque = None


# Fully validate the complete report before retaining only its consumed prefix and bound descriptors.
def decode_owned_report(
    data: Span[mut=False, UInt8, _], core_count: UInt64
) -> CheckedResult[OwnedReport]:
    comptime Result = CheckedResult[OwnedReport]
    var parsed = decode_report_borrowed(data, core_count)
    # Invalid final fields must not create an owner with partially trusted contents.
    if parsed.isa[Failure]():
        return Result(parsed[Failure].copy())
    var value = parsed[Decoded[WorkReport]].copy()
    var wire = List[UInt8](length=value.consumed, fill=0)
    Span(wire).copy_from(data[: value.consumed])
    var opaque = external_call["malloc", Optional[OpaquePointer[mut=True, MutUntrackedOrigin]]](
        c_size_t(size_of[ReportStorage]())
    )
    # Explicit foreign allocation failure exposes no default owner; native List OOM policy remains the SDK's.
    if not opaque:
        return Result(fail["allocationfailure"]())
    opaque.value().unsafe_bitcast[ReportStorage]().unsafe_write(
        ReportStorage(value.value.copy(), wire^)
    )
    return Result(OwnedReport(opaque))


# Return copied fixed/count metadata while preserving the private byte-owner relationship.
def owned_report_info(owner: OwnedReport) -> CheckedResult[OwnedReportInfo]:
    comptime Result = CheckedResult[OwnedReportInfo]
    # A null handle cannot fabricate a successfully validated empty report.
    if not owner._opaque:
        return Result(fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    return Result(
        OwnedReportInfo(
            storage.value.header.copy(),
            storage.value.core.copy(),
            storage.value.authorizer.copy(),
            storage.value.auth_gas.copy(),
            storage.value.prerequisite_count,
            storage.value.lookup_count,
            storage.value.digest_count,
            len(storage.wire),
        )
    )


# Copy authorization output at index zero or successful digest i at index i+1, bound to this owner alone.
def copy_report_blob(
    owner: OwnedReport, index: Int, output: Span[mut=True, UInt8, _]
) -> WriteResult:
    # Owner and signed index validation precede every private metadata access.
    if not owner._opaque:
        return WriteResult(fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    if index < 0 or index > storage.value.digest_count:
        return WriteResult(fail["invalidindex"]())
    var blob = storage.value.auth_output.copy()
    # A work error is not an empty successful blob and must reject payload extraction.
    if index > 0:
        var digest = storage.value.digests[index - 1].value().copy()
        if not digest.output.isa[BlobSpan]():
            # Payload-free output tags have no owner-bound bytes to extract.
            return WriteResult(fail["invalidindex"]())
        blob = digest.output[BlobSpan].copy()
    # Prove full capacity and disjointness before any destination mutation.
    if len(output) < blob.length:
        return WriteResult(fail["outputtoosmall"]())
    if overlaps(
        UInt(storage.wire.unsafe_ptr()), len(storage.wire), UInt(output.unsafe_ptr()), blob.length
    ):
        return WriteResult(fail["aliasedbuffers"]())
    output[: blob.length].copy_from(Span(storage.wire)[blob.offset : blob.offset + blob.length])
    return WriteResult(Written(blob.length))


# Re-emit the canonical consumed snapshot atomically, without exporting its backing bytes.
def encode_owned_report(owner: OwnedReport, output: Span[mut=True, UInt8, _]) -> WriteResult:
    # Default owners cannot be mistaken for a validated report.
    if not owner._opaque:
        return WriteResult(fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    if len(output) < len(storage.wire):
        # A short destination must remain completely untouched.
        return WriteResult(fail["outputtoosmall"]())
    if overlaps(
        UInt(storage.wire.unsafe_ptr()),
        len(storage.wire),
        UInt(output.unsafe_ptr()),
        len(storage.wire),
    ):
        # Unsafe callers cannot arrange output over otherwise opaque retained bytes.
        return WriteResult(fail["aliasedbuffers"]())
    output[: len(storage.wire)].copy_from(Span(storage.wire))
    return WriteResult(Written(len(storage.wire)))


# Return a digest's copied fixed fields and length-only output metadata, keeping all payloads owner-bound.
def owned_report_digest(owner: OwnedReport, index: Int) -> CheckedResult[OwnedDigestInfo]:
    comptime Result = CheckedResult[OwnedDigestInfo]
    # A missing owner or out-of-range signed index exposes only a reason.
    if not owner._opaque:
        return Result(fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    if index < 0 or index >= storage.value.digest_count:
        return Result(fail["invalidindex"]())
    var digest = storage.value.digests[index].value().copy()
    var output: OwnedWorkInfo
    # Success has a length; errors retain their payload-free protocol tag.
    if digest.output.isa[BlobSpan]():
        output = OwnedWorkInfo(OwnedPresent(digest.output[BlobSpan].length))
    else:
        output = OwnedWorkInfo(digest.output[WorkFailure].copy())
    return Result(
        OwnedDigestInfo(
            digest.service.copy(),
            digest.code_hash.copy(),
            digest.payload_hash.copy(),
            digest.accumulate_gas.copy(),
            output^,
            digest.refine.copy(),
        )
    )


# Return one owned prerequisite hash; no relationship to a mutable caller pool is needed.
def owned_report_prerequisite(owner: OwnedReport, index: Int) -> CheckedResult[PackageHash]:
    # Null owners cannot supply validated dependency identities.
    if not owner._opaque:
        return CheckedResult[PackageHash](fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    if index < 0 or index >= storage.value.prerequisite_count:
        # Signed bounds are checked before fixed-array indexing.
        return CheckedResult[PackageHash](fail["invalidindex"]())
    return CheckedResult[PackageHash](storage.value.prerequisites[index].copy())


# Return one owned key/root pair without exposing snapshot storage or source-buffer coordinates.
def owned_report_lookup(owner: OwnedReport, index: Int) -> CheckedResult[SegmentLookup]:
    # Null owners cannot supply validated dictionary entries.
    if not owner._opaque:
        return CheckedResult[SegmentLookup](fail["invalidowner"]())
    ref storage = unsafe_report_storage(owner)[]
    if index < 0 or index >= storage.value.lookup_count:
        # Fixed-array capacity alone does not establish membership in the decoded dictionary.
        return CheckedResult[SegmentLookup](fail["invalidindex"]())
    return CheckedResult[SegmentLookup](storage.value.lookup[index].copy())
