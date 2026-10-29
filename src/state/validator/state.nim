# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 safrole.tex roster/root rotation, published atomically into a full-state working
## store. Run before entropy/time advancement: C(11) still contains the parent slot. No
## ticket/schedule execution.
##
## Exposes rotateValidatorState and checked full-state rotation/publication results.

import ../../codec/state/[safrole as state_safrole, consensus as state_consensus,
    layout as state_layout, trie as state_trie]
import ../../codec/[assurances, bounded]
from ../../codec/disputes import OffenderKey
import ../../bandersnatch/bandersnatch
import ../[validators, store]

type
  ValidatorTransitionConfig* = object ## Complete chapter/roster ceilings plus a separate bound on borrowed posterior offender identities.
    safrole*: SafroleStateConfig
    offenders*: ElementLimit
  ValidatorStateError* {.pure.} = enum ## Defaults/failures have no snapshot or partial write batch; primitive refusal never fabricates a root.
    Uninitialized, None, InvalidConfig, InvalidSlot, InvalidState, MissingState, NonCanonical,
      LimitExceeded, LengthOverflow, BackendFailure
  ValidatorStateResult* = object ## Private discriminator and payload require successful selection before snapshot extraction.
    case status: ValidatorStateError
    of None:
      completed: StateStoreSnapshot # Retained immutable historical state; never a mutable map view.
    else:
      discard                       # Only the typed reason survives a refused operation.

func error*(outcome: ValidatorStateResult): ValidatorStateError =
  ## Inspect a reason without exposing state or permitting retagging.
  outcome.status
func value*(outcome: ValidatorStateResult): StateStoreSnapshot {.inline,
    requires: outcome.status == ValidatorStateError.None.} =
  ## Extract only a successfully published immutable working-store snapshot.
  outcome.completed

## Preserve actionable codec policy failures while rejecting missing structural validity.
func codecError(reason: StateComponentError): ValidatorStateError =
  case reason
  of StateComponentError.InvalidConfig: ValidatorStateError.InvalidConfig # Invalid caller profile.
  of StateComponentError.LimitExceeded: ValidatorStateError.LimitExceeded # Explicit local work policy.
  of StateComponentError.LengthOverflow: ValidatorStateError.LengthOverflow # No unsafe native narrowing.
  else: ValidatorStateError.InvalidState # No malformed/default chapter can become a roster.

## Translate complete-map errors without replacing a missing value with fabricated genesis state.
func storeError(reason: StateStoreError): ValidatorStateError =
  case reason
  of StateStoreError.Uninitialized: ValidatorStateError.Uninitialized # Default store has no state.
  of StateStoreError.MissingKey: ValidatorStateError.MissingState # Every required chapter must exist.
  of StateStoreError.LimitExceeded: ValidatorStateError.LimitExceeded # Keep aggregate write/map limits.
  of StateStoreError.LengthOverflow: ValidatorStateError.LengthOverflow # Preserve checked extent failure.
  of StateStoreError.BackendFailure: ValidatorStateError.BackendFailure # Hash refusal publishes nothing.
  else: ValidatorStateError.InvalidState # Other store errors cannot describe this fixed valid batch.

## Preserve planner failures; this stage never treats a rejected plan as an unchanged successful block.
func planError(reason: ValidatorRotationError): ValidatorStateError =
  case reason
  of ValidatorRotationError.InvalidConfig: ValidatorStateError.InvalidConfig # Invalid profile/epoch.
  of ValidatorRotationError.InvalidSlot: ValidatorStateError.InvalidSlot # Strict forward slot ordering.
  of ValidatorRotationError.NonCanonical: ValidatorStateError.NonCanonical # No offender sorting fallback.
  of ValidatorRotationError.LimitExceeded: ValidatorStateError.LimitExceeded # Explicit local work ceilings.
  of ValidatorRotationError.LengthOverflow: ValidatorStateError.LengthOverflow # Native extent refusal.
  else: ValidatorStateError.InvalidState # Default/bad source owners have no usable posterior plan.

## Copy a codec-validated bounded roster into caller-private records, never exporting retained storage.
proc records(owner: ValidatorStateSnapshot): seq[StateValidator] =
  result = newSeq[StateValidator](validatorCount(owner).value)
  for i in 0..<result.len:
    result[i] = validatorAt(owner, StateValidatorIndex(uint64(i))).value # Stable owner-bound fixed copy.

