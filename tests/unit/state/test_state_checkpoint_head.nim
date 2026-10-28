# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "state_checkpoint_head_arc_release"}

## Independent fixed-byte witness, all-prefix and every-byte corruption checks for local selection metadata.

import std/assertions
import std/syncio
import ../../../src/state/checkpoint_head as state_checkpoint_head
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded
import ../../support/testing_arc_evidence

proc cycle(head: CheckpointHead) =
  ## Successful temporary bytes and decoded metadata retire before allocator observation.
  let bytes = encodeCheckpointHead(head, ByteLimit(CheckpointHeadBytes)).value
  assert decodeCheckpointHead(bytes, ByteLimit(CheckpointHeadBytes)).error ==
      CheckpointHeadError.None
proc main() =
  ## Verify exact canonical layout, corruption refusal, owned output and checked generation exhaustion.
  let absent = default(CheckpointHeadResult[CheckpointHead])
  assert absent.error == CheckpointHeadError.Uninitialized
  assert not default(CheckpointHead).ready
  assert encodeCheckpointHead(default(CheckpointHead), ByteLimit(1000)).error ==
      CheckpointHeadError.Uninitialized
  assert nextCheckpointHead(default(CheckpointHead), default(StateRoot)).error ==
      CheckpointHeadError.Uninitialized
  var root = default(array[32, byte])
  for index in 0..<32:
    root[index] = byte(index) # An ascending root makes every fixed root position independently observable.
  let head = newCheckpointHead(CheckpointGeneration(0x0102030405060708'u64), CheckpointSlot.Second,
      StateRoot(root))
  let encoded = encodeCheckpointHead(head, ByteLimit(CheckpointHeadBytes)).value
  let magic = "RAGNAROK-HEAD-V1\n"
  assert encoded.len == magic.len + 73
  for index, character in magic:
    assert encoded[index] == byte(character) # The literal local metadata version is independently specified.
  for index in 0..<8:
    assert encoded[magic.len + index] == byte(8 - index) # Fixed LE witness is deliberately different in every octet.
  assert encoded[magic.len + 8] == 1
  for index in 0..<32:
    assert encoded[magic.len + 9 + index] == byte(index) # Root bytes cannot swap with generation or checksum.
  let checksum = [65, 200, 113, 185, 176, 155, 208, 185, 115, 127, 47, 61, 88, 138, 243, 175, 28,
      187, 198, 16, 178, 46, 182, 68, 245, 231, 101, 169, 216, 215, 47, 165]
  for index in 0..<32:
    assert encoded[magic.len + 41 + index] == byte(checksum[
        index]) # Python hashlib independent known-answer witness.
  let decoded = decodeCheckpointHead(encoded, ByteLimit(CheckpointHeadBytes)).value
  assert uint64(decoded.generation) == 0x0102030405060708'u64
  assert decoded.slot == CheckpointSlot.Second and array[32, byte](decoded.root) == root
  for size in 0..<CheckpointHeadBytes:
    assert encodeCheckpointHead(head, ByteLimit(uint64(size))).error ==
        CheckpointHeadError.LimitExceeded
    assert decodeCheckpointHead(encoded.toOpenArray(0, size - 1), ByteLimit(1000)).error ==
        CheckpointHeadError.InvalidFormat # Includes the empty prefix.
  assert decodeCheckpointHead(encoded, ByteLimit(CheckpointHeadBytes - 1)).error ==
      CheckpointHeadError.LimitExceeded
  var appended = encoded
  appended.add(0)
  assert decodeCheckpointHead(appended, ByteLimit(1000)).error == CheckpointHeadError.InvalidFormat
  for index in 0..<encoded.len:
    var corrupted = encodeCheckpointHead(head, ByteLimit(1000)).value
    let octet = corrupted[index]
    corrupted[index] = octet xor 255
    assert decodeCheckpointHead(corrupted, ByteLimit(1000)).error !=
        CheckpointHeadError.None # Every payload/checksum octet is protected.
  assert encodeCheckpointHead(head, ByteLimit(1000)).value ==
      encoded # Mutated returned buffers do not alter the immutable head.
  let next = nextCheckpointHead(head, default(StateRoot)).value
  assert uint64(next.generation) == 0x0102030405060709'u64 and next.slot == CheckpointSlot.First
  let initial = newCheckpointHead(CheckpointGeneration(0), CheckpointSlot.First, default(StateRoot))
  assert initial.ready and uint64(initial.generation) == 0
  let last = newCheckpointHead(CheckpointGeneration(high(uint64)), CheckpointSlot.Second, StateRoot(root))
  assert uint64(decodeCheckpointHead(encodeCheckpointHead(last, ByteLimit(1000)).value, ByteLimit(
      1000)).value.generation) == high(uint64)
  assert nextCheckpointHead(last, default(StateRoot)).error ==
      CheckpointHeadError.GenerationExhausted
  cycle(head)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(head) # Metadata and digest temporaries leave no retained ARC storage.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("state_checkpoint_head", 1000, before, after)
  echo "PASS checkpoint heads: exact checksummed layout, strict bounds and generation exhaustion"
main()
