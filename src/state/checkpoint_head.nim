# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Local full-checkpoint selection metadata, separate from JAM state encoding and chain trust.
## Exact fixed bytes carry a generation, slot and complete root under a corruption checksum.

import ../codec/[bounded, state_trie]
import ../crypto/primitives

const
  HeadMagic = "RAGNAROK-HEAD-V1\n"
  HeadPayloadBytes = HeadMagic.len + 41
  CheckpointHeadBytes* = HeadPayloadBytes + 32

type
  CheckpointGeneration* = distinct uint64 ## Monotonic local publication sequence, never a protocol timeslot.
  CheckpointSlot* {.pure.} = enum ## Two fixed storage slots; a head selects exactly one.
    First, Second
  CheckpointHead* = object ## Private initialized metadata cannot silently turn a default into generation zero.
    initialized: bool
    sequence: CheckpointGeneration
    selected: CheckpointSlot
    commitment: StateRoot
  CheckpointHeadError* {.pure.} = enum ## Refusals expose no initialized head or encoded prefix.
    Uninitialized, None, LimitExceeded, InvalidFormat, ChecksumMismatch, BackendFailure, GenerationExhausted
  CheckpointHeadResult*[T] = object ## Only complete success authorizes a payload.
    case status: CheckpointHeadError
    of None:
      completed: T
    else:
      discard                       # Default/error alternatives own no successful metadata.

func error*[T](outcome: CheckpointHeadResult[T]): CheckpointHeadError =
  ## Observe typed refusal without touching an absent payload.
  outcome.status
func value*[T](outcome: CheckpointHeadResult[T]): T {.inline,
    requires: outcome.status == CheckpointHeadError.None.} =
  ## Success guards both decoded metadata and encoded bytes in checked optimized builds.
  outcome.completed
func ready*(head: CheckpointHead): bool =
  ## Default heads remain distinguishable from a deliberately initialized empty-root generation.
  head.initialized
func generation*(head: CheckpointHead): CheckpointGeneration {.requires: head.initialized.} =
  ## Return the local generation without exposing writable storage.
  head.sequence
func slot*(head: CheckpointHead): CheckpointSlot {.requires: head.initialized.} =
  ## Slot selection is available only on initialized metadata.
  head.selected
func root*(head: CheckpointHead): StateRoot {.requires: head.initialized.} =
  ## This is a claimed complete root, not independent chain authentication.
  head.commitment
func newCheckpointHead*(generation: CheckpointGeneration, slot: CheckpointSlot,
    root: StateRoot): CheckpointHead =
  ## Explicit construction preserves nominal local generation and complete-root domains.
  CheckpointHead(initialized: true, sequence: generation, selected: slot, commitment: root)
func nextCheckpointHead*(head: CheckpointHead, root: StateRoot): CheckpointHeadResult[
    CheckpointHead] =
  ## Advance into the inactive slot only after proving the local counter cannot wrap.
  if not head.initialized:
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.Uninitialized)
  if uint64(head.sequence) == high(uint64):
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.GenerationExhausted)
  let selected = if head.selected == CheckpointSlot.First: CheckpointSlot.Second else: CheckpointSlot.First
  CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.None,
    completed: newCheckpointHead(CheckpointGeneration(uint64(head.sequence) + 1), selected, root))
proc encodeCheckpointHead*(head: CheckpointHead, limit: ByteLimit): CheckpointHeadResult[seq[byte]] =
  ## Prove the exact fixed allocation before copying fields or invoking the maintained digest primitive.
  if not head.initialized:
    return CheckpointHeadResult[seq[byte]](status: CheckpointHeadError.Uninitialized)
  if uint64(limit) < uint64(CheckpointHeadBytes):
    return CheckpointHeadResult[seq[byte]](status: CheckpointHeadError.LimitExceeded)
  var bytes = newSeq[byte](CheckpointHeadBytes)
  for index, character in HeadMagic:
    bytes[index] = byte(character) # The exact version excludes other persistence envelopes.
  for index in 0..<8:
    bytes[HeadMagic.len + index] = byte((uint64(head.sequence) shr (8 * index)) and
        255) # Preserve all generation bits.
  bytes[HeadMagic.len + 8] = byte(ord(head.selected))
  let root = array[32, byte](head.commitment)
  for index in 0..<32:
    bytes[HeadMagic.len + 9 + index] = root[index] # Root bytes retain their complete-state meaning.
  let digest = blake2b256(bytes.toOpenArray(0, HeadPayloadBytes - 1))
  if digest.error != CryptoError.None:
    return CheckpointHeadResult[seq[byte]](status: CheckpointHeadError.BackendFailure)
  let checksum = array[32, byte](digest.value)
  for index in 0..<32:
    bytes[HeadPayloadBytes + index] = checksum[index] # Integrity covers the version and every selected field.
  CheckpointHeadResult[seq[byte]](status: CheckpointHeadError.None, completed: bytes)
proc decodeCheckpointHead*(bytes: openArray[byte], limit: ByteLimit): CheckpointHeadResult[
    CheckpointHead] =
  ## Borrow fixed input synchronously; no length, alternative version or invalid slot is tolerated.
  if uint64(bytes.len) > uint64(limit):
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.LimitExceeded)
  if bytes.len != CheckpointHeadBytes:
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.InvalidFormat)
  for index, character in HeadMagic:
    if bytes[index] != byte(character):
      return CheckpointHeadResult[CheckpointHead](
          status: CheckpointHeadError.InvalidFormat) # A checksum cannot authorize another version.
  if bytes[HeadMagic.len + 8] > 1:
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.InvalidFormat) # Never narrow an unchecked ordinal.
  let digest = blake2b256(bytes.toOpenArray(0, HeadPayloadBytes - 1))
  if digest.error != CryptoError.None:
    return CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.BackendFailure)
  let checksum = array[32, byte](digest.value)
  for index in 0..<32:
    if bytes[HeadPayloadBytes + index] != checksum[index]:
      return CheckpointHeadResult[CheckpointHead](
          status: CheckpointHeadError.ChecksumMismatch) # Failed integrity exposes no fields.
  var generation = 0'u64
  for index in 0..<8:
    generation = generation or (uint64(bytes[HeadMagic.len + index]) shl (8 *
        index)) # Disjoint shifts cannot overflow.
  var root = default(array[32, byte])
  for index in 0..<32:
    root[index] = bytes[HeadMagic.len + 9 + index] # Every fixed field lies within the exact checked extent.
  CheckpointHeadResult[CheckpointHead](status: CheckpointHeadError.None,
    completed: newCheckpointHead(CheckpointGeneration(generation),
      CheckpointSlot(bytes[HeadMagic.len + 8]), StateRoot(root)))
