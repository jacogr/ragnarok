# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Scoped complete snapshots, path/set/batch witnesses and decoded envelopes release every ARC owner.
# @@Verification={"arc": "state_proof_lifecycle_arc_release"}
import std/[assertions, syncio]
import ../../../src/state/[store, trie_proof, snapshot_proof]
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../support/arc_evidence
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained primitive observer between success/refusal recovery stages.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse after a real completed prefix rather than inventing a typed failed result.
proc cycle() =
  ## Every complete and partial immutable owner retires before this scoped workload returns.
  fail(0)
  let maps = StateTrieLimits(items: ElementLimit(2), perValue: ByteLimit(33),
    totalValueBytes: ByteLimit(66), nodes: TrieNodeLimit(1000))
  let limits = StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(33))
  let aggregate = StateProofBatchLimits(items: ElementLimit(2), nodes: ElementLimit(498),
      valueBytes: ByteLimit(66))
  let key = chapterKey(StateChapter(0))
  let other = chapterKey(StateChapter(128))
  let entries = @[StateEntry(key: key, value: newSeq[byte](33)), StateEntry(key: other, value: @[byte 7])]
  let policy = StateStoreLimits(trie: maps, writes: ElementLimit(2), writeValueBytes: ByteLimit(66))
  let snapshot = newStateStore(entries, policy).value.snapshot.value
  let proof = generateStateProof(snapshot, key, maps, limits).value
  let wire = encodeStateProof(proof, limits, ByteLimit(20000)).value
  let decoded = decodeStateProof(wire, limits, ByteLimit(20000)).value
  assert verifyStateProof(decoded, snapshot.commitment.root, key, limits).value.bytes == newSeq[byte](33)
  let generated = generateStateProofs(entries, [key, other], maps, limits, aggregate).value
  let queries = @[generated.queryAt(0).value, generated.queryAt(1).value]
  let batch = verifyStateProofs(queries, snapshot.commitment.root, limits, aggregate).value
  assert batch.lookupAt(1).value.bytes == @[byte 7]
  failAfter(1)
  assert generateStateProofs(entries, [key, other], maps, limits, aggregate).error ==
      StateProofError.BackendFailure
  failAfter(1)
  assert verifyStateProofs(queries, snapshot.commitment.root, limits, aggregate).error ==
      StateProofError.BackendFailure
  fail(0)
  assert verifyStateProof(proof, snapshot.commitment.root, key, limits).value.present
for i in 0..<25:
  cycle() # Warm the exact ownership/fault workload before recording allocator occupancy.
let before = getOccupiedMem()
for i in 0..<1000:
  cycle() # Each cycle releases original, decoded, generated and partially failed graphs.
let after = getOccupiedMem()
assert before == after
recordArcRelease("state_proof_lifecycle", 1000, before, after)
echo "state-proof-lifecycle: ok"
