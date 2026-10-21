# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fused image decoding preserves untrusted integrity/topology refusal and independent owned lifetimes.
# @@Verification={"arc": "storage_image_decode_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset counters while keeping genuine primitive implementations enabled.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe the exact number of real record hash attempts.
proc decode(image: RepositoryImage, limits: RepositoryLimits): RepositoryResult[NodeRepository] =
  ## Serialize only locally valid records; this does not grant graph authority to the receiver.
  let body = encodeRecordCollection(image.collection, limits.codec).value
  decodeRepositoryImage(body, image.generation, image.commitment, image.roots,
    limits, ElementLimit(3), ByteLimit(1000000))
proc cycle() =
  ## Compare old and fused paths, then exercise corruption, graph, budget, ownership and publication boundaries.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let c = storageTrie(10)
  var source = newNodeRepository(limits)
  let first = source.publish(source.snapshot.value, exportFullTrie(a,
      limits.codec.records).value).value
  let second = source.publish(first, exportTrieChanges(a, b, limits.codec.records).value).value
  let third = source.publish(second, exportTrieChanges(b, c, limits.codec.records).value).value
  let selected = selectRepositoryRoots(third, [a.commitment.root, c.commitment.root], ElementLimit(2)).value
  let image = exportRepositoryImage(selected, limits.codec.records, ElementLimit(2)).value
  var body = encodeRecordCollection(image.collection, limits.codec).value
  reset(0)
  assert decodeRepositoryImage(body, RepositoryGeneration(0), image.commitment, image.roots,
    limits, ElementLimit(2), ByteLimit(1000000)).error == RepositoryError.InvalidGraph
  assert int(calls()) == 0 # Invalid metadata must not hash or allocate the physical collection first.
  var excessive = image.commitment
  excessive.entries = 17
  reset(0)
  assert decodeRepositoryImage(body, image.generation, excessive, image.roots,
    limits, ElementLimit(2), ByteLimit(1000000)).error == RepositoryError.LimitExceeded
  assert int(calls()) == 0
  var rootsWithoutCurrent = @[a.commitment.root]
  reset(0)
  assert decodeRepositoryImage(body, image.generation, image.commitment, rootsWithoutCurrent,
    limits, ElementLimit(2), ByteLimit(1000000)).error == RepositoryError.RootMismatch
  assert int(calls()) == 0
  reset(0)
  let detached = decodeRecordCollection(body, limits.codec).value
  let raw = RepositoryImage(generation: image.generation, commitment: image.commitment,
    roots: image.roots, collection: detached)
  var control = restoreRepositoryImage(raw, limits, ElementLimit(2), ByteLimit(1000000)).value
  assert int(calls()) == 10
  reset(0)
  var restored = decodeRepositoryImage(body, image.generation, image.commitment, image.roots,
    limits, ElementLimit(2), ByteLimit(1000000)).value
  assert int(calls()) == 5
  let view = restored.snapshot.value
  assert uint64(view.generation) == 3 and view.storedNodes == 5
  assert restoreStateEntries(view, c.commitment.root, limits.codec.trie).value[0].value == @[10'u8]
  assert restoreHistoricalStateEntries(view, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  assert restoreHistoricalStateEntries(view, b.commitment.root, limits.codec.trie).error ==
      RepositoryError.MissingNode
  for size in 0..<body.len:
    let truncated = decodeRepositoryImage(body.toOpenArray(0, size-1), image.generation,
      image.commitment, image.roots, limits, ElementLimit(2), ByteLimit(1000000))
    assert truncated.error != RepositoryError.None # No partial transport or graph can escape.
  var corrupt = body
  corrupt["RAGNAROK-RECORDS-V1\n".len+8+1] = corrupt["RAGNAROK-RECORDS-V1\n".len+8+1] xor 1
  let refused = decodeRepositoryImage(corrupt, image.generation, image.commitment,
    image.roots, limits, ElementLimit(2), ByteLimit(1000000))
  assert refused.error == RepositoryError.InvalidRecords
  assert refused.recordError == RecordError.HashMismatch
  let shortRoots = decodeRepositoryImage(body, image.generation, image.commitment,
    image.roots, limits, ElementLimit(1), ByteLimit(1000000))
  assert shortRoots.error == RepositoryError.LimitExceeded
  let shortBytes = decodeRepositoryImage(body, image.generation, image.commitment,
    image.roots, limits, ElementLimit(2), ByteLimit(body.len-1))
  assert shortBytes.error == RepositoryError.InvalidRecords
  assert shortBytes.recordError == RecordError.LimitExceeded
  var narrow = limits
  narrow.codec.trie.items = ElementLimit(1)
  assert decode(image, narrow).error == RepositoryError.LimitExceeded
  var bad = image
  bad.generation = RepositoryGeneration(0)
  assert decode(bad, limits).error == RepositoryError.InvalidGraph
  bad = image
  bad.commitment.entries = 1
  assert decode(bad, limits).error == RepositoryError.InvalidGraph
  bad = image
  let duplicate = bad.roots[1]
  bad.roots[0] = duplicate
  assert decode(bad, limits).error == RepositoryError.InvalidGraph
  bad = image
  bad.roots = @[b.commitment.root]
  assert decode(bad, limits).error == RepositoryError.RootMismatch
  bad = image
  let swapped = bad.collection.records[0]
  let next = bad.collection.records[1]
  bad.collection.records[0] = next
  bad.collection.records[1] = swapped
  assert decode(bad, limits).error == RepositoryError.InvalidGraph
  let complete = selectRepositoryRoots(third, [a.commitment.root, b.commitment.root,
    c.commitment.root], ElementLimit(3)).value
  var orphan = exportRepositoryImage(complete, limits.codec.records, ElementLimit(3)).value
  orphan.roots = image.roots
  assert decode(orphan, limits).error == RepositoryError.InvalidGraph
  for index in 0..<body.len:
    body[index] = 0 # Accepted graphs must own their bytes independently of serialized caller storage.
  assert restoreStateEntries(view, c.commitment.root, limits.codec.trie).value[0].value == @[10'u8]
  let changed = storageTrie(12)
  assert uint64(restored.publish(view, exportTrieChanges(c, changed,
    limits.codec.records).value).value.generation) == 4
  assert source.close == RepositoryError.None
  assert control.close == RepositoryError.None
  assert restored.close == RepositoryError.None
  assert restoreHistoricalStateEntries(view, a.commitment.root, limits.codec.trie).value.len == 2
proc emptyCurrent() =
  ## Empty current roots may retain a complete nonempty historical graph.
  let limits = storageLimits()
  let trie = storageTrie()
  var source = newNodeRepository(limits)
  let first = source.publish(source.snapshot.value, exportFullTrie(trie,
      limits.codec.records).value).value
  let empty = source.publish(first, TrieExport(base: first.commitment.root)).value
  let selected = selectRepositoryRoots(empty, [default(StateRoot), first.commitment.root],
      ElementLimit(2)).value
  let image = exportRepositoryImage(selected, limits.codec.records, ElementLimit(2)).value
  var restored = decode(image, limits).value
  assert restored.snapshot.value.commitment.entries == 0
  assert restoreHistoricalStateEntries(restored.snapshot.value, first.commitment.root,
    limits.codec.trie).value.len == 2
  assert restored.close == RepositoryError.None and source.close == RepositoryError.None
for iteration in 0..<10:
  cycle() # Warm each admitted and refused owner lifetime before ARC accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Every admitted/refused owner and transport scratch must retire independently.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_image_decode", 1000, before, after)
emptyCurrent()
echo "PASS storage image decode: single record hashing, strict graph admission, ownership and ARC"
