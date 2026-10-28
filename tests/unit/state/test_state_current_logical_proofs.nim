# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## All sixteen typed global chapters and mixed storage/absence proofs use the actual refreshed selected producer, unchanged RPV1 and independent roots.
# @@Verification={"arc":"state_current_logical_proofs_arc_release"}
import std/assertions
import std/envvars
import std/syncio
import ../../support/state_current_repeated_logical_context
import ../../support/state_current_namespace_refresh_context
import ../../support/state_current_logical_proof_context
import ../../support/testing_arc_evidence
import ../../../src/state/current_logical_refresh as state_current_logical_refresh
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/state/store as state_store
import ../../../src/app/proof_query as app_proof_query
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_accounts as codec_state_accounts
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
  ## After authentication, typed reads and exact subset projection must perform no backend hashing.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe only while no worker is active.
proc cycle(logical: CurrentLogicalState, view: ProofView, plan: StateProofPlan) =
  ## Repeated typed read captures/projection scratch retire while only already authenticated partial evidence survives.
  checkLogicalProof(logical, view, 3)
  assert projectPlannedProofs(view, plan, logicalProofLimits().view).error == ProofViewError.None
proc main() {.raises.} =
  ## Authentic current execution and full logical matching precede any proof request or independent root selection.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  let logical = executeCurrentLogicalRefresh(namespaceRefreshStages(fixture.logical,
      fixture.next).complete).value
  let root = logical.logicalProducer.currentUpdateState.commitment.root
  let plan = logicalProofPlan()
  let limits = logicalProofLimits()
  let response = executeProofQuery(logicalProofQuery(logical, plan)).value
  let wire = response.bytes(limits.wireBytes).value
  assert wire.len >= 8
  let magic = [82'u8, 80, 86, 49]
  for i in 0..<magic.len:
    # Check each RPV1 magic byte without allocating a stdlib sequence slice.
    assert wire[i] == magic[i]
  let verified = decodePlannedProofs(wire, plan, root, limits.view, limits.proof, limits.aggregate,
      limits.wireBytes).value
  let subset = captureStateProofPlan([chapterKey(StateChapter(11)), chapterServiceKey(StateChapter(
      255), ServiceIndex(123456))], ElementLimit(2)).value
  fail(1)
  cycle(logical, verified, subset)
  let partial = projectPlannedProofs(verified, subset, limits.view).value
  assert partial.readGlobalEntropy(ByteLimit(128)).error == GlobalProofError.MissingWitness
  assert partial.lookup(chapterServiceKey(StateChapter(255), ServiceIndex(123456))).value.present == false
  assert calls() == 0
  for i in 0..<25: cycle(logical, verified, subset)
  let before = getOccupiedMem()
  for i in 0..<1000: cycle(logical, verified, subset)
  let finalBytes = getOccupiedMem()
  assert before == finalBytes and calls() == 0
  recordArcRelease("state_current_logical_proofs", 1000, before, finalBytes)
  fail(0)
  echo "state-current-logical-proofs: ok"
try:
  main()
except:
  quit(2) # Neither detached response claims nor partial witnesses replace actual selected producer/root provenance.
