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
    Uninitialized, None, LimitExceeded
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
