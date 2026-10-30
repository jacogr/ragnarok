# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 judgments.tex: contextual verdict/evidence validation and immutable C(5)/C(10)
## planning. Parent rosters/time are read before Safrole rotation; no incomplete plan or
## cryptographic bypass escapes.
##
## Exposes planDisputes, checkDisputeMarker and publishDisputes with retained judgments,
## assignments and new-offender access.

import std/[algorithm, assertions]
import ../codec/disputes
import ../codec/state/[disputes as state_disputes, safrole as state_safrole,
    availability as state_availability, layout as state_layout, trie as state_trie]
import ../codec/[bounded, assurances, guarantees, report_owned, owned, header]
import ../crypto/primitives
import ./store

type
  DisputesConfig* = object ## Independent limits bound full parent chapters, roster copies and posterior judgment sets.
    rosters*: ValidatorStateConfig
    state*: DisputeStateConfig
    availability*: AvailabilityConfig
    epochSlots*: EpochSlots
    maxExtrinsicBytes*: ByteLimit
  DisputesError* {.pure.} = enum ## Failures carry only their class; no partially verified judgments, markers or candidate map.
    Uninitialized, None, InvalidConfig, MissingState, InvalidState, InvalidInput,
    InvalidEpoch, InvalidQuorum, InvalidSplit, AlreadyJudged, InvalidKey,
    InvalidSignature, InvalidEvidence, MissingFault, InvalidMarker, InvalidIndex,
    LimitExceeded, LengthOverflow, BackendFailure, ParentMismatch, PublicationFailure
  ## Private acyclic storage retains the original full parent and complete proposed immutable chapters.
  PlanData = ref object
    parent: StateStoreSnapshot
    judgments: DisputeStateSnapshot
    assignments: AvailabilitySnapshot
    entries: array[2, StateEntry]
    marker: seq[OffenderKey]
  DisputesPlan* = object ## An opaque copied handle retains one validated plan; callers cannot forge or mutate it.
    data: nil PlanData
  DisputesResult*[T] = object ## Only selected success contains its complete payload; default is a failure.
    case status: DisputesError
    of None:
      completed: T
    else:
      discard # No refused plan, entry or snapshot exists.

func error*[T](outcome: DisputesResult[T]): DisputesError =
  ## Observe a read-only reason without permitting result retagging.
  outcome.status

func value*[T](outcome: DisputesResult[T]): T {.inline,
    requires: outcome.status == DisputesError.None.} =
  ## Access a completed operation only after selecting success, including in optimized builds.
  outcome.completed

proc disputeJudgments*(plan: DisputesPlan): DisputeStateSnapshot {.requires: plan.data != nil.} =
  ## Retain the immutable posterior report/offender sets without exporting mutable sequences.
  let data = plan.data
  assert data != nil # Retain the owner while copying its child handle.
  data.judgments

proc disputeAssignments*(plan: DisputesPlan): AvailabilitySnapshot {.requires: plan.data != nil.} =
  ## Retain the complete assignment sequence after bad/wonky reports have been cleared.
  let data = plan.data
  assert data != nil # A default plan is not an empty assignment sequence.
  data.assignments

proc newOffenderCount*(plan: DisputesPlan): int {.requires: plan.data != nil.} =
  ## Observe exact culprit-then-fault marker cardinality, preserving cross-section repeated keys.
  let data = plan.data
  assert data != nil # No fabricated empty marker for a failed/default owner.
  data.marker.len

proc newOffenderAt*(plan: DisputesPlan, index: int): DisputesResult[OffenderKey] =
  ## Copy one marker identity with explicit ordinal validation and no detached backing span.
  let data = plan.data
  if data == nil: return DisputesResult[OffenderKey](status: DisputesError.Uninitialized) # No owner.
  if index < 0 or index >= data.marker.len:
    return DisputesResult[OffenderKey](status: DisputesError.InvalidIndex) # Check before access.
  DisputesResult[OffenderKey](status: DisputesError.None, completed: data.marker[index])

