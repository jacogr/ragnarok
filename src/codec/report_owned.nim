# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable report snapshots retain private wire bytes and bounded metadata through acyclic ARC
## ownership.
##
## Exposes decodeOwnedReport, report metadata/child access, bounded blob copies and re-encoding
## from retained report snapshots.

import ./composite
import ./work/[digest as work_digest, report as work_report]
import ./owned

type
  # Private acyclic storage binds all successful payload descriptors to their original validated snapshot.
  ReportData = ref object
    value: WorkReport
    wire: seq[byte]
  OwnedReport* = object ## Copying this opaque handle retains the immutable snapshot automatically; no manual release is required.
    data: nil ReportData
  OwnedReportInfo* = object ## Fixed/count metadata includes trace length and never exposes mutable bytes or detached source coordinates.
    header*: ReportHeader
    core*: CoreIndex
    authorizer*: AuthorizerHash
    authGas*: Gas
    prerequisiteCount*, lookupCount*, digestCount*, authBytes*, consumed*: int

proc reportOwnedError(error: CompositeError): OwnershipError {.raises: [].} =
  ## Preserve exact wire failures while adding the existing owner/index/allocation failure domain.
  case error
  of Uninitialized: OwnershipError.Uninitialized # No complete report exists.
  of None: OwnershipError.None # The report validated completely.
  of Truncated: OwnershipError.Truncated # A required field is missing.
  of NonCanonical: OwnershipError.NonCanonical # Count/order/uniqueness is invalid.
  of LimitExceeded: OwnershipError.LimitExceeded # A structural resource bound failed.
  of OutputTooSmall: OwnershipError.OutputTooSmall # Complete destination storage is required.
  of AliasedBuffers: OwnershipError.AliasedBuffers # Borrowed source storage must stay stable.
  of LengthOverflow: OwnershipError.LengthOverflow # A host extent is unrepresentable.
  of InvalidTag: OwnershipError.InvalidTag # No such work-output variant exists.
  of InvalidSpan: OwnershipError.InvalidSpan # A caller descriptor is invalid.

proc decodeOwnedReport*(input: openArray[byte], coreCount: uint64): OwnedResult[
    OwnedReport] {.raises: [].} =
  ## Validate every field before retaining only the consumed prefix; Nim allocation exhaustion retains its fail-stop policy.
  let parsed = decodeReportBorrowed(input, coreCount)
  # A malformed final field cannot create an owner with partially trusted data.
  if parsed.error != CompositeError.None: return ownedFailure[OwnedReport](reportOwnedError(parsed.error))
  let data = ReportData(value: parsed.value, wire: newSeq[byte](parsed.consumed))
  # Complete reports are nonempty; the decoder proved the consumed source extent.
  copyMem(addr data.wire[0], unsafeAddr input[0], parsed.consumed)
  ownedSuccess[OwnedReport](OwnedReport(data: data))

proc ownedReportInfo*(owner: OwnedReport): OwnedResult[OwnedReportInfo] {.raises: [].} =
  ## Return copied fixed/count metadata while preserving the owner's private byte/descriptor relationship.
  # Missing owners cannot fabricate successfully validated empty reports.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[OwnedReportInfo](OwnershipError.InvalidOwner)
  let value = data.value
  ownedSuccess[OwnedReportInfo](OwnedReportInfo(
    header: value.header,
    core: value.core, authorizer: value.authorizer, authGas: value.authGas,
    prerequisiteCount: value.prerequisiteCount,
    lookupCount: value.lookupCount, digestCount: value.digestCount,
    authBytes: value.authOutput.length, consumed: data.wire.len))

proc reportOwnerOverlaps(data: ReportData, output: var openArray[byte],
    length: int): bool {.raises: [].} =
  ## Compare storage ranges by address difference without overflowing pointer-end arithmetic.
  # Empty copies use no destination address and therefore cannot alias.
  if length == 0: return false
  let a = cast[uint](unsafeAddr data.wire[0])
  let b = cast[uint](addr output[0])
  (a <= b and b-a < uint(data.wire.len)) or (b < a and a-b < uint(length))

proc ownedReportOverlapsOutput*(owner: OwnedReport, output: var openArray[byte]): OwnedResult[
    bool] {.raises: [].} =
  ## Let composed atomic encoders reject overlap with any part of their complete destination in preflight.
  ## Only a Boolean leaves this owner; no backing pointer or detached coordinate is exposed.
  # Default owners have no validated storage against which an alias claim can be made.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[bool](OwnershipError.InvalidOwner)
  ownedSuccess[bool](reportOwnerOverlaps(data, output, output.len))

