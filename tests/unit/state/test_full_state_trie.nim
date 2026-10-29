# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent complete-map comparisons, exact topology, limits and immutable public ownership.

import std/[assertions, syncio]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/codec/state/[trie as state_trie, layout as state_layout]
import ../../../src/codec/bounded

proc key(number: int): StateKey =
  ## Spread authored identities across both early branches and shared suffixes.
  var raw = default(array[31, byte])
  raw[0] = byte(number mod 256)
  raw[30] = byte(number div 256)
  StateKey(raw)

proc policy(): FullStateTrieLimits =
  ## Bounded deterministic maps fit both reference and incremental implementations.
  FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(128),
    perValue: ByteLimit(64), totalValueBytes: ByteLimit(8192), nodes: TrieNodeLimit(32000)),
    writes: ElementLimit(128), writeValueBytes: ByteLimit(8192))

proc matches(trie: FullStateTrie, entries: seq[StateEntry]) =
  ## The unchanged complete-map calculator independently constructs every expected topology/root.
  let expected = stateTrieRoot(entries, policy().trie)
  assert expected.error == StateTrieError.None
  let actual = trie.commitment
  assert actual.entries == expected.value.entries and actual.nodes == expected.value.nodes
  assert array[32, byte](actual.root) == array[32, byte](expected.value.root)
  for entry in entries:
    let found = trie.lookup(entry.key)
    assert found.error == TrieError.None
    assert found.value.byteLength == entry.value.len and found.value.bytes == entry.value

proc reference(entries: seq[StateEntry], writes: seq[TrieWrite]): seq[StateEntry] =
  ## Linear full-key scans form a separate model, with no trie traversal or sorted merge.
  result = @[]
  for entry in entries:
    var touched = false
    for write in writes:
      if array[31, byte](entry.key) == array[31, byte](
          write.key): touched = true # Unique writes replace/delete this key.
    if not touched: result.add(entry) # Preserve every untouched reference entry.
  for write in writes:
    if write.kind == TrieWriteKind.Put:
      result.add(StateEntry(key: write.key, value: write.value)) # Empty bytes are still a present record.

proc topology() =
  ## Every key divergence and both prefix polarities must retain all unary branches.
  for depth in 0..<248:
    for polarity in 0..<2:
      var a = default(array[31, byte])
      if polarity == 1:
        for i in 0..<31: a[i] = 255 # Exercise all-one shared prefixes too.
      var b = a
      b[depth div 8] = b[depth div 8] xor byte(128 shr (depth mod 8))
      let first = StateEntry(key: StateKey(a), value: newSeq[byte](32))
      let second = StateEntry(key: StateKey(b), value: newSeq[byte](33))
      let before = newFullStateTrie([first], policy()).value
      let after = before.apply([TrieWrite(key: second.key, kind: TrieWriteKind.Put,
        value: second.value)]).value
      matches(after, @[first, second])
      # Direct construction must agree with both the independent calculator and incremental insertion.
      let built = newFullStateTrie([second, first], policy()).value
      matches(built, @[first, second])
      assert built.commitment.nodes == uint64(depth+3)
      let reduced = built.apply([TrieWrite(key: first.key, kind: TrieWriteKind.Delete)]).value
      matches(reduced, @[second]) # Constructed branches must also support ordinary collapse/sharing.
      assert after.commitment.nodes == uint64(depth+3)
      matches(before, @[first])
      let collapsed = after.apply([TrieWrite(key: first.key, kind: TrieWriteKind.Delete)]).value
      matches(collapsed, @[second])
      assert collapsed.commitment.nodes == 1
      let empty = collapsed.apply([TrieWrite(key: second.key, kind: TrieWriteKind.Delete)]).value
      matches(empty, @[])
      assert empty.lookup(first.key).error == TrieError.MissingKey

