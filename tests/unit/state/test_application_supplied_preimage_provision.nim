# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual block preimage provision qualifies added content and the exact updated request history.
import std/[assertions, syncio]
import ../../support/[collected_native_context, collected_mutation_context,
    current_namespace_context, current_namespace_transition_context,
    current_namespace_execution_context,
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
  options.secondProgram = namespaceHaltCode()
  let value = @[88'u8, 89, 90]
  let hash = ServicePreimageHash(array[32, byte](blake2b256(value).value))
  options.signed.serviceNamespaces[1].requests.add(StateRequestItem(hash: hash,
      length: RequestLength(3), history: requestedHistory()))
  options.signed.preimageWire = @[1'u8, 99, 0, 0, 0, 3, 88, 89, 90]
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].preimages.add(StatePreimageItem(hash: hash, value: value))
  expected[1].requests[2].history = availableHistory(RequestSlot(2))
  let key = servicePreimageKey(ServiceIndex(99), hash, ByteLimit(32)).value
  let fixture = collectMutation(origin, expected, key)
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.NewIdentity
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied[1].preimages.len == 4 and supplied[1].requests.len == 4
  assert supplied[1].requests[2].history.state == RequestState.Available
  assert uint32(supplied[1].requests[2].history.since) == 2
  fixture.checkMutationProof(true, value)
  var omitted = fixture.declarations
  omitted[1].preimages.setLen(3)
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), omitted).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-preimage-provision: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
