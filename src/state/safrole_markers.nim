# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 safrole.tex epochmarker and winningticketsmarker: state-derived immutable header
## markers.
##
## Exposes deriveSafroleMarkers/validateSafroleMarkers and checked epoch/winners marker access.

import ../codec/state_safrole as codec_state_safrole
import ../codec/state_consensus as codec_state_consensus
import ../codec/header as codec_header
import ../codec/bounded as codec_bounded
import ../codec/natural as codec_natural
import ../codec/assurances as codec_assurances

type
  SafroleMarkerConfig* = object ## Independent chapter and marker ceilings; chain epoch/tail parameters are explicit.
    state*: SafroleStateConfig
    tailStart*: EpochSlots
    maxMarkerBytes*: ByteLimit
  SafroleMarkerError* {.pure.} = enum ## Refusals carry no partial markers; mismatches distinguish epoch and winning-ticket fields.
    Uninitialized, None, MissingState, InvalidConfig, InvalidSlot, InvalidState,
    LimitExceeded, LengthOverflow, InvalidHeader, InvalidEpochMarker, InvalidWinnersMarker
  SafroleMarkers* = object ## Two immutable codec owners retain their exact marker bytes independently of supplied state.
    epochValue: OwnedEpochMarker
    winnersValue: OwnedWinnersMarker
  SafroleMarkerResult* = object ## Only successful derivation contains a complete pair; raw discriminator/payload remain private.
    case status: SafroleMarkerError
    of None:
      completed: SafroleMarkers # Acyclic owned wire snapshots outlive all borrowed input chapters.
    else:
      discard                   # Default/refused operations expose only their reason.

func error*(outcome: SafroleMarkerResult): SafroleMarkerError =
  ## Inspect the reason without retagging the result.
  outcome.status
func value*(outcome: SafroleMarkerResult): SafroleMarkers {.inline,
    requires: outcome.status == SafroleMarkerError.None.} =
  ## Extract both complete markers only after selecting successful derivation.
  outcome.completed
func epochMarker*(markers: SafroleMarkers): OwnedEpochMarker =
  ## Return an immutable epoch owner; a default pair returns a default owner that codec access rejects.
  markers.epochValue
func winnersMarker*(markers: SafroleMarkers): OwnedWinnersMarker =
  ## Return an immutable winners owner without exposing mutable tickets or detached coordinates.
  markers.winnersValue

## Preserve policy/extent failures; other codec failures identify invalid exact serialized state.
func stateError(reason: StateComponentError): SafroleMarkerError =
  case reason
  of StateComponentError.InvalidConfig: SafroleMarkerError.InvalidConfig # Invalid profile is a caller policy error.
  of StateComponentError.LimitExceeded: SafroleMarkerError.LimitExceeded # Preserve finite caller ceilings.
  of StateComponentError.LengthOverflow: SafroleMarkerError.LengthOverflow # Never narrow an unchecked extent.
  else: SafroleMarkerError.InvalidState # Malformed chapters cannot become absent markers.

## Require unique increasing identifiers without sorting or dropping attempt bytes.
proc canonical(owner: SafroleStateSnapshot, count: int): bool =
  for i in 1..<count:
    let left = array[32, byte](accumulatedTicketAt(owner, SafroleStateIndex(uint64(i-1))).value.id)
    let right = array[32, byte](accumulatedTicketAt(owner, SafroleStateIndex(uint64(i))).value.id)
    var lower = false
    for j in 0..<32:
      if left[j] < right[j]:
        lower = true # First differing octet proves identifier order.
        break
      if left[j] > right[j]: return false # Reversed identifiers are never repaired.
    if not lower: return false # Equal identifiers remain duplicates regardless of attempt.
  true

