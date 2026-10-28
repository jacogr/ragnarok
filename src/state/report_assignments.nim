# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 reportcoresareunused and availassignmentspostguarantees: pure post-assurance C(10)
## planning. This does not publish state or replace full report-policy, package, anchor or
## admitted-block context checks.
##
## Exposes planReportAssignments and access to the retained source, resulting availability state
## and serialized entry.

import ../codec/bounded as codec_bounded
import ../codec/assurances as codec_assurances
import ../codec/guarantees as codec_guarantees
import ../codec/state_safrole as codec_state_safrole
import ../codec/state_availability as codec_state_availability
import ../codec/state_layout as codec_state_layout
import ../codec/state_trie as codec_state_trie
import ../codec/report_owned as codec_report_owned
import ./guarantee_credentials as state_guarantee_credentials

type
  ReportAssignmentError* {.pure.} = enum ## Default and refused plans contain a reason only, never partial assignments or serialized progress.
    Uninitialized, None, InvalidConfig, InvalidCredentials, InvalidAssignments,
    LimitExceeded, InactiveCore, OccupiedCore
  ## Private acyclic owner binds original post-assurance state, credentials and exact completed C(10) candidate.
  AssignmentData = ref object
    credentials: VerifiedGuaranteeCredentials
    source: AvailabilitySnapshot
    candidate: AvailabilitySnapshot
    entry: StateEntry
  ReportAssignmentPlan* = object ## A completed assignment candidate is not a complete report-admission or publication certificate.
    data: nil AssignmentData
  ReportAssignmentResult*[T] = object ## Only selected success carries a retained plan or copied serialization.
    case status: ReportAssignmentError
    of None:
      completed: T
    else:
      discard # No successful payload after default initialization or refusal.

func error*[T](outcome: ReportAssignmentResult[T]): ReportAssignmentError =
  ## Inspect the reason without allowing external retagging.
  outcome.status
func value*[T](outcome: ReportAssignmentResult[T]): T {.inline,
    requires: outcome.status == ReportAssignmentError.None.} =
  ## Extract complete success only under supported checked-build contracts.
  outcome.completed

proc reportAssignmentSource*(plan: ReportAssignmentPlan): ReportAssignmentResult[
    AvailabilitySnapshot] =
  ## Retain the exact original post-assurance assignment table, independently of caller scope.
  let data = plan.data
  if data == nil:
    return ReportAssignmentResult[AvailabilitySnapshot](
        status: ReportAssignmentError.Uninitialized) # No default empty table.
  ReportAssignmentResult[AvailabilitySnapshot](status: ReportAssignmentError.None,
      completed: data.source)

proc reportAssignmentState*(plan: ReportAssignmentPlan): ReportAssignmentResult[
    AvailabilitySnapshot] =
  ## Retain the proposed immutable table, whose new children include complete original guarantees.
  let data = plan.data
  if data == nil:
    return ReportAssignmentResult[AvailabilitySnapshot](
        status: ReportAssignmentError.Uninitialized) # No partially completed candidate.
  ReportAssignmentResult[AvailabilitySnapshot](status: ReportAssignmentError.None,
      completed: data.candidate)

proc reportAssignmentByteLength*(plan: ReportAssignmentPlan): ReportAssignmentResult[int] =
  ## Inspect exact retained encoding extent before bounded callers request a copied entry; no encoding or hashing occurs.
  let data = plan.data
  if data == nil:
    return ReportAssignmentResult[int](status: ReportAssignmentError.Uninitialized) # Defaults have no encoded chapter.
  ReportAssignmentResult[int](status: ReportAssignmentError.None, completed: data.entry.value.len)

proc reportAssignmentEntry*(plan: ReportAssignmentPlan): ReportAssignmentResult[StateEntry] =
  ## Copy exact proposed chapter bytes; mutating this ordinary value cannot alter the retained candidate.
  let data = plan.data
  if data == nil:
    return ReportAssignmentResult[StateEntry](status: ReportAssignmentError.Uninitialized) # No fabricated chapter.
  var copy = StateEntry(key: data.entry.key, value: newSeq[byte](data.entry.value.len))
  # Explicitly copy mutable bytes while retaining private serialized storage.
  for i in 0..<copy.value.len: copy.value[i] = data.entry.value[i]
  ReportAssignmentResult[StateEntry](status: ReportAssignmentError.None, completed: copy)

## Preserve ordinary byte/count refusal versus invalid profile and malformed table distinctions.
func codecError(reason: AvailabilityError): ReportAssignmentError =
  case reason
  of AvailabilityError.LimitExceeded, AvailabilityError.LengthOverflow:
    ReportAssignmentError.LimitExceeded # Current resource policy must apply to old and new records alike.
  of AvailabilityError.InvalidConfig:
    ReportAssignmentError.InvalidConfig # Caller supplied an unusable chain profile.
  else:
    ReportAssignmentError.InvalidAssignments # No malformed/default nested record becomes valid state.

