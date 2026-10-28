# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A fully supplied identity-changing native successor becomes the exact logical source for later identity-preserving actual children.
import std/assertions
import std/syncio
import ../../support/app_collected_native_context
import ../../support/app_collected_mutation_context
import ../../support/app_collected_logical_context
import ../../support/state_current_namespace_context
import ../../support/state_current_namespace_transition_context
import ../../support/state_current_namespace_execution_context
import ../../support/state_accumulation_execution_context
import ../../support/state_accumulation_current_candidate_context
import ../../support/app_download_chain
import ../../support/state_supplied_services_context
import ../../support/state_current_logical_proof_context
import ../../../src/app/chain as app_chain
import ../../../src/app/current_logical as app_current_logical
import ../../../src/app/preparation_worker as app_preparation_worker
import ../../../src/app/current_block_input as app_current_block_input
import ../../../src/app/candidate as app_candidate
import ../../../src/app/logical_proof as app_logical_proof
import ../../../src/app/proof_query as app_proof_query
import ../../../src/state/current_logical as state_current_logical
import ../../../src/state/supplied_services as state_supplied_services
import ../../../src/state/supplied_logical_inventory as state_supplied_logical_inventory
import ../../../src/state/accumulation_current_update as state_accumulation_current_update
import ../../../src/state/store as state_store
import ../../../src/state/planned_proof as state_planned_proof
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/state_accounts as codec_state_accounts
import ../../../src/codec/state_composition as codec_state_composition
import ../../../src/codec/state_service_values as codec_state_service_values
proc main() {.raises.} =
  ## Raw key7 is supplied after its genuine creation, then retained unchanged across three later actual collected children.
  let value = @[91'u8, 92, 93]
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondProgram = namespaceStorageCode(value)
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].storage.add(StateStorageItem(key: @[7'u8], value: value))
  let key = serviceStorageKey(ServiceIndex(99), [7'u8], ByteLimit(1)).value
  let fixture = collectMutation(origin, expected, key)
  var logical = qualifyMutation(fixture)
  var chain = fixture.chain
  var update = logical.currentLogicalUpdate.value
  chain.installPrepared(update)
  for slot in 3'u32..5'u32:
    let wire = currentWire(signedChild(update.currentUpdateChild))
    var policies = currentCandidateLimits()
    policies.completion.composition.validators.services = ElementLimit(2)
    let receipt = collectNative(chain, wire, [], policies)
    let result = refreshCollectedLogical(chain, receipt, logical, collectedLogicalTestLimits())
    assert result.error == CollectedLogicalError.None
    let copied = copySuppliedServices(result.value.currentLogicalInventory.value,
        suppliedServicesTestLimits).value
    assert copied[1].storage.len == 3 and uint32(copied[1].metadata.lastAccumulation) == slot
    assert not sameStateSnapshot(result.value.currentLogicalContext.value.state,
        logical.currentLogicalContext.value.state)
    chain.installPrepared(receipt.currentValue.value)
    logical = result.value # Replace retained sources only after actual collection and before another native admission.
    update = logical.currentLogicalUpdate.value
  let selection = logicalProofPlan()
  let limits = LogicalProofLimits(blocks: ElementLimit(16), viewBytes: ByteLimit(33554432),
      query: logicalProofLimits())
  let response = executeProofQuery(captureLogicalProofQuery(logical, selection, limits).value).value
  let root = logical.currentLogicalContext.value.state.commitment.root
  let view = decodePlannedProofs(response.bytes(limits.query.wireBytes).value, selection, root,
    limits.query.view, limits.query.proof, limits.query.aggregate, limits.query.wireBytes).value
  checkLogicalProof(logical, view, 5)
  echo "application-supplied-identity-continuation: ok"
try:
  main()
except:
  quit(2) # Supplied complete output is not permission to substitute another physical prior or replay guest effects.
