# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 safrole.tex slotkeysequence, outside-in Z and fallbackkeysequence F. Parent C(4)
## supplies the contest/schedule; staged C(4), active roster and entropy are supplied posterior
## inputs.
##
## Exposes selectSafroleSchedule and checked immutable schedule results.

import ../../codec/state/[safrole as state_safrole, consensus as state_consensus]
import ../../codec/bounded
import ../../crypto/primitives

type
  SealerScheduleConfig* = object ## Chain epoch/tail parameters and independent finite chapter, accumulator and roster ceilings.
    state*: SafroleStateConfig
    tailStart*: EpochSlots
  SealerScheduleError* {.pure.} = enum ## Failure alternatives carry no schedule, partial fallback keys or candidate chapter.
    Uninitialized, None, MissingState, InvalidConfig, InvalidSlot, InvalidState, LimitExceeded,
      LengthOverflow, BackendFailure
  SealerScheduleResult* = object ## Only complete success retains a private immutable C(4) candidate, with no borrowed input lifetime.
    case status: SealerScheduleError
    of None:
      completed: SafroleStateSnapshot # Acyclic owned codec storage copies fixed records and selected schedule.
    else:
      discard # Defaults and refusals expose only their reason.

func error*(outcome: SealerScheduleResult): SealerScheduleError =
  ## Inspect a read-only reason without granting access to candidate storage or retagging.
  outcome.status
func value*(outcome: SealerScheduleResult): SafroleStateSnapshot {.inline,
    requires: outcome.status == SealerScheduleError.None.} =
  ## Extract the immutable candidate only after selecting successful schedule construction.
  outcome.completed

## Preserve policy/extent failures; other codec reasons identify invalid serialized input.
func codecError(reason: StateComponentError): SealerScheduleError =
  case reason
  of StateComponentError.InvalidConfig: SealerScheduleError.InvalidConfig # Caller policy cannot describe a chain.
  of StateComponentError.LimitExceeded: SealerScheduleError.LimitExceeded # Local ceiling is not a protocol rejection.
  of StateComponentError.LengthOverflow: SealerScheduleError.LengthOverflow # No unchecked native allocation/narrowing.
  else: SealerScheduleError.InvalidState # Missing/truncated/invalid values cannot become an empty contest.

## Validate strict identifier order without sorting, deduplication or attempt-based tie breaking.
proc canonical(owner: SafroleStateSnapshot, count: int): bool =
  for i in 1..<count:
    let left = array[32, byte](accumulatedTicketAt(owner, SafroleStateIndex(uint64(i-1))).value.id)
    let right = array[32, byte](accumulatedTicketAt(owner, SafroleStateIndex(uint64(i))).value.id)
    var lower = false
    for j in 0..<32:
      if left[j] < right[j]:
        lower = true # The first differing octet proves increasing identifier order.
        break
      if left[j] > right[j]: return false # A larger earlier identifier is not repaired.
    if not lower: return false # Equal identifiers are duplicates even when attempts differ.
  true

