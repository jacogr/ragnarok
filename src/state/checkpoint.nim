# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deterministic local full-map checkpoints preserve serialized keys/values and the complete root.
## This storage envelope is not a JAM wire encoding and never accepts partial light state.

import ./store
import ../codec/[state_trie, state_layout, bounded]

const
  CheckpointMagic = "RAGNAROK-FULL-V1\n"
  HeaderBytes = CheckpointMagic.len + 40

type
  CheckpointError* {.pure.} = enum ## Refusals never expose partial bytes or a fabricated complete state.
    Uninitialized, None, LimitExceeded, InvalidFormat, NonCanonical, RootMismatch, BackendFailure
  CheckpointResult*[T] = object ## Private alternatives authorize extraction only after complete success.
    case status: CheckpointError
    of None:
      completed: T
    else:
      discard # Default and failed values retain no successful payload.

func error*[T](outcome: CheckpointResult[T]): CheckpointError =
  ## Inspect the reason without selecting or exposing the payload.
  outcome.status
func value*[T](outcome: CheckpointResult[T]): T {.inline,
    requires: outcome.status == CheckpointError.None.} =
  ## Successful output is independently owned; default/refused alternatives cannot be extracted.
  outcome.completed

proc putNumber(output: var seq[byte], offset: int, number: uint64) =
  ## Internal callers prove an eight-byte destination before writing a fixed little-endian field.
  for index in 0..<8:
    output[offset + index] = byte((number shr (8 * index)) and 255) # Fixed shifts preserve all uint64 bits.

proc encodeFullCheckpoint*(snapshot: StateStoreSnapshot,
    limit: ByteLimit): CheckpointResult[seq[byte]] =
  ## Preflight the exact envelope size before allocation/copy; retain the immutable source throughout.
  if snapshot.forkStateStore.error != StateStoreError.None:
    return CheckpointResult[seq[byte]](status: CheckpointError.Uninitialized) # Defaults cannot become initialized empty maps.
  let maximum = min(uint64(limit), uint64(high(int)))
  var extent = uint64(HeaderBytes)
  if extent > maximum:
    return CheckpointResult[seq[byte]](status: CheckpointError.LimitExceeded)
  let committed = snapshot.commitment
  let count = uint64(committed.entries)
  if count > (maximum - extent) div 39:
    return CheckpointResult[seq[byte]](status: CheckpointError.LimitExceeded) # Prove all fixed-key/length overhead before multiplication.
  extent += count * 39
  for index in 0..<committed.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    let size = uint64(snapshot.lookup(key).value.byteLength)
    if size > maximum - extent:
      return CheckpointResult[seq[byte]](status: CheckpointError.LimitExceeded) # Subtraction bounds aggregate bytes without wrapping.
    extent += size
  var output = newSeq[byte](int(extent)) # Both the configured ceiling and host sequence extent are proved.
  for index, character in CheckpointMagic:
    output[index] = byte(character) # A versioned full-state domain precedes all numeric fields.
  output.putNumber(CheckpointMagic.len, count)
  let root = array[32, byte](committed.root)
  for index in 0..<32:
    output[CheckpointMagic.len + 8 + index] = root[
        index] # Copy the complete map's existing commitment, without rehashing.
  var offset = HeaderBytes
  for index in 0..<committed.entries:
    let key = snapshot.keyAt(StateEntryIndex(index)).value
    let rawKey = array[31, byte](key)
    for octet in rawKey:
      output[offset] = octet
      inc offset # Preflight included exactly 31 key bytes for this record.
    let view = snapshot.lookup(key).value
    output.putNumber(offset, uint64(view.byteLength))
    offset += 8
    let bytes = view.bytes
    for octet in bytes:
      output[offset] = octet
      inc offset # Preflight included every retained value's exact length, including zero.
  CheckpointResult[seq[byte]](status: CheckpointError.None, completed: output)