proc rotateValidatorState*(state: var StateStore, target: StateTime,
    offenders: openArray[OffenderKey], config: ValidatorTransitionConfig): ValidatorStateResult =
  ## Decode exact required chapters, rotate once, recompute the pending ring and publish C(4)/C(8)/C(9).
  ## Caller supplies canonical POST-disputes offenders. C(7), C(11), schedules and accumulators are preserved.
  ## This is a working-state substep; it neither advances the time nor commits a complete block transition.
  let policy = config.safrole
  if uint64(policy.epochSlots) == 0 or uint64(policy.validators.cores) < 2 or
      uint64(policy.validators.cores) > 341:
    return ValidatorStateResult(status: ValidatorStateError.InvalidConfig) # Pinned SRS supports at most 1023 members.
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return ValidatorStateResult(status: storeError(before.error)) # Default stores cannot supply parent state.
  var raw = default(array[5, seq[byte]])
  for i, chapter in [4, 7, 8, 9, 11]:
    let found = before.value.lookup(chapterKey(StateChapter(chapter)))
    if found.error != StateStoreError.None:
      return ValidatorStateResult(status: storeError(
          found.error)) # Missing any one input refuses the entire step.
    let limit = if i == 0: uint64(policy.maxBytes) elif i == 4: 4'u64 else: uint64(
        policy.validators.maxBytes) # Bound copies before extraction.
    if uint64(found.value.byteLength) > limit:
      return ValidatorStateResult(status: ValidatorStateError.LimitExceeded) # Never copy an over-budget chapter.
    raw[i] = found.value.bytes
  let old = decodeSafroleState(raw[0], policy)
  if old.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(
        old.error)) # No allocation of unchecked schedule/accumulator counts.
  if old.value.consumed != raw[0].len:
    return ValidatorStateResult(status: ValidatorStateError.InvalidState) # Chapter values are exact, not prefixes.
  let time = decodeStateTime(raw[4])
  if time.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(time.error)) # No truncated/default parent slot.
  if time.value.consumed != raw[4].len:
    return ValidatorStateResult(status: ValidatorStateError.InvalidState) # No suffix acceptance.
  var owners = default(array[4, ValidatorStateSnapshot])
  for i in 0..<3:
    let decoded = decodeStateValidators(raw[i+1], policy.validators)
    if decoded.error != StateComponentError.None:
      return ValidatorStateResult(status: codecError(
          decoded.error)) # Every roster fits the same explicit profile.
    if decoded.value.consumed != raw[i+1].len:
      return ValidatorStateResult(status: ValidatorStateError.InvalidState) # No trailing roster bytes.
    owners[i] = decoded.value.value
  let info = safroleInfo(old.value.snapshot).value
  var pending = newSeq[StateValidator](info.validators)
  for i in 0..<pending.len:
    pending[i] = pendingValidatorAt(old.value.snapshot, StateValidatorIndex(uint64(
        i))).value # Copy validated C(4) population.
  let framed = validatorEntry(ValidatorChapter.Staging, pending, policy.validators)
  if framed.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(framed.error)) # Temporary framing never proposes a C(7) write.
  owners[3] = decodeStateValidators(framed.value.value, policy.validators).value.value
  let planned = planValidatorRotation(owners[0], owners[3], owners[1], owners[2],
      time.value.value, target, policy.epochSlots, offenders,
      ValidatorRotationConfig(roster: policy.validators, offenders: config.offenders))
  if planned.error != ValidatorRotationError.None:
    return ValidatorStateResult(status: planError(
        planned.error)) # All input/offender validation precedes native setup work.
  if not planned.value.epochChanged:
    return ValidatorStateResult(status: ValidatorStateError.None,
      completed: before.value) # Same-epoch progress performs no setup, ring work, hashes or state writes.
  let next = planned.value
  let incoming = records(next.pending)
  # Count is codec-bounded to 6..1023; prove the byte extent again before allocating the flat ring.
  if incoming.len > 1023 or incoming.len > high(int) div 32:
    return ValidatorStateResult(status: ValidatorStateError.LengthOverflow) # No wrapped member-byte extent.
  var members = newSeq[byte](incoming.len*32)
  for i, record in incoming:
    let key = array[32, byte](record.bandersnatch)
    for j in 0..<32:
      members[i*32+j] = key[j] # Preserve every ordinal, including null/invalid keys for explicit padding normalization.
  let setup = newSetup(int(uint64(policy.validators.cores)*3))
  if setup.error != BsError.None:
    return ValidatorStateResult(status: ValidatorStateError.BackendFailure) # The chain profile selects the SRS domain even when its current roster shrinks.
  let root = commitRing(setup.value, members)
  if root.error != BsError.None:
    return ValidatorStateResult(status: ValidatorStateError.BackendFailure) # Existing invalid-point padding and valid-identity refusal apply unchanged.
  var source = SafroleState(pending: incoming, root: StateRingRoot(array[144, byte](root.value)),
      schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  case info.kind
  of SealerKind.Tickets:
    var tickets = newSeq[WinningTicket](info.slots) # Preserve the old schedule, not the full STF posterior schedule.
    for i in 0..<tickets.len:
      tickets[i] = sealerTicketAt(old.value.snapshot, SafroleStateIndex(uint64(i))).value
    source.schedule = ticketSchedule(tickets)
  of SealerKind.Keys:
    var keys = newSeq[StateBsKey](info.slots) # Preserve every fallback slot key, including duplicates.
    for i in 0..<keys.len:
      keys[i] = sealerKeyAt(old.value.snapshot, SafroleStateIndex(uint64(i))).value
    source.schedule = keySchedule(keys)
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(old.value.snapshot, SafroleStateIndex(uint64(
        i))).value # Unchanged prior ticket order/attempts.
  let c4 = safroleStateEntry(source, policy)
  if c4.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(
        c4.error)) # Resizing must fit the complete posterior chapter budget.
  let c8 = validatorEntry(ValidatorChapter.Active, records(next.active), policy.validators)
  let c9 = validatorEntry(ValidatorChapter.Previous, records(next.previous), policy.validators)
  if c8.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(c8.error)) # No writes until all posterior entries exist.
  if c9.error != StateComponentError.None:
    return ValidatorStateResult(status: codecError(c9.error)) # Previous roster cannot be published separately.
  let committed = state.apply(@[
    StateWrite(key: c4.value.key, kind: StateWriteKind.Put, value: c4.value.value),
    StateWrite(key: c8.value.key, kind: StateWriteKind.Put, value: c8.value.value),
    StateWrite(key: c9.value.key, kind: StateWriteKind.Put, value: c9.value.value)])
  if committed.error != StateStoreError.None:
    return ValidatorStateResult(status: storeError(
        committed.error)) # One atomic private candidate root, then one publication.
  ValidatorStateResult(status: ValidatorStateError.None, completed: committed.value)
