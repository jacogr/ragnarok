# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_decode_arc_release"}

## Untrusted checkpoint shape, policy, root integrity and restored ownership witnesses.

import std/[assertions, syncio]
import ../../../src/state/[checkpoint, store]
import ../../../src/codec/[state_trie, state_layout, bounded]
import ../../support/arc_evidence

proc key(number: byte): StateKey =
  ## Fixed keys make record identity and mutation offsets independently visible.
  var raw = default(array[31, byte])
  raw[0] = number
  StateKey(raw)
proc policy(): StateStoreLimits =
  ## Bound both restored complete-map storage and later mutation batches explicitly.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(1),
    totalValueBytes: ByteLimit(2), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(1))
proc cloned(input: seq[byte]): seq[byte] =
  ## Deliberately deep-copy each tampering witness without depending on sequence copy lowering.
  result = newSeq[byte](input.len)
  for index, octet in input:
    result[index] = octet # Every malformed case starts from the original exact envelope.
proc cycle(input: seq[byte]) =
  ## Full restoration and malformed refusal must release every temporary byte/map owner.
  assert decodeFullCheckpoint(input, policy(), ByteLimit(1000)).error == CheckpointError.None
  assert decodeFullCheckpoint([], policy(), ByteLimit(1000)).error == CheckpointError.InvalidFormat
proc main() =
  ## Decode exact complete roots, reject all one-byte tampering, and preserve independent state ownership.
  let original = newStateStore([StateEntry(key: key(2), value: @[22'u8]),
    StateEntry(key: key(1), value: @[11'u8])], policy()).value.snapshot.value
  let encoded = encodeFullCheckpoint(original, ByteLimit(1000)).value
  let header = "RAGNAROK-FULL-V1\n".len + 40
  let restored = decodeFullCheckpoint(encoded, policy(), ByteLimit(uint64(encoded.len)))
  assert restored.error == CheckpointError.None
  assert encodeFullCheckpoint(restored.value.snapshot.value, ByteLimit(1000)).value == encoded
  for size in 0..<encoded.len:
    assert decodeFullCheckpoint(encoded.toOpenArray(0, size - 1), policy(), ByteLimit(
        1000)).error != CheckpointError.None
    assert decodeFullCheckpoint(encoded, policy(), ByteLimit(uint64(size))).error ==
        CheckpointError.LimitExceeded
  for index in 0..<encoded.len:
    var changed = cloned(encoded)
    changed[index] = changed[index] xor 1
    assert decodeFullCheckpoint(changed, policy(), ByteLimit(1000)).error !=
        CheckpointError.None # No byte is silently discarded or left uncommitted.
  var duplicate = cloned(encoded)
  for index in 0..<31:
    let octet = duplicate[header + index]
    duplicate[header + 40 + index] = octet # Duplicate keys must fail before rehashing or sorting.
  assert decodeFullCheckpoint(duplicate, policy(), ByteLimit(1000)).error ==
      CheckpointError.NonCanonical
  var reversed = cloned(encoded)
  reversed[header] = 3
  assert decodeFullCheckpoint(reversed, policy(), ByteLimit(1000)).error ==
      CheckpointError.NonCanonical
  var trailing = cloned(encoded)
  trailing.add(0)
  assert decodeFullCheckpoint(trailing, policy(), ByteLimit(1000)).error ==
      CheckpointError.InvalidFormat
  var huge = cloned(encoded)
  for index in 0..<8:
    huge[header + 31 + index] = 255 # Full-width malicious lengths cannot wrap or allocate before extent validation.
  assert decodeFullCheckpoint(huge, policy(), ByteLimit(1000)).error ==
      CheckpointError.InvalidFormat
  var limits = policy()
  limits.trie.items = ElementLimit(1)
  assert decodeFullCheckpoint(encoded, limits, ByteLimit(1000)).error ==
      CheckpointError.LimitExceeded
  limits = policy()
  limits.trie.perValue = ByteLimit(0)
  assert decodeFullCheckpoint(encoded, limits, ByteLimit(1000)).error ==
      CheckpointError.LimitExceeded
  limits = policy()
  limits.trie.totalValueBytes = ByteLimit(1)
  assert decodeFullCheckpoint(encoded, limits, ByteLimit(1000)).error ==
      CheckpointError.LimitExceeded
  limits = policy()
  limits.trie.nodes = TrieNodeLimit(0)
  assert decodeFullCheckpoint(encoded, limits, ByteLimit(1000)).error ==
      CheckpointError.LimitExceeded
  var source = cloned(encoded)
  var store = decodeFullCheckpoint(source, policy(), ByteLimit(high(uint64))).value
  source[source.high] = 99
  assert store.snapshot.value.lookup(key(2)).value.bytes == @[22'u8]
  assert store.apply([StateWrite(key: key(2), kind: StateWriteKind.Put, value: @[33'u8])]).error ==
      StateStoreError.None
  assert original.lookup(key(2)).value.bytes == @[22'u8]
  assert restored.value.snapshot.value.lookup(key(2)).value.bytes == @[22'u8]
  let empty = newStateStore([], policy()).value.snapshot.value
  assert decodeFullCheckpoint(encodeFullCheckpoint(empty, ByteLimit(1000)).value,
    default(StateStoreLimits), ByteLimit(1000)).error == CheckpointError.None
  cycle(encoded)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(encoded) # Successful map graphs and refused results retire in each isolated call.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_decode", 1000, before, after)
  echo "PASS state checkpoint decoding: strict framing, complete roots and bounded owned restoration"
main()