proc compareIdentity[T](a, b: T): int =
  ## Compare encoded identities lexicographically, independently of nominal report/key roles.
  let x = array[32, byte](a)
  let y = array[32, byte](b)
  for i in 0..<32:
    if x[i] < y[i]: return -1 # The first unequal octet decides canonical order.
    elif x[i] > y[i]: return 1 # Later identities sort after the selected prefix.
  0

proc contains[T](values: openArray[T], value: T): bool =
  ## Membership never conflates an equal report with a validator index or an unchecked byte span.
  for item in values:
    if compareIdentity(item, value) == 0: return true # Identity equality, not object address.
  false

proc includeIdentity[T](values: var seq[T], value: T, total: var uint64,
    config: DisputeStateConfig): bool =
  ## Charge a unique posterior set insertion before growing typed storage or the aggregate item count.
  if contains(values, value): return true # Mathematical union preserves existing members once.
  if uint64(values.len) >= uint64(config.perSet) or total >= uint64(config.totalItems) or
      values.len >= high(int) div sizeof(T):
    return false # All policy and native addressing bounds precede allocation.
  values.add(value)
  inc total
  true

proc evidenceValid(key: OffenderKey, signature: DisputeSignature, target: DisputeHash,
    domain: string): bool =
  ## Verify the exact ASCII domain followed by the raw report hash; no dollar byte, prehash or terminator.
  var message = newSeq[byte](domain.len+32)
  for i, ch in domain: message[i] = byte(ch) # Fixed protocol ASCII bytes.
  let hash = array[32, byte](target)
  for i in 0..<32: message[domain.len+i] = hash[i] # Full raw report identity.
  verify(EdPublicKey(array[32, byte](key)), EdSignature(array[64, byte](signature)), message)

proc eligible(key: OffenderKey, active, previous: ValidatorStateSnapshot,
    punished: openArray[OffenderKey]): bool =
  ## Only active/previous roster identities not already punished may submit offense evidence.
  if contains(punished, key): return false # Prior offenders cannot be newly reported again.
  for roster in [active, previous]:
    for i in 0..<validatorCount(roster).value:
      let record = validatorAt(roster, StateValidatorIndex(uint64(i))).value
      if array[32, byte](record.ed25519) == array[32, byte](key): return true # Exact Ed25519 role.
  false

