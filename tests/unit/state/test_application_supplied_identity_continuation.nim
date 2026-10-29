# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A fully supplied identity-changing native successor becomes the exact logical source for later identity-preserving actual children.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    collected_logical_context, current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
    accumulation_execution_context, accumulation_current_candidate_context,
    application_download_chain,
    supplied_services_context, current_logical_proof_context]
import ../../../src/app/chain
import ../../../src/app/current/logical as current_logical
import ../../../src/app/preparation_worker
import "../../../src/app/current/block/input" as current_block_input
import ../../../src/app/candidate
import ../../../src/app/logical/proof as logical_proof
import ../../../src/app/proof/query as proof_query
import ../../../src/state/current/logical as current_logical
import ../../../src/state/supplied/[services as supplied_services,
    logical_inventory as supplied_logical_inventory]
import ../../../src/state/accumulation/current/update as accumulation_current_update
import ../../../src/state/store
import ../../../src/state/planned/proof as planned_proof
import ../../../src/codec/bounded
import ../../../src/codec/state/[accounts as state_accounts, composition as state_composition,
    service_values as state_service_values]
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
