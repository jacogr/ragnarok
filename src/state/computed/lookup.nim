# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validate original lookup age and full sealed-header ancestry against the same admitted parent endpoint.

import ../../codec/[bounded, header, assurances]
import ../../chain/parameters
import ../../crypto/primitives
import ./[recent as computed_recent, state as computed_state, links as computed_links,
    guarantee as computed_guarantee, report as computed_report]
import "../block/admission" as block_admission
import ../availability/specifier as availability_specifier
import "../export/erasure" as export_erasure
import ../bundle_erasure
import ../erasure/layout as erasure_layout
import ../[auditable_bundle, input_refinement]
import ../report/identity as report_identity
import ../authorized_refinement
import ../authorization/invocation as authorization_invocation

type
  ComputedLookupError* {.pure.} = enum ## Refusals expose no partial chain, detached root or accepted prefix.
    Uninitialized, None, InvalidSource, LookupTooOld, LimitExceeded, InvalidHeader,
    BackendFailure, BrokenAncestry, MissingLookupAnchor, WrongLookupState, InvalidIndex
  ComputedAncestorIndex* = distinct uint64 ## Retained chain ordinal is distinct from work-item and lookup-dictionary ordinals.
  ComputedLookupLimits* = object ## Independent local ceilings count parent plus older headers and their complete encoded preimages.
    headers*: ElementLimit
    headerBytes*, bytes*: ByteLimit
  ComputedLookupInfo* = object ## Fixed copied match and resource facts do not substitute for the retained source/chain.
    anchor*: ComputedAncestorIndex
    headers*: int
    bytes*: uint64
  ComputedLookupData = ref object ## Immutable acyclic ownership retains the exact recent source and all recaptured ancestor headers.
    source: RecentComputedReport
    headers: seq[OwnedHeader]
    info: ComputedLookupInfo
  LookupAnchoredComputedReport* = object ## Endpoint-relative ancestry is not a consensus, availability or signing certificate.
    data: nil ComputedLookupData
  ComputedLookupResult*[T] = object ## The private successful alternative alone contains application data.
    case status: ComputedLookupError
    of None:
      completed: T
    else:
      discard # Defaults and refusals contain reasons alone.

func error*[T](outcome: ComputedLookupResult[T]): ComputedLookupError =
  ## Inspect the selected reason without writable discriminator access.
  outcome.status

func value*[T](outcome: ComputedLookupResult[T]): T
    {.requires: outcome.status == ComputedLookupError.None.} =
  ## Guard selected successful extraction in optimized execution.
  outcome.completed

proc computedLookupSource*(bound: LookupAnchoredComputedReport): ComputedLookupResult[
    RecentComputedReport] =
  ## Share the exact original recent/report/state/block provenance.
  let data = bound.data
  if data == nil: return ComputedLookupResult[RecentComputedReport](
      status: ComputedLookupError.Uninitialized)
  ComputedLookupResult[RecentComputedReport](status: ComputedLookupError.None,
      completed: data.source)

proc computedLookupInfo*(bound: LookupAnchoredComputedReport): ComputedLookupResult[
    ComputedLookupInfo] =
  ## Copy complete match/resource facts without exposing writable chain storage.
  let data = bound.data
  if data == nil: return ComputedLookupResult[ComputedLookupInfo](
      status: ComputedLookupError.Uninitialized)
  ComputedLookupResult[ComputedLookupInfo](status: ComputedLookupError.None, completed: data.info)

proc computedLookupHeader*(bound: LookupAnchoredComputedReport,
    index: ComputedAncestorIndex): ComputedLookupResult[OwnedHeader] =
  ## Check the full nominal ordinal before narrowing into immutable retained chain storage.
  let data = bound.data
  if data == nil: return ComputedLookupResult[OwnedHeader](
      status: ComputedLookupError.Uninitialized)
  if uint64(index) >= uint64(data.headers.len):
    return ComputedLookupResult[OwnedHeader](status: ComputedLookupError.InvalidIndex) # Never mask or wrap caller indices.
  ComputedLookupResult[OwnedHeader](status: ComputedLookupError.None, completed: data.headers[int(
      uint64(index))])

