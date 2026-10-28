# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Broad persistent batches preserve independent complete-map roots, final-only quotas and owned historical values.
import std/assertions
import std/syncio
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

proc key(number: int): StateKey =
  ## Both root polarities contain long shared prefixes followed by distinct two-byte suffixes.
  var raw = default(array[31, byte])
  raw[0] = if number mod 2 == 0: 0'u8 else: 128'u8
  raw[29] = byte(number shr 8)
  raw[30] = byte(number and 255)
  StateKey(raw)

proc policy(items = 512): FullStateTrieLimits =
  ## Mutation count covers complete swaps; map/value quotas remain independent fixed extents.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(items), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(items*33), nodes: TrieNodeLimit(128000)),
    writes: ElementLimit(512), writeValueBytes: ByteLimit(16896))

proc payload(number, turn: int): seq[byte] =
  ## Fixed values span empty, inline and long encodings and never borrow production node storage.
  result = newSeq[byte]((number+turn) mod 34)
  for offset in 0..<result.len: result[offset] = byte((number+turn+offset) and 255)

proc matches(trie: FullStateTrie, expected: seq[StateEntry], limits: FullStateTrieLimits) =
  ## The separate full-map calculator supplies complete root, node and entry authority.
  let reference = stateTrieRoot(expected, limits.trie).value
  let actual = trie.commitment
  assert actual.entries == reference.entries and actual.nodes == reference.nodes
  assert array[32, byte](actual.root) == array[32, byte](reference.root)
  for entry in expected: assert trie.lookup(entry.key).value.bytes == entry.value

proc mapping(present: array[512, bool], values: array[512, seq[byte]]): seq[StateEntry] =
  ## Flat finite slots form an independent map with no traversal, branch summaries or sorted write logic.
  result = @[]
  for number in 0..<512:
    if present[number]: result.add(StateEntry(key: key(number), value: values[number]))

proc sequence() =
  ## Wide permuted Put/Delete batches retain their source and agree with independently reconstructed maps.
  var present = default(array[512, bool])
  var values = default(array[512, seq[byte]])
  for number in 0..<256:
    present[number] = true
    values[number] = payload(number, 0)
  let limits = policy()
  var current = newFullStateTrie(mapping(present, values), limits).value
  for turn in 0..<12:
    let previous = current
    let original = mapping(present, values)
    var writes: seq[TrieWrite] = @[]
    for slot in 0..<128:
      let position = (slot*65) mod 128
      let number = (position*17+turn*29) mod 512
      if position mod 3 == 0:
        writes.add(TrieWrite(key: key(number), kind: TrieWriteKind.Delete))
        present[number] = false
        values[number] = @[]
      else:
        writes.add(TrieWrite(key: key(number), kind: TrieWriteKind.Put, value: payload(number, turn+1)))
        present[number] = true
        values[number] = payload(number, turn+1) # Model bytes have independent ownership from mutable input.
    current = previous.apply(writes).value
    matches(current, mapping(present, values), limits)
    matches(previous, original, limits)
    var reversed = newSeq[TrieWrite](writes.len)
    for offset in 0..<writes.len: reversed[offset] = writes[writes.len-1-offset]
    let reordered = previous.apply(reversed).value
    matches(reordered, mapping(present, values), limits)
    for index in 0..<writes.len:
      if writes[index].kind == TrieWriteKind.Put and writes[index].value.len > 0:
        writes[index].value[0] = 255 # Later input mutation cannot change either independently published candidate.
    matches(current, mapping(present, values), limits)

proc swapWholeMap() =
  ## Final item/value budgets admit a complete replacement even when all new keys sort before old keys.
  let limits = policy(256)
  var old: seq[StateEntry] = @[]
  var expected: seq[StateEntry] = @[]
  var writes: seq[TrieWrite] = @[]
  for number in 0..<256:
    old.add(StateEntry(key: key(number+256), value: newSeq[byte](33)))
    expected.add(StateEntry(key: key(number), value: newSeq[byte](33)))
    writes.add(TrieWrite(key: key(number), kind: TrieWriteKind.Put, value: newSeq[byte](33)))
    writes.add(TrieWrite(key: key(number+256), kind: TrieWriteKind.Delete))
  let source = newFullStateTrie(old, limits).value
  let held = source.lookup(key(256)).value
  let changed = source.apply(writes).value
  matches(changed, expected, limits)
  matches(source, old, limits)
  assert held.byteLength == 33 and changed.lookup(key(256)).error == TrieError.MissingKey
  var deletes: seq[TrieWrite] = @[]
  for number in 0..<256: deletes.add(TrieWrite(key: key(number), kind: TrieWriteKind.Delete))
  let empty = changed.apply(deletes).value
  assert empty.commitment.entries == 0 and empty.commitment.nodes == 0
  assert sameTrieRevision(empty, empty.apply(deletes).value)
  let restored = empty.apply(writes).value
  matches(restored, expected, limits) # Empty-source mixed batches cannot keep absent deletes or old leaves.

proc run() =
  ## Scope all broad candidates and retained owners before the exact release observation.
  sequence()
  swapWholeMap()
run() # Warm identical arithmetic, sort and owner paths before observing retirement.
let before = getOccupiedMem()
run()
assert getOccupiedMem() == before
echo "PASS full state trie batches: wide permuted edits, final quotas, independent roots and exact release"