proc planReportAssignments*(credentials: VerifiedGuaranteeCredentials,
    postAssurances: AvailabilitySnapshot, config: AvailabilityConfig): ReportAssignmentResult[
        ReportAssignmentPlan] =
  ## Caller supplies the actual post-assurance table, not the parent table used for duplicate-package exclusion.
  ## Candidate time and active population come from the credential certificate, never a second loose projection.
  ## Revalidate the whole source and every destination before constructing the final candidate; no writes or hashing occur.
  let context = credentials.verifiedGuaranteeContext
  if context.error != GuaranteeCredentialError.None:
    return ReportAssignmentResult[ReportAssignmentPlan](
        status: ReportAssignmentError.InvalidCredentials) # Require completed credential verification, including empty batches.
  let cores = uint64(config.guarantee.cores)
  let ceiling = uint64(config.guarantee.validators)
  if cores < 2 or cores > 341 or ceiling < 6 or ceiling > cores*3 or ceiling mod 3 != 0:
    return ReportAssignmentResult[ReportAssignmentPlan](
        status: ReportAssignmentError.InvalidConfig) # Bound all core descriptors before allocation/narrowing.
  let population = uint64(context.value.population)
  if population > ceiling:
    return ReportAssignmentResult[ReportAssignmentPlan](
        status: ReportAssignmentError.LimitExceeded) # A certificate made under a looser population profile cannot bypass this ceiling.
  let info = availabilityInfo(postAssurances)
  if info.error != AvailabilityError.None:
    return ReportAssignmentResult[ReportAssignmentPlan](
        status: ReportAssignmentError.InvalidAssignments) # A default is not an all-absent table.
  if uint64(info.value.cores) != cores:
    return ReportAssignmentResult[ReportAssignmentPlan](
        status: ReportAssignmentError.InvalidConfig) # Exact fixed core domain only.
  var slots = newSeq[AvailabilityAssignment](info.value.cores)
  # Preserve every untouched child and its registration time; validate the earlier stage's postconditions.
  for i in 0..<slots.len:
    slots[i] = availabilityAt(postAssurances, AssignmentCoreIndex(i)).value
    if slots[i].present:
      if uint64(i) >= population div 3:
        return ReportAssignmentResult[ReportAssignmentPlan](
            status: ReportAssignmentError.InactiveCore) # Earlier resize clearing must already have removed inactive assignments.
      if uint64(ownedReportInfo(slots[i].guarantee.report).value.core) != uint64(i):
        return ReportAssignmentResult[ReportAssignmentPlan](
            status: ReportAssignmentError.InvalidAssignments) # A present assignment must belong to its row's core.
  let source = availabilityStateEntry(slots, config)
  if source.error != AvailabilityError.None:
    return ReportAssignmentResult[ReportAssignmentPlan](status: codecError(
        source.error)) # Recheck originally looser captures before planning any replacement.
  let count = credentials.verifiedGuaranteeCount.value
  # Reject the whole batch before replacing even the first locally copied destination.
  for i in 0..<count:
    let core = uint64(ownedReportInfo(credentials.verifiedGuaranteeAt(i).value.report).value.core)
    if core >= population div 3 or core >= cores:
      return ReportAssignmentResult[ReportAssignmentPlan](
          status: ReportAssignmentError.InactiveCore) # Current population bounds every new destination.
    if slots[int(core)].present:
      return ReportAssignmentResult[ReportAssignmentPlan](
          status: ReportAssignmentError.OccupiedCore) # Never evict a report that survived assurances.
  # Install complete guarantees, distinguishing their evaluation slot from this block's registration time.
  for i in 0..<count:
    let guarantee = credentials.verifiedGuaranteeAt(i).value
    let core = int(uint64(ownedReportInfo(guarantee.report).value.core))
    slots[core] = presentAssignment(guarantee, AssignmentSlot(uint32(context.value.slot)))
  let encoded = availabilityStateEntry(slots, config)
  if encoded.error != AvailabilityError.None:
    return ReportAssignmentResult[ReportAssignmentPlan](status: codecError(
        encoded.error)) # Aggregate new-present/byte budgets are checked without partial output.
  let captured = decodeAvailabilityState(encoded.value.value, config)
  if captured.error != AvailabilityError.None:
    return ReportAssignmentResult[ReportAssignmentPlan](status: codecError(
        captured.error)) # No candidate owner without a complete codec capture.
  ReportAssignmentResult[ReportAssignmentPlan](status: ReportAssignmentError.None,
    completed: ReportAssignmentPlan(data: AssignmentData(credentials: credentials,
      source: postAssurances,
      candidate: captured.value.snapshot, entry: encoded.value)))
