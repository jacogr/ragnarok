# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Existing test-only primitive refusal after successful prefixes cannot publish or retain private admission owners.
# @@Verification={"arc": "storage_admission_backend_failures_arc_release"}
import std/[assertions, syncio]
import ../../support/[admission_samples, storage_samples, arc_evidence]
import ../../../src/storage/[full_state_trie, node_records, record_codec, node_repository]
import ../../../src/codec/[state_layout, state_trie, bounded]
type Prefix = object ## Explicit public consumer owns only the provisional records it chose to retain.
  records: seq[TrieRecord]
  starts, calls, stopAfter: int
  declared: uint64
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Restore genuine primitives after every bounded injected failure.
proc refuseAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## The existing sequential adapter refuses the next call after a finite genuine successful prefix.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Count attempts including the one actual refused primitive operation.
proc prepare(state: var Prefix, info: RecordCollectionInfo) =
  ## Metadata preparation precedes all crypto, even when the first primitive will refuse.
  assert state.starts == 0 and int(calls()) == 0
  state.starts = 1
  state.declared = info.records
proc consume(state: var Prefix, record: var TrieRecord): bool =
  ## Distinguish an explicit public cancellation from a backend refusal before this callback.
  inc state.calls
  if state.stopAfter >= 0 and state.records.len >= state.stopAfter: return false
  state.records.add(move(record))
  true
proc publicFault(body: seq[byte], policy: RecordLimits, prefix: int, cancelled: bool) =
  ## A failed result exposes no summary payload; caller-owned provisional prefixes release independently.
  var state = Prefix(records: @[], starts: 0, calls: 0,
    stopAfter: (if cancelled: prefix else: -1), declared: 0)
  if cancelled: reset(0) # Successful hashing reaches the requested consumer refusal.
  else: refuseAfter(cint(prefix))
  let before = getOccupiedMem()
  let failed = visitOrderedRecordCollection(body, policy, state, prepare, consume)
  if cancelled:
    assert failed.error == RecordError.ConsumerRefused and state.calls == prefix+1
  else:
    assert failed.error == RecordError.BackendFailure and state.calls == prefix
  assert state.starts == 1 and state.declared == 5
  assert state.records.len == prefix and int(calls()) == prefix+1
  state.records = @[] # The explicitly retained public prefix owns no source or private repository references.
  assert getOccupiedMem() == before
  reset(0)
proc imageFault(source: AdmissionFixture, body: seq[byte], prefix: int) =
  ## Every already-staged immutable cell retires when the next locally verified record cannot be hashed.
  refuseAfter(cint(prefix))
  let before = getOccupiedMem()
  let failed = decodeAdmission(source, body)
  assert failed.error == RepositoryError.InvalidRecords
  assert failed.recordError == RecordError.BackendFailure and int(calls()) == prefix+1
  assert getOccupiedMem() == before
  reset(0)
proc publicationFault(body: seq[byte], policy: RepositoryLimits, prefix: int) =
  ## Complete codec refusal outranks staged quota flags and never replaces the original empty head.
  var owner = newNodeRepository(policy)
  let head = owner.snapshot.value
  refuseAfter(cint(prefix))
  let before = getOccupiedMem()
  let failed = owner.publishEncoded(head, body)
  assert failed.error == RepositoryError.InvalidRecords
  assert failed.recordError == RecordError.BackendFailure and int(calls()) == prefix+1
  assert getOccupiedMem() == before
  assert owner.snapshot.value.storedNodes == 0
  assert uint64(owner.snapshot.value.generation) == 0
  reset(0)
  assert owner.close == RepositoryError.None
proc cycle() =
  ## Exercise immediate and late backend failure, explicit cancellation, earlier quota and both long-leaf hash phases.
  reset(0)
  let source = admissionFixture()
  let body = admissionBody(source)
  var control = decodeAdmission(source, body).value
  let held = control.snapshot.value
  for prefix in 0..<5:
    publicFault(body, source.limits.codec, prefix, false)
    publicFault(body, source.limits.codec, prefix, true)
    imageFault(source, body, prefix)
  let full = exportFullTrie(storageTrie(7), source.limits.codec.records).value
  let batch = encodeTrieExport(full, source.limits.codec).value
  for prefix in 0..<3:
    publicationFault(batch, source.limits, prefix)
  var noRoom = source.limits
  noRoom.records = ElementLimit(0)
  publicationFault(batch, noRoom, 1) # A first valid record sets quota refusal; a later backend failure still wins.
  let large = newFullStateTrie([StateEntry(key: storageKey(0), value: newSeq[byte](64))],
    FullStateTrieLimits(trie: source.limits.codec.trie)).value
  let largeBatch = encodeTrieExport(exportFullTrie(large, source.limits.codec.records).value,
    source.limits.codec).value
  publicationFault(largeBatch, source.limits, 0) # Raw-value hashing fails before encoded-node hashing.
  publicationFault(largeBatch, source.limits, 1) # A genuine payload hash succeeds before the node hash refuses.
  var malformed = body
  malformed[0] = 0
  var none = Prefix(records: @[], starts: 0, calls: 0, stopAfter: -1, declared: 0)
  refuseAfter(0)
  assert visitOrderedRecordCollection(malformed, source.limits.codec, none, prepare,
      consume).error == RecordError.InvalidFormat
  assert none.starts == 0 and none.calls == 0 and int(calls()) == 0
  reset(0)
  assert control.close == RepositoryError.None
  assert restoreStateEntries(held, source.image.commitment.root, source.limits.codec.trie).value[
      0].value == @[10'u8]
  assert held.storedNodes == 5 # Every independent successful owner survives all injected refusals.

for iteration in 0..<10:
  cycle() # Warm all genuine success prefixes and typed refusal cleanup paths before accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Preserve the registered ARC workload without leaving primitive fault flags enabled.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_admission_backend_failures", 1000, before, after)
echo "PASS storage admission backend failures: successful prefixes, atomic refusal, cancellation and ARC"
