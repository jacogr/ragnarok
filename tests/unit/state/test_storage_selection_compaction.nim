# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact selected inventories preserve disjoint historical roots, empty maps, permutations and independent ownership.
# @@Verification={"arc": "storage_selection_compaction_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]

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

proc cycle() =
  ## Empty, singleton and several disjoint physical roots retire without keeping a source trie or table alive.
  exercise(0)
  exercise(1)
  exercise(3)

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
