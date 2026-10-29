# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 safrole.tex timekeeping/entropy equations and header.tex strict parent-slot
## ordering. Caller authenticates the header entropy VRF output and checks wall-clock admission
## separately.
##
## Exposes advanceEntropyTime and advanceEntropyTimeState for pure planning and atomic
## full-state publication.

import ../codec/state/[safrole as state_safrole, layout as state_layout, trie as state_trie]
from ../codec/header import EpochSlots
import ../crypto/primitives
import ./store

type
  EntropyInput* = distinct array[32, byte] ## Already supplied VRF output bytes, distinct from stored entropy; this constructor proves no signature.
  EntropyTimeUpdate* = object ## Complete fixed posterior values, which must be published together when updating a working store.
    entropy*: StateEntropy
    time*: StateTime
  EntropyTransitionError* {.pure.} = enum ## Failure alternatives contain no updated words, timeslot or proposed commitment.
    Uninitialized, None, InvalidConfig, InvalidSlot, InvalidState, MissingState,
    LimitExceeded, LengthOverflow, BackendFailure
  EntropyTransitionResult*[T] = object ## Success payload and discriminator remain private; defaults are uninitialized failures.
    case status: EntropyTransitionError
    of None:
      completed: T # Extract only after checking the supported success predicate.
    else:
      discard      # Failed alternatives have their reason only.

func error*[T](outcome: EntropyTransitionResult[T]): EntropyTransitionError =
  ## Read a failure reason without exposing payload storage or permitting retagging.
  outcome.status
func value*[T](outcome: EntropyTransitionResult[T]): T {.inline,
    requires: outcome.status == EntropyTransitionError.None.} =
  ## Require selected success before returning fixed values or an immutable committed snapshot.
  outcome.completed

## Preserve atomic-store reasons; no missing/default state can become fabricated entropy.
func storeError(reason: StateStoreError): EntropyTransitionError =
  case reason
  of StateStoreError.None: EntropyTransitionError.None # Complete store success only.
  of StateStoreError.Uninitialized: EntropyTransitionError.Uninitialized # Default handles are not genesis state.
  of StateStoreError.MissingKey: EntropyTransitionError.MissingState # Both chapters must exist explicitly.
  of StateStoreError.LimitExceeded: EntropyTransitionError.LimitExceeded # Keep caller store budgets explicit.
  of StateStoreError.LengthOverflow: EntropyTransitionError.LengthOverflow # Preserve native extent failures.
  of StateStoreError.BackendFailure: EntropyTransitionError.BackendFailure # Primitive refusal yields no root.
  else: EntropyTransitionError.InvalidState # Other store failures do not describe valid transition state.

proc advanceEntropyTime*(prior: StateEntropy, previous, target: StateTime,
    randomness: EntropyInput, epochSlots: EpochSlots): EntropyTransitionResult[EntropyTimeUpdate] =
  ## Advance one block using BLAKE2b-256(old accumulator || entropy VRF output), not proof bytes.
  ## History rotates once when target/epochSlots exceeds previous/epochSlots, irrespective of skipped epochs.
  if uint64(epochSlots) == 0:
    return EntropyTransitionResult[EntropyTimeUpdate](
        status: EntropyTransitionError.InvalidConfig) # Reject before unsigned division.
  if uint32(target) <= uint32(previous):
    return EntropyTransitionResult[EntropyTimeUpdate](
        status: EntropyTransitionError.InvalidSlot) # Slots never wrap, repeat or move backward.
  let changed = uint64(uint32(target)) div uint64(epochSlots) >
      uint64(uint32(previous)) div uint64(epochSlots)
  var input = default(array[64, byte])
  let accumulator = array[32, byte](prior[0])
  let output = array[32, byte](randomness)
  # Concatenate exact identities on the stack; no token, count, proof or slot bytes are hashed.
  for i in 0..<32:
    input[i] = accumulator[i]
    input[32+i] = output[i]
  let digest = blake2b256(input)
  if digest.error != CryptoError.None:
    return EntropyTransitionResult[EntropyTimeUpdate](
        status: EntropyTransitionError.BackendFailure) # No default accumulator after refusal.
  var advanced = EntropyTimeUpdate(entropy: default(StateEntropy), time: target)
  advanced.entropy[0] = StateEntropyWord(array[32, byte](digest.value))
  # Historical words use the OLD accumulator, never the newly hashed value or repeated empty-epoch rotation.
  for i in 1..<4:
    if changed:
      advanced.entropy[i] = prior[i-1] # One epoch-crossing rotation from the original four words.
    else:
      advanced.entropy[i] = prior[i] # Same-epoch progress leaves all historical values untouched.
  EntropyTransitionResult[EntropyTimeUpdate](status: EntropyTransitionError.None,
      completed: advanced)

proc advanceEntropyTimeState*(state: var StateStore, target: StateTime,
    randomness: EntropyInput, epochSlots: EpochSlots): EntropyTransitionResult[StateStoreSnapshot] =
  ## Decode exact fixed C(6)/C(11), compute privately and atomically publish both entries in one batch.
  ## Unrelated values and retained historical snapshots remain immutable; this is not full Safrole execution.
  let before = state.snapshot
  if before.error != StateStoreError.None:
    return EntropyTransitionResult[StateStoreSnapshot](status: storeError(before.error)) # No default store.
  let entropy = before.value.lookup(chapterKey(StateChapter(6)))
  if entropy.error != StateStoreError.None:
    return EntropyTransitionResult[StateStoreSnapshot](status: storeError(
        entropy.error)) # Missing is not zero entropy.
  let time = before.value.lookup(chapterKey(StateChapter(11)))
  if time.error != StateStoreError.None:
    return EntropyTransitionResult[StateStoreSnapshot](status: storeError(time.error)) # Missing is not slot zero.
  if entropy.value.byteLength != 128 or time.value.byteLength != 4:
    return EntropyTransitionResult[StateStoreSnapshot](
        status: EntropyTransitionError.InvalidState) # Bound copies and reject truncations/suffixes before decoding.
  let rawEntropy = entropy.value.bytes
  let rawTime = time.value.bytes
  let decodedEntropy = decodeStateEntropy(rawEntropy)
  let decodedTime = decodeStateTime(rawTime)
  if decodedEntropy.error != StateComponentError.None or decodedTime.error !=
      StateComponentError.None:
    return EntropyTransitionResult[StateStoreSnapshot](
        status: EntropyTransitionError.InvalidState) # No partial fixed values or automatic state repair.
  let advanced = advanceEntropyTime(decodedEntropy.value.value, decodedTime.value.value, target,
      randomness, epochSlots)
  if advanced.error != EntropyTransitionError.None:
    return EntropyTransitionResult[StateStoreSnapshot](
        status: advanced.error) # No writes before complete success.
  let nextEntropy = entropyEntry(advanced.value.entropy)
  let nextTime = timeEntry(advanced.value.time)
  let committed = state.apply(@[
      StateWrite(key: nextEntropy.key, kind: StateWriteKind.Put, value: nextEntropy.value),
      StateWrite(key: nextTime.key, kind: StateWriteKind.Put, value: nextTime.value)])
  if committed.error != StateStoreError.None:
    return EntropyTransitionResult[StateStoreSnapshot](status: storeError(
        committed.error)) # Store guarantees both-or-neither.
  EntropyTransitionResult[StateStoreSnapshot](status: EntropyTransitionError.None,
      completed: committed.value)