proc planDisputes*(parent: StateStoreSnapshot, input: OwnedDisputes,
    config: DisputesConfig): DisputesResult[DisputesPlan] =
  ## Validate against the retained parent, derive report sets/offenders and clear bad/wonky assignments.
  ## No canonical state is written; failed signatures or late serialization leave the parent untouched.
  template fail(reason: DisputesError) =
    return DisputesResult[DisputesPlan](status: reason)
  let cores = uint64(config.rosters.cores)
  if cores < 2 or cores > 341 or uint64(config.epochSlots) == 0 or
      uint64(config.rosters.validators) < 6 or uint64(config.rosters.validators) > 1023 or
      uint64(config.rosters.validators) mod 3 != 0 or
      uint64(config.availability.guarantee.cores) != cores or
      uint64(config.availability.guarantee.validators) != uint64(config.rosters.validators):
    fail(DisputesError.InvalidConfig) # Profiles must agree before reading or allocating state.
  let info = disputesInfo(input)
  if info.error != DisputeError.None: fail(DisputesError.InvalidInput) # Default is not empty.
  if uint64(info.value.consumed) > uint64(config.maxExtrinsicBytes):
    fail(DisputesError.LimitExceeded) # Bound recapture before allocating.
  var wire = newSeq[byte](info.value.consumed)
  if encodeOwnedDisputes(input, wire).error != DisputeError.None:
    fail(DisputesError.InvalidInput) # Never consume a partially encoded child.
  let recaptured = decodeDisputes(wire, DisputeConfig(validators: ValidatorCount(
    uint64(config.rosters.validators)), maxBytes: config.maxExtrinsicBytes))
  if recaptured.error != DisputeError.None: fail(DisputesError.InvalidInput) # Recheck caller policy.
  let exact = recaptured.value.owner
  let old = parent.lookup(chapterKey(StateChapter(5)))
  let rho = parent.lookup(chapterKey(StateChapter(10)))
  let activeBytes = parent.lookup(chapterKey(StateChapter(8)))
  let previousBytes = parent.lookup(chapterKey(StateChapter(9)))
  let time = parent.lookup(chapterKey(StateChapter(11)))
  if old.error == StateStoreError.Uninitialized: fail(DisputesError.Uninitialized) # No fake genesis.
  if old.error != StateStoreError.None or rho.error != StateStoreError.None or
      activeBytes.error != StateStoreError.None or previousBytes.error != StateStoreError.None or
      time.error != StateStoreError.None:
    fail(DisputesError.MissingState) # All five parent chapters are mandatory.
  if uint64(old.value.byteLength) > uint64(config.state.maxBytes) or
      uint64(rho.value.byteLength) > uint64(config.availability.maxBytes) or
      uint64(activeBytes.value.byteLength) > uint64(config.rosters.maxBytes) or
      uint64(previousBytes.value.byteLength) > uint64(config.rosters.maxBytes):
    fail(DisputesError.LimitExceeded) # Bound copies independently before decoding.
  if time.value.byteLength != 4: fail(DisputesError.InvalidState) # Exact E4, no suffix.
  let parsed = decodeDisputeState(old.value.bytes, config.state)
  let assignments = decodeAvailabilityState(rho.value.bytes, config.availability)
  let active = decodeStateValidators(activeBytes.value.bytes, config.rosters)
  let previous = decodeStateValidators(previousBytes.value.bytes, config.rosters)
  if parsed.error != DisputeStateError.None or assignments.error != AvailabilityError.None or
      active.error != StateComponentError.None or previous.error != StateComponentError.None:
    fail(DisputesError.InvalidState) # No extraction from refused component results.
  let exactJudgments = parsed.value.consumed == old.value.byteLength
  let exactAssignments = assignments.value.consumed == rho.value.byteLength
  let exactActive = active.value.consumed == activeBytes.value.byteLength
  let exactPrevious = previous.value.consumed == previousBytes.value.byteLength
  if not exactJudgments or not exactAssignments or not exactActive or not exactPrevious:
    fail(DisputesError.InvalidState) # Complete chapter values have no suffix; short predicates also format reliably.
  var source = DisputeState()
  let counts = disputeStateInfo(parsed.value.snapshot).value
  var total = 0'u64
  for kind in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]:
    source.reports[kind] = newSeq[DisputeHash](counts.reports[kind])
    for i in 0..<source.reports[kind].len:
      source.reports[kind][i] = judgedReportAt(parsed.value.snapshot, kind, DisputeStateIndex(
          uint64(i))).value # Fixed copied identity.
    total += uint64(source.reports[kind].len)
  source.offenders = newSeq[OffenderKey](counts.offenders)
  for i in 0..<source.offenders.len:
    source.offenders[i] = stateOffenderAt(parsed.value.snapshot, DisputeStateIndex(uint64(
        i))).value # Prior membership only.
  total += uint64(source.offenders.len)
  for a in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]:
    for b in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]:
      if ord(a) < ord(b):
        for target in source.reports[a]:
          if contains(source.reports[b], target): fail(DisputesError.InvalidState) # Disjoint judgments.
  let epoch = uint64(uint32(decodeStateTime(time.value.bytes).value.value)) div uint64(
      config.epochSlots)
  var removed: seq[DisputeHash] = @[]
  var good: seq[DisputeHash] = @[]
  for i in 0..<info.value.verdicts:
    let verdict = verdictAt(exact, i).value
    let age = uint64(uint32(verdict.epoch))
    if age != epoch and (epoch == 0 or age != epoch-1):
      fail(DisputesError.InvalidEpoch) # Do not wrap epoch zero to accept an ancient verdict.
    let roster = if age == epoch: active.value.value else: previous.value.value # Parent populations, before rotation.
    let population = validatorCount(roster).value
    let quorum = population div 3*2+1
    if verdict.judgments != quorum: fail(DisputesError.InvalidQuorum) # Selected population, including resized previous sets.
    for kind in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]:
      if contains(source.reports[kind], verdict.target): fail(
          DisputesError.AlreadyJudged) # Includes all prior classes.
    var positive = 0
    for j in 0..<verdict.judgments:
      let vote = judgmentAt(exact, i, j).value
      if int(uint16(vote.judge)) >= population: fail(DisputesError.InvalidKey) # E2 alone is not membership.
      let key = OffenderKey(array[32, byte](validatorAt(roster, StateValidatorIndex(uint64(uint16(
          vote.judge)))).value.ed25519))
      if not evidenceValid(key, vote.signature, verdict.target,
          if vote.valid: "jam_valid" else: "jam_invalid"):
        fail(DisputesError.InvalidSignature) # Never infer validity from vote counts alone.
      if vote.valid: inc positive # Booleans were canonically checked during recapture.
    let kind = if positive == quorum: JudgmentSet.Good
      elif positive == 0: JudgmentSet.Bad
      else: JudgmentSet.Wonky # Only the exact one-third split may select wonky below.
    if positive != quorum and positive != 0 and positive != population div 3:
      fail(DisputesError.InvalidSplit) # Reject all other mixed quorums.
    if not includeIdentity(source.reports[kind], verdict.target, total, config.state):
      fail(DisputesError.LimitExceeded) # Bound unique posterior report insertion.
    if kind == JudgmentSet.Good: good.add(verdict.target) # Every new positive verdict needs fault evidence.
    else: removed.add(verdict.target) # Only newly bad/wonky verdicts cancel assignments.
  var marker: seq[OffenderKey] = @[]
  for i in 0..<info.value.culprits:
    let evidence = culpritAt(exact, i).value
    if not contains(source.reports[JudgmentSet.Bad], evidence.target):
      fail(DisputesError.InvalidEvidence) # Culprits must guarantee a posterior bad report.
    if not eligible(evidence.key, active.value.value, previous.value.value, source.offenders):
      fail(DisputesError.InvalidKey) # Eligibility excludes prior, not newly discovered, offenders.
    if not evidenceValid(evidence.key, evidence.signature, evidence.target, "jam_guarantee"):
      fail(DisputesError.InvalidSignature) # Raw report hash under guarantee domain.
    marker.add(evidence.key) # Preserve exact section order, including cross-section repeats.
  var faultTargets: seq[DisputeHash] = @[]
  for i in 0..<info.value.faults:
    let evidence = faultAt(exact, i).value
    let kind = if evidence.valid: JudgmentSet.Bad else: JudgmentSet.Good # The signed vote must contradict the posterior verdict.
    if not contains(source.reports[kind], evidence.target): fail(
        DisputesError.InvalidEvidence) # Neither unknown nor wonky.
    if not eligible(evidence.key, active.value.value, previous.value.value, source.offenders):
      fail(DisputesError.InvalidKey) # No prior offender can be reported again.
    if not evidenceValid(evidence.key, evidence.signature, evidence.target,
        if evidence.valid: "jam_valid" else: "jam_invalid"):
      fail(DisputesError.InvalidSignature) # Validity chooses exact signing bytes.
    marker.add(evidence.key)
    faultTargets.add(evidence.target) # A valid fault can satisfy one new good verdict's witness requirement.
  for target in good:
    if not contains(faultTargets, target): fail(DisputesError.MissingFault) # Positive verdicts require at least one fault.
  for key in marker:
    if not includeIdentity(source.offenders, key, total, config.state):
      fail(DisputesError.LimitExceeded) # Union deduplicates cross-section repeats only in the state set.
  for kind in [JudgmentSet.Good, JudgmentSet.Bad, JudgmentSet.Wonky]: source.reports[kind].sort(
      compareIdentity[DisputeHash]) # Canonical posterior set encoding.
  source.offenders.sort(compareIdentity[OffenderKey]) # Marker order stays untouched.
  var slots = newSeq[AvailabilityAssignment](availabilityInfo(
      assignments.value.snapshot).value.cores)
  for i in 0..<slots.len:
    slots[i] = availabilityAt(assignments.value.snapshot, AssignmentCoreIndex(uint64(i))).value
    if slots[i].present and removed.len > 0:
      let report = slots[i].guarantee.report
      let size = ownedReportInfo(report).value.consumed
      var bytes = newSeq[byte](size)
      if encodeOwnedReport(report, bytes).error != OwnershipError.None: fail(
          DisputesError.InvalidState) # No partial report hash.
      let hash = blake2b256(bytes)
      if hash.error != CryptoError.None: fail(DisputesError.BackendFailure) # Refusal cannot silently keep an assignment.
      if contains(removed, DisputeHash(array[32, byte](hash.value))): slots[i] = absentAssignment() # Clear guarantee and registration together.
  let chapter = disputeStateEntry(source, config.state)
  if chapter.error != DisputeStateError.None: fail(
      DisputesError.LimitExceeded) # Output byte/extent policy remains binding.
  let availability = availabilityStateEntry(slots, config.availability)
  if availability.error != AvailabilityError.None: fail(
      DisputesError.LimitExceeded) # Complete output, never partial slots.
  let data = PlanData(parent: parent, judgments: decodeDisputeState(chapter.value.value,
      config.state).value.snapshot,
    assignments: decodeAvailabilityState(availability.value.value,
        config.availability).value.snapshot,
    entries: [chapter.value, availability.value], marker: marker)
  DisputesResult[DisputesPlan](status: DisputesError.None, completed: DisputesPlan(data: data))