proc checkComputedLookupAnchor*(source: RecentComputedReport, older: openArray[OwnedHeader],
    limits: ComputedLookupLimits): ComputedLookupResult[LookupAnchoredComputedReport] =
  ## Derive clock/profile/endpoint, preflight all scratch and check the entire chain before retaining any success.
  template fail(reason: ComputedLookupError) =
    return ComputedLookupResult[LookupAnchoredComputedReport](status: reason)
  let selected = source.computedRecentSource
  if selected.error != ComputedRecentError.None: fail(ComputedLookupError.InvalidSource)
  let state = selected.value
  let binding = state.computedStateAdmission.value
  let report = state.computedStateSource.value.computedLinkSource.value.computedGuaranteeReport.value
  let claimed = report.computedReportInfo.value.header
  let identity = report.computedReportSource.value.availabilitySource.value.exportErasureSource.value.bundleErasureSource.value.layoutSource.value.bundleSource.value.inputRefinementIdentity.value
  let parameters = identity.identitySource.value.authorizedSource.value.authorizationParameters.value
  let current = uint64(uint32(headerInfo(binding.admittedHeader).value.unsigned.slot))
  let age = parameters.get(maxLookupAnchorAge)
  if current > age and uint64(uint32(claimed.lookupSlot)) < current-age:
    fail(ComputedLookupError.LookupTooOld) # Saturating lower bound with inclusive equality, before hashing/copying.
  if older.len == high(int) or uint64(older.len) >= uint64(limits.headers):
    fail(ComputedLookupError.LimitExceeded) # Reserve parent before adding or allocating.
  let count = older.len+1
  if count > high(int) div sizeof(OwnedHeader) or count > high(int) div 32:
    fail(ComputedLookupError.LimitExceeded) # Bound both typed descriptor arrays before allocation.
  let parent = binding.admittedParent
  var total = 0'u64
  # Validate every owner and byte extent before any variable allocation or primitive attempt.
  for index in 0..<count:
    let owner = if index == 0: parent else: older[index-1]
    let info = headerInfo(owner)
    if info.error != HeaderError.None: fail(ComputedLookupError.InvalidHeader)
    let size = uint64(info.value.consumed)
    if size > uint64(limits.headerBytes) or size > uint64(limits.bytes)-total:
      fail(ComputedLookupError.LimitExceeded) # Invariant total<=bytes proves subtraction and later addition.
    total += size
  # Completed recent validation proves 2<=cores<=341; original Parameters prove epoch>0.
  let cores = parameters.get(coreCount)
  let config = HeaderConfig(cores: CoreCount(cores), authorValidators: ValidatorCount(3*cores),
    epochSlots: EpochSlots(parameters.get(epochPeriod)), maxBytes: limits.headerBytes)
  var headers = newSeq[OwnedHeader](count)
  var hashes = newSeq[array[32, byte]](count)
  # Recapture and hash full sealed headers, validating every supplied suffix even after a possible lookup match.
  for index in 0..<count:
    let owner = if index == 0: parent else: older[index-1]
    var wire = newSeq[byte](headerInfo(owner).value.consumed)
    if encodeOwnedHeader(owner, wire).error != HeaderError.None: fail(
        ComputedLookupError.InvalidHeader)
    let decoded = decodeHeader(wire, config)
    if decoded.error == HeaderError.LimitExceeded: fail(ComputedLookupError.LimitExceeded)
    if decoded.error != HeaderError.None: fail(ComputedLookupError.InvalidHeader)
    if decoded.value.consumed != wire.len: fail(ComputedLookupError.InvalidHeader)
    headers[index] = decoded.value.owner
    let hash = blake2b256(wire)
    if hash.error != CryptoError.None: fail(ComputedLookupError.BackendFailure)
    hashes[index] = array[32, byte](hash.value)
    if index > 0:
      let child = headerInfo(headers[index-1]).value.unsigned
      let previous = headerInfo(headers[index]).value.unsigned
      let decreasing = uint32(previous.slot) < uint32(child.slot)
      if not decreasing or array[32, byte](child.parent) != hashes[index]:
        fail(ComputedLookupError.BrokenAncestry) # No skipped, reordered, duplicate or forked retained headers.
  # Index zero lacks a newer ancestor witness; the admitted candidate is deliberately excluded from this sequence.
  for index in 1..<count:
    let fields = headerInfo(headers[index]).value.unsigned
    if hashes[index] == claimed.lookupAnchor.bytes and uint32(fields.slot) == uint32(
        claimed.lookupSlot):
      let child = headerInfo(headers[index-1]).value.unsigned
      if array[32, byte](child.priorState) != claimed.lookupStateRoot.bytes:
        fail(ComputedLookupError.WrongLookupState) # Use immediate child's prior root, never the lookup header's own prior root.
      return ComputedLookupResult[LookupAnchoredComputedReport](status: ComputedLookupError.None,
        completed: LookupAnchoredComputedReport(data: ComputedLookupData(source: source,
          headers: headers, info: ComputedLookupInfo(anchor: ComputedAncestorIndex(uint64(index)),
            headers: count, bytes: total))))
  fail(ComputedLookupError.MissingLookupAnchor)
