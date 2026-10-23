# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real native mutation receipts retain explicit known successor declarations and independently selected proof expectations.
import std/assertions
import ./[collected_native_context, collected_supplied_context, collected_logical_context,
    current_namespace_transition_context, current_logical_proof_context, accumulation_current_candidate_context]
import ../../src/app/[chain, preparation_worker, current_block_input, candidate,
    collected_supplied_plan, collected_supplied_state, proof_query]
import ../../src/state/[accumulation_current_update, accumulation_round, accumulation_queue,
    report_admission, block_transition, block_admission, current_logical, proof_plan, planned_proof,
    proof_view, store]
import ../../src/codec/[bounded, state_composition, state_layout]
import ../../src/chain/[provider, genesis]
type CollectedMutationFixture* = object ## Test-only descriptors retain genuine native execution and caller-supplied identities, never a mutation certificate.
  origin*: CurrentNamespaceTransition
  chain*: ApplicationChain
  receipt*: PreparationCompletion
  declarations*: seq[StateService]
  key*: StateKey
proc collectMutation*(origin: CurrentNamespaceTransition, declarations: openArray[StateService],
    key: StateKey, deleted = ElementLimit(0)): CollectedMutationFixture {.raises.} =
  ## Original code/namespaces entered roots and signatures; execute again on the fixed-address native worker without patching a completed map.
  var chain = initApplicationChain(origin.update.currentUpdatePriorView).value
  let owner = origin.source.round.roundBlockQueue.value.accumulationAdmission.value.reportBlockStage.value.value.admitted.admittedBlock
  var policies = currentCandidateLimits()
  policies.completion.execution.initial.guests.deletedAccounts = deleted
  policies.completion.execution.execution.round.guests.deletedAccounts = deleted
  let receipt = collectNative(chain, currentWire(owner), origin.source.older, policies)
  assert receipt.kind == PreparationCompletionKind.CurrentCompleted and
      receipt.currentValue.error == CurrentBlockInputError.None
  CollectedMutationFixture(origin: origin, chain: chain, receipt: receipt,
    declarations: successorDeclarations(receipt.currentValue.value, declarations), key: key)
proc mutationPlan*(fixture: CollectedMutationFixture): CollectedSuppliedPlan =
  ## Only the actual collected successor on the original prior can freeze supplied matching.
  planCollectedSupplied(fixture.chain, fixture.receipt, collectedSuppliedTestLimits()).value
proc qualifyMutation*(fixture: CollectedMutationFixture): CurrentLogicalState =
  ## Full supplied matching and independently retained raw identities remain required for each genuine operation.
  executeCollectedSupplied(fixture.chain, mutationPlan(fixture), fixture.declarations).value
proc checkMutationProof*(fixture: CollectedMutationFixture, present: bool, payload: seq[byte]) =
  ## Fix actual posterior and prior roots before capture; exact-plan proof validation must distinguish present bytes, proven absence and crossed roots.
  let update = fixture.receipt.currentValue.value
  let root = update.currentUpdateState.commitment.root
  let oldRoot = update.currentUpdatePriorState.commitment.root
  let plan = captureStateProofPlan([fixture.key], ElementLimit(1)).value
  let limits = logicalProofLimits()
  assert update.currentUpdateViewInfo.owners <= 9 and update.currentUpdateViewInfo.bytes <= 8388608
  let query = captureProofQuery(update.currentUpdateView.bestBlock, plan, limits).value
  let response = executeProofQuery(query).value
  let wire = response.bytes(limits.wireBytes).value
  let view = decodePlannedProofs(wire, plan, root, limits.view, limits.proof, limits.aggregate,
      limits.wireBytes).value
  let value = view.lookup(fixture.key).value
  assert value.present == present
  if present: assert value.bytes == payload # Present-empty remains a real authenticated value.
  else: assert payload.len == 0 # An authenticated absent key exposes no invented bytes.
  assert decodePlannedProofs(wire, plan, oldRoot, limits.view, limits.proof, limits.aggregate,
    limits.wireBytes).error != ProofViewError.None
