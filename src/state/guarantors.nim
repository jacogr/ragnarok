# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 utilities.tex and reporting_assurance.tex: shuffled, rotated guarantor assignments.
## Plans use posterior rosters/entropy/offenders. They do not verify signatures or publish
## C(10).
##
## Exposes validator shuffling, planGuarantors and bounded guarantorAt/shuffledIndex access.

import ../codec/state_safrole as codec_state_safrole
import ../codec/assurances as codec_assurances
import ../codec/bounded as codec_bounded
import ../codec/header as codec_header
import ../codec/guarantees as codec_guarantees
import ../codec/work_report as codec_work_report
from ../codec/disputes as codec_disputes import OffenderKey
import ../crypto/primitives as crypto_primitives

type
  GuarantorRotationSlots* = distinct uint64 ## Rotation is a chain parameter, distinct from an absolute E4 timeslot.
  GuarantorConfig* = object ## Chain profile and explicit roster/offender resource ceilings, checked before scratch allocation.
    roster*: ValidatorStateConfig
    epochSlots*: EpochSlots
    rotationSlots*: GuarantorRotationSlots
    offenders*: ElementLimit
  GuarantorError* {.pure.} = enum ## No failure exposes partial permutations, keys, or an assignment plan.
    Uninitialized, None, InvalidConfig, InvalidState, LimitExceeded, NonCanonical,
    InvalidSlot, InvalidIndex, BackendFailure
  ## Private acyclic owner retains a bounded permutation, never caller-owned mutable storage.
  PermutationData = ref object
    indices: seq[uint32]
  GuarantorPermutation* = object ## Immutable permutation handle permits only checked ordinal extraction.
    data: nil PermutationData
  GuarantorAssignment* = object ## One validator's core and copied complete record after posterior offender nulling.
    core*: CoreIndex
    validator*: StateValidator
  ## Private storage owns both rotation tables; prior may be absent before genesis.
  GuarantorData = ref object
    current, previous: seq[GuarantorAssignment]
    slot, rotation: uint64
  GuarantorPlan* = object ## A plan keeps its roster, entropy-derived assignment and slot selection inseparable.
    data: nil GuarantorData
  GuarantorResult*[T] = object ## Only the selected success alternative carries application data.
    case status: GuarantorError
    of None:
      completed: T
    else:
      discard                  # Default/refused alternatives contain a reason only.

func error*[T](outcome: GuarantorResult[T]): GuarantorError =
  ## Read status without granting mutation of the discriminator.
  outcome.status
func value*[T](outcome: GuarantorResult[T]): T {.inline,
    requires: outcome.status == GuarantorError.None.} =
  ## Supported contracts reject default/refused result extraction in checked optimized builds.
  outcome.completed

proc shuffleValidatorIndices*(count: ValidatorCount, entropy: StateEntropyWord,
    ceiling: ElementLimit): GuarantorResult[GuarantorPermutation] =
  ## Shuffle validator ordinals using BLAKE2b(seed || E4(i div 8)), four-byte LE draws, and shrinking swaps.
  ## Shuffling ordinals then dividing by three equals shuffling the repeated core labels in P(v,e,t).
  if uint64(ceiling) > 1023 or uint64(count) > uint64(ceiling):
    return GuarantorResult[GuarantorPermutation](status: GuarantorError.LimitExceeded) # Bound allocations and counters.
  let n = int(uint64(count))
  var remaining = newSeq[uint32](n)
  let data = PermutationData(indices: newSeq[uint32](n))
  for i in 0..<n:
    remaining[i] = uint32(i) # Identity input, including a valid empty permutation.
  var input = default(array[36, byte])
  let seed = array[32, byte](entropy)
  for i in 0..<32:
    input[i] = seed[i] # No domain, count prefix or terminator in the entropy expansion.
  var digest = default(array[32, byte])
  for i in 0..<n:
    if i mod 8 == 0:
      let counter = uint32(i div 8)
      for j in 0..<4:
        input[32+j] = byte((counter shr (j*8)) and 255) # Explicit E4 LE group counter.
      let hashed = blake2b256(input)
      if hashed.error != CryptoError.None:
        return GuarantorResult[GuarantorPermutation](status: GuarantorError.BackendFailure) # No partial table.
      digest = array[32, byte](hashed.value)
    var draw = 0'u32
    for j in 0..<4:
      draw = draw or (uint32(digest[(i mod 8)*4+j]) shl (j*8)) # Four distinct words per hash group.
    let selected = int(draw mod uint32(n-i))
    data.indices[i] = remaining[selected]
    let last = remaining[n-i-1]
    remaining[selected] = last # Emit chosen value, replace with final value, then shrink logically.
  GuarantorResult[GuarantorPermutation](status: GuarantorError.None,
      completed: GuarantorPermutation(data: data))

