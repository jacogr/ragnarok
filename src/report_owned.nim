## Immutable report snapshots retain private wire bytes and bounded metadata through acyclic ARC ownership.
import ./[composite, work_digest, work_report, owned]

type
  # Private acyclic storage binds all successful payload descriptors to their original validated snapshot.
  ReportData = ref object
    value: WorkReport
    wire: seq[byte]
  # Copying this opaque handle retains the immutable snapshot automatically; no manual release is required.
  OwnedReport* = object
    data: ReportData
  # Fixed/count metadata owns values and never exposes mutable bytes or detached source coordinates.
  OwnedReportInfo* = object
    header*: ReportHeader
    core*: CoreIndex
    authorizer*: AuthorizerHash
    authGas*: Gas
    prerequisiteCount*, lookupCount*, digestCount*, consumed*: int

# Preserve exact wire failures while adding the existing owner/index/allocation failure domain.
proc reportOwnedError(error: CompositeError): OwnershipError {.raises: [].} =
  case error
  of CompositeError.Uninitialized: OwnershipError.Uninitialized # No complete report exists.
  of CompositeError.None: OwnershipError.None # The report validated completely.
  of CompositeError.Truncated: OwnershipError.Truncated # A required field is missing.
  of CompositeError.NonCanonical: OwnershipError.NonCanonical # Count/order/uniqueness is invalid.
  of CompositeError.LimitExceeded: OwnershipError.LimitExceeded # A structural resource bound failed.
  of CompositeError.OutputTooSmall: OwnershipError.OutputTooSmall # Complete destination storage is required.
  of CompositeError.AliasedBuffers: OwnershipError.AliasedBuffers # Borrowed source storage must stay stable.
  of CompositeError.LengthOverflow: OwnershipError.LengthOverflow # A host extent is unrepresentable.
  of CompositeError.InvalidTag: OwnershipError.InvalidTag # No such work-output variant exists.
  of CompositeError.InvalidSpan: OwnershipError.InvalidSpan # A caller descriptor is invalid.

# Validate every field before retaining only the consumed prefix; Nim allocation exhaustion retains its fail-stop policy.
proc decodeOwnedReport*(input: openArray[byte], coreCount: uint64): OwnedResult[
    OwnedReport] {.raises: [].} =
  let parsed = decodeReportBorrowed(input, coreCount)
  # A malformed final field cannot create an owner with partially trusted data.
  if parsed.error != CompositeError.None: return OwnedResult[OwnedReport](error: reportOwnedError(parsed.error))
  let data = ReportData(value: parsed.value, wire: newSeq[byte](parsed.consumed))
  # Complete reports are nonempty; the decoder proved the consumed source extent.
  copyMem(addr data.wire[0], unsafeAddr input[0], parsed.consumed)
  OwnedResult[OwnedReport](error: OwnershipError.None, value: OwnedReport(data: data))

# Return copied fixed/count metadata while preserving the owner's private byte/descriptor relationship.
proc ownedReportInfo*(owner: OwnedReport): OwnedResult[OwnedReportInfo] {.raises: [].} =
  # Missing owners cannot fabricate successfully validated empty reports.
  if owner.data.isNil: return OwnedResult[OwnedReportInfo](error: OwnershipError.InvalidOwner)
  let value = owner.data.value
  OwnedResult[OwnedReportInfo](error: OwnershipError.None, value: OwnedReportInfo(
    header: value.header,
    core: value.core, authorizer: value.authorizer, authGas: value.authGas,
    prerequisiteCount: value.prerequisiteCount,
    lookupCount: value.lookupCount, digestCount: value.digestCount, consumed: owner.data.wire.len))

# Compare storage ranges by address difference without overflowing pointer-end arithmetic.
proc reportOwnerOverlaps(data: ReportData, output: var openArray[byte],
    length: int): bool {.raises: [].} =
  # Empty copies use no destination address and therefore cannot alias.
  if length == 0: return false
  let a = cast[uint](unsafeAddr data.wire[0])
  let b = cast[uint](addr output[0])
  (a <= b and b-a < uint(data.wire.len)) or (b < a and a-b < uint(length))

# Let composed atomic encoders reject overlap with any part of their complete destination in preflight.
# Only a Boolean leaves this owner; no backing pointer or detached coordinate is exposed.
proc ownedReportOverlapsOutput*(owner: OwnedReport, output: var openArray[byte]): OwnedResult[
    bool] {.raises: [].} =
  # Default owners have no validated storage against which an alias claim can be made.
  if owner.data.isNil: return OwnedResult[bool](error: OwnershipError.InvalidOwner)
  OwnedResult[bool](error: OwnershipError.None,
    value: reportOwnerOverlaps(owner.data, output, output.len))

