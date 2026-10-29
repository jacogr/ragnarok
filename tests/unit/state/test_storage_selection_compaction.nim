# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact selected inventories preserve disjoint historical roots, empty maps, permutations and independent ownership.
# @@Verification={"arc": "storage_selection_compaction_arc_release"}
import std/[algorithm, assertions, syncio]
import ../../support/[arc_evidence, storage_snapshot_samples]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/storage/node/repository as node_repository
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded

proc policy(): RepositoryLimits =
  ## Each historical graph is a single complete leaf; physical history has its own fixed higher ceilings.
  RepositoryLimits(codec: RecordLimits(trie: StateTrieLimits(items: ElementLimit(1),
    perValue: ByteLimit(2), totalValueBytes: ByteLimit(2), nodes: TrieNodeLimit(1)),
    records: TrieExportLimits(records: TrieNodeLimit(1024), valueBytes: ByteLimit(2048)),
    encoded: ByteLimit(1048576)), records: ElementLimit(1024), valueBytes: ByteLimit(2048))

proc payload(ordinal: int): seq[byte] =
  ## Two independent ordinal bytes cross the one-byte boundary without duplicate physical leaves.
  assert ordinal >= 0 and ordinal < 257
  @[byte(ordinal shr 8), byte(ordinal and 255)]

proc exercise(count: int) =
  ## A union may greatly exceed any one root's graph; freeze only after all roots validate independently.
  let limits = policy()
  var owner = newNodeRepository(limits)
  let empty = owner.snapshot.value
  var roots = @[empty.commitment.root]
  var trie = default(FullStateTrie)
  for ordinal in 0..<count:
    let next = newFullStateTrie([StateEntry(key: default(StateKey), value: payload(ordinal))],
      FullStateTrieLimits(trie: limits.codec.trie)).value
    let batch = if ordinal == 0: exportFullTrie(next, limits.codec.records).value
      else: exportTrieChanges(trie, next, limits.codec.records).value
    let wire = encodeTrieExport(batch, limits.codec).value
    let published = owner.publishEncoded(owner.snapshot.value, wire).value
    roots.add(published.commitment.root)
    trie = next
  let held = owner.snapshot.value
  assert owner.close == RepositoryError.None
  let ceiling = ElementLimit(1024)
  let selected = selectRepositoryRoots(held, roots, ceiling).value
  assert selected.retainedNodes == count and selected.reclaimableNodes == 0
  assert selected.retainedValueBytes == uint64(count*2)
  assert selected.retainedRootCount == count+1
  let records = exportRepositorySelection(selected, limits.codec.records).value
  let expected = encodeRecordCollection(RecordCollection(records: records), limits.codec).value
  var reversed = newSeq[StateRoot](roots.len)
  for index in 0..<roots.len:
    reversed[index] = roots[roots.len-1-index] # Reverse only existing owned root slots before adding duplicates.
  reversed.add(roots[0])
  reversed.add(roots[roots.len-1])
  let permuted = selectRepositoryRoots(held, reversed, ceiling).value
  let repeated = exportRepositorySelection(permuted, limits.codec.records).value
  let encoded = encodeRecordCollection(RecordCollection(records: repeated), limits.codec).value
  assert encoded == expected # Root order/duplicates cannot change canonical physical inventory bytes.
  var cloned = cloneRepositorySelection(selected, limits).value
  let independent = cloned.snapshot.value
  assert cloned.close == RepositoryError.None
  assert restoreHistoricalStateEntries(independent, roots[0], limits.codec.trie).value.len == 0
  for ordinal in 0..<count:
    let entries = restoreHistoricalStateEntries(independent, roots[ordinal+1],
        limits.codec.trie).value
    assert entries.len == 1 and entries[0].value == payload(ordinal)
  let current = selectRepositoryRoots(held, [roots[roots.len-1]], ceiling).value
  assert current.retainedNodes == (if count == 0: 0 else: 1)
  assert current.reclaimableNodes == (if count == 0: 0 else: count-1)
  var minimal = cloneRepositorySelection(current, limits).value
  let reduced = minimal.snapshot.value
  assert minimal.close == RepositoryError.None
  if count > 1:
    let missing = restoreHistoricalStateEntries(reduced, roots[1], limits.codec.trie)
    assert missing.error == RepositoryError.MissingNode # Unselected cells cannot survive through the compact clone.
    assert selectRepositoryRoots(held, [roots[0]], ceiling).error == RepositoryError.RootMismatch
  assert selectRepositoryRoots(held, reversed, ElementLimit(1)).error ==
      RepositoryError.LimitExceeded
  var absent = default(array[32, byte])
  absent[0] = 255
  let invalid = selectRepositoryRoots(held, [roots[roots.len-1], StateRoot(absent)], ceiling)
  assert invalid.error == RepositoryError.MissingNode # Late failure retires scratch without changing a held plan.
  assert encodeRecordCollection(RecordCollection(records: exportRepositorySelection(selected,
    limits.codec.records).value), limits.codec).value == expected
  if count > 0:
    let digest = StateNodeHash(array[32, byte](roots[1]))
    var detached = independent.lookupNode(digest).value
    detached.payload[0] = detached.payload[0] xor 128
    assert independent.lookupNode(digest).value.payload == payload(0)

