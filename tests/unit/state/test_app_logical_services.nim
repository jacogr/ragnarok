# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed actual current collection qualifies complete logical state before explicit host adoption and repeated preparation.
import std/assertions
import std/envvars
import std/syncio
import std/posix/posix
import ../../support/state_current_repeated_logical_context
import ../../support/app_collected_logical_context
import ../../support/app_collected_logical_services_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/app_download_chain
import ../../support/state_current_logical_proof_context
import ../../../src/app/services as app_services
import ../../../src/app/current_logical as app_current_logical
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/current_handoff as app_current_handoff
import ../../../src/app/candidate as app_candidate
import ../../../src/app/proof_worker as app_proof_worker
import ../../../src/app/proof_query as app_proof_query
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/current_state as state_current_state
import ../../../src/state/current_globals as state_current_globals
import ../../../src/state/current_profile as state_current_profile
import ../../../src/state/parent_logical as state_parent_logical
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/accumulation_round as state_accumulation_round
import ../../../src/state/accumulation_queue as state_accumulation_queue
import ../../../src/state/report_admission as state_report_admission
import ../../../src/state/block_transition as state_block_transition
import ../../../src/state/block_admission as state_block_admission
import ../../../src/state/store as state_store
import ../../../src/state/proof_plan as state_proof_plan
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/state/proof_view as state_proof_view
import ../../../src/state/proof_global as state_proof_global
import ../../../src/state/trie_proof as state_trie_proof
import ../../../src/chain/provider as chain_provider
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/report_owned as codec_report_owned
import ../../../src/codec/state_layout as codec_state_layout
proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Bound scalar-only polling of the actual managed proof worker.
proc main() {.raises.} =
  ## Configured startup, real preparation, complete logical refresh and adoption retain one exact physical chain.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for i in 0..<raw.len: bytes[i] = byte(raw[i])
  let fixture = repeatedLogicalFixture(decodeOwnedReport(bytes, 2).value)
  var path = "application-logical-services-chain.json"
  defer: discard posix.unlink(path.toCString())
  var owner = default(Services)
  var input = default(CurrentBlockInput)
  let source = startLogicalServices(owner, fixture, path)
  defer: owner.close() # Join before every retained source/receipt/logical graph retires.
  let original = owner.stateSnapshot.value
  let bound = fixture.first.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted
  let wire = currentWire(bound.admittedBlock)
  let ticket = beginManagedCurrent(owner, input, wire, fixture.first.source.older,
      currentCandidateLimits())
  owner.waitManagedPreparation()
  assert owner.preparationActive
  assert owner.collectPreparation(default(PreparationTicket)).kind ==
      PreparationCompletionKind.Uninitialized
  assert owner.preparationActive # Foreign collection cannot authorize touching source or original aliases.
  let receipt = owner.collectPreparation(ticket)
  assert not owner.preparationActive
  let first = owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits())
  assert first.error == CollectedLogicalError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, original)
  let update = receipt.currentValue.value
  assert owner.enqueueCurrentAccumulation(update) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.currentAccumulationPhase == CurrentHandoffPhase.Finished
  assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
  assert sameStateSnapshot(owner.stateSnapshot.value, update.currentUpdateState)
  assert owner.refreshCollectedLogical(receipt, source, collectedLogicalTestLimits()).error ==
      CollectedLogicalError.StaleUpdate
  # The completed source remains alive and untouched across the next real native preparation lease.
  let nextWire = currentWire(signedChild(update.currentUpdateChild))
  var policies = currentCandidateLimits()
  policies.completion.composition.validators.services = ElementLimit(2)
  let nextTicket = beginManagedCurrent(owner, input, nextWire, [], policies)
  owner.waitManagedPreparation()
  assert owner.preparationActive
  let nextReceipt = owner.collectPreparation(nextTicket)
  let second = owner.refreshCollectedLogical(nextReceipt, first.value, collectedLogicalTestLimits())
  assert second.error == CollectedLogicalError.None
  let next = nextReceipt.currentValue.value
  assert sameStateSnapshot(second.value.logicalProducer.currentUpdateState, next.currentUpdateState)
  assert owner.enqueueCurrentAccumulation(next) == CurrentHandoffAdmission.None
  owner.tick(0)
  assert owner.takeCurrentAccumulation.error == CurrentHandoffError.None
  # Independently fixed posterior root/plan is captured before proof enqueue; retained logical owners stay untouched until collection.
  let selected = owner.chainView.bestBlock.value.blockHash
  let root = next.currentUpdateState.commitment.root
  let plan = logicalProofPlan()
  let proofLimits = logicalProofLimits()
  let proof = owner.beginStateProof(selected, plan, proofLimits)
  assert proof.error == StateProofAdmissionError.None
  for attempt in 0..<20000:
    if owner.stateProofPhase == ProofWorkerPhase.Done: break
    discard pauseMicros(1000)
  assert owner.stateProofPhase == ProofWorkerPhase.Done and owner.stateProofActive
  assert owner.collectStateProof(default(ProofWorkerTicket)).kind ==
      ProofWorkerCompletionKind.Uninitialized
  let proofReceipt = owner.collectStateProof(proof.value)
  assert not owner.stateProofActive
  assert proofReceipt.kind == ProofWorkerCompletionKind.Completed
  let response = proofReceipt.value.value
  owner.close() # The response is detached and all shared logical owners may retire after joined shutdown.
  let view = decodePlannedProofs(response.bytes(proofLimits.wireBytes).value, plan, root,
    proofLimits.view, proofLimits.proof, proofLimits.aggregate, proofLimits.wireBytes)
  assert view.error == ProofViewError.None
  checkLogicalProof(second.value, view.value, 3)
  echo "application-logical-services: ok"
try:
  main()
except:
  quit(2) # Native startup/transport exceptions cannot satisfy any logical success assertion.
