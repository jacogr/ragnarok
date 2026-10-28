# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Freeze raw/encoded policy ordering and private atomic refusal across quotas, real edge conflicts and late hashes.
# @@Verification={"arc": "storage_admission_precedence_arc_release"}
import std/assertions
import std/syncio
import ../../support/storage_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/full_state_trie as storage_full_state_trie
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Observe real hashing without substituting digests or weakening physical integrity.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Keep ordering evidence distinct from repository and returned-view metadata.
proc unchanged(owner: NodeRepository, expected: RepositoryView) =
  ## Refused staging cannot publish even a correct-looking root under another generation or inventory.
  let current = owner.snapshot.value
  assert uint64(current.generation) == uint64(expected.generation)
  assert current.storedNodes == expected.storedNodes
  assert array[32, byte](current.commitment.root) == array[32, byte](expected.commitment.root)
proc quotaCycle() =
  ## Genuine masked-edge hash equivalence makes quota-before-conflict reachable without mocked primitives.
  var limits = storageLimits()
  limits.records = ElementLimit(5)
  let a = storageTrie(7)
  let b = storageTrie(8)
  let full = exportFullTrie(a, limits.codec.records).value
  let delta = exportTrieChanges(a, b, limits.codec.records).value
  var owner = newNodeRepository(limits)
  let first = owner.publish(owner.snapshot.value, full).value
  let head = owner.publish(first, delta).value
  assert head.storedNodes == 5
  var conflict = delta.records[delta.records.len-1]
  var left = array[32, byte](conflict.left)
  left[0] = left[0] xor 128
  conflict.left = StateNodeHash(left)
  let extra = exportFullTrie(storageTrie(99), limits.codec.records).value.records[0]
  let other = exportFullTrie(storageTrie(100), limits.codec.records).value.records[0]
  let conflicting = TrieExport(base: head.commitment.root, root: head.commitment.root,
    entries: 2, nodes: 3, records: @[conflict])
  assert validateTrieExport(conflicting, limits.codec) == RecordError.None
  let conflictingWire = encodeTrieExport(conflicting, limits.codec).value
  reset(0)
  assert owner.publishEncoded(head, conflictingWire).error == RepositoryError.RecordConflict
  assert int(calls()) == 1
  unchanged(owner, head)
  let quota = TrieExport(base: head.commitment.root, root: head.commitment.root,
    entries: 2, nodes: 3, records: @[conflict, extra])
  let quotaWire = encodeTrieExport(quota, limits.codec).value
  reset(0)
  assert owner.publish(head, quota).error == RepositoryError.LimitExceeded
  assert int(calls()) == 0 # Raw publication retains its legacy physical quota preflight before integrity.
  reset(0)
  assert owner.publishEncoded(head, quotaWire).error == RepositoryError.LimitExceeded
  assert int(calls()) == 2 # Encoded integrity completes before quota overrides an earlier detected conflict.
  unchanged(owner, head)
  var corruptConflict = quotaWire
  corruptConflict[corruptConflict.len-1] = corruptConflict[corruptConflict.len-1] xor 1
  reset(0)
  let lateConflict = owner.publishEncoded(head, corruptConflict)
  assert lateConflict.error == RepositoryError.InvalidRecords
  assert lateConflict.recordError == RecordError.HashMismatch and int(calls()) == 2
  unchanged(owner, head)
  let excess = TrieExport(base: head.commitment.root, root: head.commitment.root,
    entries: 2, nodes: 3, records: @[extra, other])
  var corruptQuota = encodeTrieExport(excess, limits.codec).value
  corruptQuota[corruptQuota.len-1] = corruptQuota[corruptQuota.len-1] xor 1
  reset(0)
  let lateQuota = owner.publishEncoded(head, corruptQuota)
  assert lateQuota.error == RepositoryError.InvalidRecords
  assert lateQuota.recordError == RecordError.HashMismatch and int(calls()) == 2
  unchanged(owner, head)
  var wrongBase = quota
  wrongBase.base = default(StateRoot)
  var wrongWire = encodeTrieExport(wrongBase, limits.codec).value
  reset(0)
  assert owner.publishEncoded(head, wrongWire).error == RepositoryError.BaseMismatch
  assert int(calls()) == 2
  reset(0)
  assert owner.publish(head, wrongBase).error == RepositoryError.BaseMismatch
  assert int(calls()) == 0
  wrongWire[wrongWire.len-1] = wrongWire[wrongWire.len-1] xor 1
  reset(0)
  let lateBase = owner.publishEncoded(head, wrongWire)
  assert lateBase.error == RepositoryError.InvalidRecords
  assert lateBase.recordError == RecordError.HashMismatch and int(calls()) == 2
  unchanged(owner, head)
  reset(0)
  assert owner.publishEncoded(first, @[0'u8]).error == RepositoryError.StaleView
  assert int(calls()) == 0
  var unopened = default(NodeRepository)
  assert unopened.publishEncoded(default(RepositoryView), @[0'u8]).error ==
      RepositoryError.Uninitialized
  assert int(calls()) == 0
  assert restoreStateEntries(first, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  assert restoreStateEntries(head, b.commitment.root, limits.codec.trie).value[0].value == @[8'u8]
proc generationCycle() =
  ## Generation exhaustion follows encoded integrity and precedes a valid extra-record quota refusal.
  var limits = storageLimits()
  limits.records = ElementLimit(3)
  let trie = storageTrie(7)
  var source = newNodeRepository(limits)
  let current = source.publish(source.snapshot.value, exportFullTrie(trie,
      limits.codec.records).value).value
  let selection = selectRepositoryRoots(current, [current.commitment.root], ElementLimit(1)).value
  var image = exportRepositoryImage(selection, limits.codec.records, ElementLimit(1)).value
  image.generation = RepositoryGeneration(high(uint64))
  var owner = restoreRepositoryImage(image, limits, ElementLimit(1), ByteLimit(500000)).value
  let head = owner.snapshot.value
  let extra = exportFullTrie(storageTrie(99), limits.codec.records).value.records[0]
  let change = TrieExport(base: head.commitment.root, root: head.commitment.root,
    entries: 2, nodes: 3, records: @[extra])
  var wire = encodeTrieExport(change, limits.codec).value
  reset(0)
  assert owner.publishEncoded(head, wire).error == RepositoryError.GenerationExhausted
  assert int(calls()) == 1
  reset(0)
  assert owner.publish(head, change).error == RepositoryError.GenerationExhausted
  assert int(calls()) == 0
  wire[wire.len-1] = wire[wire.len-1] xor 1
  reset(0)
  let late = owner.publishEncoded(head, wire)
  assert late.error == RepositoryError.InvalidRecords
  assert late.recordError == RecordError.HashMismatch and int(calls()) == 1
  unchanged(owner, head)
proc cycle() =
  ## Every staged success prefix, immutable prior view and refusal owner must retire together.
  quotaCycle()
  generationCycle()

for iteration in 0..<10:
  cycle() # Warm all genuine primitive and typed refusal paths before local lifetime accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Match the registered ARC contract while checking every private refusal owner.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_admission_precedence", 1000, before, after)
echo "PASS storage admission precedence: codec, identity, quota, conflict, late hashes and atomic ARC"