proc compareDigest(left, right: TrieRecord): int =
  ## The raw codec preserves caller order; independently canonicalize the oracle by complete physical digest.
  let a = array[32, byte](left.digest)
  let b = array[32, byte](right.digest)
  for index in 0..<32:
    if a[index] < b[index]: return -1 # First differing full-address byte fixes canonical physical order.
    if a[index] > b[index]: return 1
  0

proc shared(count: int) =
  ## Dense shared branch/leaf words must reset per root while the distinct union retains each complete address once.
  let fixture = snapshotFixture(count, 1)
  let limits = fixture.limits.repository
  var owner = cloneRepositorySelection(fixture.selection, limits).value
  var trie = restoreFullTrie(owner.snapshot.value, owner.snapshot.value.commitment.root,
    FullStateTrieLimits(trie: limits.codec.trie, writes: ElementLimit(1),
      writeValueBytes: ByteLimit(1))).value
  var versions = @[trie]
  var roots = @[trie.commitment.root]
  var raw = default(array[31, byte])
  raw[0] = byte((count-1) shr 8)
  raw[1] = byte((count-1) and 255)
  for turn in 0..<5:
    # Each single-key replacement shares most of the prior complete graph, including bitmap words.
    let next = trie.apply([TrieWrite(key: StateKey(raw), kind: TrieWriteKind.Put,
      value: @[byte(70+turn)])]).value
    let batch = exportTrieChanges(trie, next, limits.codec.records).value
    let view = owner.publish(owner.snapshot.value, batch).value
    assert array[32, byte](view.commitment.root) == array[32, byte](next.commitment.root)
    versions.add(next)
    roots.add(next.commitment.root)
    trie = next
  let view = owner.snapshot.value
  assert owner.close == RepositoryError.None
  var expected: seq[TrieRecord] = @[]
  var valueBytes = 0'u64
  for turn in [0, 2, 5]:
    # Independent full exports and complete-digest equality form an oracle without relying on selection traversal.
    let records = exportFullTrie(versions[turn], limits.codec.records).value.records
    for record in records:
      var found = false
      for prior in expected:
        if array[32, byte](prior.digest) == array[32, byte](record.digest): found = true
      if not found:
        expected.add(record)
        if record.kind == TrieRecordKind.Leaf: valueBytes += uint64(record.payload.len)
  let selected = selectRepositoryRoots(view, [roots[5], roots[0], roots[2], roots[5]],
    ElementLimit(4)).value
  assert selected.retainedNodes == expected.len and selected.retainedValueBytes == valueBytes
  expected.sort(compareDigest) # Canonical selection bytes require address order, independently of export order.
  let canonical = encodeRecordCollection(RecordCollection(records: expected), limits.codec).value
  assert encodeRepositorySelection(selected, limits.codec).value == canonical
  let reordered = selectRepositoryRoots(view, [roots[2], roots[0], roots[5]], ElementLimit(3)).value
  assert encodeRepositorySelection(reordered, limits.codec).value == canonical
  var copy = cloneRepositorySelection(selected, limits).value
  let held = copy.snapshot.value
  assert copy.close == RepositoryError.None
  for turn in [0, 2, 5]:
    let restored = restoreHistoricalStateEntries(held, roots[turn], limits.codec.trie).value
    assert restored.len == count
    assert restored[restored.len-1].value == versions[turn].lookup(StateKey(raw)).value.bytes

proc cycle() =
  ## Empty, singleton and several disjoint physical roots retire without keeping a source trie or table alive.
  exercise(0)
  exercise(1)
  exercise(3)

for count in [63, 64, 65, 129, 257]: shared(count) # Cross full and partial bitmap words with shared subtrees.
exercise(65)
exercise(257)
for warmup in 0..<10:
  cycle() # Warm the exact independent-owner and refusal paths before the release observation.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle()
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_selection_compaction", 1000, before, after)
echo "PASS storage selection compaction: historical unions, exact inventories, late refusal and ARC"
