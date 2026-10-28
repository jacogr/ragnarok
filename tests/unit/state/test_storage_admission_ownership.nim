# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fused transfers and legacy raw admission retain independent immutable values, metadata, handles and lookups.
# @@Verification={"arc": "storage_admission_ownership_arc_release"}
import std/assertions
import std/syncio
import ../../support/codec_admission_samples
import ../../support/testing_arc_evidence
import ../../../src/storage/node_records as storage_node_records
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/node_repository as storage_node_repository
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/bounded as codec_bounded
type
  LeafWitness = object ## Fixed expected identity/value never borrows the mutable source image.
    digest: StateNodeHash
    value: byte
  Counter = object ## An erased wire must refuse before any user consumer runs.
    calls: int
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Keep invalid-source preflight work separate from real setup and owner verification.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count genuine local integrity attempts without replacing cryptographic results.
proc witness(source: AdmissionFixture): LeafWitness =
  ## Select an actual one-byte fixture leaf while copying only its fixed expected bytes.
  for record in source.image.collection.records:
    if record.kind == TrieRecordKind.Leaf:
      assert record.payload.len == 1
      return LeafWitness(digest: record.digest, value: record.payload[0])
  assert false, "authored image must include a leaf"
proc count(counter: var Counter, record: var TrieRecord): bool =
  ## No payload is retained and malformed retired input must never reach this callback.
  inc counter.calls
  true
proc cycle() =
  ## Keep raw and fused owners plus an independent mutable handle alive through every source mutation.
  var source = admissionFixture()
  let policy = source.limits
  let generation = source.image.generation
  let commitment = source.image.commitment
  let roots = [source.image.roots[0], source.image.roots[1]]
  let leaf = witness(source)
  var wire = admissionBody(source)
  let inspected = inspectOrderedRecordCollection(wire, policy.codec)
  assert inspected.value.records == 5
  var raw = restoreRepositoryImage(source.image, policy, ElementLimit(2), ByteLimit(500000)).value
  var fused = decodeAdmission(source, wire).value
  let rawView = raw.snapshot.value
  let fusedView = fused.snapshot.value
  var alias = fused
  let noChange = TrieExport(base: commitment.root, root: commitment.root,
    entries: uint64(commitment.entries), nodes: commitment.nodes, records: @[])
  let noop = encodeTrieExport(noChange, policy.codec).value
  let advanced = alias.publishEncoded(alias.snapshot.value, noop).value
  assert uint64(advanced.generation) == uint64(generation)+1
  assert uint64(fused.snapshot.value.generation) == uint64(generation)
  var returned = fusedView.lookupNode(leaf.digest).value
  returned.payload[0] = returned.payload[0] xor 1
  returned.digest = default(StateNodeHash)
  assert fusedView.lookupNode(leaf.digest).value.payload == @[leaf.value]
  assert rawView.lookupNode(leaf.digest).value.payload == @[leaf.value]
  for index in 0..<wire.len:
    wire[index] = 0 # Successful fused admission retains no mutable wire storage.
  for index in 0..<source.image.collection.records.len:
    for offset in 0..<source.image.collection.records[index].payload.len:
      source.image.collection.records[index].payload[
          offset] = 0 # Raw admission never adopts caller payload owners.
    source.image.collection.records[index].digest = default(StateNodeHash)
    source.image.collection.records[index].key = default(StateKey)
    source.image.collection.records[index].left = default(StateNodeHash)
    source.image.collection.records[index].right = default(StateNodeHash)
  for index in 0..<source.image.roots.len:
    source.image.roots[index] = default(StateRoot) # Root inventories are borrowed only during synchronous admission.
  source.image.generation = RepositoryGeneration(0)
  source.image.commitment = default(StateTrieCommitment)
  source.limits.records = ElementLimit(0)
  source.limits.codec.trie.totalValueBytes = ByteLimit(0)
  assert inspected.value.records == 5 # A scalar inspection summary survives but cannot authorize another decode.
  var none = Counter(calls: 0)
  reset(0)
  assert visitOrderedRecordCollection(wire, policy.codec, none, count).error ==
      RecordError.InvalidFormat
  assert none.calls == 0 and int(calls()) == 0
  let invalid = decodeRepositoryImage(wire, generation, commitment, roots, policy,
    ElementLimit(2), ByteLimit(500000))
  assert invalid.error == RepositoryError.InvalidRecords
  assert invalid.recordError == RecordError.InvalidFormat and int(calls()) == 0
  assert restoreRepositoryImage(source.image, policy, ElementLimit(2), ByteLimit(500000)).error !=
      RepositoryError.None
  assert raw.close == RepositoryError.None and fused.close == RepositoryError.None
  assert alias.close == RepositoryError.None
  for view in [rawView, fusedView, advanced]:
    assert view.lookupNode(leaf.digest).value.payload == @[leaf.value]
    assert view.storedNodes == 5
    assert uint64(view.repositoryLimits.records) == uint64(policy.records)
    assert uint64(view.repositoryLimits.codec.trie.totalValueBytes) == uint64(
        policy.codec.trie.totalValueBytes)
    for root in roots:
      let entries = restoreHistoricalStateEntries(view, root, policy.codec.trie).value
      assert entries.len == 2 # Independent complete views survive retired buffers, changed metadata and all closes.
    assert restoreStateEntries(view, commitment.root, policy.codec.trie).value[0].value == @[10'u8]

for iteration in 0..<10:
  cycle() # Warm every copied/consumed owner and invalid-source path before local accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Match the ARC evidence contract while retaining no caller or staged owner across cycles.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_admission_ownership", 1000, before, after)
echo "PASS storage admission ownership: detached sources, independent handles, retained views and ARC"
