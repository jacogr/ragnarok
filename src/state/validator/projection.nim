# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 C(13) validator projection: parent assurances precede epoch rotation and posterior activity.
## Explicit observations certify no block provenance; immutable copied rows publish no state or stale core/service data.

import ../../codec/[bounded, header, assurances]
import ../../codec/state/[safrole as state_safrole, statistics as state_statistics]

type
  ValidatorActivityObservations* = object ## Explicit pure inputs must later be derived from one authenticated candidate.
    parentSlot*, slot*: StateTime ## Strict chronology determines whether to rotate once.
    epochSlots*: EpochSlots       ## Nonzero chain parameter, independent of slot representation.
    author*: AuthorIndex          ## Position in the posterior active roster.
    tickets*, preimages*, preimageBytes*: ActivityNatural ## Author contributions, checked against fixed E4 counters.
  ValidatorActivityLimits* = object ## Independent work/storage ceilings never request maximum-sized allocation.
    rows*: ElementLimit ## Total retained current and previous validator tuples.
    assurances*, reporters*, comparisons*: ElementLimit ## Borrowed observations and key-membership comparisons.
  ValidatorActivityInfo* = object ## Copied populations and epoch decision retain no mutable rows or observations.
    current*, previous*: int ## Posterior current and retained previous populations.
    rotated*: bool           ## Even skipped epochs rotate exactly once.
  ValidatorActivityError* {.pure.} = enum ## Only complete success contains a projection or copied row.
    Uninitialized, None, InvalidSource, InvalidTime, InvalidPopulation, InvalidAuthor,
    InvalidAssurer, InvalidIndex, InvalidEpoch, LimitExceeded, CounterOverflow
  ValidatorActivityData = ref object # Acyclic owner contains fixed rows only; no borrowed observations survive.
    rows: array[StatisticsEpoch, seq[ValidatorActivity]]
    info: ValidatorActivityInfo
  ValidatorActivityProjection* = object ## Pure validated observations establish no authenticated block certificate.
    data: nil ValidatorActivityData
  ValidatorActivityResult*[T] = object ## Defaults/refusals cannot carry partial epochs or successful observations.
    case status: ValidatorActivityError
    of None:
      completed: T # Access is guarded in checked optimized builds.
    else:
      discard      # No partial rows escape on an overflow or policy refusal.

func error*[T](outcome: ValidatorActivityResult[T]): ValidatorActivityError =
  ## Inspect a read-only reason without exposing discriminator mutation.
  outcome.status

func value*[T](outcome: ValidatorActivityResult[T]): T {.inline,
    requires: outcome.status == ValidatorActivityError.None.} =
  ## Extract only selected complete success.
  outcome.completed

proc validatorActivityInfo*(projection: ValidatorActivityProjection): ValidatorActivityResult[
    ValidatorActivityInfo] =
  ## Copy populations and rotation decision without returning retained storage.
  let data = projection.data
  if data == nil:
    return ValidatorActivityResult[ValidatorActivityInfo](
        status: ValidatorActivityError.Uninitialized)
  ValidatorActivityResult[ValidatorActivityInfo](status: ValidatorActivityError.None,
    completed: data.info)

proc projectedValidatorAt*(projection: ValidatorActivityProjection, epoch: StatisticsEpoch,
    index: StatisticsValidatorIndex): ValidatorActivityResult[ValidatorActivity] =
  ## Copy a fixed row after checking epoch and full-width nominal ordinal.
  let data = projection.data
  if data == nil:
    return ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.Uninitialized)
  if ord(epoch) > ord(StatisticsEpoch.Previous):
    return ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.InvalidEpoch)
  if uint64(index) >= uint64(data.rows[epoch].len):
    return ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.InvalidIndex)
  ValidatorActivityResult[ValidatorActivity](status: ValidatorActivityError.None,
    completed: data.rows[epoch][int(uint64(index))])

# Checked fixed-counter addition is explicit because Nimony arithmetic wraps.
proc add(row: var ValidatorActivity, measure: ValidatorMeasure, amount: uint64): bool =
  let prior = uint64(uint32(row[measure]))
  if amount > uint64(high(uint32))-prior: return false # Check before addition/narrowing.
  row[measure] = ValidatorCounter(uint32(prior+amount))
  true

