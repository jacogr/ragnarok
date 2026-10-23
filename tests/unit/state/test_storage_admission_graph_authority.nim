# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Unordered record delivery preserves serialized order but grants no root, dependency, reachability or no-op authority.
# @@Verification={"arc": "storage_admission_graph_authority_arc_release"}
import std/[assertions, syncio]
import ../../support/[storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
type LocalRecords = object ## A locally valid transport summary is independent of complete graph admission.
  digests: seq[StateNodeHash]
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Observe genuine local record hashes separately from repository validation.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Keep full-integrity attempt counts explicit for success and graph refusals.
proc consume(state: var LocalRecords, record: var TrieRecord): bool =
  ## Retain only copied fixed identities to verify the serialized transport order.
  state.digests.add(record.digest)
  true
proc locallyValid(wire: seq[byte], batch: TrieExport, policy: RecordLimits): RecordBatchInfo =
  ## Every locally valid ordered sequence of physical records can still contain false target claims.
  var state = LocalRecords(digests: @[])
  reset(0)
  let delivered = visitTrieExport(wire, policy, state, consume)
  assert delivered.error == RecordError.None and int(calls()) == batch.records.len
  assert state.digests.len == batch.records.len
  for index in 0..<state.digests.len:
    assert array[32, byte](state.digests[index]) == array[32, byte](batch.records[index].digest)
  delivered.value
proc unchanged(owner: NodeRepository, expected: RepositoryView) =
  ## Failed graph admission cannot install a different table, root or generation.
  let head = owner.snapshot.value
  assert head.storedNodes == expected.storedNodes and uint64(head.generation) == uint64(
      expected.generation)
  assert array[32, byte](head.commitment.root) == array[32, byte](expected.commitment.root)
proc reject(owner: var NodeRepository, wire: seq[byte], expected: RepositoryError, hashes: int) =
  ## Verify complete integrity before graph refusal and immediate release of all private candidate owners.
  let prior = owner.snapshot.value
  reset(0)
  let before = getOccupiedMem()
  assert owner.publishEncoded(prior, wire).error == expected
  assert int(calls()) == hashes and getOccupiedMem() == before
  unchanged(owner, prior)
proc cycle() =
  ## All full/delta permutations agree with raw admission, while valid local bytes cannot forge graph truth.
  let limits = storageLimits()
  let a = storageTrie(7)
  let b = storageTrie(8)
  let full = exportFullTrie(a, limits.codec.records).value
  let delta = exportTrieChanges(a, b, limits.codec.records).value
  assert full.records.len == 3 and delta.records.len == 2
  for order in [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]:
    var permuted = full
    permuted.records = @[full.records[order[0]], full.records[order[1]], full.records[order[2]]]
    let wire = encodeTrieExport(permuted, limits.codec).value
    let info = locallyValid(wire, permuted, limits.codec)
    assert info.records == 3 and info.entries == 2 and info.nodes == 3
    let detached = decodeTrieExport(wire, limits.codec).value
    for index in 0..<detached.records.len:
      assert array[32, byte](detached.records[index].digest) == array[32, byte](permuted.records[index].digest)
    var raw = newNodeRepository(limits)
    var fused = newNodeRepository(limits)
    let rawView = raw.publish(raw.snapshot.value, permuted).value
    reset(0)
    let fusedView = fused.publishEncoded(fused.snapshot.value, wire).value
    assert int(calls()) == 3 and fusedView.storedNodes == rawView.storedNodes
    for change in [[0, 1], [1, 0]]:
      var next = delta
      next.records = @[delta.records[change[0]], delta.records[change[1]]]
      let encoded = encodeTrieExport(next, limits.codec).value
      discard locallyValid(encoded, next, limits.codec)
      var rawAlias = raw
      var fusedAlias = fused
      let expected = rawAlias.publish(rawAlias.snapshot.value, next).value
      reset(0)
      let admitted = fusedAlias.publishEncoded(fusedAlias.snapshot.value, encoded).value
      assert int(calls()) == 2 and admitted.storedNodes == expected.storedNodes
      assert uint64(admitted.generation) == 2
      assert restoreStateEntries(admitted, b.commitment.root, limits.codec.trie).value[0].value ==
          @[8'u8]
      assert rawAlias.close == RepositoryError.None and fusedAlias.close == RepositoryError.None
    unchanged(raw, rawView)
    unchanged(fused, fusedView)
    assert raw.close == RepositoryError.None and fused.close == RepositoryError.None
    assert restoreStateEntries(fusedView, a.commitment.root, limits.codec.trie).value[0].value == @[7'u8]
  var empty = newNodeRepository(limits)
  var inflated = full
  inflated.nodes = 400 # This count fits structural policy and the key-depth bound, but is not the actual graph count.
  let inflatedWire = encodeTrieExport(inflated, limits.codec).value
  assert locallyValid(inflatedWire, inflated, limits.codec).nodes == 400
  reject(empty, inflatedWire, RepositoryError.InvalidGraph, 3)
  let missing = TrieExport(base: full.base, root: full.root, entries: full.entries,
    nodes: full.nodes, records: @[full.records[0]])
  let missingWire = encodeTrieExport(missing, limits.codec).value
  assert locallyValid(missingWire, missing, limits.codec).records == 1
  reject(empty, missingWire, RepositoryError.MissingNode, 1)
  var orphan = full
  orphan.records.add(exportFullTrie(storageTrie(99), limits.codec.records).value.records[0])
  let orphanWire = encodeTrieExport(orphan, limits.codec).value
  assert locallyValid(orphanWire, orphan, limits.codec).records == 4
  reject(empty, orphanWire, RepositoryError.InvalidGraph, 4)
  let first = empty.publishEncoded(empty.snapshot.value, encodeTrieExport(full,
      limits.codec).value).value
  let forgedNoop = TrieExport(base: first.commitment.root, root: first.commitment.root,
    entries: 3, nodes: 3, records: @[])
  let noChange = encodeTrieExport(forgedNoop, limits.codec).value
  assert locallyValid(noChange, forgedNoop, limits.codec).entries == 3
  reject(empty, noChange, RepositoryError.InvalidGraph, 0)
  assert empty.close == RepositoryError.None

for iteration in 0..<10:
  cycle() # Warm every ordering and complete-graph refusal before local lifetime accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Preserve the registered ARC contract while no raw or staged candidate survives a cycle.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_admission_graph_authority", 1000, before, after)
echo "PASS storage admission graph authority: full/delta order parity, false claims, missing/orphan nodes and ARC"