proc deriveSafroleMarkers*(parent, staged: openArray[byte], previous, target: StateTime,
    entropy: StateEntropy, config: SafroleMarkerConfig): SafroleMarkerResult =
  ## Derive markers from exact parent/posterior C(4), retained parent entropy and advancing slots.
  ## Epoch markers use parent eta[0]/eta[1] and posterior pending keys; winners use the parent contest.
  ## No entropy VRF, seal authentication, state writes or cryptographic hashing is performed here.
  let epoch = uint64(config.state.epochSlots)
  if epoch == 0 or uint64(config.tailStart) == 0 or uint64(config.tailStart) >= epoch:
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidConfig) # Both submission and tail periods must exist.
  if epoch > uint64((high(int)-1) div 33):
    return SafroleMarkerResult(status: SafroleMarkerError.LengthOverflow) # Prove complete winning-marker wire extent before allocation.
  if uint32(target) <= uint32(previous):
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidSlot) # No repeated, backward or wrapped time.
  let oversizedParent = uint64(parent.len) > uint64(config.state.maxBytes)
  let oversizedStaged = uint64(staged.len) > uint64(config.state.maxBytes)
  if oversizedParent or oversizedStaged:
    return SafroleMarkerResult(status: SafroleMarkerError.LimitExceeded) # Bound both borrowed chapters before copying either.
  let before = decodeSafroleState(parent, config.state)
  if before.error != StateComponentError.None:
    return SafroleMarkerResult(status: stateError(before.error)) # No default parent contest is synthesized.
  let after = decodeSafroleState(staged, config.state)
  if after.error != StateComponentError.None:
    return SafroleMarkerResult(status: stateError(
        after.error)) # Posterior pending records must already be structurally valid.
  if before.value.consumed != parent.len or after.value.consumed != staged.len:
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidState) # Prefix-valid chapters with suffixes reject.
  let old = safroleInfo(before.value.snapshot).value
  let current = safroleInfo(after.value.snapshot).value
  if not canonical(before.value.snapshot, old.accumulated) or not canonical(after.value.snapshot,
      current.accumulated):
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidState) # Marker construction never repairs either contest.
  let parentEpoch = uint64(uint32(previous)) div epoch
  let targetEpoch = uint64(uint32(target)) div epoch
  let beforeTail = uint64(uint32(previous)) mod epoch < uint64(config.tailStart)
  let afterTail = uint64(uint32(target)) mod epoch >= uint64(config.tailStart)
  let crossedEpoch = targetEpoch > parentEpoch
  let crossedTail = targetEpoch == parentEpoch and beforeTail and afterTail
  let winning = crossedTail and uint64(old.accumulated) == epoch
  let epochBytes = if crossedEpoch: 65+int(encode(JamNatural(uint64(
      current.validators))).len)+64*current.validators else: 1
  let winnerBytes = if winning: 1+33*int(epoch) else: 1
  if uint64(epochBytes) > uint64(config.maxMarkerBytes) or uint64(winnerBytes) > uint64(
      config.maxMarkerBytes):
    return SafroleMarkerResult(status: SafroleMarkerError.LimitExceeded) # Bound exact complete outputs before constructing marker sequences.
  var epochSource = absentEpoch()
  if crossedEpoch:
    var keys = newSeq[EpochValidator](current.validators)
    for i in 0..<keys.len:
      let record = pendingValidatorAt(after.value.snapshot, StateValidatorIndex(uint64(i))).value
      keys[i] = EpochValidator(bandersnatch: HeaderBsKey(array[32, byte](record.bandersnatch)),
        ed25519: HeaderEdKey(array[32, byte](record.ed25519))) # Preserve posterior order, nulls and repeats.
    epochSource = presentEpoch(EpochEntropy(array[32, byte](entropy[0])),
      TicketsEntropy(array[32, byte](entropy[1])), keys)
  var winnerSource = absentWinners()
  if winning:
    var tickets = newSeq[WinningTicket](int(epoch))
    for i in 0..<tickets.len:
      let ordinal = if i mod 2 == 0: i div 2 else: tickets.len-1-i div 2 # Outside-in Z preserves full id/attempt records.
      tickets[i] = accumulatedTicketAt(before.value.snapshot, SafroleStateIndex(uint64(
          ordinal))).value
    winnerSource = presentWinners(tickets)
  let headerPolicy = HeaderConfig(cores: config.state.validators.cores,
    authorValidators: ValidatorCount(uint64(config.state.validators.cores)*3),
    epochSlots: config.state.epochSlots, maxBytes: config.maxMarkerBytes)
  var epochWire = newSeq[byte](epochBytes)
  var winnerWire = newSeq[byte](winnerBytes)
  let encodedEpoch = encodeEpochMarker(epochSource, headerPolicy, epochWire)
  let encodedWinners = encodeWinnersMarker(winnerSource, headerPolicy, winnerWire)
  if encodedEpoch.error != HeaderError.None or encodedWinners.error != HeaderError.None:
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidState) # Invalid codec sources cannot publish half a pair.
  let capturedEpoch = decodeEpochMarker(epochWire, headerPolicy)
  let capturedWinners = decodeWinnersMarker(winnerWire, headerPolicy)
  if capturedEpoch.error != HeaderError.None or capturedWinners.error != HeaderError.None:
    return SafroleMarkerResult(status: SafroleMarkerError.InvalidState) # Capture both private immutable owners before success.
  SafroleMarkerResult(status: SafroleMarkerError.None, completed: SafroleMarkers(
    epochValue: capturedEpoch.value.owner, winnersValue: capturedWinners.value.owner))

