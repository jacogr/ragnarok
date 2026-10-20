# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_arc_release"}

## Independent byte-layout witnesses and bounded immutable full-map checkpoint ownership.

import std/[assertions, syncio]
import ../../../src/state/[checkpoint, store]
import ../../../src/codec/[state_trie, state_layout, bounded]
import ../../support/arc_evidence

proc key(number: byte): StateKey =
  ## Distinct complete serialized keys differ in their first octet.
  var bytes = default(array[31, byte])
  bytes[0] = number
  StateKey(bytes)
proc policy(): StateStoreLimits =
  ## Small exact policies permit empty/nonempty complete mappings without unrelated state semantics.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(100),
    totalValueBytes: ByteLimit(200), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(4), writeValueBytes: ByteLimit(200))
proc cycle(snapshot: StateStoreSnapshot) =
  ## Returned successful bytes and refused alternatives retire before allocator observation.
  let encoded = encodeFullCheckpoint(snapshot, ByteLimit(1000))
  assert encoded.error == CheckpointError.None
  assert encodeFullCheckpoint(snapshot, ByteLimit(0)).error == CheckpointError.LimitExceeded
proc main() =
  ## Verify canonical order, exact envelope bytes, every short ceiling and independent historical ownership.
  let absent = default(CheckpointResult[seq[byte]])
  assert absent.error == CheckpointError.Uninitialized
  assert encodeFullCheckpoint(default(StateStoreSnapshot), ByteLimit(1000)).error ==
      CheckpointError.Uninitialized
  let empty = newStateStore([], policy()).value.snapshot.value
  let emptyBytes = encodeFullCheckpoint(empty, ByteLimit(high(uint64))).value
  let magic = "RAGNAROK-FULL-V1\n"
  let header = magic.len + 40
  assert emptyBytes.len == header
  for index, character in magic:
    assert emptyBytes[index] == byte(character) # The storage envelope has one exact version/domain.
  for index in magic.len..<header:
    assert emptyBytes[index] == 0 # Empty count and complete empty root are independently known zero bytes.
  var store = newStateStore([StateEntry(key: key(2), value: @[11'u8, 12, 13]),
    StateEntry(key: key(1), value: @[])], policy()).value
  let original = store.snapshot.value
  let encoded = encodeFullCheckpoint(original, ByteLimit(1000)).value
  assert encoded.len == header + 78 + 3
  assert encoded[magic.len] == 2
  for index in 1..<8:
    assert encoded[magic.len + index] == 0 # Count uses fixed little-endian uint64, never a host-sized integer.
  let root = array[32, byte](original.commitment.root)
  for index in 0..<32:
    assert encoded[magic.len + 8 + index] == root[index] # Exact complete-root bytes precede sorted entries.
  assert encoded[header] == 1 and encoded[header + 39] == 2
  for index in 1..<39:
    assert encoded[header + index] == 0 # First key suffix and present-empty value length remain exact.
  assert encoded[header + 70] == 3
  for index in 71..<78:
    assert encoded[header + index] == 0 # Second value length is exactly three in uint64 little endian.
  assert encoded[header + 78] == 11 and encoded[header + 80] == 13
  for limit in 0..<encoded.len:
    assert encodeFullCheckpoint(original, ByteLimit(uint64(limit))).error ==
        CheckpointError.LimitExceeded
  assert encodeFullCheckpoint(original, ByteLimit(uint64(encoded.len))).value == encoded
  var copied = encodeFullCheckpoint(original, ByteLimit(1000)).value
  copied[copied.high] = 99
  assert encodeFullCheckpoint(original, ByteLimit(1000)).value == encoded
  assert store.apply([StateWrite(key: key(2), kind: StateWriteKind.Delete)]).error ==
      StateStoreError.None
  assert encodeFullCheckpoint(original, ByteLimit(1000)).value ==
      encoded # Later publication cannot change retained checkpoint inputs.
  assert encodeFullCheckpoint(store.snapshot.value, ByteLimit(1000)).value != encoded
  cycle(original)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(original) # Temporary output and failed results must not retain snapshot aliases or byte buffers.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint", 1000, before, after)
  echo "PASS state checkpoint encoding: exact full-map bytes, bounds and immutable ownership"
main()