proc shuffledIndex*(owner: GuarantorPermutation, index: StateValidatorIndex): GuarantorResult[
    StateValidatorIndex] =
  ## Extract a copied ordinal; default handles and out-of-range ordinals are typed refusals.
  let data = owner.data
  if data == nil:
    return GuarantorResult[StateValidatorIndex](status: GuarantorError.Uninitialized) # No fabricated identity shuffle.
  if uint64(index) >= uint64(data.indices.len):
    return GuarantorResult[StateValidatorIndex](status: GuarantorError.InvalidIndex) # Check before narrowing/access.
  GuarantorResult[StateValidatorIndex](status: GuarantorError.None, completed: StateValidatorIndex(
      data.indices[int(uint64(index))]))

## Compare exact Ed25519 identity bytes, without curve interpretation.
func compare(a, b: array[32, byte]): int =
  for i in 0..<32:
    if a[i] < b[i]: return -1 # First unequal octet establishes canonical order.
    if a[i] > b[i]: return 1 # Greater identities follow smaller ones.
  0

## Search the already checked canonical posterior offender set; never retain its borrowed storage.
proc excluded(key: StateEdKey, offenders: openArray[OffenderKey]): bool =
  var first = 0
  var last = offenders.len
  while first < last:
    let middle = first+(last-first) div 2
    let order = compare(array[32, byte](key), array[32, byte](offenders[middle]))
    if order == 0: return true # Phi nulls the complete record for this Ed25519 identity.
    if order < 0:
      last = middle # Continue in the smaller half.
    else:
      first = middle+1 # Continue in the larger half.
  false

## Build one rotation privately after profile, owner and population validation.
proc table(roster: ValidatorStateSnapshot, entropy: StateEntropyWord, slot: uint64,
    offenders: openArray[OffenderKey], config: GuarantorConfig): GuarantorResult[seq[
        GuarantorAssignment]] =
  let count = validatorCount(roster).value
  let shuffled = shuffleValidatorIndices(ValidatorCount(count), entropy, config.roster.validators)
  if shuffled.error != GuarantorError.None:
    return GuarantorResult[seq[GuarantorAssignment]](status: shuffled.error) # Preserve provider refusal.
  let rotation = (slot mod uint64(config.epochSlots)) div uint64(config.rotationSlots)
  var values = newSeq[GuarantorAssignment](count)
  for i in 0..<count:
    let core = (uint64(shuffled.value.shuffledIndex(StateValidatorIndex(
        i)).value) div 3+rotation) mod uint64(count div 3)
    let record = validatorAt(roster, StateValidatorIndex(i)).value
    values[i] = GuarantorAssignment(core: CoreIndex(core), validator: record)
    if excluded(record.ed25519, offenders):
      values[i].validator = nullValidator() # Use current nullvalkey; population and core positions stay unchanged.
  GuarantorResult[seq[GuarantorAssignment]](status: GuarantorError.None, completed: values)