proc boundaries() =
  ## Defaults, duplicates, exact ceilings and replacement budget release have explicit outcomes.
  assert default(FullStateTrie).apply([]).error == TrieError.Uninitialized
  assert default(FullStateTrie).lookup(key(0)).error == TrieError.Uninitialized
  let uninitialized = default(TrieResult[FullStateTrie])
  assert uninitialized.error == TrieError.Uninitialized
  let empty = newFullStateTrie([], default(FullStateTrieLimits)).value
  matches(empty, @[])
  assert sameTrieRevision(empty, empty.apply([]).value)
  let entry = StateEntry(key: key(0), value: @[1'u8, 2, 3])
  assert newFullStateTrie([entry, entry], policy()).error == TrieError.DuplicateKey
  var exact = FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(1),
    perValue: ByteLimit(3), totalValueBytes: ByteLimit(3), nodes: TrieNodeLimit(1)),
    writes: ElementLimit(2), writeValueBytes: ByteLimit(3))
  let trie = newFullStateTrie([entry], exact).value
  # Exact final budgets admit replacement; deletion must release both old count and bytes.
  let replaced = trie.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Delete),
    TrieWrite(key: key(1), kind: TrieWriteKind.Put, value: @[4'u8, 5, 6])]).value
  matches(replaced, @[StateEntry(key: key(1), value: @[4'u8, 5, 6])])
  assert trie.lookup(key(0)).value.bytes == entry.value
  let highKey = newFullStateTrie([StateEntry(key: key(1), value: entry.value)], exact).value
  let reordered = highKey.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Put,
    value: entry.value), TrieWrite(key: key(1), kind: TrieWriteKind.Delete)])
  assert reordered.error == TrieError.None
  matches(reordered.value, @[entry])
  let put = TrieWrite(key: key(0), kind: TrieWriteKind.Put, value: @[])
  assert trie.apply([put, put]).error == TrieError.DuplicateKey
  assert trie.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Delete,
    value: @[1'u8])]).error == TrieError.InvalidWrite
  assert trie.apply([TrieWrite(key: key(1), kind: TrieWriteKind.Put)]).error ==
      TrieError.LimitExceeded
  assert trie.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Put,
    value: newSeq[byte](4))]).error == TrieError.LimitExceeded
  let presentEmpty = trie.apply([put]).value
  assert presentEmpty.lookup(key(0)).error == TrieError.None
  assert presentEmpty.lookup(key(0)).value.byteLength == 0
  assert presentEmpty.lookup(key(1)).error == TrieError.MissingKey
  let absent = trie.apply([TrieWrite(key: key(2), kind: TrieWriteKind.Delete)]).value
  assert sameTrieRevision(absent, trie)
  # Construction uses map ceilings independently of zero mutation ceilings.
  exact.writes = ElementLimit(0)
  exact.writeValueBytes = ByteLimit(0)
  let readonly = newFullStateTrie([entry], exact).value
  assert readonly.apply([put]).error == TrieError.LimitExceeded
  exact.writes = ElementLimit(1)
  let noBytes = newFullStateTrie([entry], exact).value
  assert noBytes.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Put,
    value: @[1'u8])]).error == TrieError.LimitExceeded
  # Maximum policy counters must not wrap on ordinary bounded inputs.
  let maximum = FullStateTrieLimits(trie: StateTrieLimits(items: ElementLimit(high(uint64)),
    perValue: ByteLimit(high(uint64)), totalValueBytes: ByteLimit(high(uint64)),
    nodes: TrieNodeLimit(high(uint64))), writes: ElementLimit(high(uint64)),
    writeValueBytes: ByteLimit(high(uint64)))
  matches(newFullStateTrie([entry], maximum).value, @[entry])

proc detached(): TrieValue =
  ## Retain only a leaf after every constructor/result/revision in the producer has retired.
  var bytes = @[1'u8, 2, 3]
  let trie = newFullStateTrie([StateEntry(key: key(7), value: bytes)], policy()).value
  let retained = trie.lookup(key(7)).value
  bytes[0] = 99
  assert retained.bytes == @[1'u8, 2, 3]
  var copy = retained.bytes
  copy[0] = 88
  assert retained.bytes == @[1'u8, 2, 3]
  retained

proc ownership() =
  ## Published values own their input and retain immutable versions across independent edits.
  var input = @[StateEntry(key: key(0), value: @[7'u8])]
  let before = newFullStateTrie(input, policy()).value
  input[0].value[0] = 99
  input.setLen(0)
  var writes = @[TrieWrite(key: key(0), kind: TrieWriteKind.Put, value: @[8'u8, 9])]
  let after = before.apply(writes).value
  let held = after.lookup(key(0)).value
  writes[0].value[0] = 88
  writes.setLen(0)
  assert before.lookup(key(0)).value.bytes == @[7'u8]
  assert held.bytes == @[8'u8, 9]
  let branch = after.apply([TrieWrite(key: key(0), kind: TrieWriteKind.Delete)]).value
  assert branch.commitment.entries == 0
  assert after.lookup(key(0)).value.bytes == @[8'u8, 9]
  assert not sameTrieRevision(before, newFullStateTrie([StateEntry(key: key(0),
    value: @[7'u8])], policy()).value)

proc sequence() =
  ## Deterministic mixed multi-key writes compare against a separately maintained complete mapping.
  var model: seq[StateEntry] = @[]
  var current = newFullStateTrie([], policy()).value
  var random = 1729'u32
  for round in 0..<300:
    let previous = current
    let old = model
    var writes: seq[TrieWrite] = @[]
    for i in 0..<4:
      random = random * 1664525'u32 + 1013904223'u32 # Fixed wrapping generator is intentional test data.
      let id = int((random shr 16) mod 16)*4+i # Four distinct residues prohibit duplicate batch keys.
      let kind = if (random and 3) == 0: TrieWriteKind.Delete else: TrieWriteKind.Put
      var bytes: seq[byte] = @[]
      if kind == TrieWriteKind.Put:
        bytes = newSeq[byte](int(random mod 35))
        for j in 0..<bytes.len: bytes[j] = byte(((random shr 24)+uint32(j)) and
            255) # Values cross the inline/hash boundary.
      writes.add(TrieWrite(key: key(id), kind: kind, value: bytes))
    let completed = current.apply(writes)
    assert completed.error == TrieError.None
    current = completed.value
    model = reference(model, writes)
    matches(current, model)
    # Rebuild unsorted mixed-length maps through the constructor; no update-path cache is reused.
    var reversed: seq[StateEntry] = @[]
    for offset in 0..<model.len:
      reversed.add(model[model.len-1-offset])
    let rebuilt = newFullStateTrie(reversed, policy()).value
    matches(rebuilt, model)
    assert not sameTrieRevision(rebuilt, current)
    matches(previous, old)
    # A copied revision is an independent branch and cannot mutate either retained version.
    let forked = previous.apply([TrieWrite(key: key(200), kind: TrieWriteKind.Put)]).value
    assert forked.lookup(key(200)).value.byteLength == 0
    assert previous.lookup(key(200)).error == TrieError.MissingKey
    for write in writes:
      if write.kind == TrieWriteKind.Delete:
        assert current.lookup(write.key).error == TrieError.MissingKey

boundaries()
topology()
ownership()
sequence()
assert detached().bytes == @[1'u8, 2, 3]
echo "PASS full state trie: reference roots, all divergence bits, atomic limits and retained revisions"
