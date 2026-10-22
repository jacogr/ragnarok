# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Generic global plans bind generation to independent complete snapshots and genuine selected blocks.
import std/[assertions, syncio]
import ../../support/[proof_service_helpers, proof_query_context]
import ../../../src/state/[proof_plan, planned_proof, proof_view, trie_proof, snapshot_proof, store]
import ../../../src/chain/[genesis, state_proof]
import ../../../src/codec/[bounded, state_layout, state_trie, state_safrole]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained hash observer or fail attempted backend work during bound checks.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe that count/map preflight performs no backend work.
proc raw(proofs: StateProofSet): seq[StateProofQuery] =
  ## Detach the bounded query list through immutable set accessors.
  result = newSeq[StateProofQuery](proofs.len)
  for i in 0..<proofs.len: result[i] = proofs.queryAt(i).value
proc main() {.raises.} =
  ## Verify both membership and absence against independently obtained posterior commitments.
  let entries = @[timeEntry(StateTime(42)), entropyEntry(default(StateEntropy))]
  let source = newStateStore(entries, StateStoreLimits(trie: mapLimits,
    writes: ElementLimit(4), writeValueBytes: ByteLimit(4096))).value.snapshot.value
  let plan = captureStateProofPlan([chapterKey(StateChapter(11)), chapterKey(StateChapter(6)),
    chapterKey(StateChapter(3))], ElementLimit(3)).value
  let generated = generatePlannedProofs(source, plan, mapLimits, proofLimits, batchLimits).value
  assert generated.len == 3
  let view = verifyPlannedProofs(plan, raw(generated), source.commitment.root, proofLimits,
    batchLimits, viewLimits).value
  assert uint32(view.readProofTime.value) == 42
  assert not view.lookup(chapterKey(StateChapter(3))).value.present
  fail(1)
  var short = batchLimits
  short.items = ElementLimit(2)
  assert generatePlannedProofs(source, plan, mapLimits, proofLimits, short).error ==
      StateProofError.LimitExceeded
  var shortMap = mapLimits
  shortMap.items = ElementLimit(1)
  assert generatePlannedProofs(source, plan, shortMap, proofLimits, batchLimits).error ==
      StateProofError.LimitExceeded
  assert calls() == 0
  assert generatePlannedProofs(source, default(StateProofPlan), mapLimits, proofLimits,
      batchLimits).error == StateProofError.Uninitialized
  fail(0)
  let selected = querySelection(queryContext())
  let real = queryLimits()
  let selectedPlan = captureStateProofPlan([chapterKey(StateChapter(11)), chapterKey(StateChapter(
      6))], ElementLimit(2)).value
  let blockProofs = generateBlockPlannedProofs(selected, selectedPlan, real.map, real.proof,
      real.aggregate).value
  let received = verifyPlannedProofs(selectedPlan, raw(blockProofs), selected.value.stateRoot,
    real.proof, real.aggregate, real.view)
  assert received.error == ProofViewError.None and received.value.readProofTime.error ==
      ProofViewError.None
  let missing = default(BlockSnapshotResult)
  assert generateBlockPlannedProofs(missing, selectedPlan, real.map, real.proof,
      real.aggregate).error == StateProofError.Uninitialized
  assert generateBlockPlannedProofs(selected, default(StateProofPlan), real.map, real.proof,
      real.aggregate).error == StateProofError.Uninitialized
  echo "state-global-proof-generation: ok"
try:
  main()
except:
  quit(2) # Genuine fixture/startup failures must fail the native suite.
