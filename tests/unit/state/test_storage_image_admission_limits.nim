# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Physical union budgets and every retained complete-root policy remain independent during staged image admission.
# @@Verification={"arc": "storage_image_admission_limits_arc_release"}
import std/[assertions, syncio]
import ../../support/[admission_samples, storage_samples, arc_evidence]
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/node/records as node_records
import ../../../src/storage/record_codec
import ../../../src/storage/node/repository as node_repository
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/codec/bounded
proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset observed work without substituting cryptographic identities.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Distinguish metadata/physical preflight from complete graph policy rejection.
proc refused(source: AdmissionFixture, body: seq[byte], limits: RepositoryLimits,
    error: RepositoryError, reason: RecordError, hashes: int,
    rootLimit = ElementLimit(2), encoded = ByteLimit(500000)) =
  ## A typed refusal must occur at its intended phase and return every private owner immediately.
  reset(0)
  let before = getOccupiedMem()
  let failed = decodeRepositoryImage(body, source.image.generation, source.image.commitment,
    source.image.roots, limits, rootLimit, encoded)
  assert failed.error == error
  if error == RepositoryError.InvalidRecords:
    assert failed.recordError == reason # Codec extent/union limits retain their existing nested reason.
  assert int(calls()) == hashes and getOccupiedMem() == before
proc historicalFixture(): AdmissionFixture =
  ## The current root has one leaf, while a retained historical root needs two leaves and three nodes.
  let limits = storageLimits()
  let prior = storageTrie(7)
  let current = newFullStateTrie([StateEntry(key: storageKey(0), value: @[8'u8])],
    FullStateTrieLimits(trie: limits.codec.trie)).value
  var owner = newNodeRepository(limits)
  let first = owner.publish(owner.snapshot.value, exportFullTrie(prior,
      limits.codec.records).value).value
  let next = owner.publish(first, exportTrieChanges(prior, current,
      limits.codec.records).value).value
  let selected = selectRepositoryRoots(next, [first.commitment.root, next.commitment.root],
      ElementLimit(2)).value
  AdmissionFixture(image: exportRepositoryImage(selected, limits.codec.records, ElementLimit(
      2)).value,
    limits: limits)
proc cycle() =
  ## Exact union and per-root boundaries accept; tightening the corresponding independent dimension refuses.
  let source = admissionFixture()
  let body = admissionBody(source)
  var tight = source.limits
  tight.codec.trie.totalValueBytes = ByteLimit(2)
  tight.valueBytes = ByteLimit(3)
  reset(0)
  let restored = decodeRepositoryImage(body, source.image.generation, source.image.commitment,
    source.image.roots, tight, ElementLimit(2), ByteLimit(body.len)).value
  assert int(calls()) == 5
  let held = restored.snapshot.value
  let selected = selectRepositoryRoots(held, source.image.roots, ElementLimit(2)).value
  assert selected.retainedValueBytes == 3 and held.storedNodes == 5
  assert uint64(held.repositoryLimits.valueBytes) == 3
  assert uint64(held.repositoryLimits.codec.trie.totalValueBytes) == 2
  var narrow = tight
  narrow.valueBytes = ByteLimit(2)
  refused(source, body, narrow, RepositoryError.InvalidRecords, RecordError.LimitExceeded, 0)
  narrow = tight
  narrow.records = ElementLimit(4)
  refused(source, body, narrow, RepositoryError.InvalidRecords, RecordError.LimitExceeded, 0)
  narrow = tight
  narrow.codec.trie.perValue = ByteLimit(0)
  refused(source, body, narrow, RepositoryError.InvalidRecords, RecordError.LimitExceeded, 0)
  narrow = tight
  narrow.codec.trie.items = ElementLimit(1)
  refused(source, body, narrow, RepositoryError.LimitExceeded, RecordError.Uninitialized, 0)
  narrow = tight
  narrow.codec.trie.nodes = TrieNodeLimit(2)
  refused(source, body, narrow, RepositoryError.LimitExceeded, RecordError.Uninitialized, 0)
  narrow = tight
  narrow.codec.trie.totalValueBytes = ByteLimit(1)
  refused(source, body, narrow, RepositoryError.LimitExceeded, RecordError.Uninitialized, 5)
  refused(source, body, tight, RepositoryError.LimitExceeded, RecordError.Uninitialized, 0,
    ElementLimit(1), ByteLimit(0)) # Root metadata refusal precedes even an exhausted encoded budget.
  refused(source, body, tight, RepositoryError.InvalidRecords, RecordError.LimitExceeded, 0,
    ElementLimit(2), ByteLimit(body.len-1))
  var zero = source
  zero.image.generation = RepositoryGeneration(0)
  refused(zero, body, tight, RepositoryError.InvalidGraph, RecordError.Uninitialized, 0)
  let history = historicalFixture()
  let historyBody = admissionBody(history)
  assert history.image.commitment.entries == 1 and history.image.commitment.nodes == 1
  assert history.image.collection.records.len == 4
  var policy = history.limits
  policy.codec.trie.items = ElementLimit(1)
  refused(history, historyBody, policy, RepositoryError.LimitExceeded, RecordError.Uninitialized, 4)
  policy = history.limits
  policy.codec.trie.nodes = TrieNodeLimit(2)
  refused(history, historyBody, policy, RepositoryError.LimitExceeded, RecordError.Uninitialized, 4)
  policy = history.limits
  policy.codec.trie.totalValueBytes = ByteLimit(1)
  refused(history, historyBody, policy, RepositoryError.LimitExceeded, RecordError.Uninitialized, 4)
  for root in source.image.roots:
    let entries = restoreHistoricalStateEntries(held, root, tight.codec.trie).value
    assert entries.len == 2 # Every earlier independent owner survives all failed tighter-policy admissions.

for iteration in 0..<10:
  cycle() # Warm each distinct policy phase before exact local lifetime accounting.
let before = getOccupiedMem()
for iteration in 0..<1000:
  cycle() # Match the registered ARC workload while exercising all selected and historical root limits.
let after = getOccupiedMem()
assert before == after
recordArcRelease("storage_image_admission_limits", 1000, before, after)
echo "PASS storage image admission limits: union budgets, retained-root policies, phase ordering and ARC"