proc readNumber(input: openArray[byte], offset: int): uint64 =
  ## Each caller proves eight input bytes before decoding the fixed little-endian field.
  result = 0
  for index in 0..<8:
    result = result or (uint64(input[offset + index]) shl (8 *
        index)) # Disjoint shifts preserve every bit without addition.

proc before(left, right: array[31, byte]): bool =
  ## Strict lexical order rejects duplicates and reverse-ordered records before allocating a map.
  for index in 0..<31:
    if left[index] < right[index]: return true # The first differing key octet fixes order.
    if left[index] > right[index]: return false # Later suffixes cannot repair reverse order.
  false

proc decodeFullCheckpoint*(input: openArray[byte], limits: StateStoreLimits,
    limit: ByteLimit): CheckpointResult[StateStore] =
  ## Borrow stable input synchronously; validate its entire shape/policy before owning any entries.
  if uint64(input.len) > uint64(limit):
    return CheckpointResult[StateStore](status: CheckpointError.LimitExceeded)
  if input.len < HeaderBytes:
    return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # No partial header or alternate version is accepted.
  for index, character in CheckpointMagic:
    if input[index] != byte(character):
      return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # Exact full-state domain excludes light/unknown envelopes.
  let count = readNumber(input, CheckpointMagic.len)
  if count > uint64((input.len - HeaderBytes) div 39):
    return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # Minimum record size proves count fits native indexing too.
  if count > uint64(limits.trie.items):
    return CheckpointResult[StateStore](status: CheckpointError.LimitExceeded)
  var offset = HeaderBytes
  var remaining = uint64(limits.trie.totalValueBytes)
  var previous = default(array[31, byte])
  var seen = false
  for record in 0..<int(count):
    if input.len - offset < 39:
      return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # Earlier variable payloads may consume later fixed fields.
    var key = default(array[31, byte])
    for index in 0..<31:
      key[index] = input[offset + index] # The complete fixed record prefix was proved above.
    if seen and not before(previous, key):
      return CheckpointResult[StateStore](status: CheckpointError.NonCanonical) # Duplicates are refused rather than overwritten or sorted.
    previous = key
    seen = true
    offset += 31
    let size = readNumber(input, offset)
    offset += 8
    if size > uint64(input.len - offset):
      return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # Subtraction proves narrowing and the later offset addition.
    if size > uint64(limits.trie.perValue) or size > remaining:
      return CheckpointResult[StateStore](status: CheckpointError.LimitExceeded)
    remaining -= size
    offset += int(size)
  if offset != input.len:
    return CheckpointResult[StateStore](status: CheckpointError.InvalidFormat) # Exact consumption rejects trailers and concatenated checkpoints.
  var entries = newSeq[StateEntry](int(count))
  offset = HeaderBytes
  for record in 0..<entries.len:
    var key = default(array[31, byte])
    for index in 0..<31:
      key[index] = input[offset + index] # The first pass validated every repeated immutable coordinate.
    offset += 31
    let size = int(readNumber(input, offset))
    offset += 8
    var value = newSeq[byte](size)
    for index in 0..<size:
      value[index] = input[offset + index] # Own exact raw bytes; no view into the caller buffer escapes.
    offset += size
    entries[record] = StateEntry(key: StateKey(key), value: value)
  let made = newStateStore(entries, limits)
  if made.error != StateStoreError.None:
    let reason = if made.error == StateStoreError.LimitExceeded: CheckpointError.LimitExceeded
      else: CheckpointError.BackendFailure # Native/root-construction refusal cannot become a restored state.
    return CheckpointResult[StateStore](status: reason)
  let root = array[32, byte](made.value.snapshot.value.commitment.root)
  for index in 0..<32:
    if root[index] != input[CheckpointMagic.len + 8 + index]:
      return CheckpointResult[StateStore](status: CheckpointError.RootMismatch) # Only a fully recomputed complete-map root authorizes publication.
  CheckpointResult[StateStore](status: CheckpointError.None, completed: made.value)