proc checkDisputeMarker*(plan: DisputesPlan, candidate: OwnedHeader): DisputesError =
  ## Check the literal header sequence, not a sorted/deduplicated cumulative offender set.
  let data = plan.data
  if data == nil: return DisputesError.Uninitialized # No fabricated empty marker.
  let part = unsignedPart(candidate)
  if part.error != HeaderError.None: return DisputesError.InvalidMarker # Default header is invalid.
  if unsignedHeaderInfo(part.value).value.offenders != data.marker.len:
    return DisputesError.InvalidMarker # Exact sequence length, including cross-section repeats.
  for i in 0..<data.marker.len:
    if array[32, byte](headerOffenderAt(part.value, i).value) != array[32, byte](data.marker[i]):
      return DisputesError.InvalidMarker # Preserve culprit-then-fault order byte for byte.
  DisputesError.None

proc publishDisputes*(state: var StateStore, plan: DisputesPlan): DisputesResult[
    StateStoreSnapshot] =
  ## Publish only C(5)/C(10), bound to the exact retained parent root; later callers may stage privately.
  let data = plan.data
  if data == nil: return DisputesResult[StateStoreSnapshot](status: DisputesError.Uninitialized) # No plan.
  let parent = state.snapshot
  if parent.error != StateStoreError.None: return DisputesResult[StateStoreSnapshot](
      status: DisputesError.Uninitialized) # No store.
  if array[32, byte](parent.value.commitment.root) != array[32, byte](data.parent.commitment.root):
    return DisputesResult[StateStoreSnapshot](status: DisputesError.ParentMismatch) # Plans cannot cross state contexts.
  var writes: seq[StateWrite] = @[]
  for i in 0..<data.entries.len:
    let entry = data.entries[i]
    if parent.value.lookup(entry.key).value.bytes != entry.value:
      writes.add(StateWrite(key: entry.key, kind: StateWriteKind.Put,
          value: entry.value)) # Preserve no-op write budgets.
  let applied = state.apply(writes)
  if applied.error != StateStoreError.None:
    return DisputesResult[StateStoreSnapshot](status: if applied.error ==
        StateStoreError.BackendFailure:
      DisputesError.BackendFailure else: DisputesError.PublicationFailure) # No state handle changes on refusal.
  DisputesResult[StateStoreSnapshot](status: DisputesError.None, completed: applied.value)
