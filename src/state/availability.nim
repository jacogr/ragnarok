## GP 0.8.0 reporting_assurance.tex: parent-roster assurances, available reports and post-assurance C(10).
## Accumulation and new guarantees are separate stages; owned plans retain complete report children.
import std/assertions
import ../codec/[assurances, bounded, natural, state_safrole, state_availability,
  state_layout, state_trie, report_owned]
import ../crypto/[primitives, assurance_context]
import ./store

type
  ## One chain profile plus independent roster, assignment and newly available report ceilings.
  AvailabilityTransitionConfig* = object
    rosters*: ValidatorStateConfig
    assignments*: AvailabilityConfig
    availableReports*: ElementLimit
  ## Refusals carry no reports, assignments or partially published state.
  AvailabilityTransitionError* {.pure.} = enum
    Uninitialized, None, InvalidConfig, InvalidState, MissingState, InvalidSlot,
    LimitExceeded, InvalidIndex, UnassignedCore, ContextFailure, BackendFailure, PublicationFailure
  ## Private acyclic storage retains copied immutable assignment/report handles and the exact encoded chapter.
  AvailabilityData = ref object
    assignments: AvailabilitySnapshot
    available: seq[OwnedReport]
    entry: StateEntry
  ## Opaque plan handles cannot be forged by mixing reports and assignment buffers.
  AvailabilityPlan* = object
    data: nil AvailabilityData
  ## Complete adapter success exposes its final map and the available reports for later accumulation.
  AvailabilityUpdate* = object
    snapshot*: StateStoreSnapshot
    plan*: AvailabilityPlan
  ## Exact signature/context refusal is selected separately from ordinary policy/state failures.
  AvailabilityTransitionResult*[T] = object
    case status: AvailabilityTransitionError
    of None:
      completed: T
    of ContextFailure:
      contextReason: AssuranceContextError
    else:
      discard # Default/refused operations contain no usable plan or update.

## Read the status without allowing external retagging.
func error*[T](outcome: AvailabilityTransitionResult[
    T]): AvailabilityTransitionError = outcome.status
## Extract only complete success under supported checked-build contracts.
func value*[T](outcome: AvailabilityTransitionResult[T]): T {.inline,
    requires: outcome.status == AvailabilityTransitionError.None.} = outcome.completed
## Inspect only the explicitly selected assurance-signature/context refusal.
func contextError*[T](outcome: AvailabilityTransitionResult[T]): AssuranceContextError {.inline,
    requires: outcome.status == AvailabilityTransitionError.ContextFailure.} = outcome.contextReason
## Retain the immutable posterior assignment sequence independently of every caller handle.
proc assuredAssignments*(plan: AvailabilityPlan): AvailabilitySnapshot {.requires: plan.data != nil.} =
  let data = plan.data
  assert data != nil # A default owner is not an empty C(10).
  data.assignments
## Count newly available reports in core order, independently of timeout/resize clearing.
proc availableReportCount*(plan: AvailabilityPlan): int {.requires: plan.data != nil.} =
  let data = plan.data
  assert data != nil # No success-like empty list for an uninitialized plan.
  data.available.len
## Copy one retained complete report handle after checking its ordinal.
proc availableReportAt*(plan: AvailabilityPlan, index: int): AvailabilityTransitionResult[OwnedReport] =
  let data = plan.data
  if data == nil: return AvailabilityTransitionResult[OwnedReport](
      status: AvailabilityTransitionError.Uninitialized) # No owner.
  if index < 0 or index >= data.available.len:
    return AvailabilityTransitionResult[OwnedReport](
        status: AvailabilityTransitionError.InvalidIndex) # No unchecked access.
  AvailabilityTransitionResult[OwnedReport](status: AvailabilityTransitionError.None,
      completed: data.available[index])