proc projectValidatorActivity*(parent: ActivitySnapshot, posterior: ValidatorStateSnapshot,
    observations: ValidatorActivityObservations, assurances: openArray[ValidatorIndex],
    reporters: openArray[StateEdKey], limits: ValidatorActivityLimits): ValidatorActivityResult[
        ValidatorActivityProjection] =
  ## Borrow stable observations only during this hash-free call; retain independent fixed tuples on complete success.
  template fail(reason: ValidatorActivityError) =
    return ValidatorActivityResult[ValidatorActivityProjection](status: reason)
  let before = parent.activityInfo
  let after = posterior.validatorCount
  if before.error != ActivityError.None or after.error != StateComponentError.None:
    fail(ValidatorActivityError.InvalidSource) # Defaults cannot fabricate initialized empty rosters.
  let epoch = uint64(observations.epochSlots)
  if epoch == 0 or uint32(observations.slot) <= uint32(observations.parentSlot):
    fail(ValidatorActivityError.InvalidTime) # Division and epoch choice require valid strict chronology.
  let rotated = uint64(uint32(observations.slot)) div epoch !=
    uint64(uint32(observations.parentSlot)) div epoch
  let current = after.value
  let oldCurrent = before.value.validators[StatisticsEpoch.Current]
  let previous = if rotated: oldCurrent else: before.value.validators[StatisticsEpoch.Previous]
  if not rotated and current != oldCurrent:
    fail(ValidatorActivityError.InvalidPopulation) # Same-epoch tuples retain positional current semantics.
  if uint64(uint16(observations.author)) >= uint64(current):
    fail(ValidatorActivityError.InvalidAuthor) # Author is always a posterior position.
  if current > high(int)-previous:
    fail(ValidatorActivityError.LimitExceeded) # Prove combined native extent before addition.
  let rows = current+previous
  if uint64(rows) > uint64(limits.rows) or rows > high(int) div sizeof(ValidatorActivity):
    fail(ValidatorActivityError.LimitExceeded) # Bound both retained epoch arrays before allocation.
  if uint64(assurances.len) > uint64(limits.assurances) or
      uint64(reporters.len) > uint64(limits.reporters):
    fail(ValidatorActivityError.LimitExceeded) # Borrowed observations still consume independent work.
  if uint64(current) > 0 and uint64(reporters.len) > uint64(limits.comparisons) div uint64(current):
    fail(ValidatorActivityError.LimitExceeded) # Bound membership work without overflowing a product.
  for index in assurances:
    if uint64(uint16(index)) >= uint64(oldCurrent):
      fail(ValidatorActivityError.InvalidAssurer) # Preflight every parent position before scratch allocation.
  var assured = newSeq[bool](oldCurrent)
  for index in assurances:
    assured[int(uint16(index))] = true # Existential assurance membership counts duplicates once.
  var projected = default(array[StatisticsEpoch, seq[ValidatorActivity]])
  projected[StatisticsEpoch.Current] = newSeq[ValidatorActivity](current)
  projected[StatisticsEpoch.Previous] = newSeq[ValidatorActivity](previous)
  for index in 0..<oldCurrent:
    var row = parent.validatorActivityAt(StatisticsEpoch.Current,
      StatisticsValidatorIndex(uint64(index))).value
    if assured[index] and not add(row, ValidatorMeasure.Assurances, 1):
      fail(ValidatorActivityError.CounterOverflow) # Even a rotating epoch must increment old assurances first.
    if rotated:
      projected[StatisticsEpoch.Previous][index] = row # Updated parent current becomes previous exactly once.
    else:
      projected[StatisticsEpoch.Current][index] = row # Same epoch retains current counters and positions.
  if not rotated:
    for index in 0..<previous:
      projected[StatisticsEpoch.Previous][index] = parent.validatorActivityAt(
        StatisticsEpoch.Previous,
        StatisticsValidatorIndex(uint64(index))).value # Old previous is unchanged only within the epoch.
  for index in 0..<current:
    var row = projected[StatisticsEpoch.Current][index]
    if index == int(uint16(observations.author)):
      if not add(row, ValidatorMeasure.Blocks, 1) or
          not add(row, ValidatorMeasure.Tickets, uint64(observations.tickets)) or
          not add(row, ValidatorMeasure.PreimageCount, uint64(observations.preimages)) or
          not add(row, ValidatorMeasure.PreimageBytes, uint64(observations.preimageBytes)):
        fail(ValidatorActivityError.CounterOverflow) # Partial author updates remain private on refusal.
    let key = array[32, byte](posterior.validatorAt(StateValidatorIndex(uint64(
        index))).value.ed25519)
    var reported = false
    for reporter in reporters:
      if array[32, byte](reporter) == key:
        reported = true # Each posterior position receives a single existential increment.
    if reported and not add(row, ValidatorMeasure.Guarantees, 1):
      fail(ValidatorActivityError.CounterOverflow) # Old reporter totals cannot wrap E4.
    projected[StatisticsEpoch.Current][index] = row
  ValidatorActivityResult[ValidatorActivityProjection](status: ValidatorActivityError.None,
    completed: ValidatorActivityProjection(data: ValidatorActivityData(rows: projected,
      info: ValidatorActivityInfo(current: current, previous: previous, rotated: rotated))))
