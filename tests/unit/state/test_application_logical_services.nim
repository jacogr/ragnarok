# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Managed actual current collection qualifies complete logical state before explicit host adoption and repeated preparation.
import std/[assertions, envvars, syncio]
import std/posix/posix
import ../../support/[current_repeated_logical_context, collected_logical_context,
    collected_logical_services_context, accumulation_current_candidate_context,
    application_download_chain,
    current_logical_proof_context]
import ../../../src/app/services
import ../../../src/app/current/logical as current_logical
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/current/handoff as current_handoff
import ../../../src/app/candidate
import ../../../src/app/proof/[worker as proof_worker, query as proof_query]
import ../../../src/state/current/[logical as current_logical, state as current_state,
    globals as current_globals, profile as current_profile]
import ../../../src/state/parent/logical as parent_logical
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/accumulation/[round as accumulation_round, queue as accumulation_queue]
import ../../../src/state/report/admission as report_admission
import "../../../src/state/block/transition" as block_transition
import "../../../src/state/block/admission" as block_admission
import ../../../src/state/store
import ../../../src/state/proof/plan as proof_plan
import ../../../src/state/planned/proof as planned_proof
import ../../../src/state/proof/[view as proof_view, global as proof_global]
import ../../../src/state/trie_proof
import ../../../src/chain/[provider, genesis]
import ../../../src/codec/[bounded, report_owned]
import ../../../src/codec/state/layout as state_layout
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
