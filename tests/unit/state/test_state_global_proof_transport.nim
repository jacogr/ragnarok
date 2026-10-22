# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Mixed global/service queries retain exact scope, independent root authority and legacy RPV1 bytes.
import std/[assertions, syncio]
import ../../support/proof_service_helpers
import ../../../src/state/[proof_plan, planned_proof, proof_service, proof_view, trie_proof]
import ../../../src/codec/[bounded, state_layout, state_trie, state_safrole, state_accounts]
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset the maintained actual hash observer and optionally fail the first backend attempt.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Measure real primitive calls for scope/budget preflight and backend failure prefixes.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse the next primitive after a measured successful prefix.
proc main() =
  ## Establish independent complete-map commitments before any partial response exists.
  let service = ServiceIndex(7)
  let account = serviceMetadataEntry(service, ServiceMetadata(), ByteLimit(105)).value
  let entries = @[timeEntry(StateTime(42)), entropyEntry(default(StateEntropy)), account]
  let root = stateTrieRoot(entries, mapLimits).value.root
  let plan = captureStateProofPlan([chapterKey(StateChapter(11)), account.key,
    chapterKey(StateChapter(6))], ElementLimit(3)).value
  var queries: seq[StateProofQuery] = @[]
  for key in plan:
    queries.add(StateProofQuery(key: key, proof: generateStateProof(entries, key, mapLimits,
        proofLimits).value))
  let view = verifyPlannedProofs(plan, queries, root, proofLimits, batchLimits, viewLimits).value
  assert matchesStateProofPlan(view, plan).value
  assert uint32(view.readProofTime.value) == 42
  let wire = encodePlannedProofs(view, plan, viewLimits, proofLimits, ByteLimit(16384)).value
  let received = decodePlannedProofs(wire, plan, root, viewLimits, proofLimits, batchLimits,
      ByteLimit(16384))
  assert received.error == ProofViewError.None and uint32(received.value.readProofTime.value) == 42
  let semantic = planProofAccount(service, ElementLimit(1)).value
  let single = serviceView(entries, [account.key])
  assert encodePlannedProofs(single, semantic.toStateProofPlan, viewLimits, proofLimits, ByteLimit(
      16384)).value ==
    encodeServiceProofs(single, semantic, viewLimits, proofLimits, ByteLimit(16384)).value
  for length in 0..<wire.len:
    # Every proper wire prefix refuses without exposing a verified view prefix.
    var prefix = newSeq[byte](length)
    for i in 0..<length: prefix[i] = wire[i]
    assert decodePlannedProofs(prefix, plan, root, viewLimits, proofLimits, batchLimits, ByteLimit(
        16384)).error != ProofViewError.None
  fail(1)
  var wrong = queries
  wrong[0].key = chapterKey(StateChapter(3))
  assert verifyPlannedProofs(plan, wrong, root, proofLimits, batchLimits, viewLimits).error ==
      ProofViewError.NonCanonical
  assert calls() == 0
  var substituted = wire
  substituted[8] = substituted[8] xor 1
  assert decodePlannedProofs(substituted, plan, root, viewLimits, proofLimits, batchLimits,
      ByteLimit(16384)).error == ProofViewError.NonCanonical
  assert calls() == 0
  assert decodePlannedProofs(wire, plan, root, viewLimits, proofLimits, batchLimits, ByteLimit(
      uint64(wire.len)-1)).error == ProofViewError.LimitExceeded
  assert calls() == 0
  fail(0)
  assert decodePlannedProofs(wire, plan, root, viewLimits, proofLimits, batchLimits, ByteLimit(
      16384)).error == ProofViewError.None
  let count = calls()
  assert count > 0
  for prefix in 0..<int(count):
    # Each actual backend prefix must fail atomically with the precise proof reason.
    failAfter(cint(prefix))
    let refused = decodePlannedProofs(wire, plan, root, viewLimits, proofLimits, batchLimits,
        ByteLimit(16384))
    assert refused.error == ProofViewError.ProofFailure and refused.proofError ==
        StateProofError.BackendFailure
    assert calls() == cint(prefix+1)
  fail(0)
  let wrongRoot = decodePlannedProofs(wire, plan, default(StateRoot), viewLimits, proofLimits,
      batchLimits, ByteLimit(16384))
  assert wrongRoot.error == ProofViewError.ProofFailure and wrongRoot.proofError ==
      StateProofError.RootMismatch
  assert decodePlannedProofs(wire, default(StateProofPlan), root, viewLimits, proofLimits,
      batchLimits, ByteLimit(16384)).error == ProofViewError.Uninitialized
  echo "state-global-proof-transport: ok"
main()