# Copy authorization output at zero or digest i's successful payload at i+1, always bound to this owner alone.
proc copyReportBlob*(owner: OwnedReport, index: int, output: var openArray[byte]): OwnedResult[
    int] {.raises: [].} =
  # Owner and signed index proofs precede descriptor access.
  if owner.data.isNil: return OwnedResult[int](error: OwnershipError.InvalidOwner)
  if index < 0 or index > owner.data.value.digestCount: return OwnedResult[int](
      error: OwnershipError.InvalidIndex)
  var blob = owner.data.value.authOutput
  # Payload-free work errors reject extraction instead of appearing as empty successes.
  if index > 0:
    let digest = owner.data.value.digests[index-1]
    if digest.output.kind != WorkKind.Success: return OwnedResult[int](
        error: OwnershipError.InvalidIndex)
    blob = digest.output.blob
  # Capacity and disjointness must validate before any byte is written.
  if output.len < blob.length: return OwnedResult[int](error: OwnershipError.OutputTooSmall)
  if reportOwnerOverlaps(owner.data, output, blob.length): return OwnedResult[int](
      error: OwnershipError.AliasedBuffers)
  if blob.length > 0:
    # Captured coordinates were validated against this exact private consumed prefix.
    copyMem(addr output[0], unsafeAddr owner.data.wire[blob.offset], blob.length)
  OwnedResult[int](error: OwnershipError.None, value: blob.length)

# Atomically re-emit the canonical private snapshot without exporting its backing bytes.
proc encodeOwnedReport*(owner: OwnedReport, output: var openArray[byte]): OwnedResult[
    int] {.raises: [].} =
  # A default handle must not masquerade as a validated empty report.
  if owner.data.isNil: return OwnedResult[int](error: OwnershipError.InvalidOwner)
  let length = owner.data.wire.len
  if output.len < length: return OwnedResult[int](error: OwnershipError.OutputTooSmall)
  if reportOwnerOverlaps(owner.data, output, length): return OwnedResult[int](
      error: OwnershipError.AliasedBuffers)
  copyMem(addr output[0], unsafeAddr owner.data.wire[0], length)
  OwnedResult[int](error: OwnershipError.None, value: length)

# Return copied digest fields with length-only successful output metadata, keeping payloads private to their owner.
proc ownedReportDigest*(owner: OwnedReport, index: int): OwnedResult[OwnedDigestInfo] {.raises: [].} =
  # Missing owners and signed invalid indices expose only their reason.
  if owner.data.isNil: return OwnedResult[OwnedDigestInfo](error: OwnershipError.InvalidOwner)
  if index < 0 or index >= owner.data.value.digestCount: return OwnedResult[OwnedDigestInfo](
      error: OwnershipError.InvalidIndex)
  let digest = owner.data.value.digests[index]
  let output = if digest.output.kind == WorkKind.Success: OwnedWorkInfo(kind: WorkKind.Success,
      length: digest.output.blob.length) else: OwnedWorkInfo(kind: digest.output.kind)
  OwnedResult[OwnedDigestInfo](error: OwnershipError.None, value: OwnedDigestInfo(
    service: digest.service,
    codeHash: digest.codeHash, payloadHash: digest.payloadHash, accumulateGas: digest.accumulateGas,
    output: output, refine: digest.refine))

# Return one owned prerequisite identity, never a detached coordinate into caller storage.
proc ownedReportPrerequisite*(owner: OwnedReport, index: int): OwnedResult[PackageHash] {.raises: [].} =
  # Bounds describe decoded membership, not merely unused fixed-array capacity.
  if owner.data.isNil: return OwnedResult[PackageHash](error: OwnershipError.InvalidOwner)
  if index < 0 or index >= owner.data.value.prerequisiteCount: return OwnedResult[PackageHash](
      error: OwnershipError.InvalidIndex)
  OwnedResult[PackageHash](error: OwnershipError.None, value: owner.data.value.prerequisites[index])

# Return one owned dictionary key/root pair while preserving private backing storage.
proc ownedReportLookup*(owner: OwnedReport, index: int): OwnedResult[SegmentLookup] {.raises: [].} =
  # A null owner or invalid signed index cannot expose default dictionary metadata.
  if owner.data.isNil: return OwnedResult[SegmentLookup](error: OwnershipError.InvalidOwner)
  if index < 0 or index >= owner.data.value.lookupCount: return OwnedResult[SegmentLookup](
      error: OwnershipError.InvalidIndex)
  OwnedResult[SegmentLookup](error: OwnershipError.None, value: owner.data.value.lookup[index])
