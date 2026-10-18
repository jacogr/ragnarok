# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Lookup canonical work reports retained in configured genesis availability assignments and ready queues.
## Exposes nominal report identities and guarded immutable report results; no archive or validity claim.

import ./genesis
import ../state/store
import ../codec/[assurances, state_layout, state_safrole, state_availability, guarantees,
    report_owned, owned, bounded, state_workqueues]
import ../crypto/primitives
export report_owned, owned

type
  ## Report identity hashes the exact canonical report, excluding guarantee credentials and slots.
  WorkReportHash* = distinct array[32, byte]
  ## Missing reports differ from malformed state, resource refusal and native hash failure.
  ReportReadError* {.pure.} = enum
    Uninitialized, None, Missing, Malformed, LimitExceeded, BackendFailure
  ## The successful immutable report retains its acyclic owner after the parent decoder is released.
  ReportReadResult* = object
    case status: ReportReadError
    of None:
      completed: OwnedReport
    else:
      discard # Failures carry no report or partial bytes.

## Inspect the reason without permitting callers to retag the result.
func error*(value: ReportReadResult): ReportReadError = value.status
## Retain the immutable report only after selecting successful lookup.
func value*(value: ReportReadResult): OwnedReport {.requires: value.status ==
    ReportReadError.None.} = value.completed

