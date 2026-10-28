# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real native mutation receipts retain explicit known successor declarations and independently selected proof expectations.
import std/assertions
import ../../src/codec/state_accounts as codec_state_accounts
import ../../src/codec/state_requests as codec_state_requests
import ./pvm_accumulation_program
import ./app_collected_native_context
import ./app_collected_supplied_context
import ./app_collected_logical_context
import ./state_current_namespace_transition_context
import ./state_current_logical_proof_context
import ./state_accumulation_current_candidate_context
import ../../src/app/chain as app_chain
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/current_block_input as app_current_block_input
import ../../src/app/candidate as app_candidate
import ../../src/app/collected_supplied_plan as app_collected_supplied_plan
import ../../src/app/collected_supplied_state as app_collected_supplied_state
import ../../src/app/proof_query as app_proof_query
import ../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../src/state/accumulation_round as state_accumulation_round
import ../../src/state/accumulation_queue as state_accumulation_queue
import ../../src/state/report_admission as state_report_admission
import ../../src/state/block_transition as state_block_transition
import ../../src/state/block_admission as state_block_admission
import ../../src/state/current_logical as state_current_logical
import ../../src/state/proof_plan as state_proof_plan
import ../../src/state/planned_proof as state_planned_proof
import ../../src/state/proof_view as state_proof_view
import ../../src/state/store as state_store
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/state_composition as codec_state_composition
import ../../src/codec/state_layout as codec_state_layout
import ../../src/chain/provider as chain_provider
import ../../src/chain/genesis as chain_genesis
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
proc writeMutationCode*(value: seq[byte], ending: openArray[seq[byte]]): seq[byte] =
  ## Author a real funded key7 host write followed by explicit opcode boundaries for selected terminal behavior.
  assert value.len > 0 and value.len <= 65
  var writable = @[7'u8]
  for octet in value: writable.add(octet)
  var instructions = @[registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
    registerImmediate(9, 1), registerImmediate(10, 196609), registerImmediate(11, uint64(
        value.len)), @[10'u8, 5]]
  for instruction in ending: instructions.add(instruction) # Terminal operations execute after the actual successful write.
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(octet)
proc requestMutationCode*(hash: ServicePreimageHash, length: RequestLength,
    operations: openArray[uint8]): seq[byte] =
  ## The known request hash is initialized before each actual solicit/forget host invocation; caller supplies exact operation order.
  let raw = array[32, byte](hash)
  var writable = newSeq[byte](32)
  for i in 0..<32: writable[i] = raw[i]
  var instructions: seq[seq[byte]] = @[]
  for operation in operations:
    assert operation == 25 or operation == 26
    for instruction in [registerImmediate(7, high(uint64)), registerImmediate(8, 196608),
      registerImmediate(9, uint64(uint32(length))), @[10'u8, operation]]: instructions.add(instruction)
  instructions.add(@[50'u8, 0])
  result = @[0'u8]
  for octet in guestEnvelope(instructions, writable): result.add(octet)