## Plan from post-disputes assignments and the parent roster; posterior population is a size-only context projection.
## The caller supplies a validated posterior population in production. Tiny STF independently exercises size three.
proc planAvailability*(assignments: AvailabilitySnapshot, active: ValidatorStateSnapshot,
    posteriorPopulation: ValidatorCount, values: openArray[Assurance], parent: AssuranceParent,
    slot: StateTime, config: AvailabilityTransitionConfig): AvailabilityTransitionResult[
        AvailabilityPlan] =
  template fail(reason: AvailabilityTransitionError) =
    return AvailabilityTransitionResult[AvailabilityPlan](status: reason)
  let cores = uint64(config.rosters.cores)
  let ceiling = uint64(config.rosters.validators)
  if cores < 2 or cores > 341 or ceiling < 6 or ceiling > cores*3 or ceiling mod 3 != 0 or
      uint64(config.assignments.guarantee.cores) != cores or
      uint64(config.assignments.guarantee.validators) != ceiling or
      uint64(posteriorPopulation) < 3 or uint64(posteriorPopulation) > ceiling or uint64(
          posteriorPopulation) mod 3 != 0:
    fail(AvailabilityTransitionError.InvalidConfig) # A count comparison does not certify an otherwise invalid roster.
  let population = validatorCount(active)
  let info = availabilityInfo(assignments)
  if population.error != StateComponentError.None or info.error != AvailabilityError.None:
    fail(AvailabilityTransitionError.InvalidState) # No default roster or assignment owner.
  let count = population.value
  if uint64(count) > ceiling or uint64(values.len) > uint64(count):
    fail(AvailabilityTransitionError.LimitExceeded) # Bound key/vote scratch before allocation.
  if uint64(count)*336+uint64(natural.encode(JamNatural(count)).len) > uint64(
      config.rosters.maxBytes):
    fail(AvailabilityTransitionError.LimitExceeded) # Roster snapshot count was already codec-bounded to 1023.
  if info.value.cores != int(cores): fail(AvailabilityTransitionError.InvalidConfig) # No differently sized core owner.
  var slots = newSeq[AvailabilityAssignment](info.value.cores)
  for i in 0..<slots.len:
    slots[i] = availabilityAt(assignments, AssignmentCoreIndex(uint64(
        i))).value # Fixed copied records retain reports.
  for core in 0..<slots.len:
    if slots[core].present:
      if uint64(ownedReportInfo(slots[core].guarantee.report).value.core) != uint64(core):
        fail(AvailabilityTransitionError.InvalidState) # A valid complete assignment belongs to its own report's core.
  let original = availabilityStateEntry(slots, config.assignments)
  if original.error != AvailabilityError.None:
    fail(AvailabilityTransitionError.LimitExceeded) # Revalidate originally looser capture under current child/byte policy.
  var keys = newSeq[EdPublicKey](count)
  for i in 0..<count:
    let validator = validatorAt(active, StateValidatorIndex(uint64(i))).value
    keys[i] = EdPublicKey(array[32, byte](validator.ed25519)) # Parent active keys, before Safrole rotation/nulling.
  let verified = verifyAssurances(values, AssuranceConfig(cores: CoreCount(cores),
    validators: ValidatorCount(uint64(count))), parent, keys)
  if verified.error != AssuranceContextError.None:
    return AvailabilityTransitionResult[AvailabilityPlan](
      status: AvailabilityTransitionError.ContextFailure,
      contextReason: verified.error) # Exact signature/context cause, no partially certified count.
  var votes = newSeq[int](slots.len)
  for assurance in values:
    for core in 0..<slots.len:
      if (assurance.bits.bytes[core div 8] and byte(1 shl (core mod 8))) != 0:
        if not slots[core].present: fail(AvailabilityTransitionError.UnassignedCore) # Post-disputes absence cannot be assured.
        inc votes[core] # At most one canonical assurance per parent validator.
  var available: seq[OwnedReport] = @[]
  let resized = uint64(posteriorPopulation) != uint64(count)
  for core in 0..<slots.len:
    if slots[core].present:
      let ready = votes[core] > count div 3*2 # Strictly greater than two thirds of the parent population.
      if ready:
        if uint64(available.len) >= uint64(config.availableReports):
          fail(AvailabilityTransitionError.LimitExceeded) # Bound report-list growth before appending a handle.
        available.add(slots[core].guarantee.report) # Core order; timeout and resize do not remove this output.
      let expired = uint64(uint32(slot)) >= uint64(uint32(slots[core].registered))+5'u64
      if ready or expired or resized:
        slots[core] = absentAssignment() # Widen before adding the fixed five-slot timeout; never wrap E4.
  let encoded = availabilityStateEntry(slots, config.assignments)
  if encoded.error != AvailabilityError.None: fail(
      AvailabilityTransitionError.InvalidState) # Only validated retained children survive.
  let captured = decodeAvailabilityState(encoded.value.value, config.assignments)
  if captured.error != AvailabilityError.None: fail(
      AvailabilityTransitionError.InvalidState) # Complete immutable output owner.
  AvailabilityTransitionResult[AvailabilityPlan](status: AvailabilityTransitionError.None,
    completed: AvailabilityPlan(data: AvailabilityData(assignments: captured.value.snapshot,
      available: available, entry: encoded.value)))

