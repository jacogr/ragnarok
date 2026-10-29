# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Late image failures must release private prefix cells while preserving every independent admitted owner.
# @@Verification={"arc": "storage_image_staging_failures_arc_release"}
import std/[algorithm, assertions, syncio]
import ../../support/[admission_samples, storage_samples, arc_evidence]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/storage/node/repository as node_repository
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Count genuine local hashes across staged-prefix and complete graph refusal boundaries.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Keep physical integrity evidence independent of returned graph metadata.
proc rejected(source: AdmissionFixture, wire: seq[byte], expected: RepositoryError, hashes: int) =
  ## Each failure exposes only its reason and retires all privately allocated cells/table/scratch immediately.
  reset(0)
  let before = getOccupiedMem()
  let failed = decodeAdmission(source, wire)
  assert failed.error == expected
  if expected == RepositoryError.InvalidRecords:
    assert failed.recordError == RecordError.HashMismatch # This case reaches the final local record hash.
  assert int(calls()) == hashes and getOccupiedMem() == before
proc cycle() =
  ## Keep valid independent views alive across late hash, orphan, missing-node and masked-edge failures.
  let source = admissionFixture()
  let body = admissionBody(source)
  assert source.image.collection.records.len == 5
  var owner = decodeAdmission(source, body).value
  let held = owner.snapshot.value
  var late = body
  late[late.len-1] = late[late.len-1] xor 1
  rejected(source, late, RepositoryError.InvalidRecords, 5)
  let extra = exportFullTrie(storageTrie(99), source.limits.codec.records).value.records[0]
  var orphan = source.image.collection
  for record in orphan.records:
    assert array[32, byte](record.digest) != array[32, byte](
        extra.digest) # The extra valid leaf is genuinely outside both retained roots.
  orphan.records.add(extra)
  orphan.records.sort(compareAdmissionRecords)
  let orphanWire = encodeRecordCollection(orphan, source.limits.codec).value
  rejected(source, orphanWire, RepositoryError.InvalidGraph, 6)
  var missing = RecordCollection(records: @[])
  var removed = false
  for record in source.image.collection.records:
    if not removed and record.kind == TrieRecordKind.Leaf:
      removed = true # Every fixture leaf is required by at least one explicitly retained complete root.
    else:
      missing.records.add(record)
  assert removed and missing.records.len == 4
  let missingWire = encodeRecordCollection(missing, source.limits.codec).value
  rejected(source, missingWire, RepositoryError.MissingNode, 4)
  var masked = source.image.collection
  var changed = false
  for index in 0..<masked.records.len:
    if not changed and masked.records[index].kind == TrieRecordKind.Branch:
      var left = array[32, byte](masked.records[index].left)
      left[0] = left[0] xor 128
      masked.records[index].left = StateNodeHash(left)
      assert held.lookupNode(StateNodeHash(left)).error == RepositoryError.MissingNode
      changed = true # Local JAM hashing masks this bit, but complete physical edge admission never does.
  assert changed
  let maskedWire = encodeRecordCollection(masked, source.limits.codec).value
  rejected(source, maskedWire, RepositoryError.MissingNode, 5)
  assert held.storedNodes == 5 and uint64(held.generation) == uint64(source.image.generation)
  assert restoreStateEntries(held, source.image.commitment.root, source.limits.codec.trie).value[
      0].value == @[10'u8]
  assert owner.close == RepositoryError.None
  for root in source.image.roots:
    let entries = restoreHistoricalStateEntries(held, root, source.limits.codec.trie).value
    assert entries.len == 2 # Retained views preserve both complete mappings after close and every failure.

for iteration in 0..<10:
  cycle() # Warm real primitives and every private error cleanup path before accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Match the registered ARC evidence contract without retaining any staged prefix owner.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_image_staging_failures", 1000, before, after)
echo "PASS storage image staging failures: late hashes, orphan/missing edges, immutable views and ARC"