proc validateSafroleMarkers*(expected: SafroleMarkers, epoch: OwnedEpochMarker,
    winners: OwnedWinnersMarker): SafroleMarkerError =
  ## Compare initialized owners without copying full wire buffers or ignoring attempts/key ordering.
  ## Supplied marker owners can come directly from a structurally decoded unsigned header.
  let wantedEpoch = epochMarkerInfo(expected.epochMarker)
  let wantedWinners = winnersMarkerInfo(expected.winnersMarker)
  if wantedEpoch.error != HeaderError.None or wantedWinners.error != HeaderError.None:
    return SafroleMarkerError.Uninitialized # Default expected pairs cannot authorize marker acceptance.
  let actualEpoch = epochMarkerInfo(epoch)
  if actualEpoch.error != HeaderError.None:
    return SafroleMarkerError.InvalidEpochMarker # Uninitialized actual owners are not canonical absence.
  if actualEpoch.value.present != wantedEpoch.value.present:
    return SafroleMarkerError.InvalidEpochMarker # Missing and unexpected epoch markers both reject.
  if wantedEpoch.value.present:
    if actualEpoch.value.validators != wantedEpoch.value.validators:
      return SafroleMarkerError.InvalidEpochMarker # No truncated, extended or resized key sequence is accepted.
    if array[32, byte](actualEpoch.value.entropy) != array[32, byte](wantedEpoch.value.entropy):
      return SafroleMarkerError.InvalidEpochMarker # Parent accumulator randomness is not posterior eta[0].
    if array[32, byte](actualEpoch.value.ticketsEntropy) != array[32, byte](
        wantedEpoch.value.ticketsEntropy):
      return SafroleMarkerError.InvalidEpochMarker # Contest randomness retains its separate parent eta[1] role.
    for i in 0..<wantedEpoch.value.validators:
      let actual = epochValidatorAt(epoch, i).value
      let wanted = epochValidatorAt(expected.epochMarker, i).value
      if array[32, byte](actual.bandersnatch) != array[32, byte](wanted.bandersnatch):
        return SafroleMarkerError.InvalidEpochMarker # Each posterior Bandersnatch key occupies its original ordinal.
      if array[32, byte](actual.ed25519) != array[32, byte](wanted.ed25519):
        return SafroleMarkerError.InvalidEpochMarker # Pairing/order of Ed25519 keys matters independently.
  let actualWinners = winnersMarkerInfo(winners)
  if actualWinners.error != HeaderError.None:
    return SafroleMarkerError.InvalidWinnersMarker # A default owner is not initialized absence.
  if actualWinners.value.present != wantedWinners.value.present:
    return SafroleMarkerError.InvalidWinnersMarker # Marker eligibility requires exact presence.
  if wantedWinners.value.present:
    if actualWinners.value.tickets != wantedWinners.value.tickets:
      return SafroleMarkerError.InvalidWinnersMarker # Owners decoded under another epoch length cannot match.
    for i in 0..<wantedWinners.value.tickets:
      let actual = winningTicketAt(winners, i).value
      let wanted = winningTicketAt(expected.winnersMarker, i).value
      if array[32, byte](actual.id) != array[32, byte](wanted.id) or byte(actual.attempt) != byte(
          wanted.attempt):
        return SafroleMarkerError.InvalidWinnersMarker # Compare complete records, including the original attempt.
  SafroleMarkerError.None