proc selectSafroleSchedule*(parent, staged, active: openArray[byte], previous, target: StateTime,
    entropy2: StateEntropyWord, config: SealerScheduleConfig): SealerScheduleResult =
  ## Borrow exact parent/staged C(4) and posterior C(8) synchronously; replace only the staged schedule.
  ## Caller authenticates and stages rotation, entropy/time and ticket admission independently.
  ## The parent contest must remain available after admission resets/replaces the staged accumulator.
  let epoch = uint64(config.state.epochSlots)
  if epoch == 0 or uint64(config.tailStart) == 0 or uint64(config.tailStart) >= epoch:
    return SealerScheduleResult(status: SealerScheduleError.InvalidConfig) # Positive epoch and nonempty closing period.
  if epoch > uint64(high(int) div sizeof(WinningTicket)) or epoch-1 > uint64(high(uint32)):
    return SealerScheduleResult(status: SealerScheduleError.LengthOverflow) # Prove native schedule storage and E4 fallback indices.
  if uint32(target) <= uint32(previous):
    return SealerScheduleResult(status: SealerScheduleError.InvalidSlot) # Parent/new slots strictly advance without wrapping.
  let oversizedParent = uint64(parent.len) > uint64(config.state.maxBytes)
  let oversizedStaged = uint64(staged.len) > uint64(config.state.maxBytes)
  let oversizedActive = uint64(active.len) > uint64(config.state.validators.maxBytes)
  if oversizedParent or oversizedStaged or oversizedActive:
    return SealerScheduleResult(status: SealerScheduleError.LimitExceeded) # Bound all borrowed inputs before copying any one.
  let before = decodeSafroleState(parent, config.state)
  if before.error != StateComponentError.None:
    return SealerScheduleResult(status: codecError(
        before.error)) # No parent owner is published on malformed state.
  if before.value.consumed != parent.len:
    return SealerScheduleResult(status: SealerScheduleError.InvalidState) # A chapter is exact, never a prefix with an ignored suffix.
  let after = decodeSafroleState(staged, config.state)
  if after.error != StateComponentError.None:
    return SealerScheduleResult(status: codecError(
        after.error)) # Posterior pending/root/accumulator must already have valid extents.
  if after.value.consumed != staged.len:
    return SealerScheduleResult(status: SealerScheduleError.InvalidState) # Reject a second value appended to C(4).
  let roster = decodeStateValidators(active, config.state.validators)
  if roster.error != StateComponentError.None:
    return SealerScheduleResult(status: codecError(
        roster.error)) # Validate the supplied posterior active roster, including null/repeated records.
  if roster.value.consumed != active.len:
    return SealerScheduleResult(status: SealerScheduleError.InvalidState) # C(8) also requires exact complete consumption.
  let prior = before.value.snapshot
  let current = after.value.snapshot
  let old = safroleInfo(prior).value
  let info = safroleInfo(current).value
  if not canonical(prior, old.accumulated) or not canonical(current, info.accumulated):
    return SealerScheduleResult(status: SealerScheduleError.InvalidState) # Neither parent nor staged contests are sorted/repaired here.
  let previousEpoch = uint64(uint32(previous)) div epoch
  let targetEpoch = uint64(uint32(target)) div epoch
  let adjacentEpoch = targetEpoch-previousEpoch == 1
  let parentInTail = uint64(uint32(previous)) mod epoch >= uint64(config.tailStart)
  var source = SafroleState(pending: newSeq[StateValidator](info.validators), root: info.root,
    schedule: ticketSchedule(@[]), accumulator: newSeq[WinningTicket](info.accumulated))
  for i in 0..<source.pending.len:
    source.pending[i] = pendingValidatorAt(current, StateValidatorIndex(uint64(
        i))).value # Preserve the posterior pending roster.
  for i in 0..<source.accumulator.len:
    source.accumulator[i] = accumulatedTicketAt(current, SafroleStateIndex(uint64(
        i))).value # Preserve admitted tickets, never repurpose them as the parent contest.
  if targetEpoch == previousEpoch:
    case old.kind
    of SealerKind.Tickets:
      var selected = newSeq[WinningTicket](old.slots) # Same-epoch blocks preserve the complete prior ticket schedule.
      for i in 0..<selected.len:
        selected[i] = sealerTicketAt(prior, SafroleStateIndex(uint64(i))).value
      source.schedule = ticketSchedule(selected)
    of SealerKind.Keys:
      var selected = newSeq[StateBsKey](old.slots) # Same-epoch fallback schedules also remain unchanged.
      for i in 0..<selected.len:
        selected[i] = sealerKeyAt(prior, SafroleStateIndex(uint64(i))).value
      source.schedule = keySchedule(selected)
  elif adjacentEpoch and parentInTail and uint64(old.accumulated) == epoch:
    var selected = newSeq[WinningTicket](int(epoch)) # Adjacent crossing from the tail uses exactly a saturated parent contest.
    for i in 0..<selected.len:
      let ordinal = if i mod 2 == 0: i div 2 else: selected.len-1-i div 2 # Outside-in: low, high, next low, next high.
      selected[i] = accumulatedTicketAt(prior, SafroleStateIndex(uint64(ordinal))).value
    source.schedule = ticketSchedule(selected)
  else:
    let population = validatorCount(roster.value.value).value # Codec proves a positive allowed 3c population before modulo.
    var selected = newSeq[StateBsKey](int(epoch))
    var message = default(array[36, byte])
    let seed = array[32, byte](entropy2)
    for i in 0..<32: message[i] = seed[i] # Exactly posterior entropy[2]; no domain, count or terminator.
    for i in 0..<selected.len:
      let index = uint32(i) # E4 range was proved before allocation.
      for j in 0..<4: message[32+j] = byte((index shr (8*j)) and
          255) # E4 is little endian regardless of host alignment.
      let digest = blake2b256(message)
      if digest.error != CryptoError.None:
        return SealerScheduleResult(status: SealerScheduleError.BackendFailure) # A late hash refusal exposes no generated prefix.
      let octets = array[32, byte](digest.value)
      var random = 0'u32
      for j in 0..<4: random = random or (uint32(octets[j]) shl (8*j)) # Decode the first four hash octets as E4.
      let ordinal = int(uint64(random) mod uint64(
          population)) # Reduce before narrowing/indexing; preserve roster order and repeats.
      selected[i] = validatorAt(roster.value.value, StateValidatorIndex(uint64(
          ordinal))).value.bandersnatch
    source.schedule = keySchedule(selected)
  let encoded = safroleStateEntry(source, config.state)
  if encoded.error != StateComponentError.None:
    return SealerScheduleResult(status: codecError(
        encoded.error)) # Ticket/key width changes must fit the output chapter policy.
  let captured = decodeSafroleState(encoded.value.value, config.state)
  if captured.error != StateComponentError.None:
    return SealerScheduleResult(status: codecError(captured.error)) # No partial owner escapes a refused capture.
  SealerScheduleResult(status: SealerScheduleError.None, completed: captured.value.snapshot)