proc planGuarantors*(active, previous: ValidatorStateSnapshot, entropy: StateEntropy,
    slot: StateTime, offenders: openArray[OffenderKey], config: GuarantorConfig): GuarantorResult[
        GuarantorPlan] =
  ## Capture posterior active/previous rosters and entropy histories for this block's two admissible rotations.
  ## The caller supplies completed Safrole/disputes context; this pure planner does not authenticate that context.
  let epoch = uint64(config.epochSlots)
  let rotation = uint64(config.rotationSlots)
  if epoch == 0 or rotation == 0 or rotation > epoch or epoch mod rotation != 0 or
      uint64(config.roster.cores) > 341 or uint64(config.roster.validators) > 1023:
    return GuarantorResult[GuarantorPlan](status: GuarantorError.InvalidConfig) # Whole rotations per epoch, no division by zero.
  if uint64(offenders.len) > uint64(config.offenders):
    return GuarantorResult[GuarantorPlan](status: GuarantorError.LimitExceeded) # Bound input traversal.
  for i in 1..<offenders.len:
    if compare(array[32, byte](offenders[i-1]), array[32, byte](offenders[i])) >= 0:
      return GuarantorResult[GuarantorPlan](status: GuarantorError.NonCanonical) # No sorting/deduplication fallback.
  for roster in [active, previous]:
    let count = validatorCount(roster)
    if count.error != StateComponentError.None:
      return GuarantorResult[GuarantorPlan](status: GuarantorError.InvalidState) # Default owner is not an empty roster.
    let size = stateValidatorSize(ValidatorCount(count.value), config.roster)
    if size.error != StateComponentError.None:
      return GuarantorResult[GuarantorPlan](status: GuarantorError.InvalidConfig) # Validate counts/byte policy before allocation.
  let now = uint64(uint32(slot))
  let current = table(active, entropy[2], now, offenders, config)
  if current.error != GuarantorError.None:
    return GuarantorResult[GuarantorPlan](status: current.error) # No partially initialized plan.
  let data = GuarantorData(current: current.value, previous: @[], slot: now, rotation: rotation)
  if now >= rotation:
    let prior = now-rotation # Widened, checked subtraction; no wrapped pre-genesis rotation.
    let sameEpoch = prior div epoch == now div epoch
    let old = table(if sameEpoch: active else: previous,
      if sameEpoch: entropy[2] else: entropy[3], prior, offenders, config)
    if old.error != GuarantorError.None:
      return GuarantorResult[GuarantorPlan](status: old.error) # Discard completed current table on prior-table refusal.
    data.previous = old.value
  GuarantorResult[GuarantorPlan](status: GuarantorError.None, completed: GuarantorPlan(data: data))

proc guarantorAt*(plan: GuarantorPlan, slot: GuaranteeSlot, index: GuarantorIndex): GuarantorResult[
    GuarantorAssignment] =
  ## Select a validator's copied assignment from the report slot's current or previous rotation.
  ## This establishes only assignment eligibility: no credential signature or report context is checked here.
  let data = plan.data
  if data == nil:
    return GuarantorResult[GuarantorAssignment](status: GuarantorError.Uninitialized) # No default usable plan.
  let reportSlot = uint64(uint32(slot))
  let period = data.slot div data.rotation
  let reportPeriod = reportSlot div data.rotation
  if reportSlot > data.slot or (reportPeriod < period and period-reportPeriod > 1):
    return GuarantorResult[GuarantorAssignment](status: GuarantorError.InvalidSlot) # Exact freshness interval, no wrapping subtraction.
  let values = if reportPeriod == period: data.current else: data.previous
  if uint64(index) >= uint64(values.len):
    return GuarantorResult[GuarantorAssignment](status: GuarantorError.InvalidIndex) # Chosen roster may have a different population.
  GuarantorResult[GuarantorAssignment](status: GuarantorError.None, completed: values[int(uint64(index))])
