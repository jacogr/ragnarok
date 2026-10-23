# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual funded solicitation qualifies a new request marker with exact requested-state wire bytes.
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
  let hash = ServicePreimageHash(array[32, byte](blake2b256([71'u8, 72]).value))
  options.secondProgram = requestMutationCode(hash, RequestLength(2), [25'u8])
  let origin = namespaceTransitionFixture(nativeBase(), options)
  var expected = origin.services
  expected[1].requests.add(StateRequestItem(hash: hash, length: RequestLength(2),
      history: requestedHistory()))
  let key = serviceRequestKey(ServiceIndex(99), hash, RequestLength(2), ByteLimit(36)).value
  let fixture = collectMutation(origin, expected, key)
  let refused = preserveCurrentIdentities(origin.parent, fixture.receipt.currentValue.value, currentIdentityTestLimits)
  assert refused.error == CurrentIdentityError.NewIdentity
  let logical = qualifyMutation(fixture)
  let supplied = copySuppliedServices(logical.currentLogicalInventory.value,
      suppliedServicesTestLimits).value
  assert supplied[1].requests.len == 4 and supplied[1].requests[3].history.state ==
      RequestState.Requested
  fixture.checkMutationProof(true, @[0'u8])
  var omitted = fixture.declarations
  omitted[1].requests.setLen(3)
  assert executeCollectedSupplied(fixture.chain, mutationPlan(fixture), omitted).error ==
      CollectedSuppliedError.StateFailure
  echo "application-supplied-request-addition: ok"
try:
  main()
except:
  quit(2) # No copied post-map or fabricated completion can satisfy this selected actual successor.