## Consume the current post-disputes/Safrole map; parent active keys remain a separate retained trusted context.
## C(11) and the posterior C(8) size come from that same staged map; publish C(10) alone atomically.
proc advanceAvailabilityState*(state: var StateStore, parentActive: ValidatorStateSnapshot,
    values: openArray[Assurance], parent: AssuranceParent, slot: StateTime,
    config: AvailabilityTransitionConfig): AvailabilityTransitionResult[AvailabilityUpdate] =
  template fail(reason: AvailabilityTransitionError) =
    return AvailabilityTransitionResult[AvailabilityUpdate](status: reason)
  let retained = state.snapshot
  if retained.error != StateStoreError.None: fail(
      AvailabilityTransitionError.Uninitialized) # No synthesized state.
  let source = retained.value
  let rho = source.lookup(chapterKey(StateChapter(10)))
  let active = source.lookup(chapterKey(StateChapter(8)))
  let time = source.lookup(chapterKey(StateChapter(11)))
  if rho.error != StateStoreError.None or active.error != StateStoreError.None or time.error !=
      StateStoreError.None:
    fail(AvailabilityTransitionError.MissingState) # All staged inputs are required, including on an empty batch.
  if uint64(rho.value.byteLength) > uint64(config.assignments.maxBytes) or
      uint64(active.value.byteLength) > uint64(config.rosters.maxBytes):
    fail(AvailabilityTransitionError.LimitExceeded) # Bound original chapter copies before materializing.
  if time.value.byteLength != 4: fail(AvailabilityTransitionError.InvalidState) # Exact C(11), no suffix.
  if uint32(decodeStateTime(time.value.bytes).value.value) != uint32(slot):
    fail(AvailabilityTransitionError.InvalidSlot) # A planner cannot execute against another staged time.
  let assignments = decodeAvailabilityState(rho.value.bytes, config.assignments)
  let posterior = decodeStateValidators(active.value.bytes, config.rosters)
  if assignments.error != AvailabilityError.None or posterior.error != StateComponentError.None:
    fail(AvailabilityTransitionError.InvalidState) # No incomplete child payload extraction.
  let exactAssignments = assignments.value.consumed == rho.value.byteLength
  let exactRoster = posterior.value.consumed == active.value.byteLength
  if not exactAssignments or not exactRoster: fail(
      AvailabilityTransitionError.InvalidState) # Complete chapter values only.
  let population = ValidatorCount(uint64(validatorCount(posterior.value.value).value))
  let planned = planAvailability(assignments.value.snapshot, parentActive, population, values,
      parent, slot, config)
  if planned.error == AvailabilityTransitionError.ContextFailure:
    return AvailabilityTransitionResult[AvailabilityUpdate](
      status: AvailabilityTransitionError.ContextFailure,
      contextReason: planned.contextError) # Preserve the exact selected signature/context reason.
  if planned.error != AvailabilityTransitionError.None: fail(planned.error) # No refused plan is published.
  let plan = planned.value
  let data = plan.data
  assert data != nil # The selected success owns the complete encoded chapter.
  var writes: seq[StateWrite] = @[]
  if rho.value.bytes != data.entry.value:
    writes.add(StateWrite(key: data.entry.key, kind: StateWriteKind.Put,
        value: data.entry.value)) # Preserve no-op write budgets.
  let applied = state.apply(writes)
  if applied.error != StateStoreError.None:
    fail(if applied.error == StateStoreError.BackendFailure: AvailabilityTransitionError.BackendFailure
      else: AvailabilityTransitionError.PublicationFailure) # State stays unchanged on a failed publication.
  AvailabilityTransitionResult[AvailabilityUpdate](status: AvailabilityTransitionError.None,
    completed: AvailabilityUpdate(snapshot: applied.value, plan: plan))