## Hash one immutable canonical report and apply the reply budget only to a matching identity.
proc matchReport(report: OwnedReport, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  let metadata = ownedReportInfo(report)
  if metadata.error != OwnershipError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Require a validated retained report.
  var bytes = newSeq[byte](metadata.value.consumed)
  if encodeOwnedReport(report, bytes).error != OwnershipError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Exact allocation must permit full re-encoding.
  let identity = blake2b256(bytes)
  if identity.error != CryptoError.None:
    return ReportReadResult(status: ReportReadError.BackendFailure) # Hash refusal must not become absence.
  if array[32, byte](identity.value) == array[32, byte](hash):
    # Budget applies to the matching report, not unrelated reports needed for the search.
    if uint64(bytes.len) > uint64(limit):
      return ReportReadResult(status: ReportReadError.LimitExceeded) # Never truncate a matched report.
    return ReportReadResult(status: ReportReadError.None, completed: report)
  ReportReadResult(status: ReportReadError.Missing)

## Search complete bounded C(10) assignments using the actual C(8) validator roster.
## Absence means this node has no retained report; unknown reports are never fetched or fabricated.
proc availabilityReport(view: Genesis, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  let found = view.lookup(chapterKey(StateChapter(10)))
  if found.error == StateStoreError.Uninitialized:
    return ReportReadResult(status: ReportReadError.Uninitialized) # Default genesis contains no state.
  if found.error == StateStoreError.MissingKey:
    return ReportReadResult(status: ReportReadError.Missing) # No configured assignments supply reports.
  if found.error != StateStoreError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Preserve unexpected store failure.
  if found.value.byteLength > 1024 * 1024:
    return ReportReadResult(status: ReportReadError.LimitExceeded) # Bound parent copying before decoding.
  let roster = view.lookup(chapterKey(StateChapter(8)))
  if roster.error != StateStoreError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Credential framing needs real roster context.
  if roster.value.byteLength > 1024 * 1024:
    return ReportReadResult(status: ReportReadError.LimitExceeded) # Independently bound context copying.
  let rosterWire = roster.value.bytes
  let validators = decodeStateValidators(rosterWire, ValidatorStateConfig(cores: view.cores,
    validators: ElementLimit(1023), maxBytes: ByteLimit(1024 * 1024)))
  if validators.error != StateComponentError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Invalid roster cannot authorize report parsing.
  if validators.value.consumed != rosterWire.len:
    return ReportReadResult(status: ReportReadError.Malformed) # Require the entire chapter.
  let population = validatorCount(validators.value.value)
  if population.error != StateComponentError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Only valid owners provide counts.
  let wire = found.value.bytes
  let decoded = decodeAvailabilityState(wire, AvailabilityConfig(guarantee: GuaranteeConfig(
    cores: view.cores, validators: ValidatorCount(population.value), maxBytes: ByteLimit(1024 *
        1024)),
    maxPresent: ElementLimit(341), maxBytes: ByteLimit(1024 * 1024)))
  if decoded.error != AvailabilityError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Complete parent preflight rejects late malformed assignments.
  if decoded.value.consumed != wire.len:
    return ReportReadResult(status: ReportReadError.Malformed) # Never search only a valid prefix.
  for index in 0..<int(view.cores):
    # Assignment owners are immutable and every index is bounded by the configured core count.
    let assignment = availabilityAt(decoded.value.snapshot, AssignmentCoreIndex(index))
    if assignment.error != AvailabilityError.None:
      return ReportReadResult(status: ReportReadError.Malformed) # No partial lookup from an invalid owner.
    if assignment.value.present:
      # Only present slots contain report handles; credentials and registration time are excluded.
      let report = assignment.value.guarantee.report
      let matched = matchReport(report, hash, limit)
      if matched.error != ReportReadError.Missing:
        return matched # Success and refusal terminate lookup; only a different identity continues.
  ReportReadResult(status: ReportReadError.Missing)

## Search C(14) using the epoch length retained with this exact genesis snapshot.
## Complete-ring preflight precedes matching, including all dependency sets and trailing rows.
proc readyReport(view: Genesis, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  let found = view.lookup(chapterKey(StateChapter(14)))
  if found.error == StateStoreError.MissingKey:
    return ReportReadResult(status: ReportReadError.Missing) # An absent ready queue supplies no reports.
  if found.error != StateStoreError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # Called only after availability validates the owner.
  if found.value.byteLength > 1024 * 1024 or uint64(view.epochSlots) > 4096:
    return ReportReadResult(status: ReportReadError.LimitExceeded) # Bound bytes and even empty row descriptors before allocation.
  let wire = found.value.bytes
  let decoded = decodeReadyState(wire, WorkQueueConfig(epochSlots: view.epochSlots,
    cores: view.cores, perSlot: ElementLimit(4096), totalItems: ElementLimit(4096),
    perDependencies: ElementLimit(64), totalDependencies: ElementLimit(16384),
    reportBytes: ByteLimit(1024 * 1024), maxBytes: ByteLimit(1024 * 1024)))
  if decoded.error == WorkQueueError.LimitExceeded:
    return ReportReadResult(status: ReportReadError.LimitExceeded) # Resource refusal is distinct from absence.
  if decoded.error != WorkQueueError.None:
    return ReportReadResult(status: ReportReadError.Malformed) # No early match may hide a malformed later row.
  if decoded.value.consumed != wire.len:
    return ReportReadResult(status: ReportReadError.Malformed) # The supplied chapter has no suffix.
  let owner = decoded.value.snapshot
  for slot in 0..<int(view.epochSlots):
    # Row count and epoch policy have been validated before native narrowing.
    let position = WorkQueueSlot(slot)
    let count = readySlotCount(owner, position)
    if count.error != WorkQueueError.None:
      return ReportReadResult(status: ReportReadError.Malformed) # Invalid owners cannot supply row extents.
    for index in 0..<count.value:
      # Preserve queue order while searching every retained report, including duplicate identities.
      let item = readyItemAt(owner, position, ReadyItemIndex(index))
      if item.error != WorkQueueError.None:
        return ReportReadResult(status: ReportReadError.Malformed) # No partial item extraction.
      let matched = matchReport(item.value.report, hash, limit)
      if matched.error != ReportReadError.Missing:
        return matched # Successful report owners survive retirement of the enclosing queue.
  ReportReadResult(status: ReportReadError.Missing)

## Prefer C(10) and fall back to C(14) only for an ordinary miss; never mask malformed assignments.
## This is bounded local retention, not archive retrieval, signature checking or network fetching.
proc workReport*(view: Genesis, hash: WorkReportHash, limit: ByteLimit): ReportReadResult =
  let available = availabilityReport(view, hash, limit)
  if available.error != ReportReadError.Missing:
    return available # Preserve success, default-owner failure and every availability refusal.
  readyReport(view, hash, limit)
