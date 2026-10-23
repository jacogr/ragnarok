# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual forget/restore execution qualifies the exact three-slot retained request history.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context, current_namespace_execution_context,
    accumulation_execution_context,
    current_identity_context, supplied_services_context, pvm_accumulation_program]
import ../../../src/app/[collected_supplied_state, preparation_worker, current_block_input]
import ../../../src/state/[current_identities, current_logical, supplied_logical_inventory,
    supplied_services, accumulation_current_update, store]
import ../../../src/codec/[bounded, state_layout, state_accounts, state_composition,
    state_service_values, state_requests]
import ../../../src/crypto/primitives
proc main() {.raises.} =
  ## Real signed inputs and the fixed-address native preparation worker choose all actual regular/exceptional effects.
  var options = executionFixtureConfig()
  options.firstProgram = namespaceHaltCode()
  options.secondBalance = 1000000
  options.signed.serviceNamespaces = namespaceSeeds()
  let hash = options.signed.serviceNamespaces[1].preimages[1].hash
  options.secondProgram = requestMutationCode(hash, RequestLength(1), [26'u8, 25])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests[1].history = reavailableHistory(RequestSlot(1), RequestSlot(2), RequestSlot(2))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(1), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  let history = supplied[1].requests[1].history
  assert history.state == RequestState.Reavailable
  assert uint32(history.originalFrom) == 1 and uint32(history.removedAt) == 2 and uint32(
      history.restoredAt) == 2
  fixture.checkMutationProof(true, @[3'u8, 1, 0, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0])
  var stale = fixture.declarations
  stale[1].requests[1].history = availableHistory(RequestSlot(1))
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), stale).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-request-restoration: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