proc copyReportBlob*(owner: OwnedReport, index: int, output: var openArray[byte]): OwnedResult[
    int] {.raises: [].} =
  ## Copy authorization output at zero or digest i's successful payload at i+1, always bound to this owner alone.
  # Owner and signed index proofs precede descriptor access.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[int](OwnershipError.InvalidOwner)
  if index < 0 or index > data.value.digestCount: return ownedFailure[int](
      OwnershipError.InvalidIndex)
  var blob = data.value.authOutput
  # Payload-free work errors reject extraction instead of appearing as empty successes.
  if index > 0:
    let digest = data.value.digests[index-1]
    if digest.output.kind != WorkKind.Success: return ownedFailure[int](OwnershipError.InvalidIndex)
    blob = digest.output.blob
  # Capacity and disjointness must validate before any byte is written.
  if output.len < blob.length: return ownedFailure[int](OwnershipError.OutputTooSmall)
  if reportOwnerOverlaps(data, output, blob.length): return ownedFailure[int](
      OwnershipError.AliasedBuffers)
  if blob.length > 0:
    # Captured coordinates were validated against this exact private consumed prefix.
    copyMem(addr output[0], unsafeAddr data.wire[blob.offset], blob.length)
  ownedSuccess[int](blob.length)

proc encodeOwnedReport*(owner: OwnedReport, output: var openArray[byte]): OwnedResult[
    int] {.raises: [].} =
  ## Atomically re-emit the canonical private snapshot without exporting its backing bytes.
  # A default handle must not masquerade as a validated empty report.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[int](OwnershipError.InvalidOwner)
  let length = data.wire.len
  if output.len < length: return ownedFailure[int](OwnershipError.OutputTooSmall)
  if reportOwnerOverlaps(data, output, length): return ownedFailure[int](
      OwnershipError.AliasedBuffers)
  copyMem(addr output[0], unsafeAddr data.wire[0], length)
  ownedSuccess[int](length)

proc ownedReportDigest*(owner: OwnedReport, index: int): OwnedResult[OwnedDigestInfo] {.raises: [].} =
  ## Return copied digest fields with length-only successful output metadata, keeping payloads private to their owner.
  # Missing owners and signed invalid indices expose only their reason.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[OwnedDigestInfo](OwnershipError.InvalidOwner)
  if index < 0 or index >= data.value.digestCount: return ownedFailure[OwnedDigestInfo](
      OwnershipError.InvalidIndex)
  let digest = data.value.digests[index]
  let output = if digest.output.kind == WorkKind.Success: successfulOwnedWorkInfo(
      digest.output.blob.length) else: failedOwnedWorkInfo(digest.output.kind)
  ownedSuccess[OwnedDigestInfo](OwnedDigestInfo(
    service: digest.service,
    codeHash: digest.codeHash, payloadHash: digest.payloadHash, accumulateGas: digest.accumulateGas,
    output: output, refine: digest.refine))

proc ownedReportPrerequisite*(owner: OwnedReport, index: int): OwnedResult[PackageHash] {.raises: [].} =
  ## Return one owned prerequisite identity, never a detached coordinate into caller storage.
  # Bounds describe decoded membership, not merely unused fixed-array capacity.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[PackageHash](OwnershipError.InvalidOwner)
  if index < 0 or index >= data.value.prerequisiteCount: return ownedFailure[PackageHash](
      OwnershipError.InvalidIndex)
  ownedSuccess[PackageHash](data.value.prerequisites[index])

proc ownedReportLookup*(owner: OwnedReport, index: int): OwnedResult[SegmentLookup] {.raises: [].} =
  ## Return one owned dictionary key/root pair while preserving private backing storage.
  # A null owner or invalid signed index cannot expose default dictionary metadata.
  # Retain one stable reference so nil analysis and ARC lifetime cover all subsequent reads.
  let data = owner.data
  if data == nil: return ownedFailure[SegmentLookup](OwnershipError.InvalidOwner)
  if index < 0 or index >= data.value.lookupCount: return ownedFailure[SegmentLookup](
      OwnershipError.InvalidIndex)
  ownedSuccess[SegmentLookup](data.value.lookup[index])
