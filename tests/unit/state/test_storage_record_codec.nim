# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact storage framing, malformed/overflow refusals and independent complete node hashes.

import std/[assertions, syncio]
import ../../../src/storage/[node_records, record_codec, full_state_trie]
import ../../../src/codec/[state_layout, state_trie, bounded]

proc limits(): RecordLimits =
  ## Bounded complete maps and independently bounded physical batches.
  RecordLimits(trie: StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(132), nodes: TrieNodeLimit(1000)),
    records: TrieExportLimits(records: TrieNodeLimit(1000), valueBytes: ByteLimit(132)),
    encoded: ByteLimit(100000))
proc main() =
  ## Every prefix/trailer and uint64 count/length attack refuses without partial output.
  let policy = limits()
  let trie = newFullStateTrie([StateEntry(key: default(StateKey), value: @[7'u8])],
    FullStateTrieLimits(trie: policy.trie)).value
  let batch = exportFullTrie(trie, policy.records).value
  var encoding = encodeTrieExport(batch, policy)
  assert encoding.error == RecordError.None
  let occupied = getOccupiedMem()
  let encoded = encoding.takeValue
  assert encoding.error == RecordError.Uninitialized and getOccupiedMem() == occupied
  var decoding = decodeTrieExport(encoded, policy)
  assert decoding.error == RecordError.None
  let independent = decoding.value
  let beforeTransfer = getOccupiedMem()
  var decoded = decoding.takeValue
  assert decoding.error == RecordError.Uninitialized and getOccupiedMem() == beforeTransfer
  decoded.records[0].payload[0] = 8
  assert independent.records[0].payload == @[7'u8] # Existing copy access retains independent transport bytes.
  assert encoded.len == 178 # 105-byte header, 72-byte leaf prefix and one value byte.
  assert encoded[105] == 0 and encoded[169] == 1 and encoded[177] == 7
  # Frozen independent Python struct/hashlib witness includes every physical header and leaf byte.
  let expected = [82'u8, 65, 71, 78, 65, 82, 79, 75, 45, 84, 82, 73, 69, 45, 86, 49,
    10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 3, 118, 146, 112, 35, 113, 3, 187, 105, 207, 249, 126, 202, 164, 57,
    237, 160, 178, 57, 147, 220, 127, 245, 54, 60, 122, 167, 70, 4, 203, 213,
    99, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 3, 118, 146, 112, 35, 113,
    3, 187, 105, 207, 249, 126, 202, 164, 57, 237, 160, 178, 57, 147, 220, 127,
    245, 54, 60, 122, 167, 70, 4, 203, 213, 99, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0,
    0, 7]
  assert encoded == @expected
  for stop in 0..<encoded.len:
    # Borrow each prefix, including empty input, without invoking the allocating stdlib slice.
    assert decodeTrieExport(encoded.toOpenArray(0, stop-1), policy).error != RecordError.None
  var trailer = encoded
  trailer.add(0)
  assert decodeTrieExport(trailer, policy).error == RecordError.InvalidFormat
  var huge = encoded
  for i in 0..<8: huge[97+i] = 255 # A full-width record count cannot drive allocation.
  assert decodeTrieExport(huge, policy).error == RecordError.InvalidFormat
  huge = encoded
  for i in 0..<8: huge[169+i] = 255 # A full-width raw payload length cannot narrow or wrap.
  assert decodeTrieExport(huge, policy).error == RecordError.InvalidFormat
  var malformed = encoded
  malformed[105] = 2
  assert decodeTrieExport(malformed, policy).error == RecordError.NonCanonical
  malformed = encoded
  malformed[177] = 9
  assert decodeTrieExport(malformed, policy).error == RecordError.HashMismatch
  var exact = policy
  exact.encoded = ByteLimit(encoded.len)
  assert encodeTrieExport(batch, exact).value == encoded
  exact.encoded = ByteLimit(encoded.len-1)
  assert encodeTrieExport(batch, exact).error == RecordError.LimitExceeded
  assert decodeTrieExport(encoded, exact).error == RecordError.LimitExceeded
  var duplicate = batch
  duplicate.records.add(batch.records[0])
  assert encodeTrieExport(duplicate, policy).error == RecordError.DuplicateNode
  var spare = batch
  spare.records[0].left = batch.records[0].digest
  assert encodeTrieExport(spare, policy).error == RecordError.NonCanonical
  let restored = decodeTrieExport(encoded, policy).value
  assert restored.records[0].payload == @[7'u8]
  assert array[32, byte](restored.root) == array[32, byte](trie.commitment.root)
  # Two root branches exercise full child identities and both inline/hashed leaf forms.
  var otherKey = default(array[31, byte])
  otherKey[0] = 128
  for size in [0, 1, 32, 33]:
    let source = newFullStateTrie([StateEntry(key: default(StateKey), value: newSeq[byte](size)),
      StateEntry(key: StateKey(otherKey), value: @[9'u8])], FullStateTrieLimits(
          trie: policy.trie)).value
    let physical = exportFullTrie(source, policy.records).value
    var wire = encodeTrieExport(physical, policy).value
    let decoded = decodeTrieExport(wire, policy).value
    assert decoded.records.len == 3 and decoded.records[2].kind == TrieRecordKind.Branch
    assert array[32, byte](decoded.records[2].left) == array[32, byte](physical.records[0].digest)
    assert array[32, byte](decoded.records[2].right) == array[32, byte](physical.records[1].digest)
    assert decoded.records[0].payload.len == size
    wire[0] = 0 # Decoded record storage remains independent of its retired wire input.
    assert decoded.records[1].payload == @[9'u8]
  let empty = encodeTrieExport(default(TrieExport), policy).value
  assert empty.len == 105 and decodeTrieExport(empty, policy).value.records.len == 0

main()
echo "PASS storage record codec: exact framing, truncation, overflow, integrity and budgets"
